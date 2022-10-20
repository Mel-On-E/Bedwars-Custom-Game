dofile( "$CONTENT_DATA/Scripts/RespawnManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua" )

local DEBUG = false

Game = class( nil )
Game.enableLimitedInventory = not DEBUG
Game.enableRestrictions = not DEBUG
Game.enableFuelConsumption = not DEBUG
Game.enableAmmoConsumption = not DEBUG
Game.enableUpgrade = true

START_AREA_SPAWN_POINT = sm.vec3.new( 0, 0, 5 )
local deathDepth = -69

--SERVER

function Game.server_onCreate( self )
	print("Game.server_onCreate")
    self.sv = {}
	self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.world = sm.world.createWorld( "$CONTENT_DATA/Scripts/World.lua", "World" )
		self.storage:save( self.sv.saved )
	end

    g_respawnManager = RespawnManager()
	g_respawnManager:sv_onCreate( self.sv.saved.world )

	g_beaconManager = BeaconManager()
	g_beaconManager:sv_onCreate()

	self.sv.teamManager = sm.storage.load(69)
	if not self.sv.teamManager then
		self.sv.teamManager = sm.scriptableObject.createScriptableObject(sm.uuid.new("cb5871ae-c677-4480-94e9-31d16899d093"))
		sm.storage.save(69, self.sv.teamManager)
	end
end

function Game.server_onPlayerJoined( self, player, isNewPlayer )
    print("Game.server_onPlayerJoined")
    if isNewPlayer then
        if not sm.exists( self.sv.saved.world ) then
            sm.world.loadWorld( self.sv.saved.world )
        end
        self.sv.saved.world:loadCell( 0, 0, player, "sv_createPlayerCharacter" )

		local inventory = player:getInventory()

		sm.container.beginTransaction()

		sm.container.setItem( inventory, 0, tool_sledgehammer, 1 )
		sm.container.setItem( inventory, 1, tool_lift, 1 )

		sm.container.endTransaction()
    end
end

function Game:server_onFixedUpdate()
    --kill the fallen ones
    for _, player in ipairs(sm.player.getAllPlayers()) do
        local char = player.character
        if char and char.worldPosition.z < deathDepth then
            local params = { damage = 6969, player = player}
            sm.event.sendToPlayer( params.player, "sv_e_receiveDamage", params )

            local tumbleMod = math.sin(sm.game.getCurrentTick()/2)*420
            char:applyTumblingImpulse(sm.vec3.new(0,0,1) * tumbleMod )
        end
    end

	g_respawnManager:server_onFixedUpdate()
end

function Game.sv_createPlayerCharacter( self, world, x, y, player, params )
    local character = sm.character.createCharacter( player, world, START_AREA_SPAWN_POINT, 0, 0 )
	player:setCharacter( character )
end

function Game.sv_e_respawn( self, params )
	if params.player.character and sm.exists( params.player.character ) then
		g_respawnManager:sv_requestRespawnCharacter( params.player )
	else
		local spawnPoint = START_AREA_SPAWN_POINT
		if not sm.exists( self.sv.saved.world ) then
			sm.world.loadWorld( self.sv.saved.world )
		end
		self.sv.saved.world:loadCell( math.floor( spawnPoint.x/64 ), math.floor( spawnPoint.y/64 ), params.player, "sv_createPlayerCharacter" )
	end
end

function Game.sv_e_onSpawnPlayerCharacter( self, player )
	if player.character and sm.exists( player.character ) then
		g_respawnManager:sv_onSpawnCharacter( player )
		g_beaconManager:sv_onSpawnCharacter( player )
	else
		sm.log.warning("SurvivalGame.sv_e_onSpawnPlayerCharacter for a character that doesn't exist")
	end
end

function Game.sv_loadedRespawnCell( self, world, x, y, player )
	g_respawnManager:sv_respawnCharacter( player, world )
end

function Game.sv_enableRestrictions( self, state )
	sm.game.setEnableRestrictions( state )
	self.network:sendToClients( "client_showMessage", ( state and "Restricted" or "Unrestricted"  ) )
end

function Game.sv_setLimitedInventory( self, state )
	sm.game.setLimitedInventory( state )
	self.network:sendToClients( "client_showMessage", ( state and "Limited inventory" or "Unlimited inventory"  ) )
end

function Game.sv_toggleFly( self, params, player )
	if TeamManager.sv_getTeamColor(player) then
		self.network:sendToClient( player, "client_showMessage", "You need to be /spectator to fly" )
		return
	end

	local char = player.character
	local isSwimming = not char:isSwimming()
	char:setSwimming(isSwimming)
	char.publicData.waterMovementSpeedFraction = (isSwimming and 5 or 1)
end

function Game:sv_setSpectator(params, player)
	TeamManager.sv_setTeam(player, nil)

	self.network:sendToClients("client_showMessage", player.name .. " is now a spectator")
end

function Game:sv_bedDestroyed(color)
	local remainingPlayers = TeamManager.sv_getTeamCount(color)
	self.network:sendToClients("cl_bedDestroyed", {color = color, players = remainingPlayers})
	sm.event.sendToWorld(self.sv.saved.world, "sv_justPlayTheGoddamnSound", {effect = "bed gone"})
end

function Game:cl_bedDestroyed(params)
	local stopComplainingAboutGrammar = "players"
	if params.players == 1 then
		stopComplainingAboutGrammar = "player"
	end

	sm.gui.chatMessage(params.color .. "Bed destroyed! (" ..
		"#ffffff" .. params.players .. " " .. stopComplainingAboutGrammar .. " left" .. params.color .. ")"
	)

	sm.gui.displayAlertText(params.color .. "Bed destroyed!")
end

function Game.sv_exportMap( self, params, player )
	local obj = sm.json.parseJsonString( sm.creation.exportToString( params.body ) )
	sm.json.save( obj, "$CONTENT_DATA/Maps/Custom/"..params.name..".blueprint" )

	--update custom.json
	local custom_maps = sm.json.open("$CONTENT_DATA/Maps/custom.json")
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

function updateMapTable(t, newMap)
	local newKey = #t + 1
	for key, map in ipairs(t) do
		if map.name == newMap.name then
			newKey = key
		end
	end
	t[newKey] = newMap
end



--CLIENT

function Game:client_onCreate()
    g_survivalHud = sm.gui.createSurvivalHudGui()
	if sm.isHost then
		local invis = { "InventoryIconBackground", "InventoryBinding", "HandbookIconBackground", "HandbookBinding"}
		for _, name in pairs(invis) do
			g_survivalHud:setVisible(name, false)
		end
		g_survivalHud:setImage("LogbookImageBox", "$CONTENT_DATA/Gui/Images/Map1.png")
	else
		g_survivalHud:setVisible("BindingPanel", false)
	end

    if g_respawnManager == nil then
		assert( not sm.isHost )
		g_respawnManager = RespawnManager()
	end
	g_respawnManager:cl_onCreate()

	if g_beaconManager == nil then
		assert( not sm.isHost )
		g_beaconManager = BeaconManager()
	end
	g_beaconManager:cl_onCreate()

	if sm.isHost then
		sm.game.bindChatCommand( "/limited", {}, "cl_onChatCommand", "Use the limited inventory" )
		sm.game.bindChatCommand( "/unlimited", {}, "cl_onChatCommand", "Use the unlimited inventory" )
		sm.game.bindChatCommand( "/encrypt", {}, "cl_onChatCommand", "Restrict interactions in all warehouses" )
		sm.game.bindChatCommand( "/decrypt", {}, "cl_onChatCommand", "Unrestrict interactions in all warehouses" )

		sm.game.bindChatCommand( "/savemap", { { "string", "name", false } }, "cl_onChatCommand", "Exports custom map" )
	end

	sm.game.bindChatCommand( "/fly", {}, "cl_onChatCommand", "Toggle fly mode" )
	sm.game.bindChatCommand( "/spectator", {}, "cl_onChatCommand", "Become a spectator" )
end

function Game:cl_onChatCommand(params)
	if params[1] == "/encrypt" then
		self.network:sendToServer( "sv_enableRestrictions", true )
	elseif params[1] == "/decrypt" then
		self.network:sendToServer( "sv_enableRestrictions", false )
	elseif params[1] == "/unlimited" then
		self.network:sendToServer( "sv_setLimitedInventory", false )
	elseif params[1] == "/limited" then
		self.network:sendToServer( "sv_setLimitedInventory", true )
	elseif params[1] == "/fly" then
		self.network:sendToServer( "sv_toggleFly")
	elseif params[1] == "/spectator" then
		self.network:sendToServer( "sv_setSpectator")
	elseif params[1] == "/savemap" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid and rayCastResult.type == "body" then
			local importParams = {
				name = params[2],
				body = rayCastResult:getBody()
			}
			self.network:sendToServer( "sv_exportMap", importParams )
		else
			sm.gui.chatMessage("#ff0000Look at the map while saving it")
		end
	end
end

function Game:cl_updateMapList(newMap)
	if sm.isHost then
		updateMapTable(g_maps, newMap)
	end
end

function Game.client_showMessage( self, msg )
	sm.gui.chatMessage( msg )
end
