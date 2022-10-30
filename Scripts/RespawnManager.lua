dofile( "$SURVIVAL_DATA/Scripts/game/managers/RespawnManager.lua" )

dofile("$CONTENT_DATA/Scripts/Utils/Network.lua")

OldRespawnManager = class(RespawnManager)

function RespawnManager:sv_onCreate(overworld)
    OldRespawnManager.sv_onCreate(self, overworld)

    self.sv.flyGoBrrr = {}
end

function RespawnManager.sv_respawnCharacter( self, player, world )
    local spawnPosition = g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT
	local spawnRotation = sm.quat.identity()

	local playerBed = self:sv_getPlayerBed( player )
	if playerBed then
		-- Spawn at the bed's position if it exists, otherwise use its last known position.
		if playerBed.shape and sm.exists( playerBed.shape ) then
			spawnPosition = playerBed.shape.worldPosition
			spawnRotation = playerBed.shape.worldRotation
		else
			spawnPosition = playerBed.position
			spawnRotation = playerBed.rotation
		end
	else
		spawnPosition, spawnRotation = self:sv_getSpawner( player.character )
	end

    local team = TeamManager.sv_getTeamColor(player)
    if team and not TeamManager.sv_isBedExisting(player) then
        spawnPosition = TeamManager.sv_getTeamSpawn(team)
    end

	spawnPosition = spawnPosition + sm.vec3.new( 0, 0, player.character:getHeight() * 0.5 )
	local yaw = 0
	local pitch = 0
	local spawnDirection = spawnRotation * sm.vec3.new( 0, 0, 1 )
	yaw = math.atan2( spawnDirection.y, spawnDirection.x ) - math.pi/2
	local newCharacter = sm.character.createCharacter( player, world, spawnPosition, yaw, pitch )
	player:setCharacter( newCharacter )

    if not TeamManager.sv_getTeamColor(player) then
        local params = {
            time = sm.game.getCurrentTick() + 2,
            player = player
        }
        self.sv.flyGoBrrr[#self.sv.flyGoBrrr+1] = params
    end
end

function RespawnManager:server_onFixedUpdate()
    for id, flyThingy in pairs(self.sv.flyGoBrrr) do
        if flyThingy.time < sm.game.getCurrentTick() then
            self.sv.flyGoBrrr[id] = nil
            local char = flyThingy.player.character
            char:setSwimming(true)
            char.publicData.waterMovementSpeedFraction = 5
        end
    end
end

SecureClass(RespawnManager)