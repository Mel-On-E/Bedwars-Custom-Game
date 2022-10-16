dofile( "$SURVIVAL_DATA/Scripts/game/managers/RespawnManager.lua" )

OldRespawnManager = class(RespawnManager)

function RespawnManager:sv_onCreate(overworld)
    OldRespawnManager.sv_onCreate(self, overworld)

    self.sv.flyGoBrrr = {}
end

function RespawnManager.sv_respawnCharacter( self, player, world )
    OldRespawnManager.sv_respawnCharacter(self, player, world)

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