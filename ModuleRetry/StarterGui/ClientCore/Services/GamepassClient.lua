local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)
local GamepassConfig = require(ReplicatedStorage.Shared.Modules.GamepassConfig)

local GamepassClient = {}
GamepassClient.__index = GamepassClient

-- Dynamic pricing system
local pricingUpdateCallbacks = {} -- Store callbacks for price updates

local DEVELOPER_PRODUCT_IDS = {
	-- Gem Packs
	GEM_PACK_SMALL = 3413686220,     -- 2,500 gems
	-- Offline Earnings
	DOUBLE_OFFLINE_EARNINGS = 3413686210, -- Double offline earnings
	GEM_PACK_MEDIUM = 3413686218,    -- 15,000 gems
	GEM_PACK_LARGE = 3413686217,     -- 50,000 gems
	GEM_PACK_MEGA = 3413686216,      -- 225,000 gems

	-- Spore Packs
	SPORE_PACK_SMALL = 3413686214,   -- 400,000 spores
	SPORE_PACK_MEDIUM = 3413686213,  -- 2,000,000 spores
	SPORE_PACK_LARGE = 3413686212,   -- 5,000,000 spores
	SPORE_PACK_MEGA = 3413686211,    -- 40,000,000 spores
	
	-- Starter Pack
	STARTER_PACK = 3413686209,       -- 750,000 spores + 4,500 gems
}

function GamepassClient.new()
	local self = setmetatable({}, GamepassClient)

	self.player = Players.LocalPlayer
	self.purchaseCallbacks = {} -- Store callbacks for purchase completion

	self:_initialize()
	return self
end

function GamepassClient:_initialize()
	Logger:Info("GamepassService initializing...")

	self:_setupMarketplaceConnections()
	self:_setupDynamicPricing()

	Logger:Info("✓ GamepassService initialized")
end

function GamepassClient:_setupMarketplaceConnections()
	-- Handle developer product purchase finished
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(player, productId, isPurchased)
		if player == self.player and isPurchased then
			self:_handleProductPurchaseSuccess(productId)
		end
	end)

	-- Handle gamepass purchase finished
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if player == self.player and wasPurchased then
			self:_handleGamepassPurchaseSuccess(gamePassId)
		end
	end)
end

function GamepassClient:_handleProductPurchaseSuccess(productId)
	Logger:Info(string.format("Developer product purchase successful: %d", productId))

	-- Call any registered callbacks for this product
	local callbackKey = "product_" .. tostring(productId)
	if self.purchaseCallbacks[callbackKey] then
		for _, callback in pairs(self.purchaseCallbacks[callbackKey]) do
			if callback then
				callback()
			end
		end
		-- Clear callbacks after use
		self.purchaseCallbacks[callbackKey] = nil
	end
end

function GamepassClient:_handleGamepassPurchaseSuccess(gamePassId)
	Logger:Info(string.format("Gamepass purchase successful: %d", gamePassId))

	-- Call any registered callbacks for this gamepass
	local callbackKey = "gamepass_" .. tostring(gamePassId)
	if self.purchaseCallbacks[callbackKey] then
		for _, callback in pairs(self.purchaseCallbacks[callbackKey]) do
			if callback then
				callback()
			end
		end
		-- Clear callbacks after use
		self.purchaseCallbacks[callbackKey] = nil
	end
end

-- Purchase a developer product
function GamepassClient:PurchaseProduct(productName, onSuccess, onFailure)
	local productId = DEVELOPER_PRODUCT_IDS[productName]

	if not productId or productId == 0 then
		Logger:Warn(string.format("Developer product '%s' not configured or has placeholder ID", productName))
		if onFailure then
			onFailure("Product not configured")
		end
		return
	end

	-- Register success callback
	if onSuccess then
		local callbackKey = "product_" .. tostring(productId)
		if not self.purchaseCallbacks[callbackKey] then
			self.purchaseCallbacks[callbackKey] = {}
		end
		table.insert(self.purchaseCallbacks[callbackKey], onSuccess)
	end

	-- Prompt the purchase
	local success, result = pcall(function()
		MarketplaceService:PromptProductPurchase(self.player, productId)
	end)

	if not success then
		Logger:Error(string.format("Failed to prompt product purchase '%s': %s", productName, tostring(result)))
		if onFailure then
			onFailure(result)
		end
	else
		Logger:Info(string.format("Prompted purchase for product '%s' (ID: %d)", productName, productId))
	end
end

-- Purchase a gamepass
function GamepassClient:PurchaseGamepass(gamepassName, onSuccess, onFailure)
	local gamepassId = GamepassConfig.GAMEPASS_IDS[gamepassName]

	if not gamepassId or gamepassId == 0 then
		Logger:Warn(string.format("Gamepass '%s' not configured or has placeholder ID", gamepassName))
		if onFailure then
			onFailure("Gamepass not configured")
		end
		return
	end

	-- Register success callback
	if onSuccess then
		local callbackKey = "gamepass_" .. tostring(gamepassId)
		if not self.purchaseCallbacks[callbackKey] then
			self.purchaseCallbacks[callbackKey] = {}
		end
		table.insert(self.purchaseCallbacks[callbackKey], onSuccess)
	end

	-- Prompt the purchase
	local success, result = pcall(function()
		MarketplaceService:PromptGamePassPurchase(self.player, gamepassId)
	end)

	if not success then
		Logger:Error(string.format("Failed to prompt gamepass purchase '%s': %s", gamepassName, tostring(result)))
		if onFailure then
			onFailure(result)
		end
	else
		Logger:Info(string.format("Prompted purchase for gamepass '%s' (ID: %d)", gamepassName, gamepassId))
	end
end

-- Check if player owns a gamepass
function GamepassClient:PlayerOwnsGamepass(gamepassName, callback)
	local gamepassId = GamepassConfig.GAMEPASS_IDS[gamepassName]

	if not gamepassId or gamepassId == 0 then
		Logger:Warn(string.format("Gamepass '%s' not configured", gamepassName))
		if callback then
			callback(false)
		end
		return
	end

	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(self.player.UserId, gamepassId)
	end)

	if success then
		if callback then
			callback(result)
		end
		return result
	else
		Logger:Error(string.format("Failed to check gamepass ownership '%s': %s", gamepassName, tostring(result)))
		if callback then
			callback(false)
		end
		return false
	end
end

-- Get all configured product IDs (for debugging)
function GamepassClient:GetConfiguredProducts()
	return DEVELOPER_PRODUCT_IDS
end

-- Get all configured gamepass IDs (for debugging)
function GamepassClient:GetConfiguredGamepasses()
	return GamepassConfig.GAMEPASS_IDS
end

-- Update a product ID (useful for dynamic configuration)
function GamepassClient:SetProductId(productName, productId)
	DEVELOPER_PRODUCT_IDS[productName] = productId
	Logger:Info(string.format("Updated product '%s' ID to %d", productName, productId))
end

-- Update a gamepass ID (useful for dynamic configuration)
function GamepassClient:SetGamepassId(gamepassName, gamepassId)
	GamepassConfig.GAMEPASS_IDS[gamepassName] = gamepassId
	Logger:Info(string.format("Updated gamepass '%s' ID to %d", gamepassName, gamepassId))
end

-- Dynamic pricing methods
function GamepassClient:UpdateGamepassPricing()
	Logger:Info("Updating gamepass pricing from MarketplaceService...")

	-- Update all gamepass prices
	-- 001_ItemColumn gamepasses
	self:UpdateSingleGamepassPrice("DOUBLE_SPORES", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "01_2xSpores", "Price")
	self:UpdateSingleGamepassPrice("SUPER_MAGNET", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "02_SuperMagnet", "Price")
	self:UpdateSingleGamepassPrice("AUTO_TAP", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "03_AutoTap", "Price")
	self:UpdateSingleGamepassPrice("DOUBLE_TAPS", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "2xTaps", "Price")
	self:UpdateSingleGamepassPrice("LUCKY_GEM", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "LuckyGems", "Price")
	self:UpdateSingleGamepassPrice("ULTRA_LUCKY_GEM", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "UltraLuckyGems", "Price")

	-- Direct ShopContainer gamepasses
	self:UpdateSingleGamepassPrice("AUTO_COLLECT", "GamepassShop", "Main", "Container", "ShopContainer", "002_AutoCollect", "Price")
	self:UpdateSingleGamepassPrice("VIP", "GamepassShop", "Main", "Container", "ShopContainer", "004_VIP", "BuyButton", "Price")
	self:UpdateSingleGamepassPrice("TRIPLE_SPORES", "GamepassShop", "Main", "Container", "ShopContainer", "010_3xSpores", "BuyButton", "Price")
	self:UpdateSingleGamepassPrice("QUADRUPLE_SPORES", "GamepassShop", "Main", "Container", "ShopContainer", "011_4xSpores", "BuyButton", "Price")

	-- Update developer product prices
	-- Gem Packs in 006_GemVault
	self:UpdateSingleProductPrice("GEM_PACK_SMALL", "GamepassShop", "Main", "Container", "ShopContainer", "006_GemVault", "HandfulGems", "HandfulGems", "Fade", "Price")  -- 2,500 gems
	self:UpdateSingleProductPrice("GEM_PACK_MEDIUM", "GamepassShop", "Main", "Container", "ShopContainer", "006_GemVault", "BagGems", "BagGems", "Fade", "Price")      -- 15,000 gems
	self:UpdateSingleProductPrice("GEM_PACK_LARGE", "GamepassShop", "Main", "Container", "ShopContainer", "006_GemVault", "ChestGems", "ChestGems", "Fade", "Price")    -- 50,000 gems
	self:UpdateSingleProductPrice("GEM_PACK_MEGA", "GamepassShop", "Main", "Container", "ShopContainer", "006_GemVault", "VaultGems", "VaultGems", "Fade", "Price")     -- 225,000 gems
	
	-- Spore Packs in 008_Spores
	self:UpdateSingleProductPrice("SPORE_PACK_SMALL", "GamepassShop", "Main", "Container", "ShopContainer", "008_Spores", "SporePack1", "SporePack1", "Fade", "Price")   -- 400,000 spores
	self:UpdateSingleProductPrice("SPORE_PACK_MEDIUM", "GamepassShop", "Main", "Container", "ShopContainer", "008_Spores", "SporePack2", "SporePack2", "Fade", "Price")  -- 2,000,000 spores
	self:UpdateSingleProductPrice("SPORE_PACK_LARGE", "GamepassShop", "Main", "Container", "ShopContainer", "008_Spores", "SporePack3", "SporePack3", "Fade", "Price")   -- 5,000,000 spores
	self:UpdateSingleProductPrice("SPORE_PACK_MEGA", "GamepassShop", "Main", "Container", "ShopContainer", "008_Spores", "SporePack4", "SporePack4", "Fade", "Price")    -- 40,000,000 spores
	
	Logger:Info("All gamepass and developer product prices updated")
end

function GamepassClient:UpdateSingleGamepassPrice(gamepassName, ...)
	local path = {...}
	local priceTextPath = table.remove(path) -- Last element is the price text name

	local gamepassId = GamepassConfig.GAMEPASS_IDS[gamepassName]
	if not gamepassId or gamepassId == 0 then
		Logger:Warn(string.format("Gamepass '%s' not configured for price update", gamepassName))
		return
	end

	-- Get price from MarketplaceService
	local success, result = pcall(function()
		return MarketplaceService:GetProductInfo(gamepassId, Enum.InfoType.GamePass)
	end)

	if success and result then
		local price = result.PriceInRobux or 0
		local priceText = price > 0 and tostring(price) or "0"

		-- Navigate to the price text element
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local currentElement = playerGui

		-- Navigate through the path
		for _, elementName in ipairs(path) do
			currentElement = currentElement:FindFirstChild(elementName)
			if not currentElement then
				Logger:Warn(string.format("Could not find '%s' in path for %s price update", elementName, gamepassName))
				return
			end
		end

		-- Find the price text element
		local priceTextLabel = currentElement:FindFirstChild(priceTextPath)
		if priceTextLabel and priceTextLabel:IsA("TextLabel") then
			priceTextLabel.Text = priceText
			Logger:Info(string.format("Updated %s price to: %s", gamepassName, priceText))
		else
			Logger:Warn(string.format("Could not find price TextLabel '%s' for %s", priceTextPath, gamepassName))
		end
	else
		Logger:Error(string.format("Failed to get price info for %s: %s", gamepassName, tostring(result)))
	end
end

function GamepassClient:UpdateSingleProductPrice(productName, ...)
	local path = {...}
	local priceTextPath = table.remove(path) -- Last element is the price text name
	
	local productId = DEVELOPER_PRODUCT_IDS[productName]
	if not productId or productId == 0 then
		Logger:Warn(string.format("Developer product '%s' not configured for price update", productName))
		return
	end
	
	-- Get price from MarketplaceService
	local success, result = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	
	if success and result then
		local price = result.PriceInRobux or 0
		local priceText = price > 0 and tostring(price) or "0"
		
		-- Navigate to the price text element
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local currentElement = playerGui
		
		-- Navigate through the path
		for _, elementName in ipairs(path) do
			currentElement = currentElement:FindFirstChild(elementName)
			if not currentElement then
				Logger:Warn(string.format("Could not find '%s' in path for %s price update", elementName, productName))
				return
			end
		end
		
		-- Find the price text element
		local priceTextLabel = currentElement:FindFirstChild(priceTextPath)
		if priceTextLabel and priceTextLabel:IsA("TextLabel") then
			priceTextLabel.Text = priceText
			Logger:Info(string.format("Updated %s price to: %s", productName, priceText))
		else
			Logger:Warn(string.format("Could not find price TextLabel '%s' for %s", priceTextPath, productName))
		end
	else
		Logger:Error(string.format("Failed to get price info for %s: %s", productName, tostring(result)))
	end
end

-- Register callback for when a specific UI opens and needs price updates
function GamepassClient:RegisterPricingUpdateCallback(screenGuiName, callback)
	if not pricingUpdateCallbacks[screenGuiName] then
		pricingUpdateCallbacks[screenGuiName] = {}
	end
	table.insert(pricingUpdateCallbacks[screenGuiName], callback)
end

-- Trigger pricing updates for a specific UI
function GamepassClient:TriggerPricingUpdate(screenGuiName)
	local callbacks = pricingUpdateCallbacks[screenGuiName]
	if callbacks then
		for _, callback in ipairs(callbacks) do
			local success, result = pcall(callback)
			if not success then
				Logger:Error(string.format("Pricing update callback failed for %s: %s", screenGuiName, tostring(result)))
			end
		end
	end
end

function GamepassClient:_setupDynamicPricing()
	-- Register callback for GamepassShop pricing updates and button setup
	self:RegisterPricingUpdateCallback("GamepassShop", function()
		task.spawn(function()
			-- Wait a moment for UI to be fully loaded
			task.wait(0.5)
			self:UpdateGamepassPricing()
			self:SetupPurchaseButtons()
		end)
	end)

	Logger:Info("✓ Dynamic pricing and purchase button callbacks registered")
end

function GamepassClient:SetupPurchaseButtons()
	Logger:Info("Setting up purchase buttons for GamepassShop...")
	
	-- Setup gamepass purchase buttons
	-- 001_ItemColumn gamepasses
	self:SetupGamepassButton("DOUBLE_SPORES", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "01_2xSpores")
	self:SetupGamepassButton("SUPER_MAGNET", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "02_SuperMagnet")
	self:SetupGamepassButton("AUTO_TAP", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "03_AutoTap")
	self:SetupGamepassButton("DOUBLE_TAPS", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "2xTaps")
	self:SetupGamepassButton("LUCKY_GEM", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "LuckyGems")
	self:SetupGamepassButton("ULTRA_LUCKY_GEM", "GamepassShop", "Main", "Container", "ShopContainer", "001_ItemColumn", "UltraLuckyGems")
	
	-- Direct ShopContainer gamepasses
	self:SetupGamepassButton("AUTO_COLLECT", "GamepassShop", "Main", "Container", "ShopContainer", "002_AutoCollect")
	self:SetupGamepassButton("VIP", "GamepassShop", "Main", "Container", "ShopContainer", "004_VIP", "BuyButton")
	self:SetupGamepassButton("TRIPLE_SPORES", "GamepassShop", "Main", "Container", "ShopContainer", "010_3xSpores", "BuyButton")
	self:SetupGamepassButton("QUADRUPLE_SPORES", "GamepassShop", "Main", "Container", "ShopContainer", "011_4xSpores", "BuyButton")
	
	-- Setup developer product purchase buttons
	-- Gem Packs - the button is inside the container
	self:SetupProductButton("GEM_PACK_SMALL", "GamepassShop", "Main", "Container", "ShopContainer", "006_GemVault", "HandfulGems")
	self:SetupProductButton("GEM_PACK_MEDIUM", "GamepassShop", "Main", "Container", "ShopContainer", "006_GemVault", "BagGems")
	self:SetupProductButton("GEM_PACK_LARGE", "GamepassShop", "Main", "Container", "ShopContainer", "006_GemVault", "ChestGems")
	self:SetupProductButton("GEM_PACK_MEGA", "GamepassShop", "Main", "Container", "ShopContainer", "006_GemVault", "VaultGems")
	
	-- Spore Packs - the button is inside the container  
	self:SetupProductButton("SPORE_PACK_SMALL", "GamepassShop", "Main", "Container", "ShopContainer", "008_Spores", "SporePack1")
	self:SetupProductButton("SPORE_PACK_MEDIUM", "GamepassShop", "Main", "Container", "ShopContainer", "008_Spores", "SporePack2")
	self:SetupProductButton("SPORE_PACK_LARGE", "GamepassShop", "Main", "Container", "ShopContainer", "008_Spores", "SporePack3")
	self:SetupProductButton("SPORE_PACK_MEGA", "GamepassShop", "Main", "Container", "ShopContainer", "008_Spores", "SporePack4")
	
	Logger:Info("All purchase buttons setup complete")
end

function GamepassClient:SetupGamepassButton(gamepassName, ...)
	local path = {...}
	
	-- Navigate to the button element
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local currentElement = playerGui
	
	-- Navigate through the path
	for _, elementName in ipairs(path) do
		currentElement = currentElement:FindFirstChild(elementName)
		if not currentElement then
			Logger:Warn(string.format("Could not find '%s' in path for %s button setup", elementName, gamepassName))
			return
		end
	end
	
	-- The final element should be a button
	if currentElement and currentElement:IsA("GuiButton") then
		local connection = currentElement.MouseButton1Click:Connect(function()
			Logger:Info(string.format("Purchase button clicked for gamepass: %s", gamepassName))
			self:PurchaseGamepass(gamepassName)
		end)
		
		-- Store connection for cleanup (optional)
		Logger:Info(string.format("✓ Setup purchase button for gamepass: %s", gamepassName))
	else
		Logger:Warn(string.format("Final element is not a GuiButton for %s: %s", gamepassName, currentElement and currentElement.ClassName or "nil"))
	end
end

function GamepassClient:SetupProductButton(productName, ...)
	local path = {...}
	
	-- Navigate to the button element
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local currentElement = playerGui
	
	-- Navigate through the path
	for _, elementName in ipairs(path) do
		currentElement = currentElement:FindFirstChild(elementName)
		if not currentElement then
			Logger:Warn(string.format("Could not find '%s' in path for %s button setup", elementName, productName))
			return
		end
	end
	
	-- The final element might be a button or contain one
	local buttonElement = nil
	if currentElement and currentElement:IsA("GuiButton") then
		buttonElement = currentElement
	else
		-- Try to find a GuiButton child
		buttonElement = currentElement:FindFirstChildOfClass("GuiButton")
		if not buttonElement then
			-- Try common button names
			local commonNames = {"Button", "BuyButton", "PurchaseButton", "Buy"}
			for _, name in ipairs(commonNames) do
				local child = currentElement:FindFirstChild(name)
				if child and child:IsA("GuiButton") then
					buttonElement = child
					break
				end
			end
		end
	end
	
	if buttonElement then
		local connection = buttonElement.MouseButton1Click:Connect(function()
			Logger:Info(string.format("Purchase button clicked for developer product: %s", productName))
			self:PurchaseProduct(productName)
		end)
		
		Logger:Info(string.format("✓ Setup purchase button for product: %s (found %s)", productName, buttonElement.Name))
	else
		Logger:Warn(string.format("Could not find GuiButton for %s in element: %s", productName, currentElement and currentElement.Name or "nil"))
		-- Debug: Show available children
		if currentElement then
			local children = {}
			for _, child in pairs(currentElement:GetChildren()) do
				table.insert(children, child.Name .. "(" .. child.ClassName .. ")")
			end
			Logger:Debug(string.format("Available children in %s: %s", currentElement.Name, table.concat(children, ", ")))
		end
	end
end

function GamepassClient:Cleanup()
	-- Clear any remaining callbacks
	self.purchaseCallbacks = {}
	Logger:Info("GamepassService cleaned up")
end

return GamepassClient