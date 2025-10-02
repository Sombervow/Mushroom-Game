local RobloxMarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local GamepassConfig = require(ReplicatedStorage.Shared.Modules.GamepassConfig)

local RobuxMarketplaceService = {}
RobuxMarketplaceService.__index = RobuxMarketplaceService

-- Game Pass IDs (you'll need to replace these with your actual gamepass IDs)
local GAMEPASS_IDS = {
    -- Add your actual gamepass IDs here
    -- Example: PremiumBoost = 123456789,
}

-- Get Developer Product IDs from shared config
local DEVELOPER_PRODUCT_IDS = GamepassConfig.DEV_PRODUCT_IDS

function RobuxMarketplaceService.new()
    local self = setmetatable({}, RobuxMarketplaceService)
    self._dataService = nil
    self._wishService = nil
    self._connections = {}
    self:_initialize()
    return self
end

function RobuxMarketplaceService:_initialize()
    -- ProcessReceipt is handled by GamepassService which will forward unknown products to us
    -- Don't set ProcessReceipt here to avoid conflicts
    
    self._connections.PromptGamePassPurchaseFinished = RobloxMarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
        self:_onGamePassPurchaseFinished(player, gamePassId, wasPurchased)
    end)
    
    Logger:Info("RobuxMarketplaceService initialized successfully")
end

-- Handle developer product purchases (consumables like gems, coins, etc.)
function RobuxMarketplaceService:_processReceipt(receiptInfo)
    print("🔥🔥🔥 PROCESS RECEIPT CALLED! 🔥🔥🔥")
    print("Receipt Info: PlayerId=" .. tostring(receiptInfo.PlayerId) .. ", ProductId=" .. tostring(receiptInfo.ProductId))
    Logger:Info("🔥 PROCESS RECEIPT CALLED! 🔥")
    Logger:Info(string.format("Receipt Info: PlayerId=%d, ProductId=%d, PurchaseId=%s", 
        receiptInfo.PlayerId, receiptInfo.ProductId, tostring(receiptInfo.PurchaseId)))
    
    local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
    if not player then
        print("❌ Player not found!")
        Logger:Warn("❌ ProcessReceipt: Player not found for UserId " .. receiptInfo.PlayerId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    local productId = receiptInfo.ProductId
    local currencyType = receiptInfo.CurrencyType
    local currencySpent = receiptInfo.CurrencySpent
    
    print("✓ Player found: " .. player.Name)
    Logger:Info(string.format("✓ Player found: %s", player.Name))
    Logger:Info(string.format("Processing purchase for %s: ProductId=%d, Currency=%s, Amount=%d", 
        player.Name, productId, tostring(currencyType), currencySpent))
    
    -- Track robux spent
    if currencyType == Enum.CurrencyType.Robux and self._dataService then
        Logger:Debug(string.format("Processing robux purchase: %d robux by %s", currencySpent, player.Name))
        local success = self._dataService:AddRobuxSpent(player, currencySpent)
        if success then
            Logger:Info(string.format("✓ Tracked %d robux spent by %s", currencySpent, player.Name))
        else
            Logger:Warn(string.format("❌ Failed to track robux spent by %s", player.Name))
        end
    else
        Logger:Debug(string.format("Not tracking robux - CurrencyType: %s, DataService: %s", tostring(currencyType), tostring(self._dataService ~= nil)))
    end
    
    -- Process the actual product (you'll need to implement this based on your products)
    local success = self:_giveProductReward(player, productId)
    
    if success then
        Logger:Info(string.format("Successfully processed purchase for %s", player.Name))
        return Enum.ProductPurchaseDecision.PurchaseGranted
    else
        Logger:Error(string.format("Failed to process purchase for %s", player.Name))
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

-- Handle gamepass purchases (permanent purchases)
function RobuxMarketplaceService:_onGamePassPurchaseFinished(player, gamePassId, wasPurchased)
    if not wasPurchased then
        Logger:Info(string.format("GamePass purchase cancelled by %s (ID: %d)", player.Name, gamePassId))
        return
    end
    
    Logger:Info(string.format("GamePass purchased by %s (ID: %d)", player.Name, gamePassId))
    
    -- Get gamepass price and track robux spent
    if self._dataService then
        spawn(function()
            local success, gamePassInfo = pcall(function()
                return RobloxMarketplaceService:GetProductInfo(gamePassId, Enum.InfoType.GamePass)
            end)
            
            if success and gamePassInfo and gamePassInfo.PriceInRobux then
                local robuxSpent = gamePassInfo.PriceInRobux
                local trackSuccess = self._dataService:AddRobuxSpent(player, robuxSpent)
                if trackSuccess then
                    Logger:Info(string.format("Tracked %d robux spent on gamepass by %s", robuxSpent, player.Name))
                else
                    Logger:Warn(string.format("Failed to track gamepass robux spent by %s", player.Name))
                end
            else
                Logger:Warn(string.format("Could not get price info for gamepass %d", gamePassId))
            end
        end)
    end
    
    -- Process gamepass benefits (you'll need to implement this based on your gamepasses)
    self:_giveGamePassReward(player, gamePassId)
end

-- Give rewards for developer products (implement based on your products)
function RobuxMarketplaceService:_giveProductReward(player, productId)
    print("🔥🔥🔥 GIVE PRODUCT REWARD CALLED! 🔥🔥🔥")
    print("Player: " .. player.Name .. ", ProductID: " .. tostring(productId))
    print("Expected WISHES_5 ID: " .. tostring(DEVELOPER_PRODUCT_IDS.WISHES_5))
    print("Expected WISHES_50 ID: " .. tostring(DEVELOPER_PRODUCT_IDS.WISHES_50))
    
    Logger:Info(string.format("🔥 PROCESSING PRODUCT REWARD: Player=%s, ProductID=%d", player.Name, productId))
    Logger:Info(string.format("Expected WISHES_5 ID: %d", DEVELOPER_PRODUCT_IDS.WISHES_5))
    Logger:Info(string.format("Expected WISHES_50 ID: %d", DEVELOPER_PRODUCT_IDS.WISHES_50))
    
    -- Handle wish purchases
    if productId == DEVELOPER_PRODUCT_IDS.WISHES_5 then
        print("✅ MATCHED WISHES_5 - ADDING 5 WISHES")
        Logger:Info("✓ Matched WISHES_5 product ID - adding 5 wishes")
        return self:_addWishes(player, 5)
    elseif productId == DEVELOPER_PRODUCT_IDS.WISHES_50 then
        print("✅ MATCHED WISHES_50 - ADDING 50 WISHES")
        Logger:Info("✓ Matched WISHES_50 product ID - adding 50 wishes")
        return self:_addWishes(player, 50)
    end
    
    print("❌ UNKNOWN PRODUCT ID: " .. tostring(productId))
    Logger:Warn(string.format("❌ Unknown product ID: %d (not matching any configured products)", productId))
    return false
end

-- Give rewards for gamepasses (implement based on your gamepasses)
function RobuxMarketplaceService:_giveGamePassReward(player, gamePassId)
    -- Example implementation - you'll need to customize this
    Logger:Info(string.format("Giving gamepass reward to %s for gamepass %d", player.Name, gamePassId))
    
    -- Add your gamepass reward logic here
    -- For example:
    -- if gamePassId == GAMEPASS_IDS.PremiumBoost then
    --     -- Give permanent boost
    -- end
end

-- Check if player owns a gamepass
function RobuxMarketplaceService:PlayerOwnsGamePass(player, gamePassId)
    local success, owns = pcall(function()
        return RobloxMarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
    end)
    
    if success then
        return owns
    else
        Logger:Warn(string.format("Failed to check gamepass ownership for %s (GamePass: %d)", player.Name, gamePassId))
        return false
    end
end

-- Prompt a player to purchase a developer product
function RobuxMarketplaceService:PromptProductPurchase(player, productId)
    if not player or not productId then
        Logger:Warn("Invalid parameters for PromptProductPurchase")
        return false
    end
    
    local success, result = pcall(function()
        RobloxMarketplaceService:PromptProductPurchase(player, productId)
    end)
    
    if success then
        Logger:Info(string.format("Prompted %s to purchase product %d", player.Name, productId))
        return true
    else
        Logger:Warn(string.format("Failed to prompt purchase for %s: %s", player.Name, tostring(result)))
        return false
    end
end

-- Prompt a player to purchase a gamepass
function RobuxMarketplaceService:PromptGamePassPurchase(player, gamePassId)
    if not player or not gamePassId then
        Logger:Warn("Invalid parameters for PromptGamePassPurchase")
        return false
    end
    
    local success, result = pcall(function()
        RobloxMarketplaceService:PromptGamePassPurchase(player, gamePassId)
    end)
    
    if success then
        Logger:Info(string.format("Prompted %s to purchase gamepass %d", player.Name, gamePassId))
        return true
    else
        Logger:Warn(string.format("Failed to prompt gamepass purchase for %s: %s", player.Name, tostring(result)))
        return false
    end
end

-- Add wishes to player's account
function RobuxMarketplaceService:_addWishes(player, amount)
    print("🔥🔥🔥 ADD WISHES CALLED! 🔥🔥🔥")
    print("Player: " .. player.Name .. ", Amount: " .. tostring(amount))
    Logger:Info(string.format("🔥 _addWishes called: Player=%s, Amount=%d", player.Name, amount))
    
    if not self._dataService then
        Logger:Error("❌ DataService not available for wish purchase")
        return false
    end
    
    Logger:Info("✓ DataService is available")
    
    -- Get current data before update
    local beforeData = self._dataService:GetPlayerData(player)
    if beforeData and beforeData.WishData then
        Logger:Info(string.format("Before update: Player %s has %d wishes", player.Name, beforeData.WishData.wishes))
    else
        Logger:Info(string.format("Before update: Player %s has no WishData", player.Name))
    end
    
    local success = self._dataService:UpdatePlayerData(player, function(data)
        if not data.WishData then
            Logger:Info("Creating new WishData for player")
            data.WishData = {
                wishes = 0,
                lastWishTime = os.time(),
                inventory = {}
            }
        end
        
        local oldWishes = data.WishData.wishes
        -- Don't cap purchased wishes - only free wishes are capped at 5
        data.WishData.wishes = data.WishData.wishes + amount
        
        Logger:Info(string.format("Wish update: %d + %d = %d (no cap for purchased wishes)", oldWishes, amount, data.WishData.wishes))
    end)
    
    if success then
        Logger:Info(string.format("✓ Successfully updated player data for %s", player.Name))
        
        -- Get updated data to verify
        local afterData = self._dataService:GetPlayerData(player)
        if afterData and afterData.WishData then
            Logger:Info(string.format("After update: Player %s now has %d wishes", player.Name, afterData.WishData.wishes))
        end
        
        -- Update wish GUI if WishService is available
        if self._wishService and self._wishService.UpdatePlayerWishGUI then
            Logger:Info("Updating wish GUI via WishService")
            self._wishService:UpdatePlayerWishGUI(player)
        else
            Logger:Warn("WishService not available for GUI update")
        end
        
        return true
    else
        Logger:Error(string.format("❌ Failed to update player data for %s", player.Name))
        return false
    end
end

function RobuxMarketplaceService:SetDataService(dataService)
    self._dataService = dataService
    Logger:Debug("RobuxMarketplaceService linked with DataService")
end

function RobuxMarketplaceService:SetWishService(wishService)
    self._wishService = wishService
    Logger:Debug("RobuxMarketplaceService linked with WishService")
end

function RobuxMarketplaceService:Cleanup()
    for connectionName, connection in pairs(self._connections) do
        if connection then
            connection:Disconnect()
        end
    end
    self._connections = {}
    
    Logger:Info("RobuxMarketplaceService cleaned up")
end

return RobuxMarketplaceService