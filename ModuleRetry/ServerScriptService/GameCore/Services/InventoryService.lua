local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local HeartbeatManager = require(script.Parent.Parent.Utilities.HeartbeatManager)
local SignalManager = require(script.Parent.Parent.Utilities.SignalManager)

local InventoryService = {}
InventoryService.__index = InventoryService

-- Item configuration with rarity colors and boost effects
local ITEM_CONFIG = {
    -- Legendary items
    ["Wish Star"] = {
        rarity = "legendary",
        color = Color3.fromRGB(255, 215, 0),
        boostType = "SporeMultiplier",
        boostMultiplier = 10,
        boostDuration = 120, -- 2 minutes
        description = "A mystical star that grants 10x Spore value for 2 Minutes."
    },

    -- Epic items
    ["Energy Bar"] = {
        rarity = "epic", 
        color = Color3.fromRGB(128, 0, 128),
        boostType = "SporeSpeed",
        boostMultiplier = 3, -- 200% increase = 3x
        boostDuration = 60, -- 1 minute
        description = "Increases Spore production speed by 200% for 1 Minute."
    },
    ["Golden Apple"] = {
        rarity = "epic",
        color = Color3.fromRGB(128, 0, 128),
        boostType = "GemProduction",
        boostMultiplier = 2,
        boostDuration = 120, -- 2 minutes
        description = "A rare golden apple doubles Gem Production for 2 Minutes."
    },

    -- Rare items
    ["Gem Potion"] = {
        rarity = "rare",
        color = Color3.fromRGB(0, 100, 255),
        boostType = "GemProduction",
        boostMultiplier = 1.5,
        boostDuration = 90,
        description = "A sparkling potion that boosts Gem Production."
    },
    ["Shroom Food"] = {
        rarity = "rare",
        color = Color3.fromRGB(0, 100, 255),
        boostType = "SporeSpeed",
        boostMultiplier = 1.75,
        boostDuration = 60,
        description = "Spore Production speed boosted by 75%."
    },
    ["Bux Potion"] = {
        rarity = "rare",
        color = Color3.fromRGB(0, 100, 255),
        boostType = "CurrencyEarnings",
        boostMultiplier = 2,
        boostDuration = 120, -- 2 minutes
        description = "A valuable potion that increases currency earnings for 2 Minutes."
    },

    -- Common items
    ["Apple"] = {
        rarity = "common",
        color = Color3.fromRGB(128, 128, 128),
        boostType = "SporeSpeed",
        boostMultiplier = 1.25,
        boostDuration = 45,
        description = "A fresh, crisp apple that boosts Spore Production for 45 Seconds."
    },
    ["Bone"] = {
        rarity = "common",
        color = Color3.fromRGB(128, 128, 128),
        boostType = "GemProduction",
        boostMultiplier = 2,
        boostDuration = 30,
        description = "An old bone that doubles Gem Production for 30 Seconds."
    }
}

function InventoryService.new()
    local self = setmetatable({}, InventoryService)
    self._connections = {}
    self._dataService = nil
    self._remoteEvents = {}
    self._activeBoosts = {} -- Track active boosts per player
    self:_initialize()
    return self
end

function InventoryService:_initialize()
    Logger:Info("InventoryService initializing...")
    
    self:_setupRemoteEvents()
    self:_startBoostTimer()
    
    Logger:Info("✓ InventoryService initialized")
end

function InventoryService:_setupRemoteEvents()
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
    
    local inventoryEvents = remoteEvents:FindFirstChild("InventoryEvents")
    if not inventoryEvents then
        inventoryEvents = Instance.new("Folder")
        inventoryEvents.Name = "InventoryEvents"
        inventoryEvents.Parent = remoteEvents
    end
    
    -- Create inventory remote events
    local updateInventoryEvent = inventoryEvents:FindFirstChild("UpdateInventory")
    if not updateInventoryEvent then
        updateInventoryEvent = Instance.new("RemoteEvent")
        updateInventoryEvent.Name = "UpdateInventory"
        updateInventoryEvent.Parent = inventoryEvents
    end
    
    local useItemEvent = inventoryEvents:FindFirstChild("UseItem")
    if not useItemEvent then
        useItemEvent = Instance.new("RemoteEvent")
        useItemEvent.Name = "UseItem"
        useItemEvent.Parent = inventoryEvents
    end
    
    local syncBoostsEvent = inventoryEvents:FindFirstChild("SyncBoosts")
    if not syncBoostsEvent then
        syncBoostsEvent = Instance.new("RemoteEvent")
        syncBoostsEvent.Name = "SyncBoosts"
        syncBoostsEvent.Parent = inventoryEvents
    end
    
    local itemUsedEvent = inventoryEvents:FindFirstChild("ItemUsed")
    if not itemUsedEvent then
        itemUsedEvent = Instance.new("RemoteEvent")
        itemUsedEvent.Name = "ItemUsed"
        itemUsedEvent.Parent = inventoryEvents
    end
    
    self._remoteEvents.UpdateInventory = updateInventoryEvent
    self._remoteEvents.UseItem = useItemEvent
    self._remoteEvents.SyncBoosts = syncBoostsEvent
    self._remoteEvents.ItemUsed = itemUsedEvent
    
    -- Connect use item event
    useItemEvent.OnServerEvent:Connect(function(player, itemName)
        self:_handleUseItem(player, itemName)
    end)
    
    Logger:Info("✓ Inventory remote events setup complete")
end

function InventoryService:_startBoostTimer()
    -- Use HeartbeatManager with 1 second interval for boost timers
    self._connections.BoostTimer = HeartbeatManager.getInstance():register(function()
        if not self._dataService then return end
        
        local currentTime = tick()
        
        for _, player in pairs(Players:GetPlayers()) do
            if not player or not player.Parent then continue end
            
            local playerBoosts = self._activeBoosts[player.UserId]
            if not playerBoosts then continue end
            
            local updated = false
            for boostType, boost in pairs(playerBoosts) do
                if currentTime >= boost.endTime then
                    playerBoosts[boostType] = nil
                    updated = true
                    Logger:Info(string.format("%s's %s boost expired", player.Name, boostType))
                end
            end
            
            if updated then
                self:_syncPlayerBoosts(player)
            end
        end
    end)
end

function InventoryService:AddToInventory(player, itemName, quantity)
    if not self._dataService then
        Logger:Warn("DataService not available, cannot add item to inventory")
        return false
    end
    
    quantity = quantity or 1
    
    -- Handle gem rewards directly (don't add to inventory)
    if string.find(itemName, "Gems") then
        return self:_handleGemReward(player, itemName)
    end
    
    -- Add to player's inventory in WishData
    local success = self._dataService:UpdatePlayerData(player, function(data)
        if not data.WishData then
            data.WishData = {
                wishes = 0,
                lastWishTime = os.time(),
                inventory = {}
            }
        end
        
        if not data.WishData.inventory then
            data.WishData.inventory = {}
        end
        
        if not data.WishData.inventory[itemName] then
            data.WishData.inventory[itemName] = 0
        end
        
        data.WishData.inventory[itemName] = data.WishData.inventory[itemName] + quantity
    end)
    
    if success then
        -- Update client inventory
        self:UpdatePlayerInventoryGUI(player)
        Logger:Info(string.format("Added %dx %s to %s's inventory", quantity, itemName, player.Name))
        return true
    else
        Logger:Error(string.format("Failed to add %s to %s's inventory", itemName, player.Name))
        return false
    end
end

function InventoryService:_handleGemReward(player, itemName)
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
            Logger:Info(string.format("Gave %d gems directly to %s (not inventory)", gemAmount, player.Name))
            return true
        end
    end
    return false
end

function InventoryService:_handleUseItem(player, itemName)
    if not self._dataService then
        Logger:Warn("DataService not available, cannot use item")
        return
    end
    
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData or not playerData.WishData or not playerData.WishData.inventory then
        Logger:Warn(string.format("No inventory data found for %s", player.Name))
        return
    end
    
    local inventory = playerData.WishData.inventory
    local quantity = inventory[itemName] or 0
    
    if quantity <= 0 then
        Logger:Warn(string.format("%s tried to use %s but has none", player.Name, itemName))
        return
    end
    
    local itemConfig = ITEM_CONFIG[itemName]
    if not itemConfig then
        Logger:Warn(string.format("Unknown item used: %s", itemName))
        return
    end
    
    -- Remove item from inventory
    local success = self._dataService:UpdatePlayerData(player, function(data)
        data.WishData.inventory[itemName] = data.WishData.inventory[itemName] - 1
        if data.WishData.inventory[itemName] <= 0 then
            data.WishData.inventory[itemName] = nil
        end
    end)
    
    if success then
        -- Apply boost
        self:_applyBoost(player, itemConfig.boostType, itemConfig.boostMultiplier, itemConfig.boostDuration)
        
        -- Notify client about item usage for active boost UI
        if self._remoteEvents.ItemUsed then
            self._remoteEvents.ItemUsed:FireClient(player, itemName, itemConfig.boostDuration, itemConfig)
        end
        
        -- Update client inventory
        self:UpdatePlayerInventoryGUI(player)
        
        Logger:Info(string.format("%s used %s - applied %s boost (%.1fx for %ds)", 
            player.Name, itemName, itemConfig.boostType, itemConfig.boostMultiplier, itemConfig.boostDuration))
    end
end

function InventoryService:_applyBoost(player, boostType, multiplier, duration)
    if not self._activeBoosts[player.UserId] then
        self._activeBoosts[player.UserId] = {}
    end
    
    local endTime = tick() + duration
    self._activeBoosts[player.UserId][boostType] = {
        multiplier = multiplier,
        endTime = endTime
    }
    
    self:_syncPlayerBoosts(player)
    
    Logger:Info(string.format("Applied %s boost to %s: %.1fx for %ds", boostType, player.Name, multiplier, duration))
end

function InventoryService:_syncPlayerBoosts(player)
    local playerBoosts = self._activeBoosts[player.UserId] or {}
    self._remoteEvents.SyncBoosts:FireClient(player, playerBoosts)
end

function InventoryService:GetPlayerInventory(player)
    if not self._dataService then return {} end
    
    local playerData = self._dataService:GetPlayerData(player)
    if not playerData or not playerData.WishData or not playerData.WishData.inventory then
        return {}
    end
    
    -- Filter out gem items
    local filteredInventory = {}
    for itemName, quantity in pairs(playerData.WishData.inventory) do
        if not string.find(itemName, "Gems") and quantity > 0 then
            filteredInventory[itemName] = quantity
        end
    end
    
    return filteredInventory
end

function InventoryService:UpdatePlayerInventoryGUI(player)
    local inventory = self:GetPlayerInventory(player)
    self._remoteEvents.UpdateInventory:FireClient(player, inventory, ITEM_CONFIG)
    Logger:Debug(string.format("Sent inventory update to %s", player.Name))
end

function InventoryService:GetActiveBoosts(player)
    return self._activeBoosts[player.UserId] or {}
end

function InventoryService:GetBoostMultiplier(player, boostType)
    local playerBoosts = self._activeBoosts[player.UserId]
    if not playerBoosts then return 1.0 end
    
    local boost = playerBoosts[boostType]
    if not boost then return 1.0 end
    
    if tick() >= boost.endTime then
        playerBoosts[boostType] = nil
        return 1.0
    end
    
    return boost.multiplier
end

function InventoryService:SetDataService(dataService)
    self._dataService = dataService
    
    -- Setup existing players
    for _, player in pairs(Players:GetPlayers()) do
        if player and player.Parent then
            task.spawn(function()
                task.wait(2) -- Wait for data to be loaded
                self:UpdatePlayerInventoryGUI(player)
                self:_syncPlayerBoosts(player)
            end)
        end
    end
    
    -- Connect to PlayerDataLoaded for future players
    if dataService.PlayerDataLoaded then
        self._connections.PlayerDataLoaded = dataService.PlayerDataLoaded:Connect(function(player, playerData, isNewPlayer)
            task.spawn(function()
                task.wait(1)
                self:UpdatePlayerInventoryGUI(player)
                self:_syncPlayerBoosts(player)
            end)
        end)
    end
    
    Logger:Info("InventoryService linked with DataService")
end

function InventoryService:Cleanup()
    Logger:Info("InventoryService shutting down...")
    
    for name, connection in pairs(self._connections) do
        if connection then
            if name == "BoostTimer" then
                HeartbeatManager.getInstance():unregister(connection)
            elseif connection.Connected then
                connection:Disconnect()
            end
        end
    end
    
    self._connections = {}
    self._activeBoosts = {}
    
    Logger:Info("✓ InventoryService shutdown complete")
end

return InventoryService