local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)

local GroupRewardService = {}
GroupRewardService.__index = GroupRewardService

local GROUP_ID = 110618502  -- Sombers Games group ID
local REWARD_SPORES = 25000
local REWARD_GEMS = 1000

function GroupRewardService.new()
    local self = setmetatable({}, GroupRewardService)
    self._connections = {}
    self._dataService = nil
    self._notificationService = nil
    self._claimedCache = {} -- Permanent cache to prevent exploits - NEVER cleared
    self:_initialize()
    return self
end

function GroupRewardService:_initialize()
    self:_setupRemoteEvents()
    self:_setupPlayerCleanup()
    Logger:Info("GroupRewardService initialized")
end

function GroupRewardService:_setupRemoteEvents()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared then
        local remoteEvents = shared:FindFirstChild("RemoteEvents")
        if remoteEvents then
            local groupRewardEvents = remoteEvents:FindFirstChild("GroupRewardEvents")
            if groupRewardEvents then
                local claimGroupRewardEvent = groupRewardEvents:FindFirstChild("ClaimGroupReward")
                if claimGroupRewardEvent then
                    claimGroupRewardEvent.OnServerEvent:Connect(function(player)
                        self:HandleGroupRewardClaim(player)
                    end)
                    Logger:Info("GroupReward ClaimGroupReward event connected")
                end
                
                local getGroupRewardStatusEvent = groupRewardEvents:FindFirstChild("GetGroupRewardStatus")
                if getGroupRewardStatusEvent then
                    getGroupRewardStatusEvent.OnServerInvoke = function(player)
                        return self:GetGroupRewardStatus(player)
                    end
                    Logger:Info("GroupReward GetGroupRewardStatus function connected")
                end
            end
        end
    end
end

function GroupRewardService:_setupPlayerCleanup()
    -- SECURITY: Do NOT clean up the claimed cache when players leave
    -- The cache serves as a permanent record to prevent exploits
    -- Claimed rewards should remain in cache permanently to prevent double-claiming
    -- Memory usage is minimal since this only stores UserId -> true for claimed players
    
    Logger:Info("GroupRewardService: Cache cleanup disabled for security - claimed status persists permanently")
end

function GroupRewardService:HandleGroupRewardClaim(player)
    Logger:Info(string.format("Group reward claim attempt by player %s", player.Name))
    
    if not self._dataService then
        Logger:Error("DataService not linked to GroupRewardService")
        if self._notificationService then
            self._notificationService:ShowNotificationToPlayer(player, "Service error. Try again later.", "error")
        end
        return
    end
    
    -- Check if player has already claimed by looking at player data
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData then
        Logger:Error(string.format("Failed to get player data for %s", player.Name))
        if self._notificationService then
            self._notificationService:ShowNotificationToPlayer(player, "Error loading player data. Try again later.", "error")
        end
        return
    end
    
    -- SECURITY: Check cache first - it's the most reliable protection
    if self._claimedCache[player.UserId] then
        Logger:Info(string.format("Player %s (UserId: %d) blocked by cache - already claimed", 
            player.Name, player.UserId))
        if self._notificationService then
            self._notificationService:ShowNotificationToPlayer(player, "You have already claimed this reward!", "warning")
        end
        return
    end
    
    -- Check persistent data as backup
    if playerData.GroupRewards.claimed then
        Logger:Info(string.format("Player %s has already claimed group reward in persistent data", player.Name))
        -- Add to cache for future protection
        self._claimedCache[player.UserId] = true
        if self._notificationService then
            self._notificationService:ShowNotificationToPlayer(player, "You have already claimed this reward!", "warning")
        end
        return
    end
    
    -- Check if player is in the group
    local success, isInGroup = pcall(function()
        return player:IsInGroup(GROUP_ID)
    end)
    
    if not success then
        Logger:Error(string.format("Failed to check group membership for player %s: %s", player.Name, tostring(isInGroup)))
        if self._notificationService then
            self._notificationService:ShowNotificationToPlayer(player, "Error checking group membership. Try again later.", "error")
        end
        return
    end
    
    if not isInGroup then
        Logger:Info(string.format("Player %s is not in group %d", player.Name, GROUP_ID))
        if self._notificationService then
            self._notificationService:ShowNotificationToPlayer(player, "Complete the steps to claim your rewards!", "info")
        end
        return
    end
    
    -- Player is in group and hasn't claimed yet - award rewards
    Logger:Info(string.format("Player %s (UserId: %d) is in group %d, awarding rewards", player.Name, player.UserId, GROUP_ID))
    
    -- SECURITY: Add to cache IMMEDIATELY to prevent race conditions
    self._claimedCache[player.UserId] = true
    Logger:Info(string.format("Added %s (UserId: %d) to claim cache immediately for race condition protection", player.Name, player.UserId))
    
    -- Award spores and gems
    local sporeSuccess = self._dataService:AddSpores(player, REWARD_SPORES)
    local gemSuccess = self._dataService:AddGems(player, REWARD_GEMS)
    
    if sporeSuccess and gemSuccess then
        -- Mark player as having claimed the reward in persistent data
        Logger:Info(string.format("About to update GroupRewards data for %s", player.Name))
        local updateSuccess = self._dataService:UpdatePlayerData(player, function(data)
            Logger:Info(string.format("BEFORE UPDATE - %s GroupRewards.claimed: %s", player.Name, tostring(data.GroupRewards.claimed)))
            data.GroupRewards.claimed = true
            data.GroupRewards.claimTime = os.time()
            Logger:Info(string.format("AFTER UPDATE - %s GroupRewards.claimed: %s, claimTime: %s", 
                player.Name, tostring(data.GroupRewards.claimed), tostring(data.GroupRewards.claimTime)))
        end)
        Logger:Info(string.format("UpdatePlayerData completed for %s with result: %s", player.Name, tostring(updateSuccess)))
        
        if updateSuccess then
            local rewardText = string.format("%d Spores + %d Gems", REWARD_SPORES, REWARD_GEMS)
            Logger:Info(string.format("Successfully awarded group rewards to %s: %s", player.Name, rewardText))
            
            if self._notificationService then
                self._notificationService:ShowNotificationToPlayer(player, string.format("Group rewards claimed: %s!", rewardText), "itemReceived")
            end
        else
            Logger:Error(string.format("Failed to update claim status for %s", player.Name))
            -- Keep them in cache anyway since they got the rewards - prevents double claiming
            if self._notificationService then
                self._notificationService:ShowNotificationToPlayer(player, "Rewards awarded but claim status not saved. Contact support if you can claim again.", "warning")
            end
        end
    else
        Logger:Error(string.format("Failed to award rewards to %s - Spores: %s, Gems: %s", 
            player.Name, tostring(sporeSuccess), tostring(gemSuccess)))
        -- ROLLBACK: Remove from cache since they didn't get rewards
        self._claimedCache[player.UserId] = nil
        Logger:Info(string.format("Removed %s from claim cache due to failed reward distribution", player.Name))
        if self._notificationService then
            self._notificationService:ShowNotificationToPlayer(player, "Failed to award rewards. Try again later.", "error")
        end
    end
end

function GroupRewardService:GetGroupRewardStatus(player)
    if not self._dataService then
        Logger:Error("DataService not linked to GroupRewardService")
        return { claimed = false, error = "Service not available" }
    end
    
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData then
        Logger:Error(string.format("Failed to get player data for %s", player.Name))
        return { claimed = false, error = "Could not load player data" }
    end
    
    local persistentClaimed = playerData.GroupRewards.claimed
    local cacheClaimed = self._claimedCache[player.UserId] or false
    local hasClaimed = persistentClaimed or cacheClaimed
    
    Logger:Info(string.format("GetGroupRewardStatus for %s: persistent=%s, cache=%s, final=%s, claimTime=%s", 
        player.Name, tostring(persistentClaimed), tostring(cacheClaimed), tostring(hasClaimed), tostring(playerData.GroupRewards.claimTime)))
    
    return { claimed = hasClaimed, error = nil }
end

function GroupRewardService:_populateClaimCache(player, playerData)
    if playerData and playerData.GroupRewards and playerData.GroupRewards.claimed then
        self._claimedCache[player.UserId] = true
        Logger:Info(string.format("Populated claim cache for %s (UserId: %d) - already claimed at %s", 
            player.Name, player.UserId, tostring(playerData.GroupRewards.claimTime)))
    end
end

function GroupRewardService:SetDataService(dataService)
    self._dataService = dataService
    
    -- Populate cache with existing players when they join
    if dataService.PlayerDataLoaded then
        self._connections.PlayerDataLoaded = dataService.PlayerDataLoaded:Connect(function(player, playerData, isNewPlayer)
            self:_populateClaimCache(player, playerData)
        end)
    end
    
    -- Populate cache for current players
    for _, player in pairs(Players:GetPlayers()) do
        local playerData = dataService:GetPlayerData(player)
        if playerData then
            self:_populateClaimCache(player, playerData)
        end
    end
    
    Logger:Debug("GroupRewardService linked with DataService")
end

function GroupRewardService:SetNotificationService(notificationService)
    self._notificationService = notificationService
    Logger:Debug("GroupRewardService linked with NotificationService")
end

function GroupRewardService:Cleanup()
    for connectionName, connection in pairs(self._connections) do
        if connection then
            connection:Disconnect()
        end
    end
    self._connections = {}
    
    Logger:Info("GroupRewardService cleaned up")
end

return GroupRewardService