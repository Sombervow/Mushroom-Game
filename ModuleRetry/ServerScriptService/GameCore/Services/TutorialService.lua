local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)

local TutorialService = {}
TutorialService.__index = TutorialService

function TutorialService.new()
    local self = setmetatable({}, TutorialService)
    
    -- Player tutorial completion data
    self.playerTutorialData = {}
    
    -- Remote events
    self.remoteEvents = nil
    self.completeTutorialRemote = nil
    self.startTutorialRemote = nil
    self.syncTutorialStatusRemote = nil
    
    -- Services
    self.dataService = nil
    self.notificationService = nil
    self.wishService = nil
    
    self:_initialize()
    return self
end

function TutorialService:_initialize()
    Logger:Info("TutorialService initializing...")
    
    self:_setupRemoteEvents()
    self:_connectPlayerEvents()
    
    Logger:Info("✓ TutorialService initialized")
end

function TutorialService:_setupRemoteEvents()
    -- Wait for shared folder
    local shared = ReplicatedStorage:WaitForChild("Shared", 10)
    if not shared then
        Logger:Error("Shared folder not found in ReplicatedStorage")
        return
    end
    
    local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
    if not remoteEvents then
        Logger:Error("RemoteEvents folder not found in Shared")
        return
    end
    
    -- Create tutorial remotes folder
    local tutorialRemotes = Instance.new("Folder")
    tutorialRemotes.Name = "TutorialRemotes"
    tutorialRemotes.Parent = remoteEvents
    
    -- Create remote events
    self.completeTutorialRemote = Instance.new("RemoteEvent")
    self.completeTutorialRemote.Name = "CompleteTutorial"
    self.completeTutorialRemote.Parent = tutorialRemotes
    
    self.startTutorialRemote = Instance.new("RemoteEvent")
    self.startTutorialRemote.Name = "StartTutorial"
    self.startTutorialRemote.Parent = tutorialRemotes
    
    self.syncTutorialStatusRemote = Instance.new("RemoteEvent")
    self.syncTutorialStatusRemote.Name = "SyncTutorialStatus"
    self.syncTutorialStatusRemote.Parent = tutorialRemotes
    
    self.requestWishRewardRemote = Instance.new("RemoteEvent")
    self.requestWishRewardRemote.Name = "RequestWishReward"
    self.requestWishRewardRemote.Parent = tutorialRemotes
    
    -- Connect remote event handlers
    self.completeTutorialRemote.OnServerEvent:Connect(function(player)
        self:_onTutorialCompleted(player)
    end)
    
    self.syncTutorialStatusRemote.OnServerEvent:Connect(function(player)
        self:_onSyncTutorialStatus(player)
    end)
    
    self.requestWishRewardRemote.OnServerEvent:Connect(function(player)
        self:_giveWishReward(player)
    end)
    
    self.remoteEvents = tutorialRemotes
    
    Logger:Info("✓ Tutorial remote events created and connected")
end

function TutorialService:_connectPlayerEvents()
    -- Handle player joining
    Players.PlayerAdded:Connect(function(player)
        self:_onPlayerAdded(player)
    end)
    
    -- Handle existing players
    for _, player in pairs(Players:GetPlayers()) do
        self:_onPlayerAdded(player)
    end
    
    -- Handle player leaving
    Players.PlayerRemoving:Connect(function(player)
        self:_onPlayerRemoving(player)
    end)
end

function TutorialService:_onPlayerAdded(player)
    Logger:Info("Loading tutorial data for player: " .. player.Name)
    
    -- Initialize player data
    self.playerTutorialData[player] = {
        tutorialCompleted = false,
        dataLoaded = false
    }
    
    -- Load tutorial completion status
    spawn(function()
        self:_loadPlayerTutorialData(player)
    end)
end

function TutorialService:_onPlayerRemoving(player)
    -- Clean up player data
    self.playerTutorialData[player] = nil
    Logger:Info("Cleaned up tutorial data for player: " .. player.Name)
end

function TutorialService:_loadPlayerTutorialData(player)
    local playerData = self.playerTutorialData[player]
    if not playerData then return end
    
    Logger:Info(string.format("Loading tutorial data for %s...", player.Name))
    
    -- Wait for DataService to be available before loading tutorial data
    local maxWaitTime = 30 -- Maximum 30 seconds wait
    local waitStartTime = os.time()
    
    while not self.dataService and (os.time() - waitStartTime) < maxWaitTime do
        task.wait(0.5)
        Logger:Debug(string.format("Waiting for DataService to load tutorial data for %s...", player.Name))
    end
    
    -- Use only the main DataService for tutorial completion
    local tutorialCompleted = false
    if self.dataService then
        local mainPlayerData = self.dataService:GetPlayerData(player)
        Logger:Info(string.format("Raw player data for %s: %s", player.Name, mainPlayerData and "exists" or "nil"))
        
        if mainPlayerData then
            Logger:Info(string.format("TutorialCompleted field for %s: %s (type: %s)", 
                player.Name, tostring(mainPlayerData.TutorialCompleted), type(mainPlayerData.TutorialCompleted)))
        end
        
        if mainPlayerData and mainPlayerData.TutorialCompleted ~= nil then
            tutorialCompleted = mainPlayerData.TutorialCompleted
            Logger:Info(string.format("Tutorial status from main data for %s: %s (TutorialCompleted field exists)", 
                player.Name, tutorialCompleted and "COMPLETED" or "NOT COMPLETED"))
        else
            -- Brand new player - no tutorial data in main store
            tutorialCompleted = false
            if mainPlayerData then
                Logger:Info(string.format("No TutorialCompleted field in data for %s - treating as new player (data exists but field missing)", player.Name))
            else
                Logger:Info(string.format("No player data found for %s - treating as new player (completely new)", player.Name))
            end
        end
    else
        Logger:Error(string.format("DataService still not available after %d seconds - this indicates a critical initialization issue", maxWaitTime))
        tutorialCompleted = false
    end
    
    playerData.tutorialCompleted = tutorialCompleted
    playerData.dataLoaded = true
    
    Logger:Info(string.format("Final tutorial decision for %s: %s", 
        player.Name, playerData.tutorialCompleted and "COMPLETED" or "NOT COMPLETED"))
    
    -- Decide whether to start tutorial - reduced delay since we already waited for DataService
    spawn(function()
        task.wait(2) -- Reduced wait since DataService is now guaranteed to be available
        self:_decideTutorialStart(player)
    end)
end

function TutorialService:_decideTutorialStart(player)
    local playerData = self.playerTutorialData[player]
    if not playerData or not playerData.dataLoaded then return end
    
    if not playerData.tutorialCompleted then
        Logger:Info("Starting tutorial for new player: " .. player.Name)
        self:_startTutorialForPlayer(player)
    else
        Logger:Info("Player " .. player.Name .. " has already completed tutorial")
    end
end

function TutorialService:_startTutorialForPlayer(player)
    if not self.startTutorialRemote then
        Logger:Warn("StartTutorial remote not available")
        return
    end
    
    -- Fire to client to start tutorial
    self.startTutorialRemote:FireClient(player)
    Logger:Info("Sent start tutorial request to: " .. player.Name)
end

function TutorialService:_onTutorialCompleted(player)
    Logger:Info("Tutorial completed by player: " .. player.Name)
    
    local playerData = self.playerTutorialData[player]
    if not playerData then return end
    
    -- Update local data
    playerData.tutorialCompleted = true
    
    -- Save to data store immediately (no spawn to avoid race conditions)
    self:_saveTutorialCompletion(player)
    
    -- Optionally give rewards
    self:_giveCompletionRewards(player)
end

function TutorialService:_saveTutorialCompletion(player)
    -- Save to main DataService using the proper API
    if self.dataService then
        Logger:Info(string.format("Saving tutorial completion for %s - Step 1: Updating cache", player.Name))
        
        local success = self.dataService:UpdatePlayerData(player, function(data)
            local oldValue = data.TutorialCompleted
            data.TutorialCompleted = true
            Logger:Info(string.format("Tutorial completion for %s: %s -> %s", player.Name, tostring(oldValue), tostring(data.TutorialCompleted)))
        end)
        
        if success then
            Logger:Info("Tutorial completion updated in cache for player: " .. player.Name)
            
            -- Verify the cache was actually updated
            local playerData = self.dataService:GetPlayerData(player)
            if playerData and playerData.TutorialCompleted then
                Logger:Info(string.format("Cache verification SUCCESS: %s TutorialCompleted = %s", player.Name, tostring(playerData.TutorialCompleted)))
            else
                Logger:Error(string.format("Cache verification FAILED: %s TutorialCompleted = %s", player.Name, playerData and tostring(playerData.TutorialCompleted) or "no data"))
            end
            
            -- FIXED: Force immediate save to DataStore to ensure persistence
            Logger:Info(string.format("Saving tutorial completion for %s - Step 2: Saving to DataStore", player.Name))
            local saveSuccess = self.dataService:ManualSave(player)
            if saveSuccess then
                Logger:Info("Tutorial completion SAVED TO DATASTORE for player: " .. player.Name)
                
                -- Final verification by re-reading from cache
                local finalData = self.dataService:GetPlayerData(player)
                Logger:Info(string.format("Final verification: %s TutorialCompleted = %s", player.Name, finalData and tostring(finalData.TutorialCompleted) or "no data"))
            else
                Logger:Error("Failed to save tutorial completion to DataStore for player: " .. player.Name)
            end
            
            -- NOTE: We don't sync tutorial status here to avoid interfering with client's final steps
            -- The client will handle its own completion flow after final steps finish
        else
            Logger:Error("Failed to update tutorial completion in cache for player: " .. player.Name)
        end
    else
        Logger:Error("DataService not available - cannot save tutorial completion for player: " .. player.Name)
    end
end

function TutorialService:_giveCompletionRewards(player)
    -- Give tutorial completion rewards
    if self.dataService then
        -- Give some starting spores as a reward
        self.dataService:AddSpores(player, 500)
        Logger:Info("Awarded 500 spores to " .. player.Name .. " for completing tutorial")
    end
end

function TutorialService:_giveWishReward(player)
    if not self.dataService then
        Logger:Error("DataService not available for wish reward")
        return
    end
    
    -- FIXED: Use UpdatePlayerData to properly save the wish reward
    local success = self.dataService:UpdatePlayerData(player, function(data)
        -- Ensure WishData exists
        if not data.WishData then
            data.WishData = {
                wishes = 0,
                lastWishTime = os.time(),
                inventory = {}
            }
        end
        
        -- Add 1 wish (cap at 5)
        local oldWishes = data.WishData.wishes
        data.WishData.wishes = math.min(data.WishData.wishes + 1, 5)
        
        Logger:Info(string.format("Tutorial wish reward: %s wishes updated from %d to %d", 
            player.Name, oldWishes, data.WishData.wishes))
    end)
    
    if success then
        Logger:Info("Tutorial wish reward saved successfully for " .. player.Name)
        
        -- FIXED: Send wish notification to player
        if self.notificationService then
            self.notificationService:ShowWishEarned(player)
        else
            Logger:Warn("NotificationService not available - wish notification not sent")
        end
        
        -- FIXED: Update wish GUI if WishService is available
        if self.wishService then
            self.wishService:UpdatePlayerWishGUI(player)
        else
            Logger:Debug("WishService not available - GUI not updated (will update when player opens wish UI)")
        end
    else
        Logger:Error("Failed to save tutorial wish reward for " .. player.Name)
    end
end

function TutorialService:_onSyncTutorialStatus(player)
    local playerData = self.playerTutorialData[player]
    if not playerData or not playerData.dataLoaded then
        Logger:Warn("Tutorial status sync requested but data not loaded for: " .. player.Name)
        return
    end
    
    -- Send current status to client
    if self.syncTutorialStatusRemote then
        self.syncTutorialStatusRemote:FireClient(player, playerData.tutorialCompleted)
        Logger:Info(string.format("Synced tutorial status for %s: %s", 
            player.Name, playerData.tutorialCompleted and "COMPLETED" or "INCOMPLETE"))
    end
end

-- Public methods
function TutorialService:IsPlayerTutorialCompleted(player)
    local playerData = self.playerTutorialData[player]
    if not playerData then return false end
    
    return playerData.tutorialCompleted
end

function TutorialService:ForceStartTutorial(player)
    Logger:Info("Force starting tutorial for player: " .. player.Name)
    self:_startTutorialForPlayer(player)
end

function TutorialService:ResetPlayerTutorial(player)
    Logger:Info("Resetting tutorial for player: " .. player.Name)
    
    local playerData = self.playerTutorialData[player]
    if playerData then
        playerData.tutorialCompleted = false
    end
    
    -- Reset in main DataService using the proper API
    if self.dataService then
        local success = self.dataService:UpdatePlayerData(player, function(data)
            data.TutorialCompleted = false
        end)
        
        if success then
            Logger:Info("Tutorial reset in main data for player: " .. player.Name)
        else
            Logger:Error("Failed to reset tutorial in main data for player: " .. player.Name)
        end
    end
    
    -- Start tutorial again since it's been reset
    self:_startTutorialForPlayer(player)
end

-- Service linking
function TutorialService:SetDataService(dataService)
    self.dataService = dataService
end

function TutorialService:SetNotificationService(notificationService)
    self.notificationService = notificationService
    Logger:Info("TutorialService linked with NotificationService")
end

function TutorialService:SetWishService(wishService)
    self.wishService = wishService
    Logger:Info("TutorialService linked with WishService")
end

function TutorialService:Cleanup()
    -- Clean up player data
    self.playerTutorialData = {}
    
    -- Clean up remote events
    if self.remoteEvents then
        self.remoteEvents:Destroy()
        self.remoteEvents = nil
    end
    
    Logger:Info("✓ TutorialService cleanup complete")
end

return TutorialService