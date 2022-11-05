dofile("$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua")

World = class(nil)
World.terrainScript = "$CONTENT_DATA/Scripts/terrain.lua"
World.cellMinX = -2
World.cellMaxX = 1
World.cellMinY = -2
World.cellMaxY = 1
World.worldBorder = false
World.enableSurface = false

local MAP_SPAWNPOINT = sm.vec3.zero()
local clearDebrisInterval = 40 * 10
local doomDepth = -69

function World.server_onCreate(self)
    local data = {
        minX = self.cellMinX or 0,
        maxX = self.cellMaxX or 0,
        minY = self.cellMinY or 0,
        maxY = self.cellMaxY or 0,
        world = self.world
    }
    sm.event.sendToGame("sv_loadTerrain", data)
end

function World:server_onCellCreated(x, y)
    if x == y and x == 0 then
        self:sv_changeMap("Factory4")
    end
end

function World:server_onFixedUpdate()
    --delete loose creations
    if sm.game.getCurrentTick() % clearDebrisInterval == 0 then
        for _, body in ipairs(sm.body.getAllBodies()) do
            if body.isDynamic and body.worldPosition.z < doomDepth then
                for _, shape in ipairs(body:getShapes()) do
                    shape:destroyShape()
                end
            end
        end
    end
end

--local loot = { uuid = sm.uuid.new("c5e56da5-bc3f-4519-91c2-b307d36e15aa"), quantity = amount }
--SpawnLoot( phrv, loot, phrv.worldPosition)
function World:sv_stack_loot(hitPos, offset, userData)
    local maxStackSize = 10
    local quantity = userData.lootQuantity

    local nearbyHarvestables = sm.physics.getSphereContacts(hitPos, 1)
    for _, harvestable in pairs(nearbyHarvestables.harvestables) do
        local isLoot = sm.exists(harvestable) and
            (harvestable:getPublicData() and harvestable:getPublicData().uuid == userData.lootUid)
        if isLoot then
            if harvestable:getPublicData().quantity < maxStackSize then
                quantity = quantity - (maxStackSize - harvestable:getPublicData().quantity)

                local pos = ((hitPos + offset) + harvestable.worldPosition) / 2
                local newLoot = sm.harvestable.createHarvestable(hvs_loot, pos,
                    sm.vec3.getRotation(sm.vec3.new(0, 1, 0), sm.vec3.new(0, 0, 1)))

                newLoot:setParams({ uuid = userData.lootUid,
                    quantity = maxStackSize + math.max(0, quantity),
                    epic = userData.epic })

                harvestable:destroy()

                if quantity <= 0 then
                    break
                end
            end
        end
    end

    if quantity > 0 then
        local newLoot = sm.harvestable.createHarvestable(hvs_loot, hitPos + offset,
            sm.vec3.getRotation(sm.vec3.new(0, 1, 0), sm.vec3.new(0, 0, 1)))
        newLoot:setParams({ uuid = userData.lootUid, quantity = quantity, epic = userData.epic })
    end
end

function World.server_onProjectile(self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, target,
                                   projectileUuid)
    -- Spawn loot from projectiles with loot user data
    if userData and userData.lootUid then
        local normal = -hitVelocity:normalize()
        local zSignOffset = math.min(sign(normal.z), 0) * 0.5
        local offset = sm.vec3.new(0, 0, zSignOffset)
        self:sv_stack_loot(hitPos, offset, userData)
    end
end

function World:sv_changeMap(name)
    --reset inventories
    for _, player in ipairs(sm.player.getAllPlayers()) do
        local inventory = player:getInventory()

        sm.container.beginTransaction()
        for i = 0, 39, 1 do
            if i == 0 then
                sm.container.setItem(inventory, i, tool_sledgehammer, 1)
            elseif i == 1 then
                sm.container.setItem(inventory, i, tool_lift, 1)
            else
                sm.container.setItem(inventory, i, sm.uuid.getNil(), 0)
            end
        end
        sm.container.endTransaction()
    end

    --clear harvestables(loot)
    for x = -2, 2, 1 do
        for y = -2, 2, 1 do
            for _, harvestable in ipairs(sm.cell.getHarvestables(x, y)) do
                harvestable:destroy()
            end
        end
    end

    --clear bodies
    for _, body in ipairs(sm.body.getAllBodies()) do
        for _, shape in ipairs(body:getShapes()) do
            shape:destroyShape()
        end
    end

    --import new map
    sm.creation.importFromFile(self.world, string.format("$CONTENT_DATA/Maps/%s.blueprint", name),
        MAP_SPAWNPOINT)

    --remove helper blocks
    sm.event.sendToWorld(self.world, "sv_remove_helper_blocks")
end

function World:sv_remove_helper_blocks()
    local blk_map_building = sm.uuid.new("fada88d2-0b6e-4fdd-9fa6-5fd4c6098fd6")

    for _, body in ipairs(sm.body.getAllBodies()) do
        for _, shape in ipairs(body:getShapes()) do
            if shape.uuid == blk_map_building then
                shape:destroyShape()
            end
        end
    end
end

function World:sv_justPlayTheGoddamnSound(params)
    self.network:sendToClients("cl_justPlayTheGoddamnSound", params)
end

function World:cl_justPlayTheGoddamnSound(params)
    local pos = params.pos or sm.localPlayer.getPlayer().character.worldPosition
    sm.effect.playEffect(params.effect, pos)
end
