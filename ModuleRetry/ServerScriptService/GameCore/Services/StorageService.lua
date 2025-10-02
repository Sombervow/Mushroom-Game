local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local Constants = require(ReplicatedStorage.Shared.Modules.Constants)

local StorageService = {}
StorageService.__index = StorageService

function StorageService.new()
    local self = setmetatable({}, StorageService)
    
    -- Track spore counts per area per player
    self.playerAreaStorage = {} -- [userId][area] = count
    
    -- Services (to be linked)
    self.dataService = nil
    
    Logger:Info("StorageService initialized successfully")
    return self
end

-- Link dependencies
function StorageService:LinkDataService(dataService)
    self.dataService = dataService
    Logger:Info("✓ StorageService linked with DataService")
end

-- Get current spore count in a specific area for a player
function StorageService:GetAreaSporeCount(player, area)
    local userId = player.UserId
    if not self.playerAreaStorage[userId] then
        self.playerAreaStorage[userId] = {}
    end
    return self.playerAreaStorage[userId][area] or 0
end

-- Check if an area has space for more spores
function StorageService:CanSpawnSporeInArea(player, area)
    local currentCount = self:GetAreaSporeCount(player, area)
    return currentCount < Constants.STORAGE.MAX_SPORES_PER_AREA
end

-- Get storage capacity info for an area
function StorageService:GetAreaStorageInfo(player, area)
    local currentCount = self:GetAreaSporeCount(player, area)
    local maxCount = Constants.STORAGE.MAX_SPORES_PER_AREA
    local percentage = math.floor((currentCount / maxCount) * 1000) / 10 -- Round to 0.1%
    
    return {
        current = currentCount,
        max = maxCount,
        percentage = percentage,
        isFull = currentCount >= maxCount
    }
end

-- Track spore spawning in an area
function StorageService:OnSporeSpawned(player, area)
    local userId = player.UserId
    if not self.playerAreaStorage[userId] then
        self.playerAreaStorage[userId] = {}
    end
    
    self.playerAreaStorage[userId][area] = (self.playerAreaStorage[userId][area] or 0) + 1
    
    -- Update the storage display for this area
    self:UpdateStorageDisplay(player, area)
end

-- Track spore collection from an area
function StorageService:OnSporeCollected(player, area)
    local userId = player.UserId
    if not self.playerAreaStorage[userId] then
        return
    end
    
    if self.playerAreaStorage[userId][area] then
        self.playerAreaStorage[userId][area] = math.max(0, self.playerAreaStorage[userId][area] - 1)
        
        -- Update the storage display for this area
        self:UpdateStorageDisplay(player, area)
    end
end

-- Update the storage display UI for a specific area
function StorageService:UpdateStorageDisplay(player, area)
    local plot = self:_getPlayerPlot(player)
    if not plot then return end
    
    local storageInfo = self:GetAreaStorageInfo(player, area)
    
    -- Find the StorageSign for this area
    local areaFolder = (area == "Area1") and plot or plot:FindFirstChild(area)
    if not areaFolder then return end
    
    local storageSign = areaFolder:FindFirstChild("StorageSign")
    if not storageSign then return end
    
    local storageTracker = storageSign:FindFirstChild("StorageTracker")
    if not storageTracker then return end
    
    local surfaceGui = storageTracker:FindFirstChild("SurfaceGui")
    if not surfaceGui then return end
    
    local frame = surfaceGui:FindFirstChild("Frame")
    if not frame then return end
    
    local barContainer = frame:FindFirstChild("BarContainer")
    if not barContainer then return end
    
    local progressBar = barContainer:FindFirstChild("ProgressBar")
    local progressPercent = barContainer:FindFirstChild("ProgressPercent")
    
    -- Update progress bar if it exists
    if progressBar then
        local scaleX = storageInfo.percentage / 100
        progressBar.Size = UDim2.new(scaleX, 0, 1, 0)
        
        -- Change color based on capacity
        if storageInfo.percentage >= 100 then
            progressBar.BackgroundColor3 = Color3.fromRGB(255, 100, 100) -- Red when full
        elseif storageInfo.percentage >= 80 then
            progressBar.BackgroundColor3 = Color3.fromRGB(255, 200, 100) -- Orange when almost full
        else
            progressBar.BackgroundColor3 = Color3.fromRGB(100, 255, 100) -- Green when space available
        end
    end
    
    -- Update percentage text if it exists
    if progressPercent then
        progressPercent.Text = string.format("%.1f%%", storageInfo.percentage)
    end
end

-- Initialize storage tracking for a player (called when player joins)
function StorageService:InitializePlayerStorage(player)
    local userId = player.UserId
    self.playerAreaStorage[userId] = {}
    
    -- Count existing spores in each area
    local plot = self:_getPlayerPlot(player)
    if plot then
        Logger:Info(string.format("Initializing storage for %s - counting existing spores", player.Name))
        for _, area in ipairs(Constants.STORAGE.AREAS) do
            local count = self:_countExistingSpores(plot, area)
            self.playerAreaStorage[userId][area] = count
            Logger:Info(string.format("%s %s: Found %d existing spores", player.Name, area, count))
            self:UpdateStorageDisplay(player, area)
        end
    else
        Logger:Warn(string.format("Could not find plot for %s during storage initialization", player.Name))
    end
end

-- Count existing spores in an area (for initialization)
function StorageService:_countExistingSpores(plot, area)
    local sporesFolder
    
    if area == "Area1" then
        sporesFolder = plot:FindFirstChild("Spores")
    else
        local areaFolder = plot:FindFirstChild(area)
        if areaFolder then
            sporesFolder = areaFolder:FindFirstChild("Spores")
        end
    end
    
    if not sporesFolder then return 0 end
    
    local count = 0
    for _, child in ipairs(sporesFolder:GetChildren()) do
        -- Count all spore types including BigSpores
        if child.Name:match("Spore_") or child.Name:match("GoldSpore_") or child.Name:match("BigSpore_") then
            count = count + 1
        end
    end
    
    return count
end

-- Helper function to get player's plot
function StorageService:_getPlayerPlot(player)
    local plotName = Constants.PLOT.PLOT_PREFIX .. player.Name
    return workspace.PlayerPlots:FindFirstChild(plotName)
end

-- Manually recount spores for a player (for debugging/fixing sync issues)
function StorageService:RecountPlayerSpores(player)
    local plot = self:_getPlayerPlot(player)
    if not plot then 
        Logger:Warn(string.format("Cannot recount spores - plot not found for %s", player.Name))
        return 
    end
    
    local userId = player.UserId
    if not self.playerAreaStorage[userId] then
        self.playerAreaStorage[userId] = {}
    end
    
    Logger:Info(string.format("Recounting spores for %s", player.Name))
    for _, area in ipairs(Constants.STORAGE.AREAS) do
        local oldCount = self.playerAreaStorage[userId][area] or 0
        local newCount = self:_countExistingSpores(plot, area)
        self.playerAreaStorage[userId][area] = newCount
        Logger:Info(string.format("%s %s: %d -> %d spores (difference: %+d)", 
            player.Name, area, oldCount, newCount, newCount - oldCount))
        self:UpdateStorageDisplay(player, area)
    end
end

-- Cleanup when player leaves
function StorageService:CleanupPlayer(player)
    local userId = player.UserId
    if self.playerAreaStorage[userId] then
        self.playerAreaStorage[userId] = nil
        Logger:Info(string.format("Cleaned up storage tracking for %s", player.Name))
    end
end

function StorageService:Cleanup()
    Logger:Info("StorageService shutting down...")
    self.playerAreaStorage = {}
    Logger:Info("✓ StorageService shutdown complete")
end

return StorageService