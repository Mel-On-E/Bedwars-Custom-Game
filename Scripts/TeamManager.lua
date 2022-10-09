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
end

function TeamManager:sv_updateClientData()
    self.sv.updateClientData = true
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
    for _, player in ipairs(sm.player.getAllPlayers()) do
        local char = player.character
        if char and sm.exists(char) then --player ~= sm.localPlayer.getPlayer() and
            local color = self.cl.teams[player.id]
            char:setNameTag(color and (color .. player.name) or "")
        end
    end
end