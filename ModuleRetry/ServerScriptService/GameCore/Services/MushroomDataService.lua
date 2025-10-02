local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local HeartbeatManager = require(script.Parent.Parent.Utilities.HeartbeatManager)

local MushroomDataService = {}
MushroomDataService.__index = MushroomDataService

-- Configuration
local CONFIG = {
    SPORE_SPAWN_INTERVAL = 5, -- Base interval between spore spawns
    GOLD_CHECK_INTERVAL = 600, -- 10 minutes
    GOLD_CHANCE = 0.05, -- 5% chance per check
}

function MushroomDataService.new()
    local self = setmetatable({}, MushroomDataService)
    self._dataService = nil
    self._plotService = nil
    self._shopService = nil
    self._connections = {}
    self._playerMushroomData = {} -- Store server-side mushroom data
    self._remoteEvents = {}
    
    self:_initialize()
    return self
end

function MushroomDataService:_initialize()
    Logger:Info("MushroomDataService initializing...")
    
    self:_setupRemoteEvents()
    self:_startSporeTimer()
    self:_startGoldMushroomTimer()
    
    Logger:Info("✓ MushroomDataService initialized")
end

function MushroomDataService:_setupRemoteEvents()
    local shared = ReplicatedStorage:WaitForChild("Shared", 5)
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
    
    local mushroomEvents = remoteEvents:FindFirstChild("MushroomEvents")
    if not mushroomEvents then
        mushroomEvents = Instance.new("Folder")
        mushroomEvents.Name = "MushroomEvents"
        mushroomEvents.Parent = remoteEvents
    end
    
    -- Create remote events for client-server communication
    local updateMushroomData = mushroomEvents:FindFirstChild("UpdateMushroomData")
    if not updateMushroomData then
        updateMushroomData = Instance.new("RemoteEvent")
        updateMushroomData.Name = "UpdateMushroomData"
        updateMushroomData.Parent = mushroomEvents
    end
    
    local mushroomClicked = mushroomEvents:FindFirstChild("MushroomClicked")
    if not mushroomClicked then
        mushroomClicked = Instance.new("RemoteEvent")
        mushroomClicked.Name = "MushroomClicked"
        mushroomClicked.Parent = mushroomEvents
    end
    
    local sporeSpawned = mushroomEvents:FindFirstChild("SporeSpawned")
    if not sporeSpawned then
        sporeSpawned = Instance.new("RemoteEvent")
        sporeSpawned.Name = "SporeSpawned" 
        sporeSpawned.Parent = mushroomEvents
    end
    
    local sporeCollected = mushroomEvents:FindFirstChild("SporeCollected")
    if not sporeCollected then
        sporeCollected = Instance.new("RemoteEvent")
        sporeCollected.Name = "SporeCollected"
        sporeCollected.Parent = mushroomEvents
    end
    
    self._remoteEvents = {
        UpdateMushroomData = updateMushroomData,
        MushroomClicked = mushroomClicked,
        SporeSpawned = sporeSpawned,
        SporeCollected = sporeCollected
    }
    
    -- Connect event handlers
    mushroomClicked.OnServerEvent:Connect(function(player, mushroomId, clickPosition)
        self:_handleMushroomClick(player, mushroomId, clickPosition)
    end)
    
    sporeCollected.OnServerEvent:Connect(function(player, sporeType, amount, area)
        self:_handleSporeCollection(player, sporeType, amount, area)
    end)
    
    Logger:Info("✓ MushroomDataService remote events setup complete")
end

function MushroomDataService:_startSporeTimer()
    -- Check for spore spawning every second
    self._connections.SporeTimer = HeartbeatManager.getInstance():register(function()
        if not self._dataService then return end
        
        local currentTime = os.time()
        
        for _, player in pairs(Players:GetPlayers()) do
            if not player or not player.Parent then continue end
            
            local playerData = self._dataService:GetPlayerData(player)
            if not playerData then continue end
            
            local mushroomData = self._playerMushroomData[player]
            if not mushroomData then continue end
            
            -- Check each mushroom for spore spawning
            for area, mushrooms in pairs(mushroomData) do
                for mushroomId, mushroom in pairs(mushrooms) do
                    if self:_shouldSpawnSpore(mushroom, currentTime, playerData) then
                        self:_spawnSpore(player, mushroomId, area, mushroom)
                    end
                end
            end
        end
    end)
end

function MushroomDataService:_shouldSpawnSpore(mushroom, currentTime, playerData)
    local timeSinceLastSpawn = currentTime - (mushroom.lastSporeSpawn or 0)
    local spawnInterval = CONFIG.SPORE_SPAWN_INTERVAL
    
    -- Apply FasterShrooms upgrade if available
    if self._shopService and self._shopService.GetUpgradeLevel then
        local upgradeLevel = self._shopService:GetUpgradeLevel(playerData, "FasterShrooms")
        if upgradeLevel > 0 then
            local speedMultiplier = 1 + (upgradeLevel * 0.02) -- 2% faster per level
            spawnInterval = spawnInterval / speedMultiplier
        end
    end
    
    return timeSinceLastSpawn >= spawnInterval
end

function MushroomDataService:_spawnSpore(player, mushroomId, area, mushroomData)
    mushroomData.lastSporeSpawn = os.time()
    
    -- Determine spore type (regular vs gem)
    local isGem = math.random() < CONFIG.GEM_CHANCE
    local sporeType = isGem and "gem" or "spore"
    
    -- Send spawn event to client for visual spawning
    self._remoteEvents.SporeSpawned:FireClient(player, {
        mushroomId = mushroomId,
        sporeType = sporeType,
        area = area,
        position = mushroomData.position
    })
    
    Logger:Debug(string.format("Spawned %s from mushroom %s for %s in %s", sporeType, mushroomId, player.Name, area))
end

function MushroomDataService:_handleMushroomClick(player, mushroomId, clickPosition)
    if not self._dataService then
        Logger:Warn("DataService not available for mushroom click")
        return
    end
    
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData then
        Logger:Warn("No player data found for mushroom click from " .. player.Name)
        return
    end
    
    local mushroomData = self._playerMushroomData[player]
    if not mushroomData then
        Logger:Warn("No mushroom data found for " .. player.Name)
        return
    end
    
    -- Find the mushroom across all areas
    local mushroom = nil
    local area = nil
    for areaName, mushrooms in pairs(mushroomData) do
        if mushrooms[mushroomId] then
            mushroom = mushrooms[mushroomId]
            area = areaName
            break
        end
    end
    
    if not mushroom then
        Logger:Warn(string.format("Mushroom %s not found for %s", mushroomId, player.Name))
        return
    end
    
    -- Validate click distance (basic anti-cheat)
    local playerPosition = player.Character and player.Character.HumanoidRootPart and player.Character.HumanoidRootPart.Position
    if playerPosition then
        local distance = (Vector3.new(mushroom.position[1], mushroom.position[2], mushroom.position[3]) - playerPosition).Magnitude
        if distance > 50 then -- Reasonable click distance
            Logger:Warn(string.format("Player %s clicked mushroom from too far away (%d studs)", player.Name, math.floor(distance)))
            return
        end
    end
    
    -- Force spawn a spore
    self:_spawnSpore(player, mushroomId, area, mushroom)
    
    Logger:Debug(string.format("Player %s clicked mushroom %s in %s", player.Name, mushroomId, area))
end

function MushroomDataService:_handleSporeCollection(player, sporeType, amount, area)
    if not self._dataService then
        Logger:Warn("DataService not available for spore collection")
        return
    end
    
    -- Validate and award currency
    if sporeType == "spore" then
        local success = self._dataService:AddSpores(player, amount, "Spore Collection")
        if success then
            Logger:Debug(string.format("Awarded %d spores to %s", amount, player.Name))
        end
    elseif sporeType == "gem" then
        local success = self._dataService:AddGems(player, amount, "Gem Collection")  
        if success then
            Logger:Debug(string.format("Awarded %d gems to %s", amount, player.Name))
        end
    elseif sporeType == "bigspore" then
        local success = self._dataService:AddSpores(player, amount, "BigSpore Collection")
        if success then
            Logger:Debug(string.format("Awarded %d spores to %s from BigSpore", amount, player.Name))
        end
    end
end

function MushroomDataService:_startGoldMushroomTimer()
    self._connections.GoldTimer = HeartbeatManager.getInstance():register(function()
        -- Check for gold mushroom conversion every interval
        task.wait(CONFIG.GOLD_CHECK_INTERVAL)
        
        for _, player in pairs(Players:GetPlayers()) do
            if not player or not player.Parent then continue end
            
            local mushroomData = self._playerMushroomData[player]
            if not mushroomData then continue end
            
            -- Check each area for gold conversion chance
            for area, mushrooms in pairs(mushroomData) do
                for mushroomId, mushroom in pairs(mushrooms) do
                    if mushroom.type ~= "Mushroom_Gold" and math.random() < CONFIG.GOLD_CHANCE then
                        self:_convertToGoldMushroom(player, mushroomId, area, mushroom)
                        break -- Only one gold mushroom per check
                    end
                end
            end
        end
    end)
end

function MushroomDataService:_convertToGoldMushroom(player, mushroomId, area, mushroomData)
    mushroomData.type = "Mushroom_Gold"
    
    -- Send update to client
    self:_sendMushroomUpdate(player, mushroomId, area, mushroomData)
    
    Logger:Info(string.format("Converted mushroom %s to gold for %s in %s", mushroomId, player.Name, area))
end

function MushroomDataService:InitializePlayerMushrooms(player)
    Logger:Info(string.format("🔥 InitializePlayerMushrooms called for %s", player.Name))
    
    if not self._dataService then
        Logger:Warn("DataService not available, cannot initialize mushrooms for " .. player.Name)
        return
    end
    
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData then
        Logger:Warn("No player data found for " .. player.Name)
        return
    end
    
    Logger:Info(string.format("🔥 Got player data for %s, initializing mushrooms...", player.Name))
    
    self._playerMushroomData[player] = {}
    
    -- Load mushrooms from saved data or create defaults
    if playerData.Mushrooms and playerData.Mushrooms.Area1 then
        Logger:Info(string.format("🔥 Loading existing mushrooms from save data for %s", player.Name))
        -- Load existing mushrooms
        for area, mushrooms in pairs(playerData.Mushrooms) do
            self._playerMushroomData[player][area] = {}
            for i, mushroomInfo in ipairs(mushrooms) do
                local mushroomId = string.format("mushroom_%s_%d", area, i)
                self._playerMushroomData[player][area][mushroomId] = {
                    position = mushroomInfo.Position,
                    type = mushroomInfo.ModelType or "Mushroom_1",
                    lastSporeSpawn = os.time(),
                    id = mushroomId
                }
                Logger:Info(string.format("🔥 Loaded mushroom %s in %s", mushroomId, area))
            end
        end
    else
        Logger:Info(string.format("🔥 No existing mushroom data found for %s, creating defaults", player.Name))
        -- Create default mushrooms
        self:_createDefaultMushrooms(player)
    end
    
    -- Send all mushroom data to client
    self:_sendAllMushroomData(player)
    
    Logger:Info(string.format("Initialized mushrooms for %s", player.Name))
end

function MushroomDataService:_createDefaultMushrooms(player)
    Logger:Info(string.format("🔥 Creating default mushrooms for %s", player.Name))
    -- Create default mushroom layout
    local defaultMushrooms = {
        Area1 = {
            {position = {0, 0, 0}, type = "Mushroom_1"},
        }
    }
    
    for area, mushrooms in pairs(defaultMushrooms) do
        self._playerMushroomData[player][area] = {}
        for i, mushroomInfo in ipairs(mushrooms) do
            local mushroomId = string.format("mushroom_%s_%d", area, i)
            self._playerMushroomData[player][area][mushroomId] = {
                position = mushroomInfo.position,
                type = mushroomInfo.type,
                lastSporeSpawn = os.time(),
                id = mushroomId
            }
            Logger:Info(string.format("🔥 Created default mushroom %s in %s at position %s", mushroomId, area, tostring(mushroomInfo.position)))
        end
    end
end

function MushroomDataService:_sendAllMushroomData(player)
    local mushroomData = self._playerMushroomData[player]
    if not mushroomData then 
        Logger:Warn(string.format("🔥 No mushroom data to send for %s", player.Name))
        return 
    end
    
    Logger:Info(string.format("🔥 Sending mushroom data to %s", player.Name))
    for area, mushrooms in pairs(mushroomData) do
        for mushroomId, data in pairs(mushrooms) do
            Logger:Info(string.format("🔥 Sending: %s in %s (type: %s)", mushroomId, area, data.type))
        end
    end
    
    self._remoteEvents.UpdateMushroomData:FireClient(player, mushroomData)
end

function MushroomDataService:_sendMushroomUpdate(player, mushroomId, area, mushroomData)
    self._remoteEvents.UpdateMushroomData:FireClient(player, {
        [area] = {
            [mushroomId] = mushroomData
        }
    })
end

function MushroomDataService:AddMushroom(player, area)
    if not self._playerMushroomData[player] then
        self:InitializePlayerMushrooms(player)
    end
    
    if not self._playerMushroomData[player][area] then
        self._playerMushroomData[player][area] = {}
    end
    
    local mushroomCount = 0
    for _ in pairs(self._playerMushroomData[player][area]) do
        mushroomCount = mushroomCount + 1
    end
    
    local mushroomId = string.format("mushroom_%s_%d", area, mushroomCount + 1)
    local mushroomType = "Mushroom_1"
    if area == "Area2" then
        mushroomType = "Mushroom_3"
    elseif area == "Area3" then
        mushroomType = "Mushroom_5"  -- Assuming Area3 uses Mushroom_5
    end
    
    self._playerMushroomData[player][area][mushroomId] = {
        position = {math.random(-20, 20), 0, math.random(-20, 20)}, -- Random position
        type = mushroomType,
        lastSporeSpawn = os.time(),
        id = mushroomId
    }
    
    -- Send update to client
    self:_sendMushroomUpdate(player, mushroomId, area, self._playerMushroomData[player][area][mushroomId])
    
    Logger:Info(string.format("Added mushroom %s to %s for %s", mushroomId, area, player.Name))
    return true
end

function MushroomDataService:GetMushroomCount(player, area)
    local mushroomData = self._playerMushroomData[player]
    if not mushroomData or not mushroomData[area] then
        return 0
    end
    
    local count = 0
    for _ in pairs(mushroomData[area]) do
        count = count + 1
    end
    return count
end

function MushroomDataService:SetDataService(dataService)
    self._dataService = dataService
    Logger:Info("MushroomDataService linked with DataService")
end

function MushroomDataService:SetPlotService(plotService)
    self._plotService = plotService
    Logger:Info("MushroomDataService linked with PlotService")
end

function MushroomDataService:SetShopService(shopService)
    self._shopService = shopService
    Logger:Info("MushroomDataService linked with ShopService")
end

function MushroomDataService:Cleanup()
    Logger:Info("MushroomDataService shutting down...")
    
    for name, connection in pairs(self._connections) do
        if connection then
            HeartbeatManager.getInstance():unregister(connection)
        end
    end
    
    self._connections = {}
    self._playerMushroomData = {}
    
    Logger:Info("✓ MushroomDataService shutdown complete")
end

return MushroomDataService