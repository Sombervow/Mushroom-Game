local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local HeartbeatManager = require(script.Parent.Parent.Utilities.HeartbeatManager)
local SignalManager = require(script.Parent.Parent.Utilities.SignalManager)

local WishService = {}
WishService.__index = WishService

local WISH_TIMER = 1200 -- 20 minutes in seconds
local MAX_WISHES = 5

local REWARDS = {
    legendary = {
        chance = 0.1,
        items = {"Wish Star"}
    },
    epic = {
        chance = 3.9,
        items = {"500-1000 Gems", "Energy Bar", "Golden Apple"}
    },
    rare = {
        chance = 26,
        items = {"100-200 Gems", "Gem Potion", "Shroom Food", "Bux Potion"}
    },
    common = {
        chance = 70,
        items = {"25-75 Gems", "Apple", "Bone"}
    }
}

local ITEM_CONFIG = {
    ["Wish Star"] = {rarity = "legendary", color = Color3.fromRGB(255, 215, 0), image = "rbxassetid://18665498187"},
    ["Energy Bar"] = {rarity = "epic", color = Color3.fromRGB(128, 0, 128), image = "rbxassetid://18665498187"},
    ["Golden Apple"] = {rarity = "epic", color = Color3.fromRGB(128, 0, 128), image = "rbxassetid://18665498187"},
    ["Gem Potion"] = {rarity = "rare", color = Color3.fromRGB(0, 100, 255), image = "rbxassetid://18665498187"},
    ["Shroom Food"] = {rarity = "rare", color = Color3.fromRGB(0, 100, 255), image = "rbxassetid://18665498187"},
    ["Bux Potion"] = {rarity = "rare", color = Color3.fromRGB(0, 100, 255), image = "rbxassetid://18665498187"},
    ["Apple"] = {rarity = "common", color = Color3.fromRGB(128, 128, 128), image = "rbxassetid://18665498187"},
    ["Bone"] = {rarity = "common", color = Color3.fromRGB(128, 128, 128), image = "rbxassetid://18665498187"}
}

function WishService.new()
    local self = setmetatable({}, WishService)
    self._connections = {}
    self._dataService = nil
    self._inventoryService = nil
    self._notificationService = nil
    self._remoteEvents = {}
    self:_initialize()
    return self
end

function WishService:_initialize()
    Logger:Info("WishService initializing...")
    
    self:_setupRemoteEvents()
    self:_setupPlayerEvents()
    self:_startWishTimer()
    
    Logger:Info("✓ WishService initialized")
end

function WishService:_setupRemoteEvents()
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
    
    local wishEvents = remoteEvents:FindFirstChild("WishEvents")
    if not wishEvents then
        wishEvents = Instance.new("Folder")
        wishEvents.Name = "WishEvents"
        wishEvents.Parent = remoteEvents
    end
    
    local updateWishGUI = wishEvents:FindFirstChild("UpdateWishGUI")
    if not updateWishGUI then
        updateWishGUI = Instance.new("RemoteEvent")
        updateWishGUI.Name = "UpdateWishGUI"
        updateWishGUI.Parent = wishEvents
    end
    
    local wishSpin = wishEvents:FindFirstChild("WishSpin")
    if not wishSpin then
        wishSpin = Instance.new("RemoteEvent")
        wishSpin.Name = "WishSpin"
        wishSpin.Parent = wishEvents
    end
    
    local playWishAnimation = wishEvents:FindFirstChild("PlayWishAnimation")
    if not playWishAnimation then
        playWishAnimation = Instance.new("RemoteEvent")
        playWishAnimation.Name = "PlayWishAnimation"
        playWishAnimation.Parent = wishEvents
    end
    
    local updateInventory = wishEvents:FindFirstChild("UpdateInventory")
    if not updateInventory then
        updateInventory = Instance.new("RemoteEvent")
        updateInventory.Name = "UpdateInventory"
        updateInventory.Parent = wishEvents
    end
    
    self._remoteEvents.UpdateWishGUI = updateWishGUI
    self._remoteEvents.WishSpin = wishSpin
    self._remoteEvents.PlayWishAnimation = playWishAnimation
    self._remoteEvents.UpdateInventory = updateInventory
    
    wishSpin.OnServerEvent:Connect(function(player)
        self:_handleWishSpin(player)
    end)
    
    Logger:Info("✓ Wish remote events setup complete")
end

function WishService:_setupPlayerEvents()
    -- Don't setup players immediately - wait for proper initialization
    -- This will be handled in SetDataService when we're linked with DataService
end

function WishService:_setupPlayer(player)
    if not self._dataService then
        Logger:Warn("DataService not available, cannot setup wish data for " .. player.Name)
        return
    end
    
    -- Get player data from DataService with retry logic
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData then
        Logger:Debug(string.format("Player data not ready for %s, will retry later", player.Name))
        -- Retry after a short delay
        task.spawn(function()
            task.wait(2)
            if player and player.Parent then
                self:_setupPlayer(player)
            end
        end)
        return
    end
    
    -- Ensure wish data exists with defaults
    if not playerData.WishData then
        local currentTime = os.time()
        self._dataService:UpdatePlayerData(player, function(data)
            data.WishData = {
                wishes = 0,
                lastWishTime = currentTime, -- Set to current time, not 0
                inventory = {}
            }
        end)
        self._dataService:ManualSave(player)
        playerData = self._dataService:GetPlayerData(player) -- Get fresh data
    end
    
    local wishData = playerData.WishData
    local currentTime = os.time()
    
    -- For new players or players with lastWishTime = 0, set it to current time
    if wishData.lastWishTime == 0 then
        self._dataService:UpdatePlayerData(player, function(data)
            data.WishData.lastWishTime = currentTime
        end)
        wishData.lastWishTime = currentTime
    end
    
    -- Calculate wishes gained since last time
    if wishData.wishes < MAX_WISHES then
        local timeDiff = currentTime - wishData.lastWishTime
        local wishesGained = math.floor(timeDiff / WISH_TIMER)
        
        if wishesGained > 0 then
            self._dataService:UpdatePlayerData(player, function(data)
                data.WishData.wishes = math.min(data.WishData.wishes + wishesGained, MAX_WISHES)
                data.WishData.lastWishTime = data.WishData.lastWishTime + (wishesGained * WISH_TIMER)
            end)
            
            -- Get fresh data after the update
            local freshPlayerData = self._dataService:GetPlayerData(player)
            if freshPlayerData and freshPlayerData.WishData then
                wishData = freshPlayerData.WishData
            end
        end
    end
    
    -- Calculate time until next wish
    local timeSinceLastWish = currentTime - wishData.lastWishTime
    local timeUntilNextWish = wishData.wishes >= MAX_WISHES and 0 or (WISH_TIMER - (timeSinceLastWish % WISH_TIMER))
    
    -- Debug the time calculations
    Logger:Debug(string.format("SETUP DEBUG for %s: currentTime=%d, lastWishTime=%d, timeSince=%d, timeUntil=%d", 
        player.Name, currentTime, wishData.lastWishTime, timeSinceLastWish, timeUntilNextWish))
    
    -- Update GUI
    self._remoteEvents.UpdateWishGUI:FireClient(player, wishData.wishes, timeUntilNextWish)
    Logger:Debug(string.format("Sent UpdateWishGUI to %s: wishes=%d, timeUntil=%d", player.Name, wishData.wishes, timeUntilNextWish))
    
    -- Send inventory data
    task.spawn(function()
        task.wait(2)
        self._remoteEvents.UpdateInventory:FireClient(player, wishData.inventory or {}, ITEM_CONFIG)
    end)
    
    Logger:Info(string.format("Setup wish data for %s: %d wishes, next in %ds", player.Name, wishData.wishes, timeUntilNextWish))
end

function WishService:_startWishTimer()
    local lastUpdate = 0
    
    -- Use HeartbeatManager with 30 second interval for wish timer
    self._connections.WishTimer = HeartbeatManager.getInstance():register(function()
        if not self._dataService then return end
        
        local currentTime = os.time()
        
        -- Update every 1 second for smooth timer countdown
        if currentTime - lastUpdate >= 1 then
            lastUpdate = currentTime
            
            for _, player in pairs(Players:GetPlayers()) do
                if not player or not player.Parent then continue end
                
                local playerData = self._dataService:GetPlayerData(player)
                if not playerData or not playerData.WishData then continue end
                
                local wishData = playerData.WishData
                local timeSinceLastWish = currentTime - wishData.lastWishTime
                
                -- Only log debug info when about to award a wish or when there's an issue
                if timeSinceLastWish >= WISH_TIMER and wishData.wishes < MAX_WISHES then
                    Logger:Debug(string.format("ABOUT TO AWARD WISH for %s: timeSince=%d, WISH_TIMER=%d, wishes=%d/%d", 
                        player.Name, timeSinceLastWish, WISH_TIMER, wishData.wishes, MAX_WISHES))
                elseif timeSinceLastWish >= WISH_TIMER then
                    Logger:Debug(string.format("TIMER MET BUT MAX WISHES for %s: wishes=%d/%d", player.Name, wishData.wishes, MAX_WISHES))
                end
                
                -- Award wish if time has passed
                if timeSinceLastWish >= WISH_TIMER and wishData.wishes < MAX_WISHES then
                    self._dataService:UpdatePlayerData(player, function(data)
                        -- Double-check the condition inside the update function with the latest data
                        local latestTimeDiff = currentTime - data.WishData.lastWishTime
                        if data.WishData.wishes < MAX_WISHES and latestTimeDiff >= WISH_TIMER then
                            data.WishData.wishes = data.WishData.wishes + 1
                            data.WishData.lastWishTime = currentTime
                            Logger:Debug(string.format("INNER UPDATE: %s wishes increased to %d", player.Name, data.WishData.wishes))
                        else
                            Logger:Debug(string.format("INNER UPDATE SKIP: %s - wishes=%d, timeDiff=%d, needed=%d", player.Name, data.WishData.wishes, latestTimeDiff, WISH_TIMER))
                        end
                    end)
                    
                    -- Get fresh data immediately after update for accurate logging
                    local freshData = self._dataService:GetPlayerData(player)
                    if freshData and freshData.WishData then
                        Logger:Info(string.format("%s earned a wish! (%d/5)", player.Name, freshData.WishData.wishes))
                        
                        -- Send notification
                        if self._notificationService then
                            self._notificationService:ShowWishEarned(player)
                        end
                        
                        -- Update our working data
                        playerData = freshData
                        wishData = playerData.WishData
                        timeSinceLastWish = currentTime - wishData.lastWishTime
                    end
                end
                
                -- Calculate time until next wish
                local timeUntilNext = 0
                if wishData.wishes < MAX_WISHES then
                    timeUntilNext = WISH_TIMER - (timeSinceLastWish % WISH_TIMER)
                end
                
                -- Send update to client
                self._remoteEvents.UpdateWishGUI:FireClient(player, wishData.wishes, timeUntilNext)
            end
        end
    end)
end

function WishService:_getRandomReward()
    local roll = math.random() * 100
    local cumulative = 0
    
    for rarity, data in pairs(REWARDS) do
        cumulative = cumulative + data.chance
        if roll <= cumulative then
            local randomItem = data.items[math.random(#data.items)]
            return rarity, randomItem
        end
    end
    
    local commonItems = REWARDS.common.items
    return "common", commonItems[math.random(#commonItems)]
end

function WishService:_handleGemReward(player, itemName)
    local gemAmount = 0
    
    if itemName == "500-1000 Gems" then
        gemAmount = math.random(500, 1000)
    elseif itemName == "100-200 Gems" then
        gemAmount = math.random(100, 200)
    elseif itemName == "25-75 Gems" then
        gemAmount = math.random(25, 75)
    end
    
    if gemAmount > 0 then
        local success = self._dataService:AddGems(player, gemAmount)
        if success then
            Logger:Info(string.format("Gave %d gems to %s from wish", gemAmount, player.Name))
            return gemAmount
        end
    end
    return 0
end

function WishService:_handleReward(player, rarity, item)
    if not self._dataService then return end
    
    -- Use InventoryService if available, otherwise fall back to direct data manipulation
    if self._inventoryService then
        local success = self._inventoryService:AddToInventory(player, item, 1)
        if success then
            Logger:Info(string.format("Added %s to %s's inventory via InventoryService", item, player.Name))
        else
            Logger:Error(string.format("Failed to add %s to %s's inventory via InventoryService", item, player.Name))
        end
    else
        -- Fallback to original method
        local playerData = self._dataService:GetPlayerData(player)
        if not playerData or not playerData.WishData then return end
        
        if string.find(item, "Gems") then
            self:_handleGemReward(player, item)
        else
            self._dataService:UpdatePlayerData(player, function(data)
                if not data.WishData.inventory then 
                    data.WishData.inventory = {} 
                end
                if not data.WishData.inventory[item] then 
                    data.WishData.inventory[item] = 0 
                end
                data.WishData.inventory[item] = data.WishData.inventory[item] + 1
            end)
            
            -- Get updated data for client update
            local updatedData = self._dataService:GetPlayerData(player)
            self._remoteEvents.UpdateInventory:FireClient(player, updatedData.WishData.inventory, ITEM_CONFIG)
            Logger:Info(string.format("Added %s to %s's inventory (fallback method)", item, player.Name))
        end
    end
end

function WishService:_handleWishSpin(player)
    if not self._dataService then
        Logger:Warn("DataService not available")
        return
    end
    
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData or not playerData.WishData then
        Logger:Warn(string.format("No wish data found for %s", player.Name))
        return
    end
    
    local wishData = playerData.WishData
    if wishData.wishes <= 0 then
        Logger:Warn(string.format("%s tried to spin with no wishes", player.Name))
        return
    end
    
    self._dataService:UpdatePlayerData(player, function(data)
        data.WishData.wishes = data.WishData.wishes - 1
    end)
    
    local rarity, item = self:_getRandomReward()
    Logger:Info(string.format("%s got %s (%s) from wish", player.Name, item, rarity))
    
    self:_handleReward(player, rarity, item)
    
    self._remoteEvents.PlayWishAnimation:FireClient(player, rarity, item)
    
    local currentTime = os.time()
    local updatedData = self._dataService:GetPlayerData(player)
    local timeSinceLastWish = currentTime - updatedData.WishData.lastWishTime
    local timeUntilNextWish = WISH_TIMER - (timeSinceLastWish % WISH_TIMER)
    self._remoteEvents.UpdateWishGUI:FireClient(player, updatedData.WishData.wishes, timeUntilNextWish)
end

function WishService:UpdatePlayerWishGUI(player)
    if not self._dataService then
        Logger:Warn("DataService not available, cannot update wish GUI for " .. player.Name)
        return
    end
    
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData or not playerData.WishData then
        Logger:Warn("No wish data found for " .. player.Name)
        return
    end
    
    local wishData = playerData.WishData
    local currentTime = os.time()
    local timeSinceLastWish = currentTime - wishData.lastWishTime
    local timeUntilNext = wishData.wishes >= MAX_WISHES and 0 or (WISH_TIMER - (timeSinceLastWish % WISH_TIMER))
    
    self._remoteEvents.UpdateWishGUI:FireClient(player, wishData.wishes, timeUntilNext)
    Logger:Debug(string.format("Manual GUI update sent to %s: wishes=%d, timeUntil=%d", player.Name, wishData.wishes, timeUntilNext))
end

function WishService:SetDataService(dataService)
    self._dataService = dataService
    
    -- Delay all wish system setup to avoid interfering with critical systems
    task.spawn(function()
        task.wait(10) -- Wait 10 seconds for all other systems to fully initialize
        
        -- Setup existing players
        for _, player in pairs(Players:GetPlayers()) do
            if player and player.Parent then
                self:_setupPlayer(player)
            end
        end
        
        -- Connect to PlayerDataLoaded for future players
        if dataService.PlayerDataLoaded then
            self._connections.PlayerDataLoaded = dataService.PlayerDataLoaded:Connect(function(player, playerData, isNewPlayer)
                task.spawn(function()
                    task.wait(3) -- Delay for new players too
                    self:_setupPlayer(player)
                end)
            end)
        end
        
        Logger:Info("WishService delayed setup complete")
    end)
    
    Logger:Info("WishService linked with DataService (delayed initialization)")
end

function WishService:SetInventoryService(inventoryService)
    self._inventoryService = inventoryService
    Logger:Info("WishService linked with InventoryService")
end

function WishService:SetNotificationService(notificationService)
    self._notificationService = notificationService
    Logger:Info("WishService linked with NotificationService")
end

function WishService:Cleanup()
    Logger:Info("WishService shutting down...")
    
    for name, connection in pairs(self._connections) do
        if connection then
            if name == "WishTimer" then
                HeartbeatManager.getInstance():unregister(connection)
            elseif connection.Connected then
                connection:Disconnect()
            end
        end
    end
    
    self._connections = {}
    
    Logger:Info("✓ WishService shutdown complete")
end

return WishService