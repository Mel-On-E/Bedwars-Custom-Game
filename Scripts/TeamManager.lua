TeamManager = class()
TeamManager.isSaveObject = true

function TeamManager:server_onCreate()
    if not g_teamManager then
        g_teamManager = self

        self.sv = self.storage:load()

        if self.sv == nil then
            self.sv = {}
            self.sv.teams = {}
        end
    end
end

function TeamManager:server_onFixedUpdate()
    if self.sv.updateClientData then
        self.sv.updateClientData = false
        self.network:setClientData(self.sv)
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

function TeamManager:sv_updateClientData()
    self.sv.updateClientData = true
end

function TeamManager.sv_getTeamColor(player)
    return g_teamManager.sv.teams[player.id]
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