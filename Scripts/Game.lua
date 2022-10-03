dofile( "$SURVIVAL_DATA/Scripts/game/managers/RespawnManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua" )

Game = class( nil )

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
end

function Game.server_onPlayerJoined( self, player, isNewPlayer )
    print("Game.server_onPlayerJoined")
    if isNewPlayer then
        if not sm.exists( self.sv.saved.world ) then
            sm.world.loadWorld( self.sv.saved.world )
        end
        self.sv.saved.world:loadCell( 0, 0, player, "sv_createPlayerCharacter" )
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




--CLIENT

function Game:client_onCreate()
    g_survivalHud = sm.gui.createSurvivalHudGui()
    g_survivalHud:setVisible("BindingPanel", false)

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
end