dofile("$CONTENT_DATA/Scripts/TeamManager.lua")
dofile("$CONTENT_DATA/Scripts/Utils/Network.lua")
---@class BedwarsBed :ShapeClass
BedwarsBed = class()

local colors = {
    "#eeeeee", "#f5f071", "#cbf66f", "#68ff88", "#7eeded", "#4c6fe3", "#ae79f0", "#ee7bf0", "#f06767", "#eeaf5c",
    "#7f7f7f", "#e2db13", "#a0ea00", "#19e753", "#2ce6e6", "#0a3ee2", "#7514ed", "#cf11d2", "#d02525", "#df7f00",
    "#4a4a4a", "#817c00", "#577d07", "#0e8031", "#118787", "#0f2e91", "#500aa6", "#720a74", "#7c0000", "#673b00",
    "#222222", "#323000", "#375000", "#064023", "#0a4444", "#0a1d5a", "#35086c", "#520653", "#560202", "#472800"
}

if not g_beds then
    g_beds = {}
end

function BedwarsBed:server_onCreate()
    self.saved = self.storage:load()

    if not self.saved then
        for i = 1, #colors + 1 do
            local newColor = sm.color.new(string.sub(colors[i], 1) .. "ff")
            local exists = false
            for _, shape in pairs(g_beds) do
                if shape.color == newColor then
                    exists = true
                end
            end

            if not exists then
                self.shape:setColor(newColor)
                break
            end

            if i == #colors then
                self.network:sendToClients("cl_alert", "You can only have one Bed per color")
                self.shape:destroyPart(0)
                return
            end
        end
    end
    self.saved = true
    self.storage:save(self.saved)

    self.key = #g_beds + 1
    g_beds[self.key] = self.shape
    self.network:sendToClients("cl_create")
end

function BedwarsBed:server_onFixedUpdate()
    if sm.exists(self.shape) then
        local newColor = "#" .. tostring(self.shape.color):sub(1, 6)
        local oldColor = (self.color and "#" .. tostring(self.color):sub(1, 6)) or nil

        if not self.color then
            TeamManager.sv_setBed(newColor, true, self.shape)
        elseif self.color ~= self.shape.color then
            TeamManager.sv_setBed(oldColor, false, self.shape)
            TeamManager.sv_setBed(newColor, true, self.shape)
        end

        self.color = self.shape.color
    end
end

function BedwarsBed:server_onDestroy()
    if self.key then
        g_beds[self.key] = nil
    end

    g_respawnManager:sv_destroyBed(self.shape)

    local color = "#" .. tostring(self.color):sub(1, 6)
    TeamManager.sv_setBed(color, false, self.shape)
    sm.event.sendToGame("sv_bedDestroyed", color)
end

function BedwarsBed:server_onCellCreated(x, y)
    if x == 0 and y == 0 then
        sm.event.sendToGame("sv_preventunload", { world = self.world, minX = -2, minY = -2, maxX = 1, maxY = 1 })
    end
end

function BedwarsBed:server_onCellLoaded(x, y)
    if x == 0 and y == 0 then
        sm.event.sendToGame("sv_preventunload", { world = self.world, minX = -2, minY = -2, maxX = 1, maxY = 1 })
    end
end

function BedwarsBed:server_set_color(color, player)
    local sm_color = sm.color.new(string.sub(color, 1) .. "ff")
    for _, shape in pairs(g_beds) do
        if shape.color == sm_color then
            self.network:sendToClient(player, "cl_alert", "You can only have one Bed per color")
            return
        end
    end
    self.shape:setColor(sm_color)
end

function BedwarsBed.server_activateBed(self, character, player)
    g_respawnManager:sv_registerBed(self.shape, player.character)

    local newColor = "#" .. tostring(self.shape.color):sub(1, 6)
    local oldColor = TeamManager.sv_getTeamColor(player)

    TeamManager.sv_setTeam(player, newColor)
    if newColor ~= oldColor then
        self.network:sendToClients("client_showMessage", newColor .. player.name .. "#ffffff changed team")
    end
end

function BedwarsBed:sv_activatedBed(player)
    self:server_activateBed(nil, player)
    self.network:sendToClient(player, "cl_seat")
end

function BedwarsBed.client_onAction(self, controllerAction, state)
    local consumeAction = true
    if state == true then
        if controllerAction == sm.interactable.actions.use or controllerAction == sm.interactable.actions.jump then
            self:cl_seat()
        else
            consumeAction = false
        end
    else
        consumeAction = false
    end
    return consumeAction
end

function BedwarsBed.client_onInteract(self, character, state)
    if state == true then
        if not g_gameActive then
            self.network:sendToServer("server_activateBed", character)
        end
        self:cl_seat()
    end
end

function BedwarsBed:client_onTinker(character, state)
    if not state then return end
    if not self.gui then
        self.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/Layouts/PaintGun.layout")
        for i = 0, 40 do
            self.gui:setButtonCallback("ColorButton" .. tostring(i), "cl_onColorButton")
        end
    end
    self.gui:open()
end

function BedwarsBed:client_canInteract()
    local keyBindingText = sm.gui.getKeyBinding("Use", true)
    sm.gui.setInteractionText("", keyBindingText, "#{INTERACTION_USE}")
    if sm.isHost then
        local keyBindingText = sm.gui.getKeyBinding("Tinker", true)
        sm.gui.setInteractionText("", keyBindingText, "Color")
    end
    return true
end

function BedwarsBed:client_canTinker()
    return sm.isHost
end

function BedwarsBed:cl_onColorButton(name)
    local index = tonumber(string.sub(name, 12))
    local color = colors[index + 1]
    self.gui:close()
    self.network:sendToServer("server_set_color", color)
end

function BedwarsBed.cl_seat(self)
    if sm.localPlayer.getPlayer() and sm.localPlayer.getPlayer():getCharacter() then
        self.interactable:setSeatCharacter(sm.localPlayer.getPlayer():getCharacter())
    end
end

function BedwarsBed:cl_alert(msg)
    sm.gui.displayAlertText(msg)
end

function BedwarsBed:cl_create()
    self.client_glowEffect = sm.effect.createEffect("PlayerStart - Glow", self.interactable)
    self.client_glowEffect:start()
end

function BedwarsBed.client_showMessage(self, msg)
    sm.gui.chatMessage(msg)
end

SecureClass(BedwarsBed)
