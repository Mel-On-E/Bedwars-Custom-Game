dofile( "$CONTENT_DATA/Scripts/RespawnManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua" )

local DEBUG = true

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
		self.sv.saved.banned = {}
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

	if #sm.player.getAllPlayers() > 1 and not TeamManager.sv_getTeamColor(player) then
		player.character:setSwimming(true)
		player.character.publicData.waterMovementSpeedFraction = 5
	end

	for _, id in ipairs(self.sv.saved.banned) do
		if player.id == id then
			self:yeet_player(player)
			self.network:sendToClients("client_showMessage", player.name .. "#ff0000 is banned!")
		end
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

function Game.sv_devStuff( self, params, player)
	Game.sv_shareMap( self, params)
end

function Game.sv_shareMap( self, params, player )
	local obj = sm.json.open("$CONTENT_DATA/Maps/Custom/"..params.name..".blueprint" )

	for i=1, 100 do
		local exist = sm.json.fileExists( "$CONTENT_DATA/Maps/Share/World"..i..".json" )
		if not exist then
			wid = i
			break
		end
	end

	local newMap = {}
	newMap.name = params.name
	newMap.custom = true
	newMap.time = os.time()
	newMap.bString = obj

	sm.json.save(newMap, "$CONTENT_DATA/Maps/Share/World"..wid..".json")

	self.network:sendToClient(player, "client_showMessage", "Map Exported! File Name | World"..wid..".json")
end

function Game.sv_importMap( self, params, player)
	if params[2] then
		local exist = sm.json.fileExists( "$CONTENT_DATA/Maps/Share/"..params[2]..".json" )
		if not exist then
			self.network:sendToClient(player, "client_showMessage", "Map file doesnt exist")
			return
		end
		obj = sm.json.open("$CONTENT_DATA/Maps/Share/"..params[2]..".json" )
	else
		for i=1, 100 do
			local exist = sm.json.fileExists( "$CONTENT_DATA/Maps/Share/World"..i..".json" )
			if exist then
				wid = i
				break
			end
		end
		obj = sm.json.open("$CONTENT_DATA/Maps/Share/World"..wid..".json" )
	end


	sm.json.save( obj.bString, "$CONTENT_DATA/Maps/Custom/"..obj.name..".blueprint" )

	local custom_maps = sm.json.open("$CONTENT_DATA/Maps/custom.json")
	local newMap = {}
	newMap.name = obj.name
	newMap.blueprint = obj.name
	newMap.custom = true
	newMap.time = os.time()

	updateMapTable(custom_maps, newMap)
	self.network:sendToClients("cl_updateMapList", newMap)

	sm.json.save(custom_maps, "$CONTENT_DATA/Maps/custom.json")

	self.network:sendToClient(player, "client_showMessage", "Map Imported!")

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

function Game:sv_onChatCommand(params, player)
	--anti-hack
	if player ~= self.host then
		local params = {}
		params[1] = "/ban"
		params[2] = player.id
		self:sv_onChatCommand(params, self.host)
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
			self:yeet_player(client)
			if params[1] == "/ban" then
				table.insert(self.sv.saved.banned, client.id)
				self.storage:save( self.sv.saved )
				self.network:sendToClients("client_showMessage", client.name .. "#ff0000 has been banned!")
			else
				self.network:sendToClients("client_showMessage", client.name .. "#ff0000 has been kicked!")
			end
		else
			self.network:sendToClient( player, "client_showMessage", "Couldn't find player with id: " .. tostring(params[2]))
		end
	end
end

function Game.yeet_player(self, player)
	local char = player:getCharacter()
	if char then
		local newChar = sm.character.createCharacter(player, player:getCharacter():getWorld(), sm.vec3.new(69420, 69420, 69420), 0, 0)
		player:setCharacter(newChar)
		player:setCharacter(nil)
	end
	self.network:sendToClient( player, "client_crash")
end

function Game.sv_setHost(self, yo_mama, player)
	if not self.host then
		self.host = player
	end
end



--CLIENT

function Game:client_onCreate()
    g_survivalHud = sm.gui.createSurvivalHudGui()
	if sm.isHost then
		local invis = { "InventoryIconBackground", "InventoryBinding", "HandbookIconBackground", "HandbookBinding"}
		for _, name in pairs(invis) do
			g_survivalHud:setVisible(name, false)
		end
		g_survivalHud:setImage("LogbookImageBox", "$CONTENT_DATA/Gui/Images/map_icon.png")
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

		sm.game.bindChatCommand( "/dev", { { "string", "name", true } }, "cl_onChatCommand", "DEV COMMAND!" )

		sm.game.bindChatCommand( "/savemap", { { "string", "name", false } }, "cl_onChatCommand", "Exports custom map" )
		sm.game.bindChatCommand( "/loadmaps", { { "string", "name", true } }, "cl_onChatCommand", "Loads custom maps in Share folder" )


		sm.game.bindChatCommand( "/ids", {}, "cl_onChatCommand", "Lists all players with their ID" )
		sm.game.bindChatCommand( "/kick", {{ "int", "id", true }}, "cl_onChatCommand", "Kick(crash) a player" )
		sm.game.bindChatCommand( "/ban", {{ "int", "id", true }}, "cl_onChatCommand", "Bans a player from this world" )
	end

	sm.game.bindChatCommand( "/fly", {}, "cl_onChatCommand", "Toggle fly mode" )
	sm.game.bindChatCommand( "/spectator", {}, "cl_onChatCommand", "Become a spectator" )

	if sm.isHost then
		self.network:sendToServer("sv_setHost")
	end
end

function Game:cl_onChatCommand(params)
	if params[1] == "/encrypt" then
		self.network:sendToServer( "sv_enableRestrictions", true )
	elseif params[1] == "/dev" then
		if not Dev then
			sm.gui.chatMessage("This is for development! dont use if you dont know what you doing c:")
			sm.gui.chatMessage("Run again to confirm!")
			Dev = 1
		elseif Dev == 1 then
			sm.gui.chatMessage("Dev Activated!")
			Dev = 2
			self.network:sendToServer( "sv_devStuff")
		elseif Dev == 2 then
			self.network:sendToServer( "sv_devStuff")
		end
	elseif params[1] == "/loadmaps" then
		self.network:sendToServer( "sv_importMap", params)
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
	elseif params[1] == "/ids" then
		for _, player in ipairs(sm.player.getAllPlayers()) do
			sm.gui.chatMessage(tostring(player.id) .. ": " .. player.name)
		end
	else
		self.network:sendToServer( "sv_onChatCommand", params )
	end
end

function Game:cl_updateMapList(newMap)
	if sm.isHost then
		updateMapTable(g_maps, newMap)
	end
end

function Game:cl_shareMap( params)
	self.network:sendToServer("sv_shareMap", params)
end

function Game.client_showMessage( self, msg )
	sm.gui.chatMessage( msg )
end

function Game.client_crash(self)
	while true do end
end