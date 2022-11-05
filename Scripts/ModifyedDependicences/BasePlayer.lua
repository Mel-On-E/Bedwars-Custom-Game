dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_camera.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

BasePlayer = class( nil )

local FireDamage = 10
local FireDamageCooldown = 40
local PoisonDamage = 10
local PoisonDamageCooldown = 40

local StopTumbleTimerTickThreshold = 1.0 * 40 -- Time to keep tumble active after speed is below threshold
local MaxTumbleTimerTickThreshold = 20.0 * 40 -- Maximum time to keep tumble active before timing out
local TumbleResistTickTime = 3.0 * 40 -- Time that the player will resist tumbling after timing out
local MaxTumbleImpulseSpeed = 35
local RecentTumblesTickTimeInterval = 30.0 * 40 -- Time frame to count amount of tumbles in a row
local MaxRecentTumbles = 3

local CameraState =
{
	DEFAULT = 1,
	TUMBLING = 2,
	INTERACTABLE = 3,
	CUTSCENE = 4,
	CUSTOM = 5
}

function BasePlayer.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.inChemical = false
		self.sv.saved.inOil = false
		self.storage:save( self.sv.saved )
	end
	self:sv_init()
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.server_onRefresh( self )
	self:sv_init()
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.sv_init( self )
	self.sv.damageCooldown = Timer()
	self.sv.damageCooldown:start( 3.0 * 40 )

	self.sv.impactCooldown = Timer()
	self.sv.impactCooldown:start( 3.0 * 40 )

	self.sv.fireDamageCooldown = Timer()
	self.sv.fireDamageCooldown:start()

	self.sv.poisonDamageCooldown = Timer()
	self.sv.poisonDamageCooldown:start()

	self.sv.tumbleReset = Timer()
	self.sv.tumbleReset:start( StopTumbleTimerTickThreshold )

	self.sv.maxTumbleTimer = Timer()
	self.sv.maxTumbleTimer:start( MaxTumbleTimerTickThreshold )

	self.sv.resistTumbleTimer = Timer()
	self.sv.resistTumbleTimer:start( TumbleResistTickTime )
	self.sv.resistTumbleTimer.count = TumbleResistTickTime

	self.sv.recentTumbles = {}
end

function BasePlayer.client_onCreate( self )
	self.cl = {}
	self:cl_init()
	self.cl.cameraState = CameraState.DEFAULT
	self.player.clientPublicData = {}
end

function BasePlayer.client_onRefresh( self )
	self:cl_init()
	sm.gui.hideGui( false )
	sm.camera.setCameraState( sm.camera.state.default )
	sm.localPlayer.setLockedControls( false )
end

function BasePlayer.cl_init( self ) end

function BasePlayer.cl_n_onEvent( self, data )

	local function getCharParam()
		if self.player:isMale() then
			return 1
		else
			return 2
		end
	end

	local function playSingleHurtSound( effect, pos, damage )
		local params = {
			["char"] = getCharParam(),
			["damage"] = damage
		}
		sm.effect.playEffect( effect, pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
	end

	if data.event == "drown" then
		playSingleHurtSound( "Mechanic - HurtDrown", data.pos, data.damage )
	elseif data.event == "fatigue" then
		playSingleHurtSound( "Mechanic - Hurthunger", data.pos, data.damage)
	elseif data.event == "shock" then
		playSingleHurtSound( "Mechanic - Hurtshock", data.pos, data.damage )
	elseif data.event == "impact" then
		playSingleHurtSound( "Mechanic - Hurt", data.pos, data.damage )
	elseif data.event == "fire" then
		playSingleHurtSound( "Mechanic - HurtFire", data.pos, data.damage )
	elseif data.event == "poison" then
		playSingleHurtSound( "Mechanic - Hurtpoision", data.pos, data.damage )
	end
end

function BasePlayer.client_onClientDataUpdate( self, data )
	if sm.localPlayer.getPlayer() == self.player then
		self.cl.inChemical = data.inChemical
		self.cl.inOil = data.inOil
	end
end

function BasePlayer.client_onUpdate( self, dt )
	if self.player == sm.localPlayer.getPlayer() then
		self:cl_localPlayerUpdate( dt )
	end
end

function BasePlayer.cl_localPlayerUpdate( self, dt )
	local character = self.player:getCharacter()

	local alwaysUpdate = false
	local wantedCameraState = CameraState.DEFAULT
	local wantedCameraData = {
		hideGui = false,
		cameraState = sm.camera.state.default,
		lockedControls = false }

	if self.player.clientPublicData.cutsceneCameraData then
		wantedCameraState = CameraState.CUTSCENE
		wantedCameraData = self.player.clientPublicData.cutsceneCameraData
		alwaysUpdate = true
	elseif self.player.clientPublicData.interactableCameraData then
		wantedCameraState = CameraState.INTERACTABLE
		wantedCameraData = self.player.clientPublicData.interactableCameraData
		alwaysUpdate = true
	elseif character and character:isTumbling() then
		wantedCameraState = CameraState.TUMBLING
		wantedCameraData.cameraState = sm.camera.state.forcedTP
	elseif self.player.clientPublicData.customCameraData then
		wantedCameraState = CameraState.CUSTOM
		wantedCameraData = self.player.clientPublicData.customCameraData
		alwaysUpdate = true
		self.player.clientPublicData.customCameraData = nil
	end

	if self.cl.cameraState ~= wantedCameraState or alwaysUpdate then
		self.cl.cameraState = wantedCameraState
		if wantedCameraData.hideGui ~= nil then
			sm.gui.hideGui( wantedCameraData.hideGui )
		end
		if wantedCameraData.cameraState then
			sm.camera.setCameraState( wantedCameraData.cameraState )
		end
		if wantedCameraData.cameraPosition then
			sm.camera.setPosition( wantedCameraData.cameraPosition )
		end
		if wantedCameraData.cameraRotation then
			sm.camera.setRotation( wantedCameraData.cameraRotation )
		end
		if wantedCameraData.cameraDirection then
			sm.camera.setDirection( wantedCameraData.cameraDirection )
		end
		if wantedCameraData.cameraFov then
			sm.camera.setFov( wantedCameraData.cameraFov )
		end
		if wantedCameraData.lockedControls ~= nil then
			sm.localPlayer.setLockedControls( wantedCameraData.lockedControls )
		end
	end

	if character and character:isSwimming() and not self.cl.inChemical and not self.cl.inOil then
		self:cl_n_fillWater()
	end
end

function BasePlayer.client_onInteract( self, character, state ) end

function BasePlayer.server_onFixedUpdate( self, dt )
	local character = self.player:getCharacter()
	if character then
		self:sv_updateTumbling()
	end

	self.sv.damageCooldown:tick()
	self.sv.impactCooldown:tick()
	self.sv.fireDamageCooldown:tick()
	self.sv.poisonDamageCooldown:tick()
end

function BasePlayer.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if type( attacker ) == "Unit" or ( type( attacker ) == "Shape" and isTrapProjectile( projectileUuid ) ) then
		self:sv_takeDamage( damage, "shock" )
	end
	if self.player.character:isTumbling() then
		ApplyKnockback( self.player.character, hitVelocity:normalize(), 2000 )
	end

	if projectileUuid == projectile_water  then
		self.network:sendToClient( self.player, "cl_n_fillWater" )
	end






end

function BasePlayer.cl_n_fillWater( self )
	if self.player == sm.localPlayer.getPlayer() then
		if sm.localPlayer.getActiveItem() == obj_tool_bucket_empty then
			local params = {}
			if sm.game.getLimitedInventory() then
				params.playerInventory = sm.localPlayer.getInventory()
			else
				params.playerInventory = sm.localPlayer.getHotbar()
			end
			params.slotIndex = sm.localPlayer.getSelectedHotbarSlot()
			params.previousUid = obj_tool_bucket_empty
			params.nextUid = obj_tool_bucket_water
			params.previousQuantity = 1
			params.nextQuantity = 1
			self.network:sendToServer( "server_n_exchangeItem", params )
		end
	end
end

function BasePlayer.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( attacker ) then
		return
	end

	print("'Player' took melee damage")
	if type( attacker ) == "Unit" then
		self:sv_takeDamage( damage, "impact" )
	else
		local playerCharacter = self.player.character
		if sm.exists( playerCharacter ) then
			self.network:sendToClients( "cl_n_onEvent", { event = "impact", pos = playerCharacter.worldPosition, damage = damage * 0.01 } )
		end
	end

	-- Melee impulse
	if attacker then
		ApplyKnockback( self.player.character, hitDirection, power )
	end

end

function BasePlayer.server_onExplosion( self, center, destructionLevel )
	print("'Player' took explosion damage")
	self:sv_takeDamage( destructionLevel * 2, "impact" )
	if self.player.character:isTumbling() then
		local knockbackDirection = ( self.player.character.worldPosition - center ):normalize()
		ApplyKnockback( self.player.character, knockbackDirection, 5000 )
	end
end

function BasePlayer.sv_startTumble( self, tumbleTickTime )
	if not self.player.character:isDowned() and self.sv.resistTumbleTimer:done() then
		local currentTick = sm.game.getCurrentTick()
		self.sv.recentTumbles[#self.sv.recentTumbles+1] = currentTick
		local recentTumbles = {}
		for _, tumbleTickTimestamp in ipairs( self.sv.recentTumbles ) do
			if tumbleTickTimestamp >= currentTick - RecentTumblesTickTimeInterval then
				recentTumbles[#recentTumbles+1] = tumbleTickTimestamp
			end
		end
		self.sv.recentTumbles = recentTumbles
		if #self.sv.recentTumbles > MaxRecentTumbles then
			-- Too many tumbles in quick succession, gain temporary tumble immunity
			self.player.character:setTumbling( false )
			self.sv.maxTumbleTimer:reset()
			self.sv.tumbleReset:reset()
			self.sv.resistTumbleTimer:reset()
		else
			self.player.character:setTumbling( true )
			if tumbleTickTime then
				self.sv.tumbleReset:start( tumbleTickTime )
			else
				self.sv.tumbleReset:start( StopTumbleTimerTickThreshold )
			end
			return true
		end
	end
	return false
end

function BasePlayer.sv_updateTumbling( self )
	if not self.sv.resistTumbleTimer:done() then
		self.sv.resistTumbleTimer:tick()
	end

	if not self.player.character:isDowned() then
		if self.player.character:isTumbling() then
			self.sv.maxTumbleTimer:tick()
			if self.sv.maxTumbleTimer:done() then
				-- Stuck in the tumble state for too long, gain temporary tumble immunity
				self.player.character:setTumbling( false )
				self.sv.maxTumbleTimer:reset()
				self.sv.tumbleReset:reset()
				self.sv.resistTumbleTimer:reset()
			else
				local tumbleVelocity = self.player.character:getTumblingLinearVelocity()
				if tumbleVelocity:length() < 1.0 then
					self.sv.tumbleReset:tick()

					if self.sv.tumbleReset:done() then
						self.player.character:setTumbling( false )
						self.sv.tumbleReset:reset()
					end
				else
					self.sv.tumbleReset:reset()
				end
			end
		end
	end
end

function BasePlayer.server_n_exchangeItem( self, params )
	if sm.container.beginTransaction() then
		sm.container.spendFromSlot( params.playerInventory, params.slotIndex, params.previousUid, params.previousQuantity, true )
		sm.container.collectToSlot( params.playerInventory, params.slotIndex, params.nextUid, params.nextQuantity, true )
		sm.container.endTransaction()
	end
end

function BasePlayer.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal  )
	if not self.player.character or not sm.exists( self.player.character ) then
		return
	end

	if not self.sv.impactCooldown:done() then
		return
	end

	local collisionDamageMultiplier = 0.25
	local maxHp = 100
	if self.sv.saved.stats and self.sv.saved.stats.maxhp then
		maxHp = self.sv.saved.stats.maxhp
	end
	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.player.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, maxHp / collisionDamageMultiplier, 24 )
	damage = damage * collisionDamageMultiplier
	if damage > 0 or tumbleTicks > 0 then
		self.sv.impactCooldown:start( 0.25 * 40 )
	end
	if damage > 0 then
		print("'Player' took", damage, "collision damage")
		self:sv_takeDamage( damage, "shock" )
	end
	if g_enableCollisionTumble then
		if tumbleTicks > 0 then
			if self:sv_startTumble( tumbleTicks ) then
				-- Limit tumble velocity
				if tumbleVelocity:length2() > MaxTumbleImpulseSpeed * MaxTumbleImpulseSpeed then
					tumbleVelocity = tumbleVelocity:normalize() * MaxTumbleImpulseSpeed
				end
				self.player.character:applyTumblingImpulse( tumbleVelocity * self.player.character.mass )
				if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
					sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
				end
			end
		end
	end
end

function BasePlayer.sv_e_staminaSpend( self, stamina ) end

function BasePlayer.sv_e_receiveDamage( self, damageData )
	self:sv_takeDamage( damageData.damage )
end

function BasePlayer.sv_takeDamage( self, damage, source ) end

function BasePlayer.sv_e_respawn( self ) end

function BasePlayer.sv_startFadeToBlack( self, param )
	self.network:sendToClient( self.player, "cl_n_startFadeToBlack", { duration = param.duration, timeout = param.timeout } )
end

function BasePlayer.sv_endFadeToBlack( self, param )
	self.network:sendToClient( self.player, "cl_n_endFadeToBlack", { duration = param.duration } )
end

function BasePlayer.cl_e_startFadeToBlack( self, param )
	self:cl_n_startFadeToBlack( param )
end

function BasePlayer.cl_e_endFadeToBlack( self, param )
	self:cl_n_endFadeToBlack( param )
end

function BasePlayer.cl_n_startFadeToBlack( self, param )
	sm.gui.startFadeToBlack( param.duration, param.timeout )
end

function BasePlayer.cl_n_endFadeToBlack( self, param )
	sm.gui.endFadeToBlack( param.duration )
end

function BasePlayer.sv_e_onSpawnCharacter( self ) end

function BasePlayer.sv_e_debug( self, params ) end

function BasePlayer.sv_e_eat( self, edibleParams ) end

function BasePlayer.sv_e_feed( self, params ) end

function BasePlayer.sv_e_setRefiningState( self, params )
	local userPlayer = params.user:getPlayer()
	if userPlayer then
		if params.state == true then
			userPlayer:sendCharacterEvent( "refine" )
		else
			userPlayer:sendCharacterEvent( "refineEnd" )
		end
	end
end

function BasePlayer.sv_e_onLoot( self, params )
	self.network:sendToClient( self.player, "cl_n_onLoot", params )
end

function BasePlayer.cl_n_onLoot( self, params )
	local color
	if params.uuid then
		color = sm.shape.getShapeTypeColor( params.uuid )
	end
	local effectName = params.effectName or "Loot - Pickup"
	sm.effect.playEffect( effectName, params.pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), { ["Color"] = color } )
end

function BasePlayer.sv_e_onMsg( self, msg )
	self.network:sendToClient( self.player, "cl_n_onMsg", msg )
end

function BasePlayer.cl_n_onMsg( self, msg )
	sm.gui.displayAlertText( msg )
end

function BasePlayer.cl_n_onEffect( self, params )
	if params.host then
		sm.effect.playHostedEffect( params.name, params.host, params.boneName, params.parameters )
	else
		sm.effect.playEffect( params.name, params.position, params.velocity, params.rotation, params.scale, params.parameters )
	end
end

function BasePlayer.sv_e_onStayPesticide( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
end

function BasePlayer.sv_e_onEnterFire( self )
	if self.sv.fireDamageCooldown:done() then
		self:sv_takeDamage( FireDamage, "fire" )
		self.sv.fireDamageCooldown:start( FireDamageCooldown )
	end
end

function BasePlayer.sv_e_onStayFire( self )
	if self.sv.fireDamageCooldown:done() then
		self:sv_takeDamage( FireDamage, "fire" )
		self.sv.fireDamageCooldown:start( FireDamageCooldown )
	end
end

function BasePlayer.sv_e_onEnterChemical( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
	self.sv.saved.inChemical = true
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.sv_e_onStayChemical( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
end

function BasePlayer.sv_e_onExitChemical( self )
	self.sv.saved.inChemical = false
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.sv_e_onEnterOil( self )
	self.sv.saved.inOil = true
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.sv_e_onExitOil( self )
	self.sv.saved.inOil = false
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.client_onCancel( self )
	local myPlayer = sm.localPlayer.getPlayer()
	local myCharacter = myPlayer and myPlayer.character or nil
	if sm.exists( myCharacter ) then
		sm.event.sendToCharacter( myCharacter, "cl_e_onCancel" )
	end
end

function BasePlayer.cl_n_onMessage( self, params )
	local message = params.message or ""
	local displayTime = params.displayTime or 2
	sm.gui.displayAlertText( message, displayTime )
end