--[[
    SporeOptimizationService - Network optimization for spores without gameplay impact
    Uses lightweight representations and batched updates to reduce network load
]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local HeartbeatManager = require(script.Parent.Parent.Utilities.HeartbeatManager)

local SporeOptimizationService = {}
SporeOptimizationService.__index = SporeOptimizationService

-- Configuration
local CONFIG = {
    BATCH_UPDATE_INTERVAL = 0.5, -- Send spore updates every 0.5 seconds instead of instantly
    LIGHTWEIGHT_DISTANCE = 100, -- Distance beyond which spores become lightweight
    PHYSICS_CULL_DISTANCE = 150, -- Distance beyond which spore physics are disabled
    MAX_SPORES_PER_BATCH = 20, -- Maximum spores to process per batch
}

function SporeOptimizationService.new()
    local self = setmetatable({}, SporeOptimizationService)
    self._connections = {}
    self._sporeBatches = {} -- Player -> {spores to create}
    self._lightweightSpores = {} -- Track lightweight spore representations
    self._remoteEvents = {}
    self:_initialize()
    return self
end

function SporeOptimizationService:_initialize()
    Logger:Info("SporeOptimizationService initializing...")
    
    self:_setupRemoteEvents()
    self:_startBatchProcessing()
    
    Logger:Info("✓ SporeOptimizationService initialized")
end

function SporeOptimizationService:_setupRemoteEvents()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if not shared then
        shared = Instance.new("Folder")
        shared.Name = "Shared"
        shared.Parent = ReplicatedStorage
    end
    
    local remoteEvents = shared:FindFirstChild("RemoteEvents")
    if not remoteEvents then
        remoteEvents = Instance.new("Folder")
        remoteEvents.Name = "RemoteEvents"
        remoteEvents.Parent = shared
    end
    
    local sporeEvents = remoteEvents:FindFirstChild("SporeEvents")
    if not sporeEvents then
        sporeEvents = Instance.new("Folder")
        sporeEvents.Name = "SporeEvents"
        sporeEvents.Parent = remoteEvents
    end
    
    -- Create batched spore creation event
    if not sporeEvents:FindFirstChild("BatchSporeCreated") then
        local batchSporeEvent = Instance.new("RemoteEvent")
        batchSporeEvent.Name = "BatchSporeCreated"
        batchSporeEvent.Parent = sporeEvents
        self._remoteEvents.BatchSporeCreated = batchSporeEvent
    end
    
    -- Create lightweight spore update event
    if not sporeEvents:FindFirstChild("LightweightSporeUpdate") then
        local lightweightEvent = Instance.new("RemoteEvent")
        lightweightEvent.Name = "LightweightSporeUpdate"
        lightweightEvent.Parent = sporeEvents
        self._remoteEvents.LightweightSporeUpdate = lightweightEvent
    end
end

function SporeOptimizationService:_startBatchProcessing()
    -- Process spore batches periodically instead of immediately
    self._connections.BatchProcessor = HeartbeatManager.getInstance():register(function()
        self:_processSporeBatches()
        self:_updateLightweightSpores()
    end, CONFIG.BATCH_UPDATE_INTERVAL)
end

function SporeOptimizationService:QueueSporeCreation(playerName, sporeData)
    -- Queue spore creation instead of immediate spawning
    if not self._sporeBatches[playerName] then
        self._sporeBatches[playerName] = {}
    end
    
    table.insert(self._sporeBatches[playerName], sporeData)
end

function SporeOptimizationService:_processSporeBatches()
    for playerName, spores in pairs(self._sporeBatches) do
        if #spores > 0 then
            local player = Players:FindFirstChild(playerName)
            if player then
                -- Process in chunks to avoid overwhelming the network
                local batchSize = math.min(#spores, CONFIG.MAX_SPORES_PER_BATCH)
                local batch = {}
                
                for i = 1, batchSize do
                    table.insert(batch, spores[i])
                end
                
                -- Remove processed spores from queue
                for i = batchSize, 1, -1 do
                    table.remove(spores, i)
                end
                
                -- Send batch to relevant players
                self:_sendSporeBatch(player, batch)
            end
        end
    end
end

function SporeOptimizationService:_sendSporeBatch(targetPlayer, sporeBatch)
    -- Send spore creation data to nearby players only
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") and 
           targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            
            local distance = (player.Character.HumanoidRootPart.Position - 
                            targetPlayer.Character.HumanoidRootPart.Position).Magnitude
            
            if distance <= CONFIG.LIGHTWEIGHT_DISTANCE or player == targetPlayer then
                -- Send full spore data to nearby players and the owner
                if self._remoteEvents.BatchSporeCreated then
                    self._remoteEvents.BatchSporeCreated:FireClient(player, targetPlayer.Name, sporeBatch)
                end
            else
                -- Send lightweight data to distant players
                local lightweightBatch = {}
                for _, sporeData in pairs(sporeBatch) do
                    table.insert(lightweightBatch, {
                        name = sporeData.name,
                        position = sporeData.position,
                        isGem = sporeData.isGem,
                        isGold = sporeData.isGold
                    })
                end
                
                if self._remoteEvents.LightweightSporeUpdate then
                    self._remoteEvents.LightweightSporeUpdate:FireClient(player, targetPlayer.Name, lightweightBatch)
                end
            end
        end
    end
end

function SporeOptimizationService:_updateLightweightSpores()
    -- Update positions of lightweight spores for distant players
    -- This is much less frequent than real physics updates
    
    for _, player in pairs(Players:GetPlayers()) do
        local lightweightUpdates = {}
        
        for sporeId, sporeData in pairs(self._lightweightSpores) do
            if sporeData.spore and sporeData.spore.Parent then
                -- Check if this player should receive lightweight updates
                if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    local distance = (sporeData.spore.Position - player.Character.HumanoidRootPart.Position).Magnitude
                    
                    if distance > CONFIG.LIGHTWEIGHT_DISTANCE then
                        table.insert(lightweightUpdates, {
                            id = sporeId,
                            position = sporeData.spore.Position
                        })
                    end
                end
            else
                -- Clean up destroyed spores
                self._lightweightSpores[sporeId] = nil
            end
        end
        
        if #lightweightUpdates > 0 and self._remoteEvents.LightweightSporeUpdate then
            self._remoteEvents.LightweightSporeUpdate:FireClient(player, "position_update", lightweightUpdates)
        end
    end
end

function SporeOptimizationService:RegisterSpore(spore, sporeData)
    -- Register a spore for lightweight tracking
    local sporeId = spore:GetAttribute("SporeId") or spore.Name
    self._lightweightSpores[sporeId] = {
        spore = spore,
        data = sporeData,
        registeredTime = tick()
    }
end

function SporeOptimizationService:OptimizeSporePhysics(spore)
    -- Disable physics for spores that are far from all players
    local shouldHavePhysics = false
    
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local distance = (spore.Position - player.Character.HumanoidRootPart.Position).Magnitude
            if distance <= CONFIG.PHYSICS_CULL_DISTANCE then
                shouldHavePhysics = true
                break
            end
        end
    end
    
    -- Toggle physics based on proximity
    if shouldHavePhysics and spore.Anchored then
        spore.Anchored = false
        spore.CanCollide = true
    elseif not shouldHavePhysics and not spore.Anchored then
        spore.Anchored = true
        spore.CanCollide = false
        spore.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        spore.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
end

function SporeOptimizationService:Cleanup()
    Logger:Info("SporeOptimizationService shutting down...")
    
    for name, connection in pairs(self._connections) do
        if connection then
            if name == "BatchProcessor" then
                HeartbeatManager.getInstance():unregister(connection)
            else
                connection:Disconnect()
            end
        end
    end
    
    self._connections = {}
    self._sporeBatches = {}
    self._lightweightSpores = {}
    
    Logger:Info("✓ SporeOptimizationService shutdown complete")
end

return SporeOptimizationService