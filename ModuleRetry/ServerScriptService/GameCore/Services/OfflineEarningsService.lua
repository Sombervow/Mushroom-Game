local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local Validator = require(script.Parent.Parent.Utilities.Validator)

local OfflineEarningsService = {}
OfflineEarningsService.__index = OfflineEarningsService

-- Configuration
local CONFIG = {
    BASE_EARNINGS_PER_SECOND = 1, -- Base spores earned per second while offline
    MAX_OFFLINE_HOURS = 24, -- Maximum hours of offline earnings
    MINIMUM_OFFLINE_TIME = 60, -- Minimum seconds offline to show earnings screen
}

function OfflineEarningsService.new()
    local self = setmetatable({}, OfflineEarningsService)
    
    self._dataService = nil
    self._connections = {}
    
    self:_initialize()
    return self
end

function OfflineEarningsService:_initialize()
    Logger:Info("OfflineEarningsService initializing...")
    
    self:_setupRemoteEvents()
    self:_setupPlayerConnections()
    
    Logger:Info("✓ OfflineEarningsService initialized")
end

function OfflineEarningsService:_setupRemoteEvents()
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local remoteEvents = shared:WaitForChild("RemoteEvents")
    
    -- Create ShowOfflineEarnings remote event
    local showOfflineEarnings = Instance.new("RemoteEvent")
    showOfflineEarnings.Name = "ShowOfflineEarnings"
    showOfflineEarnings.Parent = remoteEvents
    
    -- Create ClaimOfflineEarnings remote event
    local claimOfflineEarnings = Instance.new("RemoteEvent")
    claimOfflineEarnings.Name = "ClaimOfflineEarnings"
    claimOfflineEarnings.Parent = remoteEvents
    
    claimOfflineEarnings.OnServerEvent:Connect(function(player, amount)
        self:HandleClaimRequest(player, amount)
    end)
    
    self.showOfflineEarningsEvent = showOfflineEarnings
    self.claimOfflineEarningsEvent = claimOfflineEarnings
end

function OfflineEarningsService:_setupPlayerConnections()
    -- Handle player joining
    local connection = Players.PlayerAdded:Connect(function(player)
        self:_onPlayerJoined(player)
    end)
    table.insert(self._connections, connection)
    
    -- Handle existing players
    for _, player in pairs(Players:GetPlayers()) do
        self:_onPlayerJoined(player)
    end
end

function OfflineEarningsService:_onPlayerJoined(player)
    -- Wait for DataService to load player data, then check offline earnings
    spawn(function()
        wait(3) -- Give DataService time to load player data
        
        if self._dataService then
            self:CheckOfflineEarnings(player)
        else
            Logger:Warn("DataService not available for offline earnings check")
        end
    end)
end

function OfflineEarningsService:CheckOfflineEarnings(player)
    if not self._dataService then
        Logger:Error("DataService not available")
        return
    end
    
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData then
        Logger:Warn(string.format("No player data found for %s", player.Name))
        return
    end
    
    local currentTime = tick()
    local lastSave = playerData.LastSave or currentTime
    local offlineTime = currentTime - lastSave
    
    Logger:Info(string.format("Player %s was offline for %.1f seconds", player.Name, offlineTime))
    
    -- Check if player was offline long enough to show earnings
    if offlineTime >= CONFIG.MINIMUM_OFFLINE_TIME then
        local maxOfflineTime = CONFIG.MAX_OFFLINE_HOURS * 3600 -- Convert to seconds
        local cappedOfflineTime = math.min(offlineTime, maxOfflineTime)
        
        local earningsPerSecond = self:CalculateEarningsPerSecond(player, playerData)
        
        Logger:Info(string.format("Showing offline earnings to %s: %.1f seconds at %.2f per second", 
            player.Name, cappedOfflineTime, earningsPerSecond))
        
        -- Show offline earnings UI to client
        self.showOfflineEarningsEvent:FireClient(player, cappedOfflineTime, earningsPerSecond)
    else
        Logger:Info(string.format("Player %s offline time too short: %.1f seconds", player.Name, offlineTime))
    end
end

function OfflineEarningsService:CalculateEarningsPerSecond(player, playerData)
    -- Base earnings per second
    local baseEarnings = CONFIG.BASE_EARNINGS_PER_SECOND
    
    -- Calculate multipliers based on player's mushrooms and upgrades
    local mushroomMultiplier = self:_calculateMushroomMultiplier(playerData)
    
    -- You can add more multipliers here based on:
    -- - Player level
    -- - Purchased upgrades
    -- - Premium status
    -- - Special events
    
    local totalEarnings = baseEarnings * mushroomMultiplier
    
    Logger:Debug(string.format("Earnings calculation for %s: base=%.2f, mushroom=%.2f, total=%.2f", 
        player.Name, baseEarnings, mushroomMultiplier, totalEarnings))
    
    return totalEarnings
end

function OfflineEarningsService:_calculateMushroomMultiplier(playerData)
    local multiplier = 1.0
    
    if playerData.PlotObjects and playerData.PlotObjects.Mushrooms then
        local mushroomCount = 0
        for _, mushroomData in pairs(playerData.PlotObjects.Mushrooms) do
            mushroomCount = mushroomCount + 1
        end
        
        -- Each mushroom adds 10% to offline earnings (0.1 multiplier)
        multiplier = multiplier + (mushroomCount * 0.1)
    end
    
    return multiplier
end

function OfflineEarningsService:HandleClaimRequest(player, amount)
    if not Validator:IsPositiveNumber(amount) or amount <= 0 then
        Logger:Warn(string.format("Invalid claim amount from %s: %s", player.Name, tostring(amount)))
        return
    end
    
    if not self._dataService then
        Logger:Error("DataService not available for claim")
        return
    end
    
    -- Add the claimed amount to player's spores
    local success = self._dataService:AddSpores(player, amount)
    
    if success then
        Logger:Info(string.format("Player %s claimed %d offline spores", player.Name, amount))
        
        -- Update last save time to prevent re-claiming
        local updateSuccess = self._dataService:UpdatePlayerData(player, function(data)
            data.LastSave = tick()
        end)
        
        if not updateSuccess then
            Logger:Warn(string.format("Failed to update LastSave time for %s", player.Name))
        end
    else
        Logger:Error(string.format("Failed to add claimed spores to %s", player.Name))
    end
end

function OfflineEarningsService:SetDataService(dataService)
    self._dataService = dataService
end

function OfflineEarningsService:Cleanup()
    Logger:Info("OfflineEarningsService shutting down...")
    
    for _, connection in pairs(self._connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    Logger:Info("✓ OfflineEarningsService shutdown complete")
end

return OfflineEarningsService