--[[
    SporeRenderingService - Client-side optimized spore rendering
    Handles batched spore creation and lightweight representations
]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local SporeRenderingService = {}
SporeRenderingService.__index = SporeRenderingService

local player = Players.LocalPlayer

-- Configuration
local CONFIG = {
    LIGHTWEIGHT_DISTANCE = 100,
    BATCH_RENDER_DELAY = 0.1, -- Slight delay to batch rendering
    SPORE_POOL_SIZE = 50, -- Pool unused spore instances
}

function SporeRenderingService.new()
    local self = setmetatable({}, SporeRenderingService)
    self._connections = {}
    self._sporePool = {
        regular = {},
        gem = {}
    }
    self._activeSpores = {}
    self._lightweightSpores = {}
    self._pendingBatches = {}
    self:_initialize()
    return self
end

function SporeRenderingService:_initialize()
    Logger:Info("SporeRenderingService initializing...")
    
    self:_setupRemoteEvents()
    self:_prepareSporePool()
    
    Logger:Info("✓ SporeRenderingService initialized")
end

function SporeRenderingService:_setupRemoteEvents()
    local shared = ReplicatedStorage:WaitForChild("Shared", 5)
    if not shared then return end
    
    local remoteEvents = shared:WaitForChild("RemoteEvents", 5)
    if not remoteEvents then return end
    
    local sporeEvents = remoteEvents:WaitForChild("SporeEvents", 5)
    if not sporeEvents then return end
    
    -- Handle batched spore creation
    local batchSporeEvent = sporeEvents:WaitForChild("BatchSporeCreated", 5)
    if batchSporeEvent then
        self._connections.BatchSporeCreated = batchSporeEvent.OnClientEvent:Connect(function(playerName, sporeBatch)
            self:_handleSporeBatch(playerName, sporeBatch)
        end)
    end
    
    -- Handle lightweight spore updates
    local lightweightEvent = sporeEvents:WaitForChild("LightweightSporeUpdate", 5)
    if lightweightEvent then
        self._connections.LightweightSporeUpdate = lightweightEvent.OnClientEvent:Connect(function(playerName, updateData)
            self:_handleLightweightUpdate(playerName, updateData)
        end)
    end
end

function SporeRenderingService:_prepareSporePool()
    -- Pre-create spore instances to avoid lag spikes
    local sporeTemplate = ReplicatedStorage:FindFirstChild("SporePart")
    local gemTemplate = ReplicatedStorage:FindFirstChild("GemSporePart")
    
    if sporeTemplate then
        for i = 1, CONFIG.SPORE_POOL_SIZE do
            local spore = sporeTemplate:Clone()
            spore.Parent = nil
            spore.Anchored = true
            spore.Transparency = 1
            table.insert(self._sporePool.regular, spore)
        end
    end
    
    if gemTemplate then
        for i = 1, CONFIG.SPORE_POOL_SIZE / 4 do -- Fewer gem spores needed
            local spore = gemTemplate:Clone()
            spore.Parent = nil
            spore.Anchored = true
            spore.Transparency = 1
            table.insert(self._sporePool.gem, spore)
        end
    end
    
    Logger:Info(string.format("Prepared spore pool: %d regular, %d gem", #self._sporePool.regular, #self._sporePool.gem))
end

function SporeRenderingService:_getPooledSpore(isGem)
    local pool = isGem and self._sporePool.gem or self._sporePool.regular
    
    if #pool > 0 then
        return table.remove(pool)
    else
        -- Pool exhausted, create new spore
        local templateName = isGem and "GemSporePart" or "SporePart"
        local template = ReplicatedStorage:FindFirstChild(templateName)
        if template then
            return template:Clone()
        end
    end
    
    return nil
end

function SporeRenderingService:_returnSporeToPool(spore)
    -- Reset spore and return to pool
    spore.Anchored = true
    spore.CanCollide = false
    spore.Transparency = 1
    spore.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    spore.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    spore.Parent = nil
    
    local isGem = spore.Name:find("Gem") ~= nil
    local pool = isGem and self._sporePool.gem or self._sporePool.regular
    
    if #pool < CONFIG.SPORE_POOL_SIZE then
        table.insert(pool, spore)
    else
        spore:Destroy() -- Pool is full, destroy excess
    end
end

function SporeRenderingService:_handleSporeBatch(playerName, sporeBatch)
    -- Add slight delay to batch rendering and reduce frame drops
    table.insert(self._pendingBatches, {
        playerName = playerName,
        batch = sporeBatch,
        processTime = tick() + CONFIG.BATCH_RENDER_DELAY
    })
    
    -- Process pending batches
    self:_processPendingBatches()
end

function SporeRenderingService:_processPendingBatches()
    local currentTime = tick()
    
    for i = #self._pendingBatches, 1, -1 do
        local pendingBatch = self._pendingBatches[i]
        
        if currentTime >= pendingBatch.processTime then
            -- Process this batch
            self:_renderSporeBatch(pendingBatch.playerName, pendingBatch.batch)
            table.remove(self._pendingBatches, i)
        end
    end
end

function SporeRenderingService:_renderSporeBatch(playerName, sporeBatch)
    local playerPlots = Workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then return end
    
    local plot = playerPlots:FindFirstChild("Plot_" .. playerName)
    if not plot then return end
    
    -- Render spores with proper spacing to avoid frame drops
    for i, sporeData in ipairs(sporeBatch) do
        -- Add tiny delays between spore creation to smooth out frame rate
        task.wait(0.01)
        self:_createOptimizedSpore(plot, sporeData)
    end
end

function SporeRenderingService:_createOptimizedSpore(plot, sporeData)
    local spore = self:_getPooledSpore(sporeData.isGem)
    if not spore then return end
    
    -- Extract player name from plot
    local playerName = plot.Name:match("Plot_(.+)")
    
    -- Setup spore properties
    spore.Name = sporeData.name
    spore.Position = sporeData.position
    spore.Transparency = 0
    
    -- Apply gold effect if needed
    if sporeData.isGold and spore:FindFirstChild("PointLight") then
        spore.PointLight.Enabled = true
        spore.PointLight.Color = Color3.fromRGB(255, 215, 0)
    end
    
    -- Determine target folder (Area1 or Area2)
    local targetFolder
    if sporeData.area == "Area2" then
        local area2 = plot:FindFirstChild("Area2")
        if area2 then
            targetFolder = area2:FindFirstChild("Spores")
        end
    else
        targetFolder = plot:FindFirstChild("Spores")
    end
    
    if targetFolder then
        spore.Parent = targetFolder
        
        -- Enable physics and movement
        spore.Anchored = false
        spore.CanCollide = true
        
        -- Apply launch velocity
        if sporeData.velocity then
            spore.AssemblyLinearVelocity = sporeData.velocity
        end
        
        -- Store in active spores
        self._activeSpores[spore] = {
            spawnTime = tick(),
            playerName = playerName
        }
        
        -- Auto-cleanup after lifetime
        task.delay(600, function() -- 10 minutes
            if spore.Parent then
                self:_removeSpore(spore)
            end
        end)
    else
        -- Return to pool if no valid folder
        self:_returnSporeToPool(spore)
    end
end

function SporeRenderingService:_handleLightweightUpdate(playerName, updateData)
    -- Handle lightweight spore updates for distant players
    if updateData == "position_update" then
        -- This would update positions of lightweight representations
        -- For now, we'll skip implementing the full lightweight system
        -- as the pooling and batching already provide significant optimization
        return
    end
    
    -- Handle new lightweight spores
    if type(updateData) == "table" then
        for _, lightweightData in pairs(updateData) do
            self:_createLightweightSpore(playerName, lightweightData)
        end
    end
end

function SporeRenderingService:_createLightweightSpore(playerName, lightweightData)
    -- Create a simple visual representation without physics
    -- This is much lighter on network and performance
    local spore = self:_getPooledSpore(lightweightData.isGem)
    if not spore then return end
    
    spore.Name = lightweightData.name
    spore.Position = lightweightData.position
    spore.Transparency = 0.3 -- Slightly transparent to indicate it's lightweight
    spore.Anchored = true
    spore.CanCollide = false
    
    -- Store as lightweight spore
    self._lightweightSpores[lightweightData.name] = spore
    
    -- Parent to workspace temporarily (not in plot folders to avoid collection)
    spore.Parent = Workspace
end

function SporeRenderingService:_removeSpore(spore)
    -- Clean up a spore and return it to pool
    if self._activeSpores[spore] then
        self._activeSpores[spore] = nil
    end
    
    self:_returnSporeToPool(spore)
end

function SporeRenderingService:Cleanup()
    Logger:Info("SporeRenderingService cleaning up...")
    
    for _, connection in pairs(self._connections) do
        if connection then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    
    -- Clean up all spores
    for spore in pairs(self._activeSpores) do
        if spore.Parent then
            spore:Destroy()
        end
    end
    
    for _, spore in pairs(self._lightweightSpores) do
        if spore.Parent then
            spore:Destroy()
        end
    end
    
    -- Clean up pools
    for _, pool in pairs(self._sporePool) do
        for _, spore in pairs(pool) do
            spore:Destroy()
        end
    end
    
    Logger:Info("✓ SporeRenderingService cleaned up")
end

return SporeRenderingService