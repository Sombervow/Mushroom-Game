local GamepassService = {}
GamepassService.__index = GamepassService

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local GamepassConfig = require(ReplicatedStorage.Shared.Modules.GamepassConfig)

-- Developer Product Configuration (using actual product IDs)
local DEVELOPER_PRODUCTS = {
    -- Gem Packs
    [3413686220] = {type = "gems", amount = 2500, name = "GEM_PACK_SMALL"},
    [3413686218] = {type = "gems", amount = 15000, name = "GEM_PACK_MEDIUM"},
    [3413686217] = {type = "gems", amount = 50000, name = "GEM_PACK_LARGE"},
    [3413686216] = {type = "gems", amount = 225000, name = "GEM_PACK_MEGA"},
    
    -- Spore Packs
    [3413686214] = {type = "spores", amount = 400000, name = "SPORE_PACK_SMALL"},
    [3413686213] = {type = "spores", amount = 2000000, name = "SPORE_PACK_MEDIUM"},
    [3413686212] = {type = "spores", amount = 5000000, name = "SPORE_PACK_LARGE"},
    [3413686211] = {type = "spores", amount = 40000000, name = "SPORE_PACK_MEGA"},
    
    -- Special Products
    [3413686210] = {type = "special", amount = 1, name = "DOUBLE_OFFLINE_EARNINGS"},
    [3413686209] = {type = "starter_pack", spores = 750000, gems = 4500, name = "STARTER_PACK"},
}

function GamepassService.new(logger, dataService)
	local self = setmetatable({}, GamepassService)
	
	self.logger = logger
	self.dataService = dataService
	self.playerGamepasses = {}
	self.autoTapLoops = {} -- Track auto tap loops for each player
	self.autoCollectLoops = {} -- Track auto collect loops for each player
	
	return self
end

function GamepassService:initialize()
	Logger:Info("GamepassService: Initializing GamepassService")
	
	-- Connect to purchase events
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if wasPurchased then
			self:onGamepassPurchased(player, gamePassId)
		end
	end)
	
	-- Set up ProcessReceipt for developer products (REQUIRED for dev products to work)
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:processReceipt(receiptInfo)
	end
	
	-- Connect to player events
	Players.PlayerAdded:Connect(function(player)
		self:loadPlayerGamepasses(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self.playerGamepasses[player] = nil
		self:stopAutoTap(player)
		self:stopAutoCollect(player)
	end)
end

function GamepassService:loadPlayerGamepasses(player)
	Logger:Info(string.format("GamepassService: Loading gamepasses for player %s", player.Name))
	self.playerGamepasses[player] = {}
	
	for gamepassName, gamepassId in pairs(GamepassConfig.GAMEPASS_IDS) do
		Logger:Info(string.format("GamepassService: Checking gamepass %s (ID: %d) for player %s", gamepassName, gamepassId, player.Name))
		if gamepassId > 0 then
			local success, hasGamepass = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
			end)
			
			if success then
				self.playerGamepasses[player][gamepassName] = hasGamepass
				Logger:Info(string.format("GamepassService: Player %s gamepass %s = %s", player.Name, gamepassName, tostring(hasGamepass)))
			else
				Logger:Error(string.format("GamepassService: Failed to check gamepass %s for player %s", gamepassName, player.Name))
				self.playerGamepasses[player][gamepassName] = false
			end
		else
			Logger:Info(string.format("GamepassService: Skipping gamepass %s (ID is 0)", gamepassName))
			self.playerGamepasses[player][gamepassName] = false
		end
	end
	
	-- Start auto tap if player has the gamepass
	self:checkAndStartAutoTap(player)
	
	-- Start auto collect if player has the gamepass
	self:checkAndStartAutoCollect(player)
	
	-- Apply VIP effects if player has VIP
	if self:hasGamepass(player, "VIP") then
		self:applyVipEffects(player)
		
		-- Setup character respawn handling for overhead tag
		player.CharacterAdded:Connect(function(character)
			-- Wait a moment for character to fully load
			task.wait(0.5)
			self:setupVipOverheadTag(player)
		end)
	end
end

function GamepassService:onGamepassPurchased(player, gamePassId)
	Logger:Info(string.format("GamepassService: Player %s purchased gamepass %d", player.Name, gamePassId))
	
	-- Update player gamepass cache
	for gamepassName, configId in pairs(GamepassConfig.GAMEPASS_IDS) do
		if configId == gamePassId then
			if not self.playerGamepasses[player] then
				self.playerGamepasses[player] = {}
			end
			self.playerGamepasses[player][gamepassName] = true
			
			-- Apply immediate effects for certain gamepasses
			if gamepassName == "VIP_STARTER_PACK" then
				self:applyVipStarterPack(player)
			elseif gamepassName == "AUTO_TAP" then
				self:startAutoTap(player)
			elseif gamepassName == "AUTO_COLLECT" then
				self:startAutoCollect(player)
			elseif gamepassName == "VIP" then
				self:applyVipEffects(player)
			end
			break
		end
	end
end

function GamepassService:processReceipt(receiptInfo)
	Logger:Info(string.format("ProcessReceipt called! ProductId: %d, PlayerId: %d", receiptInfo.ProductId, receiptInfo.PlayerId))
	
	-- Find the player who made the purchase
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player left the game, but we should still award the purchase when they rejoin
		-- For now, we'll just log it and grant on next join if implemented
		Logger:Warn(string.format("Player with UserId %d not found for product purchase %d", receiptInfo.PlayerId, receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	Logger:Info(string.format("Found player %s for product purchase", player.Name))
	
	local productData = DEVELOPER_PRODUCTS[receiptInfo.ProductId]
	if not productData then
		Logger:Info(string.format("Product ID %d not found in GamepassService, checking RobuxMarketplaceService...", receiptInfo.ProductId))
		-- Try RobuxMarketplaceService for wish purchases and other products
		if self.robuxMarketplaceService and self.robuxMarketplaceService._processReceipt then
			return self.robuxMarketplaceService:_processReceipt(receiptInfo)
		else
			Logger:Warn(string.format("Unknown developer product ID: %d (no RobuxMarketplaceService available)", receiptInfo.ProductId))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	
	local success = false
	
	-- Award currency based on product type
	if productData.type == "starter_pack" then
		Logger:Info(string.format("Product type: %s, spores: %d, gems: %d", productData.type, productData.spores, productData.gems))
	else
		Logger:Info(string.format("Product type: %s, amount: %d", productData.type, productData.amount or 0))
	end
	
	if productData.type == "gems" then
		if self.dataService then
			Logger:Info(string.format("Calling AddGems for %s with amount %d", player.Name, productData.amount))
			success = self.dataService:AddGems(player, productData.amount, "Developer Product: " .. productData.name)
			if success then
				Logger:Info(string.format("SUCCESS: Awarded %d gems to %s from product purchase", productData.amount, player.Name))
			else
				Logger:Error(string.format("FAILED: Could not award %d gems to %s", productData.amount, player.Name))
			end
		else
			Logger:Error("DataService not available in GamepassService!")
		end
	elseif productData.type == "spores" then
		if self.dataService then
			Logger:Info(string.format("Calling AddSpores for %s with amount %d", player.Name, productData.amount))
			success = self.dataService:AddSpores(player, productData.amount, "Developer Product: " .. productData.name)
			if success then
				Logger:Info(string.format("SUCCESS: Awarded %d spores to %s from product purchase", productData.amount, player.Name))
			else
				Logger:Error(string.format("FAILED: Could not award %d spores to %s", productData.amount, player.Name))
			end
		else
			Logger:Error("DataService not available in GamepassService!")
		end
	elseif productData.type == "starter_pack" then
		-- Handle starter pack - gives both spores and gems
		if self.dataService then
			Logger:Info(string.format("Processing starter pack for %s: %d spores, %d gems", player.Name, productData.spores, productData.gems))
			
			local sporeSuccess = self.dataService:AddSpores(player, productData.spores, "Developer Product: " .. productData.name)
			local gemSuccess = self.dataService:AddGems(player, productData.gems, "Developer Product: " .. productData.name)
			
			if sporeSuccess and gemSuccess then
				success = true
				Logger:Info(string.format("SUCCESS: Starter pack awarded to %s - %d spores, %d gems", player.Name, productData.spores, productData.gems))
			else
				Logger:Error(string.format("FAILED: Starter pack partially failed for %s - spores: %s, gems: %s", player.Name, tostring(sporeSuccess), tostring(gemSuccess)))
			end
		else
			Logger:Error("DataService not available in GamepassService!")
		end
	elseif productData.type == "special" then
		-- Handle special products like double offline earnings
		if productData.name == "DOUBLE_OFFLINE_EARNINGS" then
			-- This could be handled by setting a player attribute or data field
			if self.dataService then
				success = true -- For now, just log it
				Logger:Info(string.format("Applied %s to %s", productData.name, player.Name))
			end
		end
	end
	
	if success then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	else
		Logger:Error(string.format("Failed to process product purchase for %s", player.Name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

-- Keep the old method for compatibility
function GamepassService:onProductPurchased(player, productId)
	Logger:Info(string.format("GamepassService: Player %s purchased developer product %d (legacy method)", player.Name, productId))
	-- This method is now deprecated in favor of ProcessReceipt
end

function GamepassService:applyVipStarterPack(player)
	-- Give starter pack rewards
	self.dataService:AddSpores(player, 10000, "VIP Starter Pack")
	self.dataService:AddGems(player, 100, "VIP Starter Pack")
	
	-- Add 3 extra mushrooms to their plot (handled by MushroomService)
	local mushroomService = self.mushroomService
	if mushroomService then
		for i = 1, 3 do
			mushroomService:addMushroomToPlot(player)
		end
	end
end

function GamepassService:hasGamepass(player, gamepassName)
	if not self.playerGamepasses[player] then
		return false
	end
	return self.playerGamepasses[player][gamepassName] == true
end

function GamepassService:getSporeMultiplier(player)
	local multiplier = 1
	local hasDoubleSpores = self:hasGamepass(player, "DOUBLE_SPORES")
	local hasTripleSpores = self:hasGamepass(player, "TRIPLE_SPORES")
	local hasQuadrupleSpores = self:hasGamepass(player, "QUADRUPLE_SPORES")
	
	
	-- Apply 2x spores first
	if hasDoubleSpores then
		multiplier = multiplier * 2
	end
	
	-- Apply 3x spores only if player has 2x spores first (stacks for 5x total)
	if hasTripleSpores and hasDoubleSpores then
		multiplier = multiplier + 3 -- Add 3 more for total of 5x (2x + 3x = 5x)
		-- Logger:Info(string.format("GamepassService: Applied triple spores bonus (2x + 3x = 5x total) for %s", player.Name))
	elseif hasTripleSpores and not hasDoubleSpores then
		Logger:Info(string.format("GamepassService: Player %s has triple spores but not double spores - triple spores ignored", player.Name))
	end
	
	-- Apply 4x spores only if player has 3x spores (which requires 2x) - stacks for 9x total
	if hasQuadrupleSpores and hasTripleSpores and hasDoubleSpores then
		multiplier = multiplier + 4 -- Add 4 more for total of 9x (2x + 3x + 4x = 9x)
		-- Logger:Info(string.format("GamepassService: Applied quadruple spores bonus (2x + 3x + 4x = 9x total) for %s", player.Name))
	elseif hasQuadrupleSpores and not (hasTripleSpores and hasDoubleSpores) then
		Logger:Info(string.format("GamepassService: Player %s has quadruple spores but missing prerequisites - quadruple spores ignored", player.Name))
	end
	
	return multiplier
end

function GamepassService:getGemMultiplier(player)
	local multiplier = 1
	
	if self:hasGamepass(player, "TRIPLE_GEMS") then
		multiplier = multiplier * 3
	end
	
	return multiplier
end

function GamepassService:getCollectionRadiusMultiplier(player)
	local multiplier = 1
	
	-- Super Magnet doubles the pickup radius
	if self:hasGamepass(player, "SUPER_MAGNET") then
		multiplier = multiplier * 2
		Logger:Info(string.format("GamepassService: Applied Super Magnet (2x radius) for %s", player.Name))
	end
	
	-- Legacy MEGA_COLLECTOR for flat bonus (if still needed)
	if self:hasGamepass(player, "MEGA_COLLECTOR") then
		-- This adds a flat +10 stud bonus on top of the multiplier
		-- Could be changed to another multiplier if preferred
		Logger:Info(string.format("GamepassService: Applied Mega Collector (+10 studs) for %s", player.Name))
	end
	
	Logger:Info(string.format("GamepassService: Collection radius multiplier for %s = %.1f", player.Name, multiplier))
	return multiplier
end

function GamepassService:getCollectionRadiusBonus(player)
	local bonus = 0
	
	-- Legacy method for flat bonuses
	if self:hasGamepass(player, "MEGA_COLLECTOR") then
		bonus = bonus + 10
	end
	
	return bonus
end

function GamepassService:getSporeSpawnRateMultiplier(player)
	local multiplier = 1
	
	if self:hasGamepass(player, "INSTANT_SPAWN") then
		multiplier = multiplier * 10
	end
	
	return multiplier
end

function GamepassService:getPlotSizeMultiplier(player)
	local multiplier = 1
	
	if self:hasGamepass(player, "PLOT_EXPANDER") then
		multiplier = multiplier * 1.5
	end
	
	return multiplier
end

function GamepassService:getClickMultiplier(player)
	local multiplier = 1
	
	if self:hasGamepass(player, "DOUBLE_TAPS") then
		multiplier = multiplier * 2
		-- Logger:Info(string.format("GamepassService: Applied Double Taps (2x click value) for %s", player.Name))
	end
	
	return multiplier
end

function GamepassService:getGemChanceMultiplier(player)
	local multiplier = 1
	local hasLuckyGem = self:hasGamepass(player, "LUCKY_GEM")
	local hasUltraLuckyGem = self:hasGamepass(player, "ULTRA_LUCKY_GEM")
	
	if hasLuckyGem then
		multiplier = multiplier * 2
		-- Logger:Info(string.format("GamepassService: Applied Lucky Gem (2x gem chance) for %s", player.Name))
	end
	
	if hasUltraLuckyGem then
		multiplier = multiplier * 3
		-- Logger:Info(string.format("GamepassService: Applied Ultra Lucky Gem (3x gem chance) for %s", player.Name))
	end
	
	-- Log final multiplier if both are active
	if hasLuckyGem and hasUltraLuckyGem then
		-- Logger:Info(string.format("GamepassService: Combined gem chance multiplier for %s: %.1fx (2x * 3x = 6x)", player.Name, multiplier))
	end
	
	return multiplier
end

function GamepassService:linkServices(services)
	self.mushroomService = services.MushroomService
	self.plotService = services.PlotService
	self.robuxMarketplaceService = services.RobuxMarketplaceService
end

function GamepassService:startAutoTap(player)
	if not self:hasGamepass(player, "AUTO_TAP") then
		return
	end
	
	-- Don't start if already running
	if self.autoTapLoops[player] then
		return
	end
	
	Logger:Info(string.format("GamepassService: Starting auto tap for %s", player.Name))
	
	-- Set to true before spawning so the loop doesn't exit immediately
	self.autoTapLoops[player] = true
	
	local function autoTapLoop()
		while self.autoTapLoops[player] and player.Parent and self:hasGamepass(player, "AUTO_TAP") do
			local success, result = pcall(function()
				self:performAutoTap(player)
			end)
			
			if not success then
				Logger:Error(string.format("GamepassService: Auto tap error for %s: %s", player.Name, tostring(result)))
			end
			
			task.wait(0.5) -- Auto tap every 0.5 seconds to reduce lag
		end
		
		self.autoTapLoops[player] = nil
		Logger:Info(string.format("GamepassService: Auto tap stopped for %s", player.Name))
	end
	
	-- Replace the boolean with the actual thread
	self.autoTapLoops[player] = task.spawn(autoTapLoop)
end

function GamepassService:stopAutoTap(player)
	if self.autoTapLoops[player] then
		self.autoTapLoops[player] = nil
		Logger:Info(string.format("GamepassService: Stopped auto tap for %s", player.Name))
	end
end

function GamepassService:performAutoTap(player)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		return
	end
	
	local playerPosition = player.Character.HumanoidRootPart.Position
	local maxDistance = 20
	local closestMushroom = nil
	local closestDistance = math.huge
	
	-- Get player's plot to search only their mushrooms
	local playerPlot = nil
	local playerPlots = game.Workspace:FindFirstChild("PlayerPlots")
	if playerPlots then
		playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	end
	
	if not playerPlot then
		return -- No plot found
	end
	
	-- Search for mushrooms in player's plot using direct iteration
	local function searchMushroomsInFolder(folder)
		if not folder then return end
		
		for _, obj in pairs(folder:GetChildren()) do
			if obj.Name:match("MushroomModel_") and obj:IsA("Model") then
				local mainPart = obj.PrimaryPart or obj:FindFirstChild("Stem") or obj:FindFirstChildOfClass("BasePart")
				if mainPart then
					local distance = (playerPosition - mainPart.Position).Magnitude
					if distance <= maxDistance and distance < closestDistance then
						closestMushroom = obj
						closestDistance = distance
					end
				end
			end
		end
	end
	
	-- Search Area1 mushrooms
	local area1Mushrooms = playerPlot:FindFirstChild("Mushrooms")
	searchMushroomsInFolder(area1Mushrooms)
	
	-- Search Area2 mushrooms if Area2 exists
	local area2 = playerPlot:FindFirstChild("Area2")
	if area2 then
		local area2Mushrooms = area2:FindFirstChild("Mushrooms")
		searchMushroomsInFolder(area2Mushrooms)
	end
	
	-- Search Area3 mushrooms if Area3 exists
	local area3 = playerPlot:FindFirstChild("Area3")
	if area3 then
		local area3Mushrooms = area3:FindFirstChild("Mushrooms")
		searchMushroomsInFolder(area3Mushrooms)
	end
	
	-- Auto click the closest mushroom if found
	if closestMushroom and self.mushroomService then
		self.mushroomService:ForceMushroomClick(player, closestMushroom)
	end
end

-- Method to check and start auto tap when gamepass is purchased or player joins
function GamepassService:checkAndStartAutoTap(player)
	if self:hasGamepass(player, "AUTO_TAP") then
		self:startAutoTap(player)
	end
end

function GamepassService:startAutoCollect(player)
	if not self:hasGamepass(player, "AUTO_COLLECT") then
		return
	end
	
	-- Don't start if already running
	if self.autoCollectLoops[player] then
		return
	end
	
	Logger:Info(string.format("GamepassService: Starting auto collect for %s", player.Name))
	
	-- Set to true before spawning so the loop doesn't exit immediately
	self.autoCollectLoops[player] = true
	
	local function autoCollectLoop()
		while self.autoCollectLoops[player] and player.Parent and self:hasGamepass(player, "AUTO_COLLECT") do
			local success, result = pcall(function()
				self:performAutoCollect(player)
			end)
			
			if not success then
				Logger:Error(string.format("GamepassService: Auto collect error for %s: %s", player.Name, tostring(result)))
			end
			
			task.wait(0.1) -- Auto collect every 0.1 seconds for instant collection feel
		end
		
		self.autoCollectLoops[player] = nil
		Logger:Info(string.format("GamepassService: Auto collect stopped for %s", player.Name))
	end
	
	-- Replace the boolean with the actual thread
	self.autoCollectLoops[player] = task.spawn(autoCollectLoop)
end

function GamepassService:stopAutoCollect(player)
	if self.autoCollectLoops[player] then
		self.autoCollectLoops[player] = nil
		Logger:Info(string.format("GamepassService: Stopped auto collect for %s", player.Name))
	end
end

function GamepassService:performAutoCollect(player)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		return
	end
	
	-- Get player's plot to search only their spores
	local playerPlot = nil
	local playerPlots = game.Workspace:FindFirstChild("PlayerPlots")
	if playerPlots then
		playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	end
	
	if not playerPlot then
		return -- No plot found
	end
	
	-- Collect all spores in player's plot using direct iteration
	local function collectSporesFromFolder(folder)
		if not folder then return end
		
		for _, obj in pairs(folder:GetChildren()) do
			if obj:IsA("BasePart") then
				local isSpore = obj.Name:match("SporePart_") or obj.Name:match("ClickedSporePart_")
				local isGem = obj.Name:match("GemSporePart_") or obj.Name:match("ClickedGemSporePart_") 
				local isBigSpore = obj.Name:match("BigSpore_")
				local isGoldSpore = obj.Name:match("GoldSporePart_") or obj.Name:match("GoldClickedSporePart_") or obj.Name:match("GoldGemSporePart_")
				
				if isSpore or isGem or isBigSpore or isGoldSpore then
					-- Determine item type for collection
					local itemType = "spore"
					if isBigSpore then
						itemType = "bigspore"
					elseif isGem then
						itemType = "gem"
					end
					
					-- Simulate collection by calling DataService directly
					if self.dataService then
						self.dataService:_handleItemCollection(player, obj, itemType, obj.Name)
					end
				end
			end
		end
	end
	
	-- Collect from Area1 spores
	local area1Spores = playerPlot:FindFirstChild("Spores")
	collectSporesFromFolder(area1Spores)
	
	-- Collect from Area2 spores if Area2 exists
	local area2 = playerPlot:FindFirstChild("Area2")
	if area2 then
		local area2Spores = area2:FindFirstChild("Spores")
		collectSporesFromFolder(area2Spores)
	end
	
	-- Collect from Area3 spores if Area3 exists
	local area3 = playerPlot:FindFirstChild("Area3")
	if area3 then
		local area3Spores = area3:FindFirstChild("Spores")
		collectSporesFromFolder(area3Spores)
	end
end

-- Method to check and start auto collect when gamepass is purchased or player joins
function GamepassService:checkAndStartAutoCollect(player)
	if self:hasGamepass(player, "AUTO_COLLECT") then
		self:startAutoCollect(player)
	end
end

function GamepassService:applyVipEffects(player)
	Logger:Info(string.format("GamepassService: Applying VIP effects for %s", player.Name))
	
	-- Apply VIP chat tag
	self:setupVipChatTag(player)
	
	-- Apply VIP overhead tag
	self:setupVipOverheadTag(player)
end

function GamepassService:setupVipChatTag(player)
	local success, result = pcall(function()
		if player:GetAttribute("VipChatTagApplied") then
			return -- Already applied
		end
		
		-- Try TextChatService first (new chat system)
		local TextChatService = game:GetService("TextChatService")
		if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			-- Wait for ChatService to be ready
			local chatService = TextChatService:WaitForChild("ChatService", 5)
			if chatService then
				-- Wait for player's speaker to be created
				task.spawn(function()
					local maxAttempts = 10
					local attempt = 0
					
					while attempt < maxAttempts and player.Parent do
						attempt = attempt + 1
						local speaker = chatService:GetSpeaker(player.Name)
						
						if speaker then
							-- Create VIP chat tag
							local vipTag = {
								TagText = "VIP",
								TagColor = Color3.fromRGB(255, 215, 0) -- Gold
							}
							
							speaker:SetExtraData("Tags", {vipTag})
							player:SetAttribute("VipChatTagApplied", true)
							Logger:Info(string.format("Applied VIP chat tag to %s using TextChatService", player.Name))
							return
						end
						
						task.wait(1) -- Wait 1 second between attempts
					end
					
					Logger:Warn(string.format("Could not find ChatSpeaker for %s after %d attempts", player.Name, maxAttempts))
				end)
			else
				Logger:Warn("ChatService not found in TextChatService")
			end
		else
			-- Legacy chat system - use ChatService
			local ChatService = game:GetService("Chat")
			local success2, result2 = pcall(function()
				-- Wait for speaker to exist
				task.spawn(function()
					local maxAttempts = 10
					local attempt = 0
					
					while attempt < maxAttempts and player.Parent do
						attempt = attempt + 1
						local speaker = ChatService:GetSpeaker(player.Name)
						
						if speaker then
							-- Add VIP tag to legacy chat
							speaker:SetExtraData("Tags", {{TagText = "VIP", TagColor = Color3.fromRGB(255, 215, 0)}})
							player:SetAttribute("VipChatTagApplied", true)
							Logger:Info(string.format("Applied VIP chat tag to %s using legacy ChatService", player.Name))
							return
						end
						
						task.wait(1)
					end
					
					Logger:Warn(string.format("Could not find legacy ChatSpeaker for %s after %d attempts", player.Name, maxAttempts))
				end)
			end)
			
			if not success2 then
				Logger:Warn(string.format("Legacy chat tag failed for %s: %s", player.Name, tostring(result2)))
			end
		end
	end)
	
	if not success then
		Logger:Warn(string.format("Failed to setup VIP chat tag for %s: %s", player.Name, tostring(result)))
	end
end

function GamepassService:setupVipOverheadTag(player)
	-- Create VIP tag above player's head
	local success, result = pcall(function()
		if player.Character and player.Character:FindFirstChild("Head") then
			-- Check if tag already exists
			local existingTag = player.Character.Head:FindFirstChild("VipTag")
			if not existingTag then
				-- Create VIP overhead tag
				local vipGui = Instance.new("BillboardGui")
				vipGui.Name = "VipTag"
				vipGui.Size = UDim2.new(0, 100, 0, 25)
				vipGui.StudsOffset = Vector3.new(0, 3, 0)
				vipGui.Parent = player.Character.Head
				
				local vipFrame = Instance.new("Frame")
				vipFrame.Size = UDim2.new(1, 0, 1, 0)
				vipFrame.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Gold
				vipFrame.BorderSizePixel = 0
				vipFrame.Parent = vipGui
				
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 8)
				corner.Parent = vipFrame
				
				local vipLabel = Instance.new("TextLabel")
				vipLabel.Size = UDim2.new(1, 0, 1, 0)
				vipLabel.BackgroundTransparency = 1
				vipLabel.Text = "👑 VIP"
				vipLabel.TextColor3 = Color3.fromRGB(0, 0, 0) -- Black text
				vipLabel.TextScaled = true
				vipLabel.Font = Enum.Font.GothamBold
				vipLabel.Parent = vipFrame
				
				Logger:Info(string.format("Applied VIP overhead tag to %s", player.Name))
			end
		else
			-- Character not ready, try again later
			task.wait(1)
			if player.Parent then -- Player still in game
				self:setupVipOverheadTag(player)
			end
		end
	end)
	
	if not success then
		Logger:Warn(string.format("Failed to apply VIP overhead tag to %s: %s", player.Name, tostring(result)))
	end
end

function GamepassService:getDailyRewardMultiplier(player)
	local multiplier = 1
	
	if self:hasGamepass(player, "VIP") then
		multiplier = multiplier * 2
		Logger:Info(string.format("GamepassService: Applied VIP daily reward multiplier (2x) for %s", player.Name))
	end
	
	return multiplier
end

-- Helper method to update developer product IDs
function GamepassService:SetDeveloperProductId(productType, size, productId)
	local productKey = nil
	if productType == "gems" then
		if size == "small" then productKey = 1001
		elseif size == "medium" then productKey = 1002
		elseif size == "large" then productKey = 1003
		elseif size == "mega" then productKey = 1004
		end
	elseif productType == "spores" then
		if size == "small" then productKey = 2001
		elseif size == "medium" then productKey = 2002
		elseif size == "large" then productKey = 2003
		elseif size == "mega" then productKey = 2004
		end
	end
	
	if productKey then
		local oldData = DEVELOPER_PRODUCTS[productKey]
		if oldData then
			-- Create new entry with actual product ID
			DEVELOPER_PRODUCTS[productId] = {
				type = oldData.type,
				amount = oldData.amount,
				name = oldData.name
			}
			-- Remove placeholder entry
			DEVELOPER_PRODUCTS[productKey] = nil
			Logger:Info(string.format("Updated %s %s pack (ID: %d) with %d %s", size, productType, productId, oldData.amount, productType))
		end
	else
		Logger:Warn(string.format("Invalid product configuration: %s %s", productType, size))
	end
end

-- Helper method to get all configured developer products (for debugging)
function GamepassService:GetDeveloperProducts()
	return DEVELOPER_PRODUCTS
end

return GamepassService