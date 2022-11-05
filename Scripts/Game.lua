dofile("$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua")

dofile("$CONTENT_DATA/Scripts/Utils/Network.lua")
dofile("$CONTENT_DATA/Scripts/RespawnManager.lua")

---@class Game : GameClass
Game = class(nil)
Game.enableLimitedInventory = true
Game.enableRestrictions = true
Game.enableFuelConsumption = true
Game.enableAmmoConsumption = true
Game.enableUpgrade = true

START_AREA_SPAWN_POINT = sm.vec3.new(0, 0, 5)
local deathDepth = -69

function updateMapTable(t, newMap)
	local newKey = #t + 1
	for key, map in ipairs(t) do
		if map.name == newMap.name then
			newKey = key
		end
	end
	t[newKey] = newMap
end

-- GameClass Callbacks --

function Game:server_onCreate()
	print("Game.server_onCreate")
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.world = sm.world.createWorld("$CONTENT_DATA/Scripts/World.lua", "World")
		self.sv.saved.banned = {}
		self.storage:save(self.sv.saved)
	end

	g_respawnManager = RespawnManager()
	g_respawnManager:sv_onCreate(self.sv.saved.world)

	g_beaconManager = BeaconManager()
	g_beaconManager:sv_onCreate()

	self.sv.teamManager = sm.storage.load(69)
	if not self.sv.teamManager then
		self.sv.teamManager = sm.scriptableObject.createScriptableObject(sm.uuid.new("cb5871ae-c677-4480-94e9-31d16899d093"))
		sm.storage.save(69, self.sv.teamManager)
	end

	self.sv.authorised = { [1] = true } -- Player ids.
	self.sv.newPlayers = {}
end

--cursed stuff to disable chunk unloading
function Game:sv_loadTerrain(data)
	for x = data.minX, data.maxX do
		for y = data.minY, data.maxY do
			data.world:loadCell(x, y, nil)
		end
	end
end

function Game:client_onCreate()
	print("Game.client_onCreate")
	g_survivalHud = sm.gui.createSurvivalHudGui()
	if sm.isHost then
		local invis = { "InventoryIconBackground", "InventoryBinding", "HandbookIconBackground", "HandbookBinding" }
		for _, name in pairs(invis) do
			g_survivalHud:setVisible(name, false)
		end
		g_survivalHud:setImage("LogbookImageBox", "$CONTENT_DATA/Gui/Images/map_icon.png")
	else
		g_survivalHud:setVisible("BindingPanel", false)
	end

	if g_respawnManager == nil then
		assert(not sm.isHost)
		g_respawnManager = RespawnManager()
	end
	g_respawnManager:cl_onCreate()

	if g_beaconManager == nil then
		assert(not sm.isHost)
		g_beaconManager = BeaconManager()
	end
	g_beaconManager:cl_onCreate()
end

function Game:server_onPlayerJoined(player, isNewPlayer)
	print("Game.server_onPlayerJoined")
	if isNewPlayer then
		if not sm.exists(self.sv.saved.world) then
			sm.world.loadWorld(self.sv.saved.world)
		end
		self.sv.saved.world:loadCell(0, 0, player, "sv_createPlayerCharacter")

		local inventory = player:getInventory()

		sm.container.beginTransaction()

		sm.container.setItem(inventory, 0, tool_sledgehammer, 1)
		sm.container.setItem(inventory, 1, tool_lift, 1)

		sm.container.endTransaction()
	end

	if #sm.player.getAllPlayers() > 1 and not TeamManager.sv_getTeamColor(player) then
		self.sv.newPlayers[#self.sv.newPlayers + 1] = player
	end

	for _, id in ipairs(self.sv.saved.banned) do
		if player.id == id then
			self:sv_yeet_player(player)
			self.network:sendToClients("client_showMessage", player.name .. "#ff0000 is banned!")
		end
	end

	self.network:sendToClient(player, "cl_onAssignCommands", self:Authorised(player))
end

function Game:sv_jankySussySus(params)
	sm.event.sendToWorld(self.sv.saved.world, params.callback, params)
end

function Game:server_onFixedUpdate()
	for _, player in ipairs(sm.player.getAllPlayers()) do
		local char = player.character
		if char and char.worldPosition.z < deathDepth then
			local params = { damage = 6969, player = player }
			sm.event.sendToPlayer(params.player, "sv_e_receiveDamage", params)

			local tumbleMod = math.sin(sm.game.getCurrentTick() / 2) * 420
			char:applyTumblingImpulse(sm.vec3.new(0, 0, 1) * tumbleMod)
		end
	end

	for _, player in ipairs(self.sv.newPlayers) do
		if player.character then
			player.character:setSwimming(true)
			player.character.publicData.waterMovementSpeedFraction = 5
			self.sv.newPlayers[_] = nil
		end
	end

	g_respawnManager:server_onFixedUpdate()
end

-- Command Handling --

---@param player Player
function Game:server_onChatCommand(params, player)
	if params[1] == "/fly" then
		self:sv_toggleFly(player)
	elseif params[1] == "/spectator" then
		self:sv_setSpectator(player)
	elseif params[1] == "/freecam" and not g_teamManager.sv_getTeamColor(player) then
		if g_teamManager.settings.ForceFreecam and not self:Authorised(player) then return end
		sm.event.sendToWorld(self.sv.saved.world, "sv_enableFreecam", { state = params[2], players = { player } })
	elseif params[1] == "/tm" then
		local team = TeamManager.sv_getTeamColor(player)
		if not team then
			self.network:sendToClient(player, "client_showMessage", "#ff0000Not in a team!")

			return
		end
		local msg = ""

		table.remove(params, 1)

		for _, v in pairs(params) do
			msg = msg .. " " .. v
		end
		for _, p in pairs(sm.player.getAllPlayers()) do
			if TeamManager.sv_getTeamColor(p) ~= team then goto continue end


			self.network:sendToClient(p, "client_showMessage", team .. player:getName() .. "#ffffff :" .. msg)

			::continue::
		end
	end

	if not self:Authorised(player) then return end

	if params[1] == "/encrypt" then
		sm.game.setEnableRestrictions(true)
		self:sv_Alert("Restricted")
		return
	elseif params[1] == "/decrypt" then
		sm.game.setEnableRestrictions(false)
		self:sv_Alert("Unrestricted")
		return
	elseif params[1] == "/unlimited" then
		sm.game.setLimitedInventory(false)
		self:sv_Alert("Unlimited inventory")
		return
	elseif params[1] == "/limited" then
		sm.game.setLimitedInventory(true)
		self:sv_Alert("Limited inventory")
		return
	elseif params[1] == "/lockteams" then
		g_teamManager.settings.CanChangeTeam = not params[2]
		self:sv_Alert(params[2] and "Teams Locked!" or "Teams Unlocked!")
		return
	elseif params[1] == "/forcefreecam" then
		g_teamManager.settings.ForceFreecam = params[2]
		self:sv_Alert(params[2] and "Enforced Spectator Freecam Enabled!" or "Enforced Spectator Freecam Disabled!")
		return
	elseif params[1] == "/start" then
		self:sv_start()
		return
	end

	if params[1] == "/ban" or params[1] == "/kick" then
		local client

		for _, player1 in ipairs(sm.player.getAllPlayers()) do
			if player1.id == params[2] then
				client = player1
			end
		end

		if client then
			self:sv_yeet_player(client)
			if params[1] == "/ban" then
				self.sv.saved.banned[#self.sv.saved.banned + 1] = client.id
				self.storage:save(self.sv.saved)
				self.network:sendToClients("client_showMessage", client.name .. "#ff0000 has been banned!")
			else
				self.network:sendToClients("client_showMessage", client.name .. "#ff0000 has been kicked!")
			end
		else
			self.network:sendToClient(player, "client_showMessage", "Couldn't find player with id: " .. tostring(params[2]))
		end
	end

	if player.id ~= 1 then return end

	if params[1] == "/auth" then
		local Result = self:Authorise(params[2]) and "Success" or "Already Authed"
		self:sv_Alert(Result, 1)
	elseif params[1] == "/unauth" then
		local Result = self:Unauthorise(params[2]) and "Success" or "Not Authed"
		self:sv_Alert(Result, 1)
	elseif params[1] == "/authlist" then
		for key, auth in pairs(self.sv.authorised) do
			self.network:sendToClient(player, "client_showMessage", tostring(key) .. ":" .. tostring(auth))
		end
	end
end

function Game:cl_onChatCommand(params) -- just don't handle the command if its a server side command. (unless you need client data)
	if params[1] == "/savemap" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast(100)
		if rayCastValid and rayCastResult.type == "body" then
			local importParams = {
				name = params[2],
				body = rayCastResult:getBody()
			}
			self.network:sendToServer("server_exportMap", importParams)
		else
			sm.gui.chatMessage("#ff0000Look at the map while saving it")
		end
	elseif params[1] == "/ids" then
		for _, player in ipairs(sm.player.getAllPlayers()) do
			sm.gui.chatMessage(tostring(player.id) .. ": " .. player.name)
		end
	elseif params[1] == "/forceteam" then
		local Player
		for _, plr in ipairs(sm.player.getAllPlayers()) do
			if plr.id == params[2] then
				Player = plr
				break
			end
		end
		if not Player then self:cl_Alert({ Text = "Invaild PlayerId" }) return end
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast(100)
		if rayCastValid and rayCastResult.type == "body" then
			local Distance = math.huge
			local Object = nil
			for _, shape in ipairs(rayCastResult:getBody():getShapes()) do
				local Dis = (rayCastResult.pointWorld - shape:getWorldPosition()):length()
				if Dis < Distance then
					Distance = Dis
					Object = shape
				end
			end
			if Object.uuid == sm.uuid.new("6488a8fa-1187-45e8-8dac-47d13bdaa026") then
				self.network:sendToServer("server_forceTeam", { bed = Object, player = Player })
			else
				self.network:sendToServer("server_forceTeam", { player = Player })
			end
		end
	else
		self.network:sendToServer("server_onChatCommand", params)
	end
end

function Game:cl_onAssignCommands(authorised)
	sm.game.bindChatCommand("/fly", {}, "cl_onChatCommand", "Toggle fly mode")
	sm.game.bindChatCommand("/spectator", {}, "cl_onChatCommand", "Become a spectator")
	sm.game.bindChatCommand("/tm",
		{ { "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true },
			{ "string", "message", true }, { "string", "message", true }, { "string", "message", true }, }, "cl_onChatCommand",
		"Team message")

	if authorised then
		sm.game.bindChatCommand("/limited", {}, "cl_onChatCommand", "Use the limited inventory")
		sm.game.bindChatCommand("/unlimited", {}, "cl_onChatCommand", "Use the unlimited inventory")
		sm.game.bindChatCommand("/encrypt", {}, "cl_onChatCommand", "Restrict interactions in all warehouses")
		sm.game.bindChatCommand("/decrypt", {}, "cl_onChatCommand", "Unrestrict interactions in all warehouses")
		sm.game.bindChatCommand("/start", {}, "cl_onChatCommand", "Start a game!")
		sm.game.bindChatCommand("/stop", {}, "cl_onChatCommand", "Stop a game!")

		sm.game.bindChatCommand("/freecam", { { "bool", "state", false } }, "cl_onChatCommand", "Toggle Freecam")
		sm.game.bindChatCommand("/forcefreecam", { { "bool", "state", false } }, "cl_onChatCommand",
			"Spectators will be stuck in freecam.")
		sm.game.bindChatCommand("/lockteams", { { "bool", "state", false } }, "cl_onChatCommand", "Toggles Team Changing.")
		sm.game.bindChatCommand("/forceteam", { { "int", "id", false } }, "cl_onChatCommand",
			"Forces Player Into Team. (Stare at a bed)")

		-- Moderation --
		sm.game.bindChatCommand("/ids", {}, "cl_onChatCommand", "Lists all players with their ID")
		sm.game.bindChatCommand("/kick", { { "int", "id", false } }, "cl_onChatCommand", "Kick(crash) a player")
		sm.game.bindChatCommand("/ban", { { "int", "id", false } }, "cl_onChatCommand", "Bans a player from this world")
	end

	if sm.isHost then
		-- Maps --
		sm.game.bindChatCommand("/savemap", { { "string", "name", false } }, "cl_onChatCommand", "Exports custom map")

		-- Auth --
		sm.game.bindChatCommand("/auth", { { "int", "id", false } }, "cl_onChatCommand", "Authorise a player.")
		sm.game.bindChatCommand("/unauth", { { "int", "id", false } }, "cl_onChatCommand", "Unauthorise a player.")
		sm.game.bindChatCommand("/authlist", {}, "cl_onChatCommand", "Get authorised players.")
	end
end

-- Commands --

function Game:sv_start()
	sm.event.sendToWorld(self.sv.saved.world, "sv_start")

	for _, plr in ipairs(sm.player.getAllPlayers()) do
		self:sv_e_respawn({ player = plr })
	end
end

function Game:sv_forceFreecam(params)
	sm.event.sendToWorld(self.sv.saved.world, "sv_enableFreecam", { state = params[1], players = params[2] })
end

function Game:server_exportMap(params, player)
	if not player.id == 1 then return end
	local obj = sm.json.parseJsonString(sm.creation.exportToString(params.body))
	sm.json.save(obj, "$CONTENT_DATA/Maps/Custom/" .. params.name .. ".blueprint")

	--update custom.json
	local custom_maps = sm.json.open("$CONTENT_DATA/Maps/custom.json") or {}
	local newMap = {}
	newMap.name = params.name
	newMap.blueprint = params.name
	newMap.custom = true
	newMap.time = os.time()

	updateMapTable(custom_maps, newMap)
	self.network:sendToClients("cl_updateMapList", newMap)

	sm.json.save(custom_maps, "$CONTENT_DATA/Maps/custom.json")

	self.network:sendToClient(player, "client_showMessage", "Map saved!")
end

function Game:server_forceTeam(parameters, player)
	if not self:Authorised(player) or not sm.exists(parameters.player.character) then return end
	if parameters.bed then
		sm.event.sendToInteractable(parameters.bed:getInteractable(), "sv_activatedBed", parameters.player)
	else
		TeamManager.sv_setTeam(player, nil)
	end
end

function Game:sv_toggleFly(player)
	if TeamManager.sv_getTeamColor(player) then
		self.network:sendToClient(player, "client_showMessage", "You need to be /spectator to fly")
		return
	end

	local char = player.character
	local isSwimming = not char:isSwimming()
	char:setSwimming(isSwimming)
	char.publicData.waterMovementSpeedFraction = (isSwimming and 5 or 1)
end

function Game:sv_setSpectator(player)
	if not g_teamManager.settings.CanChangeTeam and not self:Authorised(player) then return end
	TeamManager.sv_setTeam(player, nil)

	self.network:sendToClients("client_showMessage", player.name .. " is now a spectator")
end

-- Callbacks --

function Game:sv_createPlayerCharacter(world, x, y, player, params)
	local character = sm.character.createCharacter(player, world, START_AREA_SPAWN_POINT, 0, 0)
	player:setCharacter(character)
end

function Game:sv_bedDestroyed(color)
	local remainingPlayers = TeamManager.sv_getTeamCount(color)
	self.network:sendToClients("client_bedDestroyed", { color = color, players = remainingPlayers })
	sm.event.sendToWorld(self.sv.saved.world, "sv_justPlayTheGoddamnSound", { effect = "bed gone" })
end

function Game:client_bedDestroyed(params)
	local stopComplainingAboutGrammar = "players"
	if params.players == 1 then
		stopComplainingAboutGrammar = "player"
	end

	sm.gui.chatMessage(params.color .. "Bed destroyed! (" ..
		"#ffffff" .. params.players .. " " .. stopComplainingAboutGrammar .. " left" .. params.color .. ")"
	)

	sm.gui.displayAlertText(params.color .. "Bed destroyed!")

end

function Game:sv_e_respawn(params)
	if params.player.character and sm.exists(params.player.character) then
		g_respawnManager:sv_requestRespawnCharacter(params.player)
	else
		local spawnPoint = START_AREA_SPAWN_POINT
		if not sm.exists(self.sv.saved.world) then
			sm.world.loadWorld(self.sv.saved.world)
		end
		self.sv.saved.world:loadCell(math.floor(spawnPoint.x / 64), math.floor(spawnPoint.y / 64), params.player,
			"sv_createPlayerCharacter")
	end
end

function Game:sv_e_onSpawnPlayerCharacter(plr)
	if plr.character and sm.exists(plr.character) then
		g_respawnManager:sv_onSpawnCharacter(plr)
		g_beaconManager:sv_onSpawnCharacter(plr)
	else
		sm.log.warning("SurvivalGame.sv_e_onSpawnPlayerCharacter for a character that doesn't exist")
	end
end

function Game:sv_loadedRespawnCell(world, x, y, player)
	g_respawnManager:sv_respawnCharacter(player, world)
end

function Game:client_showMessage(msg)
	sm.gui.chatMessage(msg)
end

function Game:client_crash()
	self.sv.saved.world:reloadCell(0, 0) -- bugsplat
end

function Game:sv_yeet_player(player)
	local char = player:getCharacter()
	if char then
		local newChar = sm.character.createCharacter(player, player:getCharacter():getWorld(), sm.vec3.new(69420, 69420, 69420)
			, 0, 0)
		player:setCharacter(newChar)
		player:setCharacter(nil)
	end
	self.network:sendToClient(player, "client_crash")
end

function Game:cl_updateMapList(newMap)
	if sm.isHost then
		updateMapTable(g_maps, newMap)
	end
end

function Game:cl_Alert(data)
	sm.gui.displayAlertText(tostring(data.Text), tonumber(data.Duration) or 4)
end

function Game:sv_Alert(T, D, PL)
	if PL then
		for _, plr in ipairs(PL) do
			self.network:sendToClient(plr, "cl_Alert", { Text = T, Duration = D })
		end
	else
		self.network:sendToClients("cl_Alert", { Text = T, Duration = D })
	end
end

-- Auth Functions --

function Game:Authorised(player)
	if self.sv.authorised[player.id] then
		return true
	end
	return false
end

function Game:Authorise(id)
	if not self.sv.authorised[id] then
		self.sv.authorised[id] = true
		return true
	end
	return false
end

function Game:Unauthorise(id)
	if id == 1 then return false end
	if self.sv.authorised[id] then
		self.sv.authorised[id] = nil
		return true
	end
	return false
end

function Game:cl_shareMap(params)
	self.network:sendToServer("sv_shareMap", params) -- ?
end

SecureClass(Game)
