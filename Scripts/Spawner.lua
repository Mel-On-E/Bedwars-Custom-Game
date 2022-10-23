dofile "$SURVIVAL_DATA/Scripts/game/survival_items.lua"
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

Spawner = class( nil )
Spawner.maxParentCount = 1
Spawner.connectionInput = sm.interactable.connectionType.logic
Spawner.poseWeightCount = 1

function Spawner.server_onCreate( self )
	self:resetSpawnTime()
end

function Spawner:resetSpawnTime()
	self.spawnTime = sm.game.getCurrentTick() + self.data.spawnInterval
end

function Spawner.server_onFixedUpdate( self, timeStep )
	local parent = self.interactable:getSingleParent()
	if parent then
		self.interactable.active = parent.active
	end

	if self.interactable.active and self.spawnTime <= sm.game.getCurrentTick() then
		local lootList = {}

		for _, drop in ipairs(self.data.drops) do
			for uuid, chance in pairs(drop) do
				if math.random(1, chance) == 1 then
					lootList[#lootList+1] = { uuid = sm.uuid.new(uuid), quantity = 1 }
				end
			end
		end

		SpawnLoot( self.shape, lootList, self.shape.worldPosition + sm.vec3.new( 0, 0, 1.0 ) )
		self:resetSpawnTime()
	end
end

function Spawner:sv_toggle()
	self.interactable.active = not self.interactable.active
	print("active?")
end

function Spawner:client_canInteract()
	if self.interactable:getSingleParent() then
		return false
	end
	return true
end

function Spawner:client_onInteract(char, state)
	if state then
		self.network:sendToServer("sv_toggle")
	end
end

function Spawner:client_onUpdate()
	self.interactable:setPoseWeight(0, self.interactable.active and 1 or 0)
end