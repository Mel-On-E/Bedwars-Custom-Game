TeamManager = class()
TeamManager.isSaveObject = true

function TeamManager:server_onCreate()
    if not g_teamManager then
        g_teamManager = self

        self.sv = self.storage:load()

        if self.sv == nil then
            self.sv = {}
            self.sv.teams = {}
            self.sv.beds = {}
            self.sv.teamSpawnpoints = {}
        end

        self.init = true
    end
end

function TeamManager:server_onFixedUpdate()
    if self.sv.updateClientData then
        self.sv.updateClientData = false
        self.network:setClientData(self.sv)
    end

    if self.init then
        --set fly state on init
        for _, player in ipairs(sm.player.getAllPlayers()) do
            if player.character then
                self.init = false

                if not TeamManager.sv_getTeamColor(player) then
                    player.character:setSwimming(true)
                    player.character.publicData.waterMovementSpeedFraction = 5
                end
            end
        end
    end
end

function TeamManager.sv_setTeam(player, color)
	g_teamManager.sv.teams[player.id] = color
    g_teamManager.storage:save(g_teamManager.sv)
    g_teamManager.sv.updateClientData = true

    local char = player.character
    char:setSwimming(not color)
	char.publicData.waterMovementSpeedFraction = (not color and 5) or 1
end

function TeamManager.sv_setBed(color, exists, shape)
	g_teamManager.sv.beds[color] = exists or yo_mama
    g_teamManager.sv.teamSpawnpoints[color] = (sm.exists(shape) and shape.worldPosition) or g_teamManager.sv.teamSpawnpoints[color]
    g_teamManager.storage:save(g_teamManager.sv)
end

function TeamManager.sv_isBedExisting(color)
	return g_teamManager.sv.beds[color]
end

function TeamManager:sv_updateClientData()
    self.sv.updateClientData = true
end

function TeamManager.sv_getTeamColor(player)
    return g_teamManager.sv.teams[player.id]
end

function TeamManager.sv_getTeamCount(color)
    local count = 0
    for id, team in pairs(g_teamManager.sv.teams) do
        if team == color then
            count = count + 1
        end
    end
    return count
end

function TeamManager.sv_getTeamsCount()
    local teams = {}
    for id, team in pairs(g_teamManager.sv.teams) do
        if not team then
            goto continue
        end

        for _, countedTeam in ipairs(teams) do
            if team == countedTeam then
               goto continue
            end
        end
        teams[#teams+1] = team
        ::continue::
    end
    return #teams
end

function TeamManager.sv_getLastTeam()
    for id, team in pairs(g_teamManager.sv.teams) do
        if team then
            return team
        end
    end
end

function TeamManager.sv_getTeamSpawn(color)
    return g_teamManager.sv.teamSpawnpoints[color]
end






function TeamManager:client_onCreate()
    self.cl = {}
    self.cl.teams = {}

    if not g_teamManager then
        g_teamManager = self
    end

    self.network:sendToServer("sv_updateClientData")
end

function TeamManager:client_onClientDataUpdate(clientData, channel)
	self.cl.teams = clientData.teams
end

function TeamManager:client_onFixedUpdate()
    local ownTeam = self.cl.teams[sm.localPlayer.getPlayer().id]

    for _, player in ipairs(sm.player.getAllPlayers()) do
        local char = player.character
        if char and sm.exists(char) then --player ~= sm.localPlayer.getPlayer() and
            local team = self.cl.teams[player.id]
            local showNameTag = (ownTeam == team and team) or (not ownTeam and team)
            char:setNameTag(showNameTag and (team .. player.name) or "")
        end
    end
end