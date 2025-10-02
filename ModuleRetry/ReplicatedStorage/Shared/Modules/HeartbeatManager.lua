--[[
    HeartbeatManager - Centralized heartbeat management to reduce memory usage
    Consolidates multiple heartbeat connections into a single efficient system
]]--

local RunService = game:GetService("RunService")

local HeartbeatManager = {}
HeartbeatManager.__index = HeartbeatManager

-- Singleton instance
local instance = nil

-- Callback storage
local callbacks = {}
local nextCallbackId = 1

function HeartbeatManager.getInstance()
    if not instance then
        instance = setmetatable({}, HeartbeatManager)
        instance:_initialize()
    end
    return instance
end

function HeartbeatManager:_initialize()
    self._connection = RunService.Heartbeat:Connect(function(deltaTime)
        for id, callback in pairs(callbacks) do
            local success, err = pcall(callback.func, deltaTime)
            if not success then
                warn("[HeartbeatManager] Callback error:", err)
                -- Remove errored callbacks to prevent spam
                callbacks[id] = nil
            end
        end
    end)
end

-- Register a callback to run on heartbeat
-- Returns an ID that can be used to unregister
function HeartbeatManager:register(func, interval)
    interval = interval or 0 -- Default to every frame
    
    local id = nextCallbackId
    nextCallbackId = nextCallbackId + 1
    
    local lastTime = 0
    callbacks[id] = {
        func = function(deltaTime)
            lastTime = lastTime + deltaTime
            if lastTime >= interval then
                func(deltaTime)
                lastTime = 0
            end
        end
    }
    
    return id
end

-- Unregister a callback
function HeartbeatManager:unregister(id)
    callbacks[id] = nil
end

-- Clean up all callbacks and connection
function HeartbeatManager:cleanup()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
    callbacks = {}
    instance = nil
end

return HeartbeatManager