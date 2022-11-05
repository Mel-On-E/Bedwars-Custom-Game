dofile("$CONTENT_DATA/Scripts/Utils/Network.lua")

Freecam = class()

function Freecam:client_onDestroy()
    self:client_disable()
end

function Freecam:client_onCreate()
    self.cl = {}
    self.cl.direction = sm.vec3.new(0, 0, 0)
    self.cl.velocity = sm.vec3.new(0, 0, 0)
    self.cl.defaultspeed = 1
    self.cl.speed = self.cl.defaultspeed
    self.cl.enabled = false
end

function Freecam:client_onUpdate(dt)
    if not self.cl.enabled then return end
    self.cl.velocity = (self.cl.velocity + self:client_local(self.cl.direction * self.cl.speed)) * 0.95
    sm.camera.setPosition(sm.camera.getPosition() + self.cl.velocity * dt)
    sm.camera.setDirection(sm.localPlayer.getPlayer().character.direction)
    sm.camera.setFov(sm.camera.getDefaultFov())
end

function Freecam:client_onAction(action, state)
    if not self.cl.enabled then return end
    local val = state and 1 or -1
    if action == sm.interactable.actions.forward then
        self.cl.direction = self.cl.direction + sm.vec3.new(0, 1 * val, 0)
    end
    if action == sm.interactable.actions.backward then
        self.cl.direction = self.cl.direction + sm.vec3.new(0, -1 * val, 0)
    end
    if action == sm.interactable.actions.left then
        self.cl.direction = self.cl.direction + sm.vec3.new(-1 * val, 0, 0)
    end
    if action == sm.interactable.actions.right then
        self.cl.direction = self.cl.direction + sm.vec3.new(1 * val, 0, 0)
    end
    if action == sm.interactable.actions.jump then
        self.cl.speed = state and self.cl.defaultspeed * 2 or self.cl.defaultspeed
    end
    return true
end

function Freecam:client_local(vec)
    return sm.camera.getDirection() * vec.y + sm.camera.getRight() * vec.x + sm.camera.getUp() * vec.z
end

function Freecam:client_enable()
    if self.cl.enabled then return end
    local char = sm.localPlayer.getPlayer().character
    if char then
        sm.camera.setCameraState(sm.camera.state.cutsceneTP)
        char:setLockingInteractable(self.interactable)
        self.cl.direction = sm.vec3.new(0, 0, 0)
        self.cl.velocity = sm.vec3.new(0, 0, 0)
        self.cl.enabled = true
    end
end

function Freecam:client_disable()
    if not self.cl.enabled then return end
    local char = sm.localPlayer.getPlayer().character
    if char then
        self.cl.enabled = false
        char:setLockingInteractable(nil)
        sm.camera.setCameraState(sm.camera.state.default)
    end
end

function Freecam:sv_enable(arr)
    for _, player in ipairs(arr) do
        self.network:sendToClient(player, "client_enable")
        if player.character then
            player.character:setWorldPosition(sm.vec3.new(0, 0, 500))
        end
    end
end

function Freecam:sv_disable(arr)
    for _, player in ipairs(arr) do
        self.network:sendToClient(player, "client_disable")
        if player.character then
            player.character:setWorldPosition(sm.vec3.new(0, 0, 50))
        end
    end
end

function Freecam:server_canErase()
    return false
end

function Freecam:client_canErase()
    return false
end

function Freecam:server_onFixedUpdate()
    if lastGameState ~= g_gameActive and not g_gameActive then
        self:sv_disable(sm.player.getAllPlayers())
    end
    lastGameState = g_gameActive
end

SecureClass(Freecam)
