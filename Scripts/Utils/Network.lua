local NetworkingStrings = {"server_"}
local ServerStrings = {"server_","sv_"}
local ClientStrings = {"client_","cl_"}

---@param array table list of strings.
---@param string string string to be searched.
---@return boolean result contains one of the array strings.
local function ContainsStrings(array,string)
    for _,str in ipairs(array) do
        if string.find(string.lower(string),string.lower(str)) then
            return true
        end
    end
    return false
end

---@param Name string name for logging.
---@param Function function function to proxy.
---@param Server boolean isServerMode check.
---@param PreventNetworking boolean prevents player variable.
---@return function proxy proxy function.
local function SecureNetworking(Name,Function,Server,PreventNetworking)
    local function Hook(self,param1,plr,...)
        if sm.isServerMode() ~= Server and Server ~= nil then
            local Username = type(plr) == "Player" and plr:getName().. " " or ""
            sm.log.info(Username..Name.." Mismatching Servermode.")
            return
        end
        if type(plr) == "Player" and PreventNetworking then
            local Username = type(plr) == "Player" and plr:getName().. " " or ""
            sm.log.info(Username..Name.." Disabled Networking.")
            return
        end
        return Function(self,param1,plr,...)
    end
    return Hook
end

---@param Class class class to secure.
function SecureClass(Class)
    for key,val in pairs(Class) do
        if type(val) == "function" then
            local ServerMode = nil
            local PreventNetworking = true
            if ContainsStrings(ServerStrings,key) then
                ServerMode = true
            elseif ContainsStrings(ClientStrings,key) then
                ServerMode = false
            end
            if ContainsStrings(NetworkingStrings,key) then
                PreventNetworking = false
            end
            sm.log.info(key,ServerMode,PreventNetworking)
            Class[key] = SecureNetworking(key,val,ServerMode,PreventNetworking)
        end
    end
end

--[[
    server_ for networking
    sv_ for server functions

    client_ & cl_ for client
]]