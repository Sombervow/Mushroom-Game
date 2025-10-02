local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Logger = require(script.Parent.Parent.Utilities.Logger)

local PlayerService = {}
PlayerService.__index = PlayerService

function PlayerService.new()
    local self = setmetatable({}, PlayerService)
    self._connections = {}
    self._dataService = nil
    self._plotService = nil
    self:_initialize()
    return self
end

function PlayerService:_initialize()
    self._connections.PlayerAdded = Players.PlayerAdded:Connect(function(player)
        self:_onPlayerJoined(player)
    end)
    
    self._connections.CharacterAdded = Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            self:_onCharacterSpawned(player, character)
        end)
    end)
    
    Logger:Info("PlayerService initialized successfully")
end

function PlayerService:SetServices(dataService, plotService, robloxAnalyticsService)
    self._dataService = dataService
    self._plotService = plotService
    self._robloxAnalyticsService = robloxAnalyticsService
    
    -- Listen for player data loaded to update leaderstats
    if dataService and dataService.PlayerDataLoaded then
        self._connections.PlayerDataLoaded = dataService.PlayerDataLoaded:Connect(function(player, playerData)
            self:_updateLeaderstats(player, playerData)
        end)
    end
    
    Logger:Debug("PlayerService linked with DataService and PlotService")
end

function PlayerService:_onPlayerJoined(player)
    Logger:Info(string.format("Player %s joined the game (ID: %d)", player.Name, player.UserId))
    
    self:_createLeaderstats(player)
    
    player.CharacterAdded:Connect(function(character)
        self:_onCharacterSpawned(player, character)
    end)
end

function PlayerService:_onCharacterSpawned(player, character)
    -- Wait for character to fully load
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
    if not humanoidRootPart then
        Logger:Error(string.format("HumanoidRootPart not found for player %s", player.Name))
        return
    end
    
    wait(0.5) -- Additional wait to ensure everything is ready
    
    -- Track analytics for player spawning
    if self._robloxAnalyticsService then
        self._robloxAnalyticsService:TrackPlayerSpawned(player)
    end
    
    if self._plotService then
        local success = self._plotService:TeleportPlayerToPlot(player)
        if not success then
            Logger:Warn(string.format("Failed to teleport %s to plot", player.Name))
        end
    else
        Logger:Warn("PlotService not available for character spawn handling")
    end
end

function PlayerService:HandlePlayerRespawn(player)
    if not player.Character then
        Logger:Warn(string.format("Cannot respawn player %s - no character", player.Name))
        return false
    end
    
    if self._plotService then
        local success = self._plotService:TeleportPlayerToPlot(player)
        if success then
            Logger:Info(string.format("Respawned player %s to their plot", player.Name))
            return true
        else
            Logger:Error(string.format("Failed to respawn player %s to plot", player.Name))
            return false
        end
    else
        Logger:Error("PlotService not available for respawn handling")
        return false
    end
end

function PlayerService:GetPlayerStats(player)
    if not self._dataService then
        Logger:Warn("DataService not available for stats retrieval")
        return nil
    end
    
    local data = self._dataService:GetPlayerData(player)
    if not data then
        return nil
    end
    
    return {
        Spores = data.Spores,
        Gems = data.Gems,
        AssignedPlot = data.AssignedPlot
    }
end

function PlayerService:GetPlayerPlotInfo(player)
    if not self._plotService then
        Logger:Warn("PlotService not available for plot info")
        return nil
    end
    
    local plotId = self._plotService:GetPlayerPlot(player)
    local spawnPoint = self._plotService:GetPlayerSpawnPoint(player)
    
    return {
        plotId = plotId,
        spawnPoint = spawnPoint and spawnPoint.Position or nil
    }
end

function PlayerService:TeleportPlayerToPlot(player, plotId)
    if not self._plotService then
        Logger:Warn("PlotService not available for teleportation")
        return false
    end
    
    return self._plotService:TeleportPlayerToPlot(player, plotId)
end

function PlayerService:GivePlayerReward(player, spores, gems)
    if not self._dataService then
        Logger:Warn("DataService not available for rewards")
        return false
    end
    
    local success = true
    
    if spores and spores > 0 then
        success = success and self._dataService:AddSpores(player, spores)
    end
    
    if gems and gems > 0 then
        success = success and self._dataService:AddGems(player, gems)
    end
    
    if success then
        Logger:Info(string.format("Gave player %s rewards: %d spores, %d gems", 
            player.Name, spores or 0, gems or 0))
    else
        Logger:Error(string.format("Failed to give rewards to player %s", player.Name))
    end
    
    return success
end

function PlayerService:DeductPlayerCurrency(player, spores, gems)
    if not self._dataService then
        Logger:Warn("DataService not available for currency deduction")
        return false
    end
    
    local success = true
    
    if spores and spores > 0 then
        success = success and self._dataService:SpendSpores(player, spores)
    end
    
    if gems and gems > 0 then
        success = success and self._dataService:SpendGems(player, gems)
    end
    
    if success then
        Logger:Info(string.format("Deducted from player %s: %d spores, %d gems", 
            player.Name, spores or 0, gems or 0))
    else
        Logger:Warn(string.format("Failed to deduct currency from player %s", player.Name))
    end
    
    return success
end

function PlayerService:SavePlayerData(player)
    if not self._dataService then
        Logger:Warn("DataService not available for manual save")
        return false
    end
    
    return self._dataService:ManualSave(player)
end

function PlayerService:KickPlayer(player, reason)
    reason = reason or "Kicked by administrator"
    Logger:Info(string.format("Kicking player %s: %s", player.Name, reason))
    player:Kick(reason)
end

function PlayerService:GetOnlinePlayers()
    local onlinePlayers = {}
    for _, player in pairs(Players:GetPlayers()) do
        table.insert(onlinePlayers, {
            name = player.Name,
            userId = player.UserId,
            displayName = player.DisplayName,
            accountAge = player.AccountAge
        })
    end
    return onlinePlayers
end

function PlayerService:GetPlayerByName(playerName)
    for _, player in pairs(Players:GetPlayers()) do
        if string.lower(player.Name) == string.lower(playerName) or 
           string.lower(player.DisplayName) == string.lower(playerName) then
            return player
        end
    end
    return nil
end

function PlayerService:IsPlayerInGame(userId)
    return Players:GetPlayerByUserId(userId) ~= nil
end

function PlayerService:BroadcastMessage(message, excludePlayer)
    Logger:Info(string.format("Broadcasting message: %s", message))
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= excludePlayer then
            local gui = player:FindFirstChild("PlayerGui")
            if gui then
            end
        end
    end
end

function PlayerService:_createLeaderstats(player)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player
    
    local spores = Instance.new("NumberValue")
    spores.Name = "Spores"
    spores.Value = 0
    spores.Parent = leaderstats
    
    local gems = Instance.new("NumberValue")
    gems.Name = "Gems"
    gems.Value = 0
    gems.Parent = leaderstats
    
    -- RobuxSpent removed from Roblox leaderstats - only tracked in custom leaderboards
    
    Logger:Debug(string.format("Created leaderstats for player %s (Spores, Gems only)", player.Name))
end

function PlayerService:_updateLeaderstats(player, playerData)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then
        Logger:Warn(string.format("Leaderstats not found for player %s", player.Name))
        return
    end
    
    local spores = leaderstats:FindFirstChild("Spores")
    if spores then
        spores.Value = playerData.Spores or 0
    end
    
    local gems = leaderstats:FindFirstChild("Gems")
    if gems then
        gems.Value = playerData.Gems or 0
    end
    
    -- RobuxSpent no longer updated in Roblox leaderstats - only tracked in custom leaderboards
    
    Logger:Debug(string.format("Updated leaderstats for %s: %d spores, %d gems", 
        player.Name, playerData.Spores or 0, playerData.Gems or 0))
end

function PlayerService:UpdatePlayerLeaderstats(player)
    if not self._dataService then
        Logger:Warn("DataService not available for leaderstats update")
        return
    end
    
    local playerData = self._dataService:GetPlayerData(player)
    if playerData then
        self:_updateLeaderstats(player, playerData)
    end
end

function PlayerService:Cleanup()
    for connectionName, connection in pairs(self._connections) do
        if connection then
            connection:Disconnect()
        end
    end
    self._connections = {}
    
    Logger:Info("PlayerService cleaned up")
end

return PlayerService