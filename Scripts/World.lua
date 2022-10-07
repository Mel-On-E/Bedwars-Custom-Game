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
local stackCheckInterval = 50
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
    if sm.game.getCurrentTick() % stackCheckInterval == 0 then
        
    end
    


end

--local loot = { uuid = sm.uuid.new("c5e56da5-bc3f-4519-91c2-b307d36e15aa"), quantity = amount }
--SpawnLoot( phrv, loot, phrv.worldPosition)


function World:resetStackCheckTime()
	stackCheckInterval = sm.game.getCurrentTick() + 5
end

function World:makeHarvestables( hitPos, offset, userData)
    local succ, trigger = sm.physics.spherecast(hitPos, hitPos + sm.vec3.new(0,0,0.001), 1, nil, 512)
    lastQuantity = 0
    local harvest = trigger:getHarvestable()
    if sm.exists(harvest) then
        local succ, trigger = sm.physics.spherecast(hitPos, hitPos + sm.vec3.new(0,0,0.001), 1, nil, 512)
        lastQuantity = 0
        local harvest = trigger:getHarvestable()
        if harvest:getPublicData().uuid == sm.uuid.new("c5e56da5-bc3f-4519-91c2-b307d36e15aa") then
            if not harvest:getPublicData().marked then
                harvest:setParams( { uuid = userData.lootUid, quantity = userData.lootQuantity, epic = userData.epic, marked = true })
                lastQuantity = harvest:getPublicData().quantity
                harvest:destroy()
            end
            local lootHarvestable = sm.harvestable.createHarvestable( hvs_loot, hitPos + offset, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) ) )
            lootHarvestable:setParams( { uuid = userData.lootUid, quantity = lastQuantity + 1, epic = userData.epic  } )
        elseif harvest:getPublicData().uuid == sm.uuid.new("edd445cc-c298-4ce3-9a58-745c1bee1bc7") then
            if not harvest:getPublicData().marked then
                harvest:setParams( { uuid = userData.lootUid, quantity = userData.lootQuantity, epic = userData.epic, marked = true })
                lastQuantity = harvest:getPublicData().quantity
                harvest:destroy()
            end
            local lootHarvestable = sm.harvestable.createHarvestable( hvs_loot, hitPos + offset, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) ) )
            lootHarvestable:setParams( { uuid = userData.lootUid, quantity = lastQuantity + 1, epic = userData.epic  } )
        end
    else
        local lootHarvestable = sm.harvestable.createHarvestable( hvs_loot, hitPos + offset, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) ) )
        lootHarvestable:setParams( { uuid = userData.lootUid, quantity = userData.lootQuantity, epic = userData.epic  } )
    end
    --elseif userData.lootUid == sm.uuid.new("edd445cc-c298-4ce3-9a58-745c1bee1bc7") then
end


function World.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, target, projectileUuid )
	-- Spawn loot from projectiles with loot user data
    if userData.lootUid == sm.uuid.new("c5e56da5-bc3f-4519-91c2-b307d36e15aa") or userData.lootUid == sm.uuid.new("edd445cc-c298-4ce3-9a58-745c1bee1bc7") then
        if userData and userData.lootUid then
            local normal = -hitVelocity:normalize()
            local zSignOffset = math.min( sign( normal.z ), 0 ) * 0.5
            local offset = sm.vec3.new( 0, 0, zSignOffset )
            pcall(World.makeHarvestables, self, hitPos, offset, userData)
        end
    else
        if userData and userData.lootUid then
            print(userData.lootUid)
            local normal = -hitVelocity:normalize()
            local zSignOffset = math.min( sign( normal.z ), 0 ) * 0.5
            local offset = sm.vec3.new( 0, 0, zSignOffset )
            local lootHarvestable = sm.harvestable.createHarvestable( hvs_loot, hitPos + offset, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) ) )
            lootHarvestable:setParams( { uuid = userData.lootUid, quantity = userData.lootQuantity, epic = userData.epic  } )
        end
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