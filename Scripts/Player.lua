dofile("$CONTENT_DATA/Scripts/ModifyedDependicences/BasePlayer.lua")
dofile("$SURVIVAL_DATA/scripts/game/quest_util.lua")

dofile("$CONTENT_DATA/Scripts/Utils/Network.lua")

Player = class(BasePlayer)

local respawnTime = 10 * 40


local StatsTickRate = 40

local PerSecond = StatsTickRate / 40
local PerMinute = StatsTickRate / (40 * 60)

local FoodRecoveryThreshold = 5 -- Recover hp when food is above this value
local FastFoodRecoveryThreshold = 50 -- Recover hp fast when food is above this value
local HpRecovery = 50 * PerMinute
local FastHpRecovery = 75 * PerMinute
local FoodCostPerHpRecovery = 0.2
local FastFoodCostPerHpRecovery = 0.2

local FoodCostPerStamina = 0.02
local WaterCostPerStamina = 0.1
local SprintStaminaCost = 0.7 / 40 -- Per tick while sprinting
local CarryStaminaCost = 1.4 / 40 -- Per tick while carrying

local FoodLostPerSecond = 100 / 3.5 / 24 / 60
local WaterLostPerSecond = 100 / 2.5 / 24 / 60

local FatigueDamageHp = 1 * PerSecond
local FatigueDamageWater = 2 * PerSecond

local RespawnTimeout = 60 * 40

local RespawnFadeDuration = 0.45
local RespawnEndFadeDuration = 0.45

local RespawnFadeTimeout = 5.0
local RespawnDelay = RespawnFadeDuration * 40
local RespawnEndDelay = 1.0 * 40

local BaguetteSteps = 9

function Player.server_onCreate(self)
	self.sv = {}
	self.sv.saved = self.storage:load()
	self.sv.saved = self.sv.saved or {}
	self.sv.saved.stats = self.sv.saved.stats or {
		hp = 100, maxhp = 100,
		food = 100, maxfood = 100,
		water = 100, maxwater = 100
	}
	if self.sv.saved.isConscious == nil then self.sv.saved.isConscious = true end
	if self.sv.saved.hasRevivalItem == nil then self.sv.saved.hasRevivalItem = false end
	if self.sv.saved.isNewPlayer == nil then self.sv.saved.isNewPlayer = true end
	self.storage:save(self.sv.saved)

	self:sv_init()
	self.network:setClientData(self.sv.saved)
end

function Player.server_onRefresh(self)
	self:sv_init()
	self.network:setClientData(self.sv.saved)
end

function Player.sv_init(self)
	BasePlayer.sv_init(self)
	self.sv.staminaSpend = 0

	self.sv.statsTimer = Timer()
	self.sv.statsTimer:start(StatsTickRate)

	self.sv.spawnparams = {}
end

function Player.client_onCreate(self)
	BasePlayer.client_onCreate(self)
	self.cl = self.cl or {}
	self.cl.respawnTimer = 0
	if self.player == sm.localPlayer.getPlayer() then
		if g_survivalHud then
			g_survivalHud:open()
		end

		self.cl.hungryEffect = sm.effect.createEffect("Mechanic - StatusHungry")
		self.cl.thirstyEffect = sm.effect.createEffect("Mechanic - StatusThirsty")
	end

	self:cl_init()
end

function Player.cl_init(self)
	self.cl.revivalChewCount = 0
end

function Player.client_onClientDataUpdate(self, data)
	BasePlayer.client_onClientDataUpdate(self, data)
	if sm.localPlayer.getPlayer() == self.player then

		if self.cl.stats == nil then self.cl.stats = data.stats end -- First time copy to avoid nil errors

		if g_survivalHud then
			g_survivalHud:setSliderData("Health", data.stats.maxhp * 10 + 1, data.stats.hp * 10)
			g_survivalHud:setSliderData("Food", data.stats.maxfood * 10 + 1, data.stats.food * 10)
			g_survivalHud:setSliderData("Water", data.stats.maxwater * 10 + 1, data.stats.water * 10)
		end

		if self.cl.hasRevivalItem ~= data.hasRevivalItem then
			self.cl.revivalChewCount = 0
		end

		if self.player.character then
			local charParam = self.player:isMale() and 1 or 2
			self.cl.hungryEffect:setParameter("char", charParam)
			self.cl.thirstyEffect:setParameter("char", charParam)

			if data.stats.food <= 5 and not self.cl.hungryEffect:isPlaying() and data.isConscious then
				self.cl.hungryEffect:start()
			elseif (data.stats.food > 5 or not data.isConscious) and self.cl.hungryEffect:isPlaying() then
				self.cl.hungryEffect:stop()
			end
			if data.stats.water <= 5 and not self.cl.thirstyEffect:isPlaying() and data.isConscious then
				self.cl.thirstyEffect:start()
			elseif (data.stats.water > 5 or not data.isConscious) and self.cl.thirstyEffect:isPlaying() then
				self.cl.thirstyEffect:stop()
			end
		end

		if data.stats.food <= 5 and self.cl.stats.food > 5 then
			sm.gui.displayAlertText("#{ALERT_HUNGER}", 5)
		end
		if data.stats.water <= 5 and self.cl.stats.water > 5 then
			sm.gui.displayAlertText("#{ALERT_THIRST}", 5)
		end

		if data.stats.hp < self.cl.stats.hp and data.stats.breath == 0 then
			sm.gui.displayAlertText("#{DAMAGE_BREATH}", 1)
		elseif data.stats.hp < self.cl.stats.hp and data.stats.food == 0 then
			sm.gui.displayAlertText("#{DAMAGE_HUNGER}", 1)
		elseif data.stats.hp < self.cl.stats.hp and data.stats.water == 0 then
			sm.gui.displayAlertText("#{DAMAGE_THIRST}", 1)
		end

		self.cl.stats = data.stats
		self.cl.isConscious = data.isConscious
		self.cl.hasRevivalItem = data.hasRevivalItem

		sm.localPlayer.setBlockSprinting(data.stats.food == 0 or data.stats.water == 0)
	end
end

function Player.cl_localPlayerUpdate(self, dt)
	BasePlayer.cl_localPlayerUpdate(self, dt)

	local character = self.player:getCharacter()

	if character and not self.cl.isConscious then
		local keyBindingText = sm.gui.getKeyBinding("Use", true)
		if self.cl.hasRevivalItem then
			if self.cl.revivalChewCount < BaguetteSteps then
				sm.gui.setInteractionText("", keyBindingText, "#{INTERACTION_EAT} (" .. self.cl.revivalChewCount .. "/10)")
			else
				sm.gui.setInteractionText("", keyBindingText, "#{INTERACTION_REVIVE}")
			end
		elseif self.cl.respawnTimer > 0 then
			local o1 = "<p textShadow='false' bg='gui_keybinds_bg_orange' color='#4f4f4f' spacing='9'>"
			local o2 = "</p>"
			local seconds = math.ceil(self.cl.respawnTimer / 40)
			sm.gui.setInteractionText("", "Respawn in: " .. o1 .. tostring(seconds) .. o2)
		else
			sm.gui.setInteractionText("", keyBindingText, "#{INTERACTION_RESPAWN}")
		end
	end

	if character then
		self.cl.hungryEffect:setPosition(character.worldPosition)
		self.cl.thirstyEffect:setPosition(character.worldPosition)
	end
end

function Player.client_onInteract(self, character, state)
	if state == true then
		if not self.cl.isConscious then
			if self.cl.hasRevivalItem then
				if self.cl.revivalChewCount >= BaguetteSteps then
					self.network:sendToServer("server_n_revive")
					self.cl.respawnTimer = 0
				end
				self.cl.revivalChewCount = self.cl.revivalChewCount + 1
				self.network:sendToServer("server_onEvent", { type = "character", data = "chew" })
			elseif self.cl.respawnTimer == 0 then
				self.network:sendToServer("server_n_tryRespawn")
			end
		end
	end
end

function Player.server_onFixedUpdate(self, dt)
	BasePlayer.server_onFixedUpdate(self, dt)

	if g_survivalDev and not self.sv.saved.isConscious and not self.sv.saved.hasRevivalItem then
		if sm.container.canSpend(self.player:getInventory(), obj_consumable_longsandwich, 1) then
			if sm.container.beginTransaction() then
				sm.container.spend(self.player:getInventory(), obj_consumable_longsandwich, 1, true)
				if sm.container.endTransaction() then
					self.sv.saved.hasRevivalItem = true
					self.player:sendCharacterEvent("baguette")
					self.network:setClientData(self.sv.saved)
				end
			end
		end
	end

	-- Delays the respawn so clients have time to fade to black
	if self.sv.respawnDelayTimer then
		self.sv.respawnDelayTimer:tick()
		if self.sv.respawnDelayTimer:done() then
			self:sv_e_respawn()
			self.sv.respawnDelayTimer = nil
		end
	end

	-- End of respawn sequence
	if self.sv.respawnEndTimer then
		self.sv.respawnEndTimer:tick()
		if self.sv.respawnEndTimer:done() then
			self.network:sendToClient(self.player, "cl_n_endFadeToBlack", { duration = RespawnEndFadeDuration })
			self.sv.respawnEndTimer = nil;
		end
	end

	-- If respawn failed, restore the character
	if self.sv.respawnTimeoutTimer then
		self.sv.respawnTimeoutTimer:tick()
		if self.sv.respawnTimeoutTimer:done() then
			self:sv_e_onSpawnCharacter()
		end
	end

	local character = self.player:getCharacter()
	if character then
		-- Spend stamina on sprinting
		if character:isSprinting() then
			self.sv.staminaSpend = self.sv.staminaSpend + SprintStaminaCost
		end

		-- Spend stamina on carrying
		if not self.player:getCarry():isEmpty() then
			self.sv.staminaSpend = self.sv.staminaSpend + CarryStaminaCost
		end
	end

	-- Update stamina, food and water stats
	if character and self.sv.saved.isConscious and not (g_godMode or character:isSwimming()) then
		self.sv.statsTimer:tick()
		if self.sv.statsTimer:done() then
			self.sv.statsTimer:start(StatsTickRate)

			-- Recover health from food
			if self.sv.saved.stats.food > FoodRecoveryThreshold then
				local fastRecoveryFraction = 0

				-- Fast recovery when food is above fast threshold
				if self.sv.saved.stats.food > FastFoodRecoveryThreshold then
					local recoverableHp = math.min(self.sv.saved.stats.maxhp - self.sv.saved.stats.hp, FastHpRecovery)
					local foodSpend = math.min(recoverableHp * FastFoodCostPerHpRecovery,
						math.max(self.sv.saved.stats.food - FastFoodRecoveryThreshold, 0))
					local recoveredHp = foodSpend / FastFoodCostPerHpRecovery

					self.sv.saved.stats.hp = math.min(self.sv.saved.stats.hp + recoveredHp, self.sv.saved.stats.maxhp)
					self.sv.saved.stats.food = self.sv.saved.stats.food - foodSpend
					fastRecoveryFraction = (recoveredHp) / FastHpRecovery
				end

				-- Normal recovery
				local recoverableHp = math.min(self.sv.saved.stats.maxhp - self.sv.saved.stats.hp,
					HpRecovery * (1 - fastRecoveryFraction))
				local foodSpend = math.min(recoverableHp * FoodCostPerHpRecovery,
					math.max(self.sv.saved.stats.food - FoodRecoveryThreshold, 0))
				local recoveredHp = foodSpend / FoodCostPerHpRecovery

				self.sv.saved.stats.hp = math.min(self.sv.saved.stats.hp + recoveredHp, self.sv.saved.stats.maxhp)
				self.sv.saved.stats.food = self.sv.saved.stats.food - foodSpend
			end

			-- Spend water and food on stamina usage
			self.sv.saved.stats.water = math.max(self.sv.saved.stats.water - self.sv.staminaSpend * WaterCostPerStamina, 0)
			self.sv.saved.stats.food = math.max(self.sv.saved.stats.food - self.sv.staminaSpend * FoodCostPerStamina, 0)
			self.sv.staminaSpend = 0

			-- Decrease food and water with time
			self.sv.saved.stats.food = math.max(self.sv.saved.stats.food - FoodLostPerSecond, 0)
			self.sv.saved.stats.water = math.max(self.sv.saved.stats.water - WaterLostPerSecond, 0)

			local fatigueDamageFromHp = false
			if self.sv.saved.stats.food <= 0 then
				self:sv_takeDamage(FatigueDamageHp, "fatigue")
				fatigueDamageFromHp = true
			end
			if self.sv.saved.stats.water <= 0 then
				if not fatigueDamageFromHp then
					self:sv_takeDamage(FatigueDamageWater, "fatigue")
				end
			end

			self.storage:save(self.sv.saved)
			self.network:setClientData(self.sv.saved)
		end
	end
end

function Player.sv_e_staminaSpend(self, stamina)
	if not g_godMode then
		if stamina > 0 then
			self.sv.staminaSpend = self.sv.staminaSpend + stamina
		end
	end
end

function Player.sv_takeDamage(self, damage, source, attacker)
	if damage > 0 then
		damage = damage * GetDifficultySettings().playerTakeDamageMultiplier
		local character = self.player:getCharacter()
		local lockingInteractable = character:getLockingInteractable()
		if lockingInteractable and lockingInteractable:hasSeat() then
			lockingInteractable:setSeatCharacter(character)
		end

		if not g_godMode and self.sv.damageCooldown:done() then
			if self.sv.saved.isConscious then
				self.sv.saved.stats.hp = math.max(self.sv.saved.stats.hp - damage, 0)

				print("'Player' took:", damage, "damage.", self.sv.saved.stats.hp, "/", self.sv.saved.stats.maxhp, "HP")

				source = source or "shock" --always play a sound
				self.network:sendToClients("cl_n_onEvent",
					{ event = source, pos = character:getWorldPosition(), damage = damage * 0.01 })

				if self.sv.saved.stats.hp <= 0 then
					print("'Player' knocked out!")
					self.sv.respawnInteractionAttempted = false
					self.sv.saved.isConscious = false
					character:setTumbling(true)
					character:setDowned(true)

					self.network:sendToClient(self.player, "cl_setRespawnTimer")

					local team = TeamManager.sv_getTeamColor(self.player)

					--I'm too lazy to make useful documentation, but here is a comment anyway
					if team then
						if attacker then
							self.network:sendToClients("cl_msg",
								(team or "") ..
								self.player.name .. "#ffffff was pwned by " .. (TeamManager.sv_getTeamColor(attacker) or "") .. attacker.name)
						else
							self.network:sendToClients("cl_msg", (team or "") .. self.player.name .. " #ffffffdied")
						end
						if not TeamManager.sv_isBedExisting(team) then
							self:sv_removePlayer(self.player)

							--please forgive me. I have sinned in jank.
						end
					end
				end

				self.storage:save(self.sv.saved)
				self.network:setClientData(self.sv.saved)
			end
		else
			print("'Player' resisted", damage, "damage")
		end
	end
end

function Player:sv_removePlayer(player)
	local team = TeamManager.sv_getTeamColor(player) or ""
	TeamManager.sv_setTeam(player, nil)
	self.network:sendToClients("cl_msg", player.name .. " is now a spectator")

	local remainingPlayers = TeamManager.sv_getTeamCount(team)
	local stopComplainingAboutGrammar = "players"
	if remainingPlayers == 1 then
		stopComplainingAboutGrammar = "player"
	end

	if remainingPlayers > 0 then
		local msg = tostring(remainingPlayers) .. team .. "#ffffff " .. stopComplainingAboutGrammar .. " left!"
		self.network:sendToClients("cl_msg", msg)
	else
		self.network:sendToClients("cl_msg", team .. "TEAM ELIMINATED!")
		self.network:sendToClients("cl_alert", team .. "TEAM ELIMINATED!")

		local remainingTeams = TeamManager.sv_getTeamsCount()
		local stopComplainingAboutGrammar = "teams"
		if remainingTeams == 1 then
			stopComplainingAboutGrammar = "team"
		end

		if remainingTeams > 1 then
			self.network:sendToClients("cl_msg", tostring(remainingTeams) .. " " .. stopComplainingAboutGrammar .. " remaining!")
		else
			local winner = TeamManager.sv_getLastTeam()
			local msg = (winner and winner .. "TEAM WON!") or "NOBODY WON"
			self.network:sendToClients("cl_msg", msg)
			self.network:sendToClients("cl_alert", msg)
			sm.event.sendToGame("sv_jankySussySus", { callback = "sv_justPlayTheGoddamnSound", effect = "game finish" })
			g_gameActive = false
		end
	end
end

function Player.server_n_revive(self)
	local character = self.player:getCharacter()
	if not self.sv.saved.isConscious and self.sv.saved.hasRevivalItem and not self.sv.spawnparams.respawn then
		print("Player", self.player.id, "revived")
		self.sv.saved.stats.hp = self.sv.saved.stats.maxhp
		self.sv.saved.stats.food = self.sv.saved.stats.maxfood
		self.sv.saved.stats.water = self.sv.saved.stats.maxwater
		self.sv.saved.isConscious = true
		self.sv.saved.hasRevivalItem = false
		self.storage:save(self.sv.saved)
		self.network:setClientData(self.sv.saved)
		self.network:sendToClient(self.player, "cl_n_onEffect", { name = "Eat - EatFinish", host = self.player.character })
		if character then
			character:setTumbling(false)
			character:setDowned(false)
		end
		self.sv.damageCooldown:start(40)
		self.player:sendCharacterEvent("revive")
	end
end

function Player.sv_e_respawn(self)
	if self.sv.spawnparams.respawn then
		if not self.sv.respawnTimeoutTimer then
			self.sv.respawnTimeoutTimer = Timer()
			self.sv.respawnTimeoutTimer:start(RespawnTimeout)
		end
		return
	end
	if not self.sv.saved.isConscious then
		g_respawnManager:sv_performItemLoss(self.player)
		self.sv.spawnparams.respawn = true

		sm.event.sendToGame("sv_e_respawn", { player = self.player })
	else
		print("Player must be unconscious to respawn")
	end
end

function Player.server_n_tryRespawn(self)
	if not self.sv.saved.isConscious and not self.sv.respawnDelayTimer and not self.sv.respawnInteractionAttempted then
		self.sv.respawnInteractionAttempted = true
		self.sv.respawnEndTimer = nil;
		self.network:sendToClient(self.player, "cl_n_startFadeToBlack",
			{ duration = RespawnFadeDuration, timeout = RespawnFadeTimeout })

		self.sv.respawnDelayTimer = Timer()
		self.sv.respawnDelayTimer:start(RespawnDelay)
	end
end

function Player.sv_e_onSpawnCharacter(self)
	if self.sv.spawnparams.respawn then
		local playerBed = g_respawnManager:sv_getPlayerBed(self.player)
		if playerBed and playerBed.shape and sm.exists(playerBed.shape) and
			playerBed.shape.body:getWorld() == self.player.character:getWorld() then
			-- Attempt to seat the respawned character in a bed
			self.network:sendToClient(self.player, "cl_seatCharacter", { shape = playerBed.shape })
		end

		self.sv.respawnEndTimer = Timer()
		self.sv.respawnEndTimer:start(RespawnEndDelay)
	end

	if self.sv.saved.isNewPlayer or self.sv.spawnparams.respawn then
		print("Player", self.player.id, "spawned")
		if self.sv.saved.isNewPlayer then
			self.sv.saved.stats.hp = self.sv.saved.stats.maxhp
			self.sv.saved.stats.food = self.sv.saved.stats.maxfood
			self.sv.saved.stats.water = self.sv.saved.stats.maxwater
		else
			self.sv.saved.stats.hp = 100
			self.sv.saved.stats.food = 30
			self.sv.saved.stats.water = 30
		end
		self.sv.saved.isConscious = true
		self.sv.saved.hasRevivalItem = false
		self.sv.saved.isNewPlayer = false
		self.storage:save(self.sv.saved)
		self.network:setClientData(self.sv.saved)

		self.player.character:setTumbling(false)
		self.player.character:setDowned(false)
		self.sv.damageCooldown:start(40)
	else
		-- Player rejoined the game
		if self.sv.saved.stats.hp <= 0 or not self.sv.saved.isConscious then
			self.player.character:setTumbling(true)
			self.player.character:setDowned(true)
		end
	end

	self.sv.respawnInteractionAttempted = false
	self.sv.respawnDelayTimer = nil
	self.sv.respawnTimeoutTimer = nil
	self.sv.spawnparams = {}

	sm.event.sendToGame("sv_e_onSpawnPlayerCharacter", self.player)

	if not TeamManager.sv_getTeamColor(self.player) then
		sm.event.sendToWorld(self.player.character:getWorld(), "sv_enableFreecam",
			{ state = g_gameActive, players = { self.player } })
	end
end

function Player.cl_seatCharacter(self, params)
	if sm.exists(params.shape) then
		params.shape.interactable:setSeatCharacter(self.player.character)
	end
end

function Player.sv_e_eat(self, edibleParams)
	if edibleParams.hpGain then
		self:sv_restoreHealth(edibleParams.hpGain)
	end
	if edibleParams.foodGain then
		self:sv_restoreFood(edibleParams.foodGain)

		self.network:sendToClient(self.player, "cl_n_onEffect", { name = "Eat - EatFinish", host = self.player.character })
	end
	if edibleParams.waterGain then
		self:sv_restoreWater(edibleParams.waterGain)
		-- self.network:sendToClient( self.player, "cl_n_onEffect", { name = "Eat - DrinkFinish", host = self.player.character } )
	end
	self.storage:save(self.sv.saved)
	self.network:setClientData(self.sv.saved)
end

function Player.sv_e_feed(self, params)
	if not self.sv.saved.isConscious and not self.sv.saved.hasRevivalItem then
		if sm.container.beginTransaction() then
			sm.container.spend(params.playerInventory, params.foodUuid, 1, true)
			if sm.container.endTransaction() then
				self.sv.saved.hasRevivalItem = true
				self.player:sendCharacterEvent("baguette")
				self.network:setClientData(self.sv.saved)
			end
		end
	end
end

function Player.sv_restoreHealth(self, health)
	if self.sv.saved.isConscious then
		self.sv.saved.stats.hp = self.sv.saved.stats.hp + health
		self.sv.saved.stats.hp = math.min(self.sv.saved.stats.hp, self.sv.saved.stats.maxhp)
		print("'Player' restored:", health, "health.", self.sv.saved.stats.hp, "/", self.sv.saved.stats.maxhp, "HP")
	end
end

function Player.sv_restoreFood(self, food)
	if self.sv.saved.isConscious then
		food = food * (0.8 + (self.sv.saved.stats.maxfood - self.sv.saved.stats.food) / self.sv.saved.stats.maxfood * 0.2)
		self.sv.saved.stats.food = self.sv.saved.stats.food + food
		self.sv.saved.stats.food = math.min(self.sv.saved.stats.food, self.sv.saved.stats.maxfood)
		print("'Player' restored:", food, "food.", self.sv.saved.stats.food, "/", self.sv.saved.stats.maxfood, "FOOD")
	end
end

function Player.sv_restoreWater(self, water)
	if self.sv.saved.isConscious then
		water = water *
			(0.8 + (self.sv.saved.stats.maxwater - self.sv.saved.stats.water) / self.sv.saved.stats.maxwater * 0.2)
		self.sv.saved.stats.water = self.sv.saved.stats.water + water
		self.sv.saved.stats.water = math.min(self.sv.saved.stats.water, self.sv.saved.stats.maxwater)
		print("'Player' restored:", water, "water.", self.sv.saved.stats.water, "/", self.sv.saved.stats.maxwater, "WATER")
	end
end

function Player.client_onCancel(self)
	BasePlayer.client_onCancel(self)
	g_effectManager:cl_cancelAllCinematics()
end

function Player:cl_setRespawnTimer()
	self.cl.respawnTimer = respawnTime
end

function Player:client_onFixedUpdate()
	self.cl.respawnTimer = math.max(self.cl.respawnTimer - 1, 0)
end

function Player:server_onProjectile(hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal,
                                    projectileUuid)
	BasePlayer.server_onProjectile(self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal,
		projectileUuid)

	if type(attacker) == "Player" then
		self:sv_takeDamage(damage / 2, "shock", attacker)
	end
end

function Player:server_onMelee(hitPos, attacker, damage, power, hitDirection)
	BasePlayer.server_onMelee(self, hitPos, attacker, damage, power, hitDirection)

	if type(attacker) == "Player" then
		self:sv_takeDamage(damage, "impact", attacker)
	end
end

function Player.server_onInventoryChanges(self, container, changes)
	if sm.game.getLimitedInventory() then
		local obj_bedwars_bed = sm.uuid.new("6488a8fa-1187-45e8-8dac-47d13bdaa026")
		if FindInventoryChange(changes, obj_bedwars_bed) > 0 then
			sm.container.beginTransaction()
			sm.container.spend(self.player:getInventory(), obj_bedwars_bed, 1)
			sm.container.endTransaction()
		end
	end
end

function Player:sv_msg(msg)
	self.network:sendToClients("cl_msg", msg)
end

function Player:sv_alertg(msg)
	self.network:sendToClients("cl_alert", msg)
end

function Player:cl_msg(msg)
	sm.gui.chatMessage(msg)
end

function Player:cl_alert(msg)
	sm.gui.displayAlertText(msg)
end

SecureClass(Player)
