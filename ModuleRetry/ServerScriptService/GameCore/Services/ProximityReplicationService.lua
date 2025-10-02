--[[
    ProximityReplicationService - Optimizes network replication based on player proximity
    Reduces spore replication to distant players to save bandwidth
]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local HeartbeatManager = require(script.Parent.Parent.Utilities.HeartbeatManager)

local ProximityReplicationService = {}
ProximityReplicationService.__index = ProximityReplicationService

-- Configuration
local CONFIG = {
    MAX_REPLICATION_DISTANCE = 200, -- Studs - spores beyond this distance won't replicate
    UPDATE_INTERVAL = 2, -- Check proximity every 2 seconds
    MIN_SPORE_AGE = 1, -- Don't cull spores younger than 1 second
}

function ProximityReplicationService.new()
    local self = setmetatable({}, ProximityReplicationService)
    self._connections = {}
    self._trackedSpores = {}
    self:_initialize()
    return self
end

function ProximityReplicationService:_initialize()
    Logger:Info("ProximityReplicationService initializing...")
    
    -- Start proximity checking
    self._connections.ProximityCheck = HeartbeatManager.getInstance():register(function()
        self:_updateSporeVisibility()
    end, CONFIG.UPDATE_INTERVAL)
    
    -- Listen for new spores
    self._connections.SporeAdded = CollectionService:GetInstanceAddedSignal("Spore"):Connect(function(spore)
        self:_trackSpore(spore)
    end)
    
    self._connections.SporeRemoved = CollectionService:GetInstanceRemovedSignal("Spore"):Connect(function(spore)
        self:_untrackSpore(spore)
    end)
    
    Logger:Info("✓ ProximityReplicationService initialized")
end

function ProximityReplicationService:_trackSpore(spore)
    if not spore:IsA("BasePart") then return end
    
    -- Tag spores for tracking
    if spore.Name:match("SporePart_") or spore.Name:match("GemSporePart_") then
        self._trackedSpores[spore] = {
            spawnTime = tick(),
            lastVisibilityUpdate = 0
        }
        CollectionService:AddTag(spore, "Spore")
    end
end

function ProximityReplicationService:_untrackSpore(spore)
    self._trackedSpores[spore] = nil
end

function ProximityReplicationService:_updateSporeVisibility()
    local currentTime = tick()
    
    for spore, data in pairs(self._trackedSpores) do
        if not spore.Parent then
            self._trackedSpores[spore] = nil
            continue
        end
        
        -- Don't cull very new spores
        if currentTime - data.spawnTime < CONFIG.MIN_SPORE_AGE then
            continue
        end
        
        -- Update visibility for each player
        for _, player in pairs(Players:GetPlayers()) do
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local distance = (spore.Position - player.Character.HumanoidRootPart.Position).Magnitude
                
                -- Set network ownership to closest player for better performance
                if distance < CONFIG.MAX_REPLICATION_DISTANCE then
                    spore:SetNetworkOwner(player)
                    break
                else
                    spore:SetNetworkOwner(nil) -- Server owns distant spores
                end
            end
        end
    end
end

function ProximityReplicationService:Cleanup()
    Logger:Info("ProximityReplicationService shutting down...")
    
    for name, connection in pairs(self._connections) do
        if connection then
            if name == "ProximityCheck" then
                HeartbeatManager.getInstance():unregister(connection)
            else
                connection:Disconnect()
            end
        end
    end
    
    self._connections = {}
    self._trackedSpores = {}
    
    Logger:Info("✓ ProximityReplicationService shutdown complete")
end

return ProximityReplicationService