dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )

World = class( nil )
World.terrainScript = "$CONTENT_DATA/Scripts/terrain.lua"
World.cellMinX = -2
World.cellMaxX = 1
World.cellMinY = -2
World.cellMaxY = 1
World.worldBorder = false
World.enableSurface = false

local MAP_SPAWNPOINT = sm.vec3.zero()
local clearDebrisInterval = 40*10
local doomDepth = -69

function World:server_onCellCreated( x, y )
    if x == y and x == 0 then      
        self:server_changeMap("map1")
    end
end

function World:server_onFixedUpdate()
    --delete loose creations
    if sm.game.getCurrentTick() % clearDebrisInterval == 0 then
        for _, body in ipairs( sm.body.getAllBodies() ) do
            if body.isDynamic and body.worldPosition.z < doomDepth then
                for _, shape in ipairs( body:getShapes() ) do
                    shape:destroyShape()
                end
            end
        end
    end
end

function World.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, target, projectileUuid )
	-- Spawn loot from projectiles with loot user data
	if userData and userData.lootUid then
		local normal = -hitVelocity:normalize()
		local zSignOffset = math.min( sign( normal.z ), 0 ) * 0.5
		local offset = sm.vec3.new( 0, 0, zSignOffset )
		local lootHarvestable = sm.harvestable.createHarvestable( hvs_loot, hitPos + offset, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) ) )
		lootHarvestable:setParams( { uuid = userData.lootUid, quantity = userData.lootQuantity, epic = userData.epic  } )
	end
end

function World:server_changeMap(name)
    for _, body in ipairs( sm.body.getAllBodies() ) do
		for _, shape in ipairs( body:getShapes() ) do
			shape:destroyShape()
		end
	end

    sm.creation.importFromFile(self.world, string.format("$CONTENT_DATA/Maps/%s.blueprint", name) ,
        MAP_SPAWNPOINT)
end

function World:sv_justPlayTheGoddamnSound(params)
    self.network:sendToClients("cl_justPlayTheGoddamnSound", params)
end

function World:cl_justPlayTheGoddamnSound(params)
    local pos = params.pos or sm.localPlayer.getPlayer().character.worldPosition
    sm.effect.playEffect(params.effect, pos)
end