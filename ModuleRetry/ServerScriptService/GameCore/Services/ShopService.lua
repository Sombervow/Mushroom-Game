local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local Types = require(ReplicatedStorage.Shared.Modules.Types)

local ShopService = {}
ShopService.__index = ShopService

-- Shop configuration
local SHOP_CONFIG = {
	SporeUpgrade = {
		baseCost = 20,
		costMultiplier = 1.08, -- Unified 8% increase (was 50%, cut to ~8%)
		upgradeBonus = 0.08 -- 8% increase
	},
	MushroomPurchase = {
		baseCost = 20,
		costMultiplier = 1.11 -- Unified 11% increase
	},
	-- Separate mushroom shop configurations
	Area1MushroomShop = {
		baseCost = 20,
		costMultiplier = 1.11, -- Unified 11% increase
		maxLevel = 100  -- Level cap
	},
	Area2MushroomShop = {
		baseCost = 20,  -- Area2 starts at 20 spores (same as Area1)
		costMultiplier = 1.11, -- Unified 11% increase
		maxLevel = 100  -- Level cap
	},
	Area3MushroomShop = {
		baseCost = 20,  -- Area3 starts at 20 spores (same as Area1/2)
		costMultiplier = 1.11, -- Unified 11% increase
		maxLevel = 100  -- Level cap
	},
	-- Spore upgrade caps for ascension requirements
	SporeUpgradeCaps = {
		area1MaxLevel = 100,  -- Max level for Area1 spore upgrades
		area2MaxLevel = 100   -- Max level for Area2 spore upgrades
	},
	-- Gem Shop Upgrades (flat 2 gems per level, max level 20)
	FastRunner = {
		baseCost = 10,
		costIncrease = 2, -- +2 gems per level
		speedBonus = 0.04, -- 4% increase per level
		maxLevel = 20 -- Level cap
	},
	PickUpRange = {
		baseCost = 10,
		costIncrease = 2, -- +2 gems per level
		rangeBonus = 0.25, -- +0.25 studs per level
		maxLevel = 20 -- Level cap
	},
	FasterShrooms = {
		baseCost = 10,
		costIncrease = 2, -- +2 gems per level
		speedBonus = 0.02, -- +2% production speed per level
		maxLevel = 20 -- Level cap
	},
	ShinySpore = {
		baseCost = 10,
		costIncrease = 2, -- +2 gems per level
		valueBonus = 0.02, -- +2% spore value per level
		maxLevel = 20 -- Level cap
	},
	GemHunter = {
		baseCost = 15,
		costIncrease = 2, -- +2 gems per level (reduced from 3)
		gemBonus = 0.02, -- +2% gem drop chance per level
		maxLevel = 20 -- Level cap
	}
}

-- Sound configuration
local SOUND_CONFIG = {
	PURCHASE_SUCCESS = "rbxassetid://111122618487379", -- Purchase success sound
	PURCHASE_FAIL = "rbxassetid://89567959268147", -- Can't afford sound
	VOLUME = 0.6
}

function ShopService.new()
	local self = setmetatable({}, ShopService)
	self._connections = {}
	self._dataService = nil
	self._mushroomService = nil
	self._gamepassService = nil
	self._playerUpgrades = {} -- Track player upgrade levels
	self._tutorialPurchaseSuccess = nil -- Tutorial purchase tracking
	self:_initialize()
	return self
end

-- Sound helper functions
function ShopService:_playPurchaseSuccessSound(player)
	Logger:Info(string.format("Playing purchase success sound for %s (ID: %s)", player.Name, SOUND_CONFIG.PURCHASE_SUCCESS))
	
	local sound = Instance.new("Sound")
	sound.SoundId = SOUND_CONFIG.PURCHASE_SUCCESS
	sound.Volume = SOUND_CONFIG.VOLUME
	sound.Parent = SoundService
	sound.Name = "PurchaseSuccessSound_" .. player.Name
	
	Logger:Info(string.format("Created sound object: %s, Parent: %s, Volume: %s", sound.SoundId, tostring(sound.Parent), tostring(sound.Volume)))
	
	-- Add error handling
	local success, err = pcall(function()
		sound:Play()
		Logger:Info("Sound:Play() called successfully")
	end)
	
	if not success then
		Logger:Error(string.format("Failed to play purchase success sound: %s", tostring(err)))
	else
		Logger:Info("Purchase success sound play command executed")
	end
	
	-- Clean up after playing
	sound.Ended:Connect(function()
		Logger:Info("Purchase success sound ended, destroying...")
		sound:Destroy()
	end)
	game:GetService("Debris"):AddItem(sound, 10) -- Even longer cleanup time for debugging
end

function ShopService:_playPurchaseFailSound(player)
	Logger:Info(string.format("Playing purchase fail sound for %s (ID: %s)", player.Name, SOUND_CONFIG.PURCHASE_FAIL))
	
	local sound = Instance.new("Sound")
	sound.SoundId = SOUND_CONFIG.PURCHASE_FAIL
	sound.Volume = SOUND_CONFIG.VOLUME
	sound.Parent = SoundService
	sound.Name = "PurchaseFailSound_" .. player.Name
	
	Logger:Info(string.format("Created sound object: %s, Parent: %s, Volume: %s", sound.SoundId, tostring(sound.Parent), tostring(sound.Volume)))
	
	-- Add error handling
	local success, err = pcall(function()
		sound:Play()
		Logger:Info("Sound:Play() called successfully")
	end)
	
	if not success then
		Logger:Error(string.format("Failed to play purchase fail sound: %s", tostring(err)))
	else
		Logger:Info("Purchase fail sound play command executed")
	end
	
	-- Clean up after playing
	sound.Ended:Connect(function()
		Logger:Info("Purchase fail sound ended, destroying...")
		sound:Destroy()
	end)
	game:GetService("Debris"):AddItem(sound, 10) -- Even longer cleanup time for debugging
end

function ShopService:_promptDevProduct(player, productType)
	-- Prompt the cheapest dev product for the currency type they need
	local marketplaceService = game:GetService("MarketplaceService")
	
	if productType == "spores" then
		-- Prompt cheapest spore pack (Small = 3413686214)
		local success, result = pcall(function()
			marketplaceService:PromptProductPurchase(player, 3413686214)
		end)
		if success then
			Logger:Info(string.format("Prompted cheapest spore pack for %s", player.Name))
		else
			Logger:Error(string.format("Failed to prompt spore pack for %s: %s", player.Name, tostring(result)))
		end
	elseif productType == "gems" then
		-- Prompt cheapest gem pack (Small = 3413686220)
		local success, result = pcall(function()
			marketplaceService:PromptProductPurchase(player, 3413686220)
		end)
		if success then
			Logger:Info(string.format("Prompted cheapest gem pack for %s", player.Name))
		else
			Logger:Error(string.format("Failed to prompt gem pack for %s: %s", player.Name, tostring(result)))
		end
	else
		Logger:Warn(string.format("Unknown product type: %s for player %s", productType, player.Name))
	end
end

function ShopService:_initialize()
	if RunService:IsServer() then
		self:_setupRemoteEvents()

		-- Handle players joining/leaving
		self._connections.PlayerAdded = Players.PlayerAdded:Connect(function(player)
			-- Initialize with defaults - these will be overwritten when data loads
			self._playerUpgrades[player.UserId] = {
				sporeUpgradeLevel = 0, -- Legacy field for backwards compatibility
				area1SporeUpgradeLevel = 0,
				area2SporeUpgradeLevel = 0,
				-- Gem upgrades - default to 1 to match server expectation
				fastRunnerLevel = 1,
				pickUpRangeLevel = 1,
				fasterShroomsLevel = 1,
				shinySporeLevel = 1,
				gemHunterLevel = 1
			}

			-- Apply speed boost when character spawns
			local charConnection
			charConnection = player.CharacterAdded:Connect(function(character)
				task.wait(1) -- Wait for character to fully load
				self:_applySpeedBoost(player)
			end)

			-- Store connection for cleanup
			self._connections["CharacterAdded_" .. player.UserId] = charConnection
		end)

		self._connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
			self._playerUpgrades[player.UserId] = nil
		end)

		Logger:Info("ShopService initialized successfully")
	end
end

function ShopService:_setupRemoteEvents()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
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

	local remoteFunctions = shared:FindFirstChild("RemoteFunctions")
	if not remoteFunctions then
		remoteFunctions = Instance.new("Folder")
		remoteFunctions.Name = "RemoteFunctions"
		remoteFunctions.Parent = shared
	end

	local shopEvents = remoteEvents:FindFirstChild("ShopEvents")
	if not shopEvents then
		shopEvents = Instance.new("Folder")
		shopEvents.Name = "ShopEvents"
		shopEvents.Parent = remoteEvents
	end

	-- Purchase spore upgrade remote (Area1)
	local purchaseSporeUpgrade = shopEvents:FindFirstChild("PurchaseSporeUpgrade")
	if not purchaseSporeUpgrade then
		purchaseSporeUpgrade = Instance.new("RemoteEvent")
		purchaseSporeUpgrade.Name = "PurchaseSporeUpgrade"
		purchaseSporeUpgrade.Parent = shopEvents
	end

	-- Purchase Area2 spore upgrade remote
	local purchaseArea2SporeUpgrade = shopEvents:FindFirstChild("PurchaseArea2SporeUpgrade")
	if not purchaseArea2SporeUpgrade then
		purchaseArea2SporeUpgrade = Instance.new("RemoteEvent")
		purchaseArea2SporeUpgrade.Name = "PurchaseArea2SporeUpgrade"
		purchaseArea2SporeUpgrade.Parent = shopEvents
	end

	-- Purchase mushroom remote
	local purchaseMushroom = shopEvents:FindFirstChild("PurchaseMushroom")
	if not purchaseMushroom then
		purchaseMushroom = Instance.new("RemoteEvent")
		purchaseMushroom.Name = "PurchaseMushroom"
		purchaseMushroom.Parent = shopEvents
	end

	-- Purchase Area2 remote
	local purchaseArea2 = shopEvents:FindFirstChild("PurchaseArea2")
	if not purchaseArea2 then
		purchaseArea2 = Instance.new("RemoteEvent")
		purchaseArea2.Name = "PurchaseArea2"
		purchaseArea2.Parent = shopEvents
	end

	-- Purchase Area3 (Ascend) remote
	local purchaseArea3 = shopEvents:FindFirstChild("PurchaseArea3")
	if not purchaseArea3 then
		purchaseArea3 = Instance.new("RemoteEvent")
		purchaseArea3.Name = "PurchaseArea3"
		purchaseArea3.Parent = shopEvents
	end

	-- Area2 unlock animation remote (create early so client can connect)
	local area2UnlockAnimation = shopEvents:FindFirstChild("Area2UnlockAnimation")
	if not area2UnlockAnimation then
		area2UnlockAnimation = Instance.new("RemoteEvent")
		area2UnlockAnimation.Name = "Area2UnlockAnimation"
		area2UnlockAnimation.Parent = shopEvents
	end

	-- Area3 unlock animation remote (create early so client can connect)
	local area3UnlockAnimation = shopEvents:FindFirstChild("Area3UnlockAnimation")
	if not area3UnlockAnimation then
		area3UnlockAnimation = Instance.new("RemoteEvent")
		area3UnlockAnimation.Name = "Area3UnlockAnimation"
		area3UnlockAnimation.Parent = shopEvents
	end

	-- Shop data updated remote (to refresh client UI)
	local shopDataUpdated = shopEvents:FindFirstChild("ShopDataUpdated")
	if not shopDataUpdated then
		shopDataUpdated = Instance.new("RemoteEvent")
		shopDataUpdated.Name = "ShopDataUpdated"
		shopDataUpdated.Parent = shopEvents
	end

	-- Tutorial success tracking remotes
	local tutorialPurchaseSuccess = shopEvents:FindFirstChild("TutorialPurchaseSuccess")
	if not tutorialPurchaseSuccess then
		tutorialPurchaseSuccess = Instance.new("RemoteEvent")
		tutorialPurchaseSuccess.Name = "TutorialPurchaseSuccess"
		tutorialPurchaseSuccess.Parent = shopEvents
	end

	-- Sync shop data remote (for early loading)
	local syncShopData = shopEvents:FindFirstChild("SyncShopData")
	if not syncShopData then
		syncShopData = Instance.new("RemoteEvent")
		syncShopData.Name = "SyncShopData"
		syncShopData.Parent = shopEvents
	end

	-- Separate mushroom shop remotes
	local purchaseArea1Mushroom = shopEvents:FindFirstChild("PurchaseArea1Mushroom")
	if not purchaseArea1Mushroom then
		purchaseArea1Mushroom = Instance.new("RemoteEvent")
		purchaseArea1Mushroom.Name = "PurchaseArea1Mushroom"
		purchaseArea1Mushroom.Parent = shopEvents
	end

	local purchaseArea2Mushroom = shopEvents:FindFirstChild("PurchaseArea2Mushroom")
	if not purchaseArea2Mushroom then
		purchaseArea2Mushroom = Instance.new("RemoteEvent")
		purchaseArea2Mushroom.Name = "PurchaseArea2Mushroom"
		purchaseArea2Mushroom.Parent = shopEvents
	end

	local purchaseArea3Mushroom = shopEvents:FindFirstChild("PurchaseArea3Mushroom")
	if not purchaseArea3Mushroom then
		purchaseArea3Mushroom = Instance.new("RemoteEvent")
		purchaseArea3Mushroom.Name = "PurchaseArea3Mushroom"
		purchaseArea3Mushroom.Parent = shopEvents
	end

	-- Create GemShopRemotes folder for upgrade-specific events
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if not gemShopRemotes then
		gemShopRemotes = Instance.new("Folder")
		gemShopRemotes.Name = "GemShopRemotes"
		gemShopRemotes.Parent = ReplicatedStorage
	else
	end

	-- Individual upgrade remotes (following old system pattern)
	local purchaseFastRunner = gemShopRemotes:FindFirstChild("PurchaseFastRunner")
	if not purchaseFastRunner then
		purchaseFastRunner = Instance.new("RemoteEvent")
		purchaseFastRunner.Name = "PurchaseFastRunner"
		purchaseFastRunner.Parent = gemShopRemotes
	end

	local syncFastRunner = gemShopRemotes:FindFirstChild("SyncFastRunner")
	if not syncFastRunner then
		syncFastRunner = Instance.new("RemoteEvent")
		syncFastRunner.Name = "SyncFastRunner"
		syncFastRunner.Parent = gemShopRemotes
	end

	local fastRunnerConfirm = gemShopRemotes:FindFirstChild("FastRunnerConfirm")
	if not fastRunnerConfirm then
		fastRunnerConfirm = Instance.new("RemoteEvent")
		fastRunnerConfirm.Name = "FastRunnerConfirm"
		fastRunnerConfirm.Parent = gemShopRemotes
	end

	-- PickUpRange upgrade remotes
	local purchasePickUpRange = gemShopRemotes:FindFirstChild("PurchasePickUpRange")
	if not purchasePickUpRange then
		purchasePickUpRange = Instance.new("RemoteEvent")
		purchasePickUpRange.Name = "PurchasePickUpRange"
		purchasePickUpRange.Parent = gemShopRemotes
	end

	local syncPickUpRange = gemShopRemotes:FindFirstChild("SyncPickUpRange")
	if not syncPickUpRange then
		syncPickUpRange = Instance.new("RemoteEvent")
		syncPickUpRange.Name = "SyncPickUpRange"
		syncPickUpRange.Parent = gemShopRemotes
	end

	local pickUpRangeConfirm = gemShopRemotes:FindFirstChild("PickUpRangeConfirm")
	if not pickUpRangeConfirm then
		pickUpRangeConfirm = Instance.new("RemoteEvent")
		pickUpRangeConfirm.Name = "PickUpRangeConfirm"
		pickUpRangeConfirm.Parent = gemShopRemotes
	end

	-- FasterShrooms upgrade remotes
	local purchaseFasterShrooms = gemShopRemotes:FindFirstChild("PurchaseFasterShrooms")
	if not purchaseFasterShrooms then
		purchaseFasterShrooms = Instance.new("RemoteEvent")
		purchaseFasterShrooms.Name = "PurchaseFasterShrooms"
		purchaseFasterShrooms.Parent = gemShopRemotes
	end

	local syncFasterShrooms = gemShopRemotes:FindFirstChild("SyncFasterShrooms")
	if not syncFasterShrooms then
		syncFasterShrooms = Instance.new("RemoteEvent")
		syncFasterShrooms.Name = "SyncFasterShrooms"
		syncFasterShrooms.Parent = gemShopRemotes
	end

	local fasterShroomsConfirm = gemShopRemotes:FindFirstChild("FasterShroomsConfirm")
	if not fasterShroomsConfirm then
		fasterShroomsConfirm = Instance.new("RemoteEvent")
		fasterShroomsConfirm.Name = "FasterShroomsConfirm"
		fasterShroomsConfirm.Parent = gemShopRemotes
	end

	-- ShinySpore upgrade events
	local purchaseShinySpore = gemShopRemotes:FindFirstChild("PurchaseShinySpore")
	if not purchaseShinySpore then
		purchaseShinySpore = Instance.new("RemoteEvent")
		purchaseShinySpore.Name = "PurchaseShinySpore"
		purchaseShinySpore.Parent = gemShopRemotes
	else
	end

	local syncShinySpore = gemShopRemotes:FindFirstChild("SyncShinySpore")
	if not syncShinySpore then
		syncShinySpore = Instance.new("RemoteEvent")
		syncShinySpore.Name = "SyncShinySpore"
		syncShinySpore.Parent = gemShopRemotes
	end

	local shinySporeConfirm = gemShopRemotes:FindFirstChild("ShinySporeConfirm")
	if not shinySporeConfirm then
		shinySporeConfirm = Instance.new("RemoteEvent")
		shinySporeConfirm.Name = "ShinySporeConfirm"
		shinySporeConfirm.Parent = gemShopRemotes
	end

	-- GemHunter upgrade events
	local purchaseGemHunter = gemShopRemotes:FindFirstChild("PurchaseGemHunter")
	if not purchaseGemHunter then
		purchaseGemHunter = Instance.new("RemoteEvent")
		purchaseGemHunter.Name = "PurchaseGemHunter"
		purchaseGemHunter.Parent = gemShopRemotes
	end

	local syncGemHunter = gemShopRemotes:FindFirstChild("SyncGemHunter")
	if not syncGemHunter then
		syncGemHunter = Instance.new("RemoteEvent")
		syncGemHunter.Name = "SyncGemHunter"
		syncGemHunter.Parent = gemShopRemotes
	end

	local gemHunterConfirm = gemShopRemotes:FindFirstChild("GemHunterConfirm")
	if not gemHunterConfirm then
		gemHunterConfirm = Instance.new("RemoteEvent")
		gemHunterConfirm.Name = "GemHunterConfirm"
		gemHunterConfirm.Parent = gemShopRemotes
	end

	-- Connect event handlers
	self._connections.PurchaseSporeUpgrade = purchaseSporeUpgrade.OnServerEvent:Connect(function(player)
		self:_handleSporeUpgradePurchase(player, "Area1")
	end)

	self._connections.PurchaseArea2SporeUpgrade = purchaseArea2SporeUpgrade.OnServerEvent:Connect(function(player)
		self:_handleSporeUpgradePurchase(player, "Area2")
	end)

	self._connections.PurchaseMushroom = purchaseMushroom.OnServerEvent:Connect(function(player, area)
		self:_handleMushroomPurchase(player, area)
	end)

	self._connections.PurchaseArea2 = purchaseArea2.OnServerEvent:Connect(function(player)
		self:_handleArea2Purchase(player)
	end)

	self._connections.PurchaseArea3 = purchaseArea3.OnServerEvent:Connect(function(player)
		self:_handleArea3Purchase(player)
	end)

	-- Connect shop data sync handler
	self._connections.SyncShopData = syncShopData.OnServerEvent:Connect(function(player)
		self:_syncShopData(player)
	end)

	-- Store tutorial remote reference
	self._tutorialPurchaseSuccess = tutorialPurchaseSuccess

	-- Connect separate mushroom shop handlers (if remotes exist)
	if purchaseArea1Mushroom then
		self._connections.PurchaseArea1Mushroom = purchaseArea1Mushroom.OnServerEvent:Connect(function(player)
			self:_handleArea1MushroomPurchase(player)
		end)
	end

	if purchaseArea2Mushroom then
		self._connections.PurchaseArea2Mushroom = purchaseArea2Mushroom.OnServerEvent:Connect(function(player)
			self:_handleArea2MushroomPurchase(player)
		end)
	end

	if purchaseArea3Mushroom then
		self._connections.PurchaseArea3Mushroom = purchaseArea3Mushroom.OnServerEvent:Connect(function(player)
			self:_handleArea3MushroomPurchase(player)
		end)
	end

	-- Connect gem shop upgrade handlers
	self._connections.PurchaseFastRunner = purchaseFastRunner.OnServerEvent:Connect(function(player, clientCost, clientLevel)
		self:_handleFastRunnerPurchase(player, clientCost, clientLevel)
	end)

	self._connections.SyncFastRunner = syncFastRunner.OnServerEvent:Connect(function(player)
		self:_syncFastRunnerData(player)
	end)

	-- Connect PickUpRange upgrade handlers
	self._connections.PurchasePickUpRange = purchasePickUpRange.OnServerEvent:Connect(function(player, clientCost, clientLevel)
		self:_handlePickUpRangePurchase(player, clientCost, clientLevel)
	end)

	self._connections.SyncPickUpRange = syncPickUpRange.OnServerEvent:Connect(function(player)
		self:_syncPickUpRangeData(player)
	end)

	-- Connect FasterShrooms upgrade handlers
	self._connections.PurchaseFasterShrooms = purchaseFasterShrooms.OnServerEvent:Connect(function(player, clientCost, clientLevel)
		self:_handleFasterShroomsPurchase(player, clientCost, clientLevel)
	end)

	self._connections.SyncFasterShrooms = syncFasterShrooms.OnServerEvent:Connect(function(player)
		self:_syncFasterShroomsData(player)
	end)

	-- Connect ShinySpore upgrade handlers
	self._connections.PurchaseShinySpore = purchaseShinySpore.OnServerEvent:Connect(function(player, clientCost, clientLevel)
		self:_handleShinySporePurchase(player, clientCost, clientLevel)
	end)

	self._connections.SyncShinySpore = syncShinySpore.OnServerEvent:Connect(function(player)
		self:_syncShinySporeData(player)
	end)

	-- Connect GemHunter upgrade handlers
	self._connections.PurchaseGemHunter = purchaseGemHunter.OnServerEvent:Connect(function(player, clientCost, clientLevel)
		self:_handleGemHunterPurchase(player, clientCost, clientLevel)
	end)

	self._connections.SyncGemHunter = syncGemHunter.OnServerEvent:Connect(function(player)
		self:_syncGemHunterData(player)
	end)

	-- GetGemShopData remote function is created by Main.lua, just connect handler
	local getGemShopData = remoteFunctions:WaitForChild("GetGemShopData", 10)
	if getGemShopData then
		-- Connect gem shop data handler (this will override Main.lua's handler)
		getGemShopData.OnServerInvoke = function(player)
			return self:GetGemShopDataForPlayer(player)
		end
		Logger:Debug("GetGemShopData handler connected")
	else
		Logger:Error("GetGemShopData remote function not found - was it created by Main.lua?")
	end

	Logger:Debug("Shop remote events set up")
end

function ShopService:SetServices(dataService, mushroomService, gamepassService, notificationService, robloxAnalyticsService)
	self._dataService = dataService
	self._mushroomService = mushroomService
	self._gamepassService = gamepassService
	self._notificationService = notificationService
	self._robloxAnalyticsService = robloxAnalyticsService

	if dataService and dataService.PlayerDataLoaded then
		self._connections.PlayerDataLoaded = dataService.PlayerDataLoaded:Connect(function(player, playerData, isNewPlayer)
			-- Debug: Log the raw player data
			Logger:Info(string.format("PlayerDataLoaded for %s, isNew: %s", player.Name, tostring(isNewPlayer)))
			Logger:Info(string.format("Raw SporeUpgradeLevel in data: %s", tostring(playerData.SporeUpgradeLevel)))

			-- Initialize or load player upgrade data
			local upgradeLevel = playerData.SporeUpgradeLevel or 0
			local fastRunnerLevel = playerData.FastRunnerLevel or 1
			local pickUpRangeLevel = playerData.PickUpRangeLevel or 1
			local fasterShroomsLevel = playerData.FasterShroomsLevel or 1
			local shinySporeLevel = playerData.ShinySporeLevel or 1
			local gemHunterLevel = playerData.GemHunterLevel or 1


			-- Load area-specific spore upgrade levels
			local area1SporeUpgradeLevel = playerData.Area1SporeUpgradeLevel or 0
			local area2SporeUpgradeLevel = playerData.Area2SporeUpgradeLevel or 0

			self._playerUpgrades[player.UserId] = {
				sporeUpgradeLevel = upgradeLevel, -- Legacy field for backwards compatibility
				area1SporeUpgradeLevel = area1SporeUpgradeLevel,
				area2SporeUpgradeLevel = area2SporeUpgradeLevel,
				fastRunnerLevel = fastRunnerLevel,
				pickUpRangeLevel = pickUpRangeLevel,
				fasterShroomsLevel = fasterShroomsLevel,
				shinySporeLevel = shinySporeLevel,
				gemHunterLevel = gemHunterLevel
			}


			-- Ensure upgrade fields exist in player data
			if playerData.SporeUpgradeLevel == nil then
				Logger:Warn(string.format("SporeUpgradeLevel missing for %s, initializing to 0", player.Name))
				self._dataService:UpdatePlayerData(player, function(data)
					data.SporeUpgradeLevel = 0
				end)
			end


			if playerData.FastRunnerLevel == nil then
				Logger:Warn(string.format("FastRunnerLevel missing for %s, initializing to 1", player.Name))
				self._dataService:UpdatePlayerData(player, function(data)
					data.FastRunnerLevel = 1
				end)
			end

			if playerData.PickUpRangeLevel == nil then
				Logger:Warn(string.format("PickUpRangeLevel missing for %s, initializing to 1", player.Name))
				self._dataService:UpdatePlayerData(player, function(data)
					data.PickUpRangeLevel = 1
				end)
				-- Update in-memory data and sync immediately
				self._playerUpgrades[player.UserId].pickUpRangeLevel = 1
				self:_syncPickUpRangeData(player)
			end

			if playerData.FasterShroomsLevel == nil then
				Logger:Warn(string.format("FasterShroomsLevel missing for %s, initializing to 1", player.Name))
				self._dataService:UpdatePlayerData(player, function(data)
					data.FasterShroomsLevel = 1
				end)
				-- Update in-memory data and sync immediately
				self._playerUpgrades[player.UserId].fasterShroomsLevel = 1
				self:_syncFasterShroomsData(player)
			end

			if playerData.ShinySporeLevel == nil then
				Logger:Warn(string.format("ShinySporeLevel missing for %s, initializing to 1", player.Name))
				self._dataService:UpdatePlayerData(player, function(data)
					data.ShinySporeLevel = 1
				end)
				-- Update in-memory data and sync immediately
				self._playerUpgrades[player.UserId].shinySporeLevel = 1
				self:_syncShinySporeData(player)
			end

			if playerData.GemHunterLevel == nil then
				Logger:Warn(string.format("GemHunterLevel missing for %s, initializing to 1", player.Name))
				self._dataService:UpdatePlayerData(player, function(data)
					data.GemHunterLevel = 1
				end)
				-- Update in-memory data and sync immediately
				self._playerUpgrades[player.UserId].gemHunterLevel = 1
				self:_syncGemHunterData(player)
			end

			-- Apply speed boost when player loads
			if fastRunnerLevel > 1 then  -- Only apply boost if above base level
				task.spawn(function()
					-- Wait for character to be ready
					if player.Character then
						task.wait(1)
						self:_applySpeedBoost(player)
					else
						-- Wait for character spawn
						local connection
						connection = player.CharacterAdded:Connect(function()
							connection:Disconnect()
							task.wait(1)
							self:_applySpeedBoost(player)
						end)
					end
				end)
			end

			-- Sync upgrade data with client after a short delay to ensure client is ready
			task.spawn(function()
				task.wait(0.5) -- Small delay to ensure client services are initialized
				Logger:Info(string.format("AUTO-SYNCING all shop data for %s after data load", player.Name))
				self:_syncShopData(player)
				self:_syncFastRunnerData(player)
				self:_syncPickUpRangeData(player)
				self:_syncFasterShroomsData(player)
				self:_syncShinySporeData(player)
				self:_syncGemHunterData(player)
				Logger:Info(string.format("AUTO-SYNC complete for %s", player.Name))
			end)

			Logger:Info(string.format("ShopService: Loaded spore upgrade level %d for player %s", upgradeLevel, player.Name))
		end)
	end

	Logger:Debug("ShopService linked with DataService and MushroomService")
end

function ShopService:_handleSporeUpgradePurchase(player, area)
	area = area or "Area1" -- Default to Area1 for backwards compatibility
	
	if not self._dataService then
		Logger:Error("DataService not available for spore upgrade purchase")
		return
	end

	-- Check if Area2 is unlocked for Area2 purchases
	if area == "Area2" then
		local isArea2Unlocked = self._dataService:IsArea2Unlocked(player)
		if not isArea2Unlocked then
			Logger:Info(string.format("Player %s tried to purchase Area2 spore upgrade but Area2 is not unlocked", player.Name))
			return
		end
	end

	-- Get current upgrade level for the specific area
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("No upgrade data found for player %s", player.Name))
		return
	end

	local currentLevel
	if area == "Area2" then
		currentLevel = playerUpgrades.area2SporeUpgradeLevel or 0
		Logger:Debug(string.format("DEBUG: %s current Area2 spore level: %d", player.Name, currentLevel))
	else
		currentLevel = playerUpgrades.area1SporeUpgradeLevel or playerUpgrades.sporeUpgradeLevel or 0
		Logger:Debug(string.format("DEBUG: %s current Area1 spore level: %d (area1: %d, legacy: %d)", 
			player.Name, currentLevel, playerUpgrades.area1SporeUpgradeLevel or 0, playerUpgrades.sporeUpgradeLevel or 0))
	end

	-- Check spore upgrade level caps
	if area == "Area2" then
		Logger:Debug(string.format("DEBUG: Area2 spore upgrade - Player %s currentLevel: %d, maxLevel: %d", 
			player.Name, currentLevel, SHOP_CONFIG.SporeUpgradeCaps.area2MaxLevel))
		if currentLevel >= SHOP_CONFIG.SporeUpgradeCaps.area2MaxLevel then
			Logger:Info(string.format("Player %s has reached Area2 spore upgrade level cap (%d/%d)", 
				player.Name, currentLevel, SHOP_CONFIG.SporeUpgradeCaps.area2MaxLevel))
			return
		end
	else
		Logger:Debug(string.format("DEBUG: Area1 spore upgrade - Player %s currentLevel: %d, maxLevel: %d", 
			player.Name, currentLevel, SHOP_CONFIG.SporeUpgradeCaps.area1MaxLevel))
		if currentLevel >= SHOP_CONFIG.SporeUpgradeCaps.area1MaxLevel then
			Logger:Info(string.format("Player %s has reached Area1 spore upgrade level cap (%d/%d)", 
				player.Name, currentLevel, SHOP_CONFIG.SporeUpgradeCaps.area1MaxLevel))
			return
		end
	end

	local upgradeCost = self:_calculateSporeUpgradeCost(currentLevel)

	-- Check if player has enough spores
	local currentSpores = self._dataService:GetSpores(player)
	if currentSpores < upgradeCost then
		Logger:Info(string.format("Player %s cannot afford %s spore upgrade (need %.2f, have %.2f)", 
			player.Name, area, upgradeCost, currentSpores))
		
		Logger:Info("=== INSUFFICIENT FUNDS DETECTED - Playing fail sound ===")
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
		return
	end

	-- Spend spores and increase upgrade level
	if self._dataService:SpendSpores(player, upgradeCost) then
		-- Update upgrade level for the specific area
		if area == "Area2" then
			playerUpgrades.area2SporeUpgradeLevel = currentLevel + 1
		else
			playerUpgrades.area1SporeUpgradeLevel = currentLevel + 1
			-- Keep legacy field updated for backwards compatibility
			playerUpgrades.sporeUpgradeLevel = playerUpgrades.area1SporeUpgradeLevel
		end

		-- Save upgrade level to player data immediately
		local updateSuccess = self._dataService:UpdatePlayerData(player, function(data)
			if area == "Area2" then
				data.Area2SporeUpgradeLevel = playerUpgrades.area2SporeUpgradeLevel
				Logger:Info(string.format("Saving Area2SporeUpgradeLevel = %d for player %s", playerUpgrades.area2SporeUpgradeLevel, player.Name))
			else
				data.Area1SporeUpgradeLevel = playerUpgrades.area1SporeUpgradeLevel
				data.SporeUpgradeLevel = playerUpgrades.area1SporeUpgradeLevel -- Keep legacy field updated
				Logger:Info(string.format("Saving Area1SporeUpgradeLevel = %d for player %s", playerUpgrades.area1SporeUpgradeLevel, player.Name))
			end
		end)

		if not updateSuccess then
			Logger:Error(string.format("Failed to update player data for %s %s upgrade", player.Name, area))
			return
		end

		-- Calculate new bonus percentage (area-specific)
		local newBonus = self:GetSporeMultiplier(player, area)
		local newLevel = area == "Area2" and playerUpgrades.area2SporeUpgradeLevel or playerUpgrades.area1SporeUpgradeLevel
		
		Logger:Info(string.format("Player %s purchased %s spore upgrade level %d (%.1f%% bonus) for %.2f spores", 
			player.Name, area, newLevel, (newBonus - 1) * 100, upgradeCost))

		-- Track Roblox Analytics
		if self._robloxAnalyticsService then
			local upgradeType = area == "Area1" and "area1SporeUpgrade" or "area2SporeUpgrade"
			self._robloxAnalyticsService:TrackUpgradeCompleted(player, "Spore", upgradeType, newLevel, upgradeCost)
			
			-- Track first spore upgrade in onboarding
			if newLevel == 1 then
				self._robloxAnalyticsService:TrackFirstSporeUpgrade(player)
			end
			
			-- Track spore upgrade milestones
			self._robloxAnalyticsService:TrackSporeUpgradeMilestone(player, area, newLevel)
		end

		-- Play purchase success sound
		self:_playPurchaseSuccessSound(player)

		-- Fire tutorial success event for spore upgrades
		if self._tutorialPurchaseSuccess then
			self._tutorialPurchaseSuccess:FireClient(player, "sporeUpgrade", area)
		end

		-- Sync updated shop data to client immediately
		self:_syncShopData(player)
	else
		Logger:Error(string.format("Failed to spend spores for player %s %s upgrade", player.Name, area))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
	end
end

function ShopService:_handleMushroomPurchase(player, area)
	area = area or "Area1" -- Default to Area1

	if not self._dataService or not self._mushroomService then
		Logger:Error("Required services not available for mushroom purchase")
		return
	end

	-- Get player's plot
	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		Logger:Error("PlayerPlots not found")
		return
	end

	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		Logger:Error(string.format("Plot not found for player %s", player.Name))
		return
	end

	-- Check if Area2 purchase is valid
	if area == "Area2" then
		local isArea2Unlocked = self._dataService:IsArea2Unlocked(player)
		Logger:Debug(string.format("Area2 unlock check for %s: %s", player.Name, tostring(isArea2Unlocked)))

		if not isArea2Unlocked then
			Logger:Warn(string.format("Player %s tried to purchase Area2 mushroom without Area2 unlocked (according to data)", player.Name))

			-- Debug: Let's check the raw data
			local playerData = self._dataService:GetPlayerData(player)
			if playerData then
				Logger:Debug(string.format("Raw Area2Unlocked value for %s: %s", player.Name, tostring(playerData.Area2Unlocked)))
			else
				Logger:Error(string.format("No player data found for %s", player.Name))
			end
			return
		end
	elseif area == "Area3" then
		local isArea3Unlocked = (self._dataService.IsArea3Unlocked and self._dataService:IsArea3Unlocked(player)) or false
		Logger:Debug(string.format("Area3 unlock check for %s: %s", player.Name, tostring(isArea3Unlocked)))

		if not isArea3Unlocked then
			Logger:Warn(string.format("Player %s tried to purchase Area3 mushroom without Area3 unlocked", player.Name))
			return
		end
	end

	-- Get current mushroom count for the area
	local currentMushroomCount
	if area == "Area2" then
		currentMushroomCount = self._dataService:GetArea2MushroomCount(player)
	elseif area == "Area3" then
		currentMushroomCount = (self._dataService.GetArea3MushroomCount and self._dataService:GetArea3MushroomCount(player)) or 0
	else
		currentMushroomCount = self._dataService:GetArea1MushroomCount(player)
	end

	-- Check area caps (50 mushrooms per area)
	if currentMushroomCount >= 50 then
		Logger:Info(string.format("Player %s has reached mushroom cap for %s (%d/50)", 
			player.Name, area, currentMushroomCount))
		return
	end

	-- Use separate shop levels for cost calculation
	local purchaseCost
	if area == "Area2" then
		local currentLevel = self._dataService:GetArea2MushroomShopLevel(player)

		-- Check level cap
		if currentLevel >= SHOP_CONFIG.Area2MushroomShop.maxLevel then
			Logger:Info(string.format("Player %s has reached Area2 mushroom shop level cap (%d/100)", 
				player.Name, currentLevel))
			return
		end

		purchaseCost = self:_calculateArea2MushroomShopCost(currentLevel)
	elseif area == "Area3" then
		local currentLevel = (self._dataService.GetArea3MushroomShopLevel and self._dataService:GetArea3MushroomShopLevel(player)) or 0

		-- Check level cap
		if currentLevel >= SHOP_CONFIG.Area3MushroomShop.maxLevel then
			Logger:Info(string.format("Player %s has reached Area3 mushroom shop level cap (%d/100)", 
				player.Name, currentLevel))
			return
		end

		purchaseCost = self:_calculateArea3MushroomShopCost(currentLevel)
	else
		local currentLevel = self._dataService:GetArea1MushroomShopLevel(player)

		-- Check level cap
		if currentLevel >= SHOP_CONFIG.Area1MushroomShop.maxLevel then
			Logger:Info(string.format("Player %s has reached Area1 mushroom shop level cap (%d/100)", 
				player.Name, currentLevel))
			return
		end

		purchaseCost = self:_calculateArea1MushroomShopCost(currentLevel)
	end

	-- Check if player has enough spores
	local currentSpores = self._dataService:GetSpores(player)
	if currentSpores < purchaseCost then
		Logger:Info(string.format("Player %s cannot afford %s mushroom (need %.2f, have %.2f)", 
			player.Name, area, purchaseCost, currentSpores))
		
		Logger:Info("=== INSUFFICIENT FUNDS DETECTED (MUSHROOM) - Playing fail sound ===")
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
		return
	end

	-- Spend spores and spawn mushroom
	if self._dataService:SpendSpores(player, purchaseCost) then
		-- Add a new mushroom in the specified area
		local success = self._mushroomService:AddMushroom(player, area)
		if success then
			-- Increment the appropriate shop level
			if area == "Area2" then
				self._dataService:IncrementArea2MushroomShopLevel(player)
			elseif area == "Area3" then
				if self._dataService.IncrementArea3MushroomShopLevel then
					self._dataService:IncrementArea3MushroomShopLevel(player)
				end
			else
				self._dataService:IncrementArea1MushroomShopLevel(player)
			end

			Logger:Info(string.format("Player %s purchased %s mushroom for %.2f spores", 
				player.Name, area, purchaseCost))

			-- Track Roblox Analytics
			if self._robloxAnalyticsService then
				local mushroomCount = area == "Area1" and (self._dataService:GetArea1MushroomCount(player) or 0) or 
									  area == "Area2" and (self._dataService:GetArea2MushroomCount(player) or 0) or
									  area == "Area3" and (self._dataService:GetArea3MushroomCount(player) or 0) or 0
				
				local upgradeType = area:lower() .. "Mushroom"
				self._robloxAnalyticsService:TrackUpgradeCompleted(player, "Mushroom", upgradeType, mushroomCount, purchaseCost)
				
				-- Track first mushroom purchase in onboarding
				if mushroomCount == 1 then
					self._robloxAnalyticsService:TrackFirstMushroomPurchase(player)
				end
				
				-- Track mushroom milestones
				self._robloxAnalyticsService:TrackMushroomMilestone(player, area, mushroomCount)
			end

			-- Play purchase success sound
			self:_playPurchaseSuccessSound(player)

			-- Fire tutorial success event for mushroom purchases
			if self._tutorialPurchaseSuccess then
				self._tutorialPurchaseSuccess:FireClient(player, "mushroom", area)
			end

			-- Sync updated shop data to client immediately with fresh data
			self:_syncShopData(player)
		else
			-- Refund if mushroom spawn failed
			self._dataService:AddSpores(player, purchaseCost)
			Logger:Error(string.format("Failed to add %s mushroom for player %s, refunded spores", area, player.Name))
		end
	else
		Logger:Error(string.format("Failed to spend spores for player %s %s mushroom purchase", player.Name, area))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
	end
end

function ShopService:_canPlayerAscend(player)
	-- Check if player has maxed both Area1 and Area2 spore upgrades and mushroom shop levels
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Debug(string.format("ASCEND DEBUG: No player upgrades found for %s", player.Name))
		return false
	end

	-- Check Area1 spore upgrades (max 100)
	local area1SporeLevel = playerUpgrades.area1SporeUpgradeLevel or 0
	Logger:Debug(string.format("ASCEND DEBUG: %s Area1 spore level: %d/%d", player.Name, area1SporeLevel, SHOP_CONFIG.SporeUpgradeCaps.area1MaxLevel))
	if area1SporeLevel < SHOP_CONFIG.SporeUpgradeCaps.area1MaxLevel then
		Logger:Debug(string.format("ASCEND DEBUG: %s failed Area1 spore requirement", player.Name))
		return false
	end

	-- Check Area2 spore upgrades (max 100)  
	local area2SporeLevel = playerUpgrades.area2SporeUpgradeLevel or 0
	Logger:Debug(string.format("ASCEND DEBUG: %s Area2 spore level: %d/%d", player.Name, area2SporeLevel, SHOP_CONFIG.SporeUpgradeCaps.area2MaxLevel))
	if area2SporeLevel < SHOP_CONFIG.SporeUpgradeCaps.area2MaxLevel then
		Logger:Debug(string.format("ASCEND DEBUG: %s failed Area2 spore requirement", player.Name))
		return false
	end

	-- Check Area1 mushroom shop level (max 49, since 50 mushrooms - 1 starting = 49 purchases)
	local area1MushroomLevel = self._dataService:GetArea1MushroomShopLevel(player)
	Logger:Debug(string.format("ASCEND DEBUG: %s Area1 mushroom level: %d/49", player.Name, area1MushroomLevel))
	if area1MushroomLevel < 49 then
		Logger:Debug(string.format("ASCEND DEBUG: %s failed Area1 mushroom requirement", player.Name))
		return false
	end

	-- Check Area2 mushroom shop level (max 50, since Area2 doesn't have a starting mushroom)
	local area2MushroomLevel = self._dataService:GetArea2MushroomShopLevel(player)
	Logger:Debug(string.format("ASCEND DEBUG: %s Area2 mushroom level: %d/50", player.Name, area2MushroomLevel))
	if area2MushroomLevel < 50 then
		Logger:Debug(string.format("ASCEND DEBUG: %s failed Area2 mushroom requirement", player.Name))
		return false
	end

	Logger:Info(string.format("ASCEND DEBUG: %s meets ALL requirements for ascension!", player.Name))
	return true
end

function ShopService:_handleArea3Purchase(player)
	Logger:Info(string.format("ASCEND DEBUG: Area3 purchase handler called for %s", player.Name))
	
	if not self._dataService then
		Logger:Error("DataService not available for Area3 purchase")
		return
	end

	-- Check if Area3 is already unlocked
	if (self._dataService.IsArea3Unlocked and self._dataService:IsArea3Unlocked(player)) then
		Logger:Info(string.format("Player %s already has Area3 unlocked", player.Name))
		return
	end

	-- Debug player upgrades data
	local playerUpgrades = self._playerUpgrades[player.UserId]
	Logger:Info(string.format("ASCEND DEBUG: Player upgrades for %s: %s", player.Name, tostring(playerUpgrades ~= nil)))
	if playerUpgrades then
		Logger:Info(string.format("ASCEND DEBUG: %s upgrade levels - Area1Spore: %d, Area2Spore: %d", 
			player.Name, playerUpgrades.area1SporeUpgradeLevel or 0, playerUpgrades.area2SporeUpgradeLevel or 0))
	end

	-- Check if player can ascend (has max levels in both areas)
	Logger:Info(string.format("ASCEND DEBUG: Checking ascend requirements for %s", player.Name))
	
	-- Print detailed requirements for debugging
	local requirementsStatus = self:GetAscendRequirements(player)
	Logger:Info(string.format("ASCEND REQUIREMENTS:\n%s", requirementsStatus))
	
	if not self:_canPlayerAscend(player) then
		Logger:Info(string.format("Player %s cannot ascend - requirements not met", player.Name))
		
		-- Track Roblox Analytics for failed ascension attempt
		if self._robloxAnalyticsService then
			-- Could track this as a separate funnel step or custom event
			Logger:Info(string.format("Player %s failed ascension requirements", player.Name))
		end
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
		return
	end
	Logger:Info(string.format("ASCEND DEBUG: %s passed all requirements, proceeding with ascension", player.Name))

	-- Ascend is free, just unlock Area3
	if self._dataService.UnlockArea3 then
		if self._dataService:UnlockArea3(player) then
			Logger:Info(string.format("Player %s ascended to Area3!", player.Name))

			-- Track Roblox Analytics
			if self._robloxAnalyticsService then
				self._robloxAnalyticsService:TrackArea3Unlock(player)
				self._robloxAnalyticsService:TrackGameProgressionMilestone(player, "area3_unlocked")
			end

			-- Play purchase success sound
			self:_playPurchaseSuccessSound(player)

			-- Trigger Area3 unlock animation on client first
			self:_triggerArea3UnlockAnimation(player)

			-- Wait for white screen to appear before removing walls
			task.spawn(function()
				task.wait(0.5) -- Delay walls disappearing until after white screen
				self:_removeArea3Walls(player)
			end)

			-- Sync updated shop data to client
			self:_syncShopData(player)
		else
			Logger:Error(string.format("Failed to unlock Area3 for player %s", player.Name))
			
			-- Play purchase fail sound
			self:_playPurchaseFailSound(player)
		end
	else
		Logger:Error("DataService does not support Area3 unlocking yet")
		
		-- Play purchase fail sound
		self:_playPurchaseFailSound(player)
	end
end

function ShopService:_handleArea2Purchase(player)
	if not self._dataService then
		Logger:Error("DataService not available for Area2 purchase")
		return
	end

	-- Check if Area2 is already unlocked
	if self._dataService:IsArea2Unlocked(player) then
		Logger:Info(string.format("Player %s already has Area2 unlocked", player.Name))
		return
	end

	-- Check if player has enough spores (1 million)
	local area2Cost = 1000000
	local currentSpores = self._dataService:GetSpores(player)
	if currentSpores < area2Cost then
		Logger:Info(string.format("Player %s cannot afford Area2 (need %d, have %.2f)", 
			player.Name, area2Cost, currentSpores))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
		return
	end

	-- Spend spores and unlock Area2
	if self._dataService:SpendSpores(player, area2Cost) then
		-- Unlock Area2 in data
		if self._dataService:UnlockArea2(player) then
			Logger:Info(string.format("Player %s purchased Area2 for %d spores", player.Name, area2Cost))

			-- Track Roblox Analytics
			if self._robloxAnalyticsService then
				self._robloxAnalyticsService:TrackArea2Unlock(player)
				self._robloxAnalyticsService:TrackGameProgressionMilestone(player, "area2_unlocked")
			end

			-- Play purchase success sound
			self:_playPurchaseSuccessSound(player)

			-- Trigger Area2 unlock animation on client first
			self:_triggerArea2UnlockAnimation(player)

			-- Wait for white screen to appear before removing walls
			task.spawn(function()
				task.wait(0.5) -- Delay walls disappearing until after white screen
				self:_removeArea2Walls(player)
			end)

			-- Sync updated shop data to client
			self:_syncShopData(player)
		else
			-- Refund if unlock failed
			self._dataService:AddSpores(player, area2Cost)
			Logger:Error(string.format("Failed to unlock Area2 for player %s, refunded spores", player.Name))
		end
	else
		Logger:Error(string.format("Failed to spend spores for player %s Area2 purchase", player.Name))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
	end
end

function ShopService:_removeArea2Walls(player)
	-- Get player's plot
	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		Logger:Error("PlayerPlots not found for wall removal")
		return
	end

	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		Logger:Error(string.format("Plot not found for player %s for wall removal", player.Name))
		return
	end

	local area2 = playerPlot:FindFirstChild("Area2")
	if not area2 then
		Logger:Error(string.format("Area2 not found in plot for player %s", player.Name))
		return
	end

	-- Remove walls (Wall1, Wall2, Wall3, Wall4) and PurchaseWall
	local wallsRemoved = 0

	-- Remove the numbered walls
	for i = 1, 4 do
		local wall = area2:FindFirstChild("Wall" .. i)
		if wall then
			wall:Destroy()
			wallsRemoved = wallsRemoved + 1
			Logger:Debug(string.format("Removed Wall%d from %s's Area2", i, player.Name))
		end
	end

	-- Remove the PurchaseWall
	local purchaseWall = area2:FindFirstChild("PurchaseWall")
	if purchaseWall then
		purchaseWall:Destroy()
		wallsRemoved = wallsRemoved + 1
		Logger:Debug(string.format("Removed PurchaseWall from %s's Area2", player.Name))
	end

	Logger:Info(string.format("Removed %d walls (including PurchaseWall) from %s's Area2", wallsRemoved, player.Name))
end

function ShopService:_removeArea3Walls(player)
	-- Get player's plot
	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		Logger:Error("PlayerPlots not found for Area3 wall removal")
		return
	end

	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		Logger:Error(string.format("Plot not found for player %s for Area3 wall removal", player.Name))
		return
	end

	local area3 = playerPlot:FindFirstChild("Area3")
	if not area3 then
		Logger:Error(string.format("Area3 not found in plot for player %s", player.Name))
		return
	end

	-- Remove walls (Wall1, Wall2, Wall3, Wall4) and PurchaseWall
	local wallsRemoved = 0

	-- Remove the numbered walls
	for i = 1, 4 do
		local wall = area3:FindFirstChild("Wall" .. i)
		if wall then
			wall:Destroy()
			wallsRemoved = wallsRemoved + 1
			Logger:Debug(string.format("Removed Wall%d from %s's Area3", i, player.Name))
		end
	end

	-- Remove the PurchaseWall
	local purchaseWall = area3:FindFirstChild("PurchaseWall")
	if purchaseWall then
		purchaseWall:Destroy()
		wallsRemoved = wallsRemoved + 1
		Logger:Debug(string.format("Removed PurchaseWall from %s's Area3", player.Name))
	end

	Logger:Info(string.format("Removed %d walls (including PurchaseWall) from %s's Area3", wallsRemoved, player.Name))
end

function ShopService:_triggerArea2UnlockAnimation(player)
	-- Find the Area2 unlock animation remote event (created during initialization)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if shared then
		local remoteEvents = shared:FindFirstChild("RemoteEvents")
		if remoteEvents then
			local shopEvents = remoteEvents:FindFirstChild("ShopEvents")
			if shopEvents then
				local area2UnlockAnimation = shopEvents:FindFirstChild("Area2UnlockAnimation")
				if area2UnlockAnimation then
					-- Trigger the animation on the client
					area2UnlockAnimation:FireClient(player)
					Logger:Info(string.format("Triggered Area2 unlock animation for %s", player.Name))
				else
					Logger:Error("Area2UnlockAnimation remote event not found when trying to trigger animation")
				end
			end
		end
	end
end

function ShopService:_triggerArea3UnlockAnimation(player)
	-- Find the Area3 unlock animation remote event (created during initialization)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if shared then
		local remoteEvents = shared:FindFirstChild("RemoteEvents")
		if remoteEvents then
			local shopEvents = remoteEvents:FindFirstChild("ShopEvents")
			if shopEvents then
				local area3UnlockAnimation = shopEvents:FindFirstChild("Area3UnlockAnimation")
				if area3UnlockAnimation then
					-- Trigger the animation on the client
					area3UnlockAnimation:FireClient(player)
					Logger:Info(string.format("Triggered Area3 unlock animation for %s", player.Name))
				else
					Logger:Error("Area3UnlockAnimation remote event not found when trying to trigger animation")
				end
			end
		end
	end
end

function ShopService:_handleArea1MushroomPurchase(player)
	if not self._dataService or not self._mushroomService then
		Logger:Error("Required services not available for Area1 mushroom purchase")
		return
	end

	-- Get current shop level for Area1
	local currentLevel = self._dataService:GetArea1MushroomShopLevel(player)

	-- Check level cap
	Logger:Debug(string.format("MUSHROOM PURCHASE DEBUG: Player %s attempting Area1 mushroom purchase. Current level: %d, Max level: %d", 
		player.Name, currentLevel, SHOP_CONFIG.Area1MushroomShop.maxLevel))
	if currentLevel >= SHOP_CONFIG.Area1MushroomShop.maxLevel then
		Logger:Info(string.format("Player %s has reached Area1 mushroom shop level cap (%d/%d)", 
			player.Name, currentLevel, SHOP_CONFIG.Area1MushroomShop.maxLevel))
		return
	end

	local purchaseCost = self:_calculateArea1MushroomShopCost(currentLevel)

	-- Check if player has enough spores
	local currentSpores = self._dataService:GetSpores(player)
	if currentSpores < purchaseCost then
		Logger:Info(string.format("Player %s cannot afford Area1 mushroom (need %.2f, have %.2f)", 
			player.Name, purchaseCost, currentSpores))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
		return
	end

	-- Check mushroom count limit (50 per area)
	local currentMushroomCount = self._dataService:GetArea1MushroomCount(player)
	if currentMushroomCount >= 50 then
		Logger:Info(string.format("Player %s has reached mushroom cap for Area1 (%d/50)", 
			player.Name, currentMushroomCount))
		return
	end

	-- Spend spores and spawn mushroom
	if self._dataService:SpendSpores(player, purchaseCost) then
		-- Get player's plot
		local playerPlots = workspace:FindFirstChild("PlayerPlots")
		if not playerPlots then
			Logger:Error("PlayerPlots not found")
			self._dataService:AddSpores(player, purchaseCost) -- Refund
			return
		end

		local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
		if not playerPlot then
			Logger:Error(string.format("Plot not found for player %s", player.Name))
			self._dataService:AddSpores(player, purchaseCost) -- Refund
			return
		end

		-- Add mushroom to Area1
		local success = self._mushroomService:AddMushroom(player, "Area1")
		if success then
			-- Increment shop level
			self._dataService:IncrementArea1MushroomShopLevel(player)

			Logger:Info(string.format("Player %s purchased Area1 mushroom for %.2f spores (level %d -> %d)", 
				player.Name, purchaseCost, currentLevel, currentLevel + 1))

			-- Play purchase success sound
			self:_playPurchaseSuccessSound(player)

			-- Sync updated shop data to client
			self:_syncShopData(player)
		else
			-- Refund if mushroom spawn failed
			self._dataService:AddSpores(player, purchaseCost)
			Logger:Error(string.format("Failed to add Area1 mushroom for player %s, refunded spores", player.Name))
		end
	else
		Logger:Error(string.format("Failed to spend spores for player %s Area1 mushroom purchase", player.Name))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
	end
end

function ShopService:_handleArea2MushroomPurchase(player)
	if not self._dataService or not self._mushroomService then
		Logger:Error("Required services not available for Area2 mushroom purchase")
		return
	end

	-- Check if Area2 is unlocked
	if not self._dataService:IsArea2Unlocked(player) then
		Logger:Warn(string.format("Player %s tried to purchase Area2 mushroom without Area2 unlocked", player.Name))
		return
	end

	-- Get current shop level for Area2
	local currentLevel = self._dataService:GetArea2MushroomShopLevel(player)

	-- Check level cap
	Logger:Debug(string.format("MUSHROOM PURCHASE DEBUG: Player %s attempting Area2 mushroom purchase. Current level: %d, Max level: %d", 
		player.Name, currentLevel, SHOP_CONFIG.Area2MushroomShop.maxLevel))
	if currentLevel >= SHOP_CONFIG.Area2MushroomShop.maxLevel then
		Logger:Info(string.format("Player %s has reached Area2 mushroom shop level cap (%d/%d)", 
			player.Name, currentLevel, SHOP_CONFIG.Area2MushroomShop.maxLevel))
		return
	end

	local purchaseCost = self:_calculateArea2MushroomShopCost(currentLevel)

	-- Check if player has enough spores
	local currentSpores = self._dataService:GetSpores(player)
	if currentSpores < purchaseCost then
		Logger:Info(string.format("Player %s cannot afford Area2 mushroom (need %.2f, have %.2f)", 
			player.Name, purchaseCost, currentSpores))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
		return
	end

	-- Check mushroom count limit (50 per area)
	local currentMushroomCount = self._dataService:GetArea2MushroomCount(player)
	if currentMushroomCount >= 50 then
		Logger:Info(string.format("Player %s has reached mushroom cap for Area2 (%d/50)", 
			player.Name, currentMushroomCount))
		return
	end

	-- Spend spores and spawn mushroom
	if self._dataService:SpendSpores(player, purchaseCost) then
		-- Get player's plot
		local playerPlots = workspace:FindFirstChild("PlayerPlots")
		if not playerPlots then
			Logger:Error("PlayerPlots not found")
			self._dataService:AddSpores(player, purchaseCost) -- Refund
			return
		end

		local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
		if not playerPlot then
			Logger:Error(string.format("Plot not found for player %s", player.Name))
			self._dataService:AddSpores(player, purchaseCost) -- Refund
			return
		end

		-- Add mushroom to Area2
		local success = self._mushroomService:AddMushroom(player, "Area2")
		if success then
			-- Increment shop level
			self._dataService:IncrementArea2MushroomShopLevel(player)

			Logger:Info(string.format("Player %s purchased Area2 mushroom for %.2f spores (level %d -> %d)", 
				player.Name, purchaseCost, currentLevel, currentLevel + 1))

			-- Play purchase success sound
			self:_playPurchaseSuccessSound(player)

			-- Sync updated shop data to client
			self:_syncShopData(player)
		else
			-- Refund if mushroom spawn failed
			self._dataService:AddSpores(player, purchaseCost)
			Logger:Error(string.format("Failed to add Area2 mushroom for player %s, refunded spores", player.Name))
		end
	else
		Logger:Error(string.format("Failed to spend spores for player %s Area2 mushroom purchase", player.Name))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
	end
end

function ShopService:_handleArea3MushroomPurchase(player)
	if not self._dataService or not self._mushroomService then
		Logger:Error("Required services not available for Area3 mushroom purchase")
		return
	end

	-- Check if Area3 is unlocked
	if not ((self._dataService.IsArea3Unlocked and self._dataService:IsArea3Unlocked(player)) or false) then
		Logger:Warn(string.format("Player %s tried to purchase Area3 mushroom without Area3 unlocked", player.Name))
		return
	end

	-- Get current shop level for Area3
	local currentLevel = (self._dataService.GetArea3MushroomShopLevel and self._dataService:GetArea3MushroomShopLevel(player)) or 0

	-- Check level cap
	if currentLevel >= SHOP_CONFIG.Area3MushroomShop.maxLevel then
		Logger:Info(string.format("Player %s has reached Area3 mushroom shop level cap (%d/100)", 
			player.Name, currentLevel))
		return
	end

	local purchaseCost = self:_calculateArea3MushroomShopCost(currentLevel)

	-- Check if player has enough spores
	local currentSpores = self._dataService:GetSpores(player)
	if currentSpores < purchaseCost then
		Logger:Info(string.format("Player %s cannot afford Area3 mushroom (need %.2f, have %.2f)", 
			player.Name, purchaseCost, currentSpores))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
		return
	end

	-- Check mushroom count limit (50 per area)
	local currentMushroomCount = (self._dataService.GetArea3MushroomCount and self._dataService:GetArea3MushroomCount(player)) or 0
	if currentMushroomCount >= 50 then
		Logger:Info(string.format("Player %s has reached mushroom cap for Area3 (%d/50)", 
			player.Name, currentMushroomCount))
		return
	end

	-- Spend spores and spawn mushroom
	if self._dataService:SpendSpores(player, purchaseCost) then
		-- Get player's plot
		local playerPlots = workspace:FindFirstChild("PlayerPlots")
		if not playerPlots then
			Logger:Error("PlayerPlots not found")
			self._dataService:AddSpores(player, purchaseCost) -- Refund
			return
		end

		local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
		if not playerPlot then
			Logger:Error(string.format("Plot not found for player %s", player.Name))
			self._dataService:AddSpores(player, purchaseCost) -- Refund
			return
		end

		-- Add mushroom to Area3
		local success = self._mushroomService:AddMushroom(player, "Area3")
		if success then
			-- Increment shop level
			if self._dataService.IncrementArea3MushroomShopLevel then
				self._dataService:IncrementArea3MushroomShopLevel(player)
			end

			Logger:Info(string.format("Player %s purchased Area3 mushroom for %.2f spores (level %d -> %d)", 
				player.Name, purchaseCost, currentLevel, currentLevel + 1))

			-- Play purchase success sound
			self:_playPurchaseSuccessSound(player)

			-- Sync updated shop data to client
			self:_syncShopData(player)
		else
			-- Refund if mushroom spawn failed
			self._dataService:AddSpores(player, purchaseCost)
			Logger:Error(string.format("Failed to add Area3 mushroom for player %s, refunded spores", player.Name))
		end
	else
		Logger:Error(string.format("Failed to spend spores for player %s Area3 mushroom purchase", player.Name))
		
		-- Play purchase fail sound and prompt spore dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "spores")
	end
end

function ShopService:_handleFastRunnerPurchase(player, clientCost, clientLevel)
	Logger:Info(string.format("Processing FastRunner purchase for %s - ClientCost: %d, ClientLevel: %d", 
		player.Name, clientCost, clientLevel))

	if not self._dataService then
		Logger:Error("DataService not available for FastRunner purchase")
		return
	end

	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Player upgrades not found for %s", player.Name))
		return
	end

	local serverLevel = playerUpgrades.fastRunnerLevel
	local serverCost = self:_calculateFastRunnerCost(serverLevel)

	-- Check level cap
	if serverLevel >= SHOP_CONFIG.FastRunner.maxLevel then
		Logger:Info(string.format("Player %s has reached FastRunner level cap (%d/%d)", 
			player.Name, serverLevel, SHOP_CONFIG.FastRunner.maxLevel))
		return
	end

	-- Security validation: client data must match server
	if clientLevel ~= serverLevel then
		Logger:Warn(string.format("Level mismatch for %s FastRunner: client=%d, server=%d", 
			player.Name, clientLevel, serverLevel))
		-- Sync correct data to client
		self:_syncFastRunnerData(player)
		return
	end

	if clientCost ~= serverCost then
		Logger:Warn(string.format("Cost mismatch for %s FastRunner: client=%d, server=%d", 
			player.Name, clientCost, serverCost))
		-- Sync correct data to client  
		self:_syncFastRunnerData(player)
		return
	end

	-- Check if player has enough gems
	local currentGems = self._dataService:GetGems(player)
	if currentGems < serverCost then
		Logger:Info(string.format("Player %s cannot afford FastRunner upgrade (need %d, have %d)", 
			player.Name, serverCost, currentGems))
		
		Logger:Info("=== INSUFFICIENT GEMS DETECTED (FASTRUNNER) - Playing fail sound ===")
		
		-- Track Roblox Analytics for failed purchase
		if self._robloxAnalyticsService then
			self._robloxAnalyticsService:TrackUpgradeFailed(player, "Gem", "FastRunner", "insufficient_gems")
		end
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
		return
	end

	-- Spend gems and apply upgrade
	if self._dataService:SpendGems(player, serverCost) then
		-- Increase upgrade level
		local oldLevel = playerUpgrades.fastRunnerLevel
		playerUpgrades.fastRunnerLevel = playerUpgrades.fastRunnerLevel + 1
		local newLevel = playerUpgrades.fastRunnerLevel
		
		-- Track gem upgrade milestone
		if self._robloxAnalyticsService then
			self._robloxAnalyticsService:TrackGemUpgradeMilestone(player, "FastRunner", newLevel)
		end

		Logger:Info(string.format("FastRunner level updated for %s: %d -> %d", player.Name, oldLevel, newLevel))

		-- Save upgrade level to player data
		local updateSuccess = self._dataService:UpdatePlayerData(player, function(data)
			data.FastRunnerLevel = newLevel
			Logger:Info(string.format("Saving FastRunnerLevel = %d for player %s", newLevel, player.Name))
		end)

		if not updateSuccess then
			Logger:Error(string.format("Failed to update player data for %s FastRunner upgrade", player.Name))
			return
		end

		-- Apply speed boost to player character
		self:_applySpeedBoost(player)

		-- Calculate new values for client
		local newWalkSpeed = self:_calculateWalkSpeed(newLevel)
		local newSpeedPercent = (newLevel * SHOP_CONFIG.FastRunner.speedBonus) * 100

		-- Send confirmation to client with new values
		self:_confirmFastRunnerPurchase(player, newLevel, newWalkSpeed, newSpeedPercent)

		-- Fire tutorial success event for gem shop purchases
		if self._tutorialPurchaseSuccess then
			self._tutorialPurchaseSuccess:FireClient(player, "gemShop", "FastRunner")
		end

		Logger:Info(string.format("Player %s purchased FastRunner level %d (%.0f%% speed) for %d gems", 
			player.Name, newLevel, newSpeedPercent, serverCost))

		-- Track Roblox Analytics
		if self._robloxAnalyticsService then
			self._robloxAnalyticsService:TrackUpgradeCompleted(player, "Gem", "FastRunner", newLevel, serverCost)
			
			-- Track gem upgrade milestones (need to count total gem upgrades)
			local totalGemUpgrades = self:_getTotalGemUpgrades(player)
			if totalGemUpgrades then
				self._robloxAnalyticsService:TrackGemUpgradeMilestone(player, totalGemUpgrades)
			end
		end

		-- Play purchase success sound
		self:_playPurchaseSuccessSound(player)
	else
		Logger:Error(string.format("Failed to spend gems for player %s FastRunner upgrade", player.Name))
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
	end
end

function ShopService:_handlePickUpRangePurchase(player, clientCost, clientLevel)
	Logger:Info(string.format("Processing PickUpRange purchase for %s - ClientCost: %d, ClientLevel: %d", 
		player.Name, clientCost, clientLevel))

	if not self._dataService then
		Logger:Error("DataService not available for PickUpRange purchase")
		return
	end

	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Player upgrades not found for %s", player.Name))
		return
	end

	local serverLevel = playerUpgrades.pickUpRangeLevel
	local serverCost = self:_calculatePickUpRangeCost(serverLevel)

	-- Check level cap
	if serverLevel >= SHOP_CONFIG.PickUpRange.maxLevel then
		Logger:Info(string.format("Player %s has reached PickUpRange level cap (%d/%d)", 
			player.Name, serverLevel, SHOP_CONFIG.PickUpRange.maxLevel))
		return
	end

	-- Security validation: client data must match server
	if clientLevel ~= serverLevel then
		Logger:Warn(string.format("Level mismatch for %s PickUpRange: client=%d, server=%d", 
			player.Name, clientLevel, serverLevel))
		-- Sync correct data to client
		self:_syncPickUpRangeData(player)
		return
	end

	if clientCost ~= serverCost then
		Logger:Warn(string.format("Cost mismatch for %s PickUpRange: client=%d, server=%d", 
			player.Name, clientCost, serverCost))
		-- Sync correct data to client  
		self:_syncPickUpRangeData(player)
		return
	end

	-- Check if player has enough gems
	local currentGems = self._dataService:GetGems(player)
	if currentGems < serverCost then
		Logger:Info(string.format("Player %s cannot afford PickUpRange upgrade (need %d, have %d)", 
			player.Name, serverCost, currentGems))
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
		return
	end

	-- Spend gems and apply upgrade
	if self._dataService:SpendGems(player, serverCost) then
		-- Increase upgrade level
		local oldLevel = playerUpgrades.pickUpRangeLevel
		playerUpgrades.pickUpRangeLevel = playerUpgrades.pickUpRangeLevel + 1
		local newLevel = playerUpgrades.pickUpRangeLevel
		
		-- Track gem upgrade milestone
		if self._robloxAnalyticsService then
			self._robloxAnalyticsService:TrackGemUpgradeMilestone(player, "PickUpRange", newLevel)
		end

		Logger:Info(string.format("PickUpRange level updated for %s: %d -> %d", player.Name, oldLevel, newLevel))

		-- Save upgrade level to player data
		local updateSuccess = self._dataService:UpdatePlayerData(player, function(data)
			data.PickUpRangeLevel = newLevel
			Logger:Info(string.format("Saving PickUpRangeLevel = %d for player %s", newLevel, player.Name))
		end)

		if not updateSuccess then
			Logger:Error(string.format("Failed to update player data for %s PickUpRange upgrade", player.Name))
			return
		end

		-- Calculate new values for client
		local newRange = self:_calculatePickUpRange(newLevel, player)

		-- Send confirmation to client with new values
		self:_confirmPickUpRangePurchase(player, newLevel, newRange)

		-- Fire tutorial success event for gem shop purchases
		if self._tutorialPurchaseSuccess then
			self._tutorialPurchaseSuccess:FireClient(player, "gemShop", "PickUpRange")
		end

		Logger:Info(string.format("Player %s purchased PickUpRange level %d (%.2f studs) for %d gems", 
			player.Name, newLevel, newRange, serverCost))

		-- Play purchase success sound
		self:_playPurchaseSuccessSound(player)
	else
		Logger:Error(string.format("Failed to spend gems for player %s PickUpRange upgrade", player.Name))
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
	end
end

function ShopService:_handleFasterShroomsPurchase(player, clientCost, clientLevel)
	Logger:Info(string.format("Processing FasterShrooms purchase for %s - ClientCost: %d, ClientLevel: %d", 
		player.Name, clientCost, clientLevel))

	if not self._dataService then
		Logger:Error("DataService not available for FasterShrooms purchase")
		return
	end

	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Player upgrades not found for %s", player.Name))
		return
	end

	local serverLevel = playerUpgrades.fasterShroomsLevel
	local serverCost = self:_calculateFasterShroomsCost(serverLevel)

	-- Check level cap
	if serverLevel >= SHOP_CONFIG.FasterShrooms.maxLevel then
		Logger:Info(string.format("Player %s has reached FasterShrooms level cap (%d/%d)", 
			player.Name, serverLevel, SHOP_CONFIG.FasterShrooms.maxLevel))
		return
	end

	-- Security validation: client data must match server
	if clientLevel ~= serverLevel then
		Logger:Warn(string.format("Level mismatch for %s FasterShrooms: client=%d, server=%d", 
			player.Name, clientLevel, serverLevel))
		-- Sync correct data to client
		self:_syncFasterShroomsData(player)
		return
	end

	if clientCost ~= serverCost then
		Logger:Warn(string.format("Cost mismatch for %s FasterShrooms: client=%d, server=%d", 
			player.Name, clientCost, serverCost))
		-- Sync correct data to client  
		self:_syncFasterShroomsData(player)
		return
	end

	-- Check if player has enough gems
	local currentGems = self._dataService:GetGems(player)
	if currentGems < serverCost then
		Logger:Info(string.format("Player %s cannot afford FasterShrooms upgrade (need %d, have %d)", 
			player.Name, serverCost, currentGems))
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
		return
	end

	-- Spend gems and apply upgrade
	if self._dataService:SpendGems(player, serverCost) then
		-- Increase upgrade level
		local oldLevel = playerUpgrades.fasterShroomsLevel
		playerUpgrades.fasterShroomsLevel = playerUpgrades.fasterShroomsLevel + 1
		local newLevel = playerUpgrades.fasterShroomsLevel
		
		-- Track gem upgrade milestone
		if self._robloxAnalyticsService then
			self._robloxAnalyticsService:TrackGemUpgradeMilestone(player, "FasterShrooms", newLevel)
		end

		Logger:Info(string.format("FasterShrooms level updated for %s: %d -> %d", player.Name, oldLevel, newLevel))

		-- Save upgrade level to player data
		local updateSuccess = self._dataService:UpdatePlayerData(player, function(data)
			data.FasterShroomsLevel = newLevel
			Logger:Info(string.format("Saving FasterShroomsLevel = %d for player %s", newLevel, player.Name))
		end)

		if not updateSuccess then
			Logger:Error(string.format("Failed to update player data for %s FasterShrooms upgrade", player.Name))
			return
		end

		-- Calculate new values for client
		local newSpeedBonus = self:_calculateShroomSpeedBonus(newLevel)

		-- Send confirmation to client with new values
		self:_confirmFasterShroomsPurchase(player, newLevel, newSpeedBonus)

		-- Fire tutorial success event for gem shop purchases
		if self._tutorialPurchaseSuccess then
			self._tutorialPurchaseSuccess:FireClient(player, "gemShop", "FasterShrooms")
		end

		Logger:Info(string.format("Player %s purchased FasterShrooms level %d (%.0f%% speed) for %d gems", 
			player.Name, newLevel, newSpeedBonus * 100, serverCost))

		-- Play purchase success sound
		self:_playPurchaseSuccessSound(player)
	else
		Logger:Error(string.format("Failed to spend gems for player %s FasterShrooms upgrade", player.Name))
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
	end
end

function ShopService:_calculateSporeUpgradeCost(currentLevel)
	local baseCost = SHOP_CONFIG.SporeUpgrade.baseCost
	local multiplier = SHOP_CONFIG.SporeUpgrade.costMultiplier
	local cost = baseCost * (multiplier ^ currentLevel)
	return math.floor(cost * 100 + 0.5) / 100 -- Round to 2 decimals
end

function ShopService:_calculateMushroomCost(currentMushroomCount)
	local baseCost = SHOP_CONFIG.MushroomPurchase.baseCost
	local multiplier = SHOP_CONFIG.MushroomPurchase.costMultiplier
	local cost = baseCost * (multiplier ^ currentMushroomCount)
	return math.floor(cost * 100 + 0.5) / 100 -- Round to 2 decimals
end

function ShopService:_calculateArea1MushroomShopCost(currentLevel)
	local baseCost = SHOP_CONFIG.Area1MushroomShop.baseCost
	local multiplier = SHOP_CONFIG.Area1MushroomShop.costMultiplier
	local cost = baseCost * (multiplier ^ currentLevel)
	return math.floor(cost * 100 + 0.5) / 100 -- Round to 2 decimals
end

function ShopService:_calculateArea2MushroomShopCost(currentLevel)
	local baseCost = SHOP_CONFIG.Area2MushroomShop.baseCost
	local multiplier = SHOP_CONFIG.Area2MushroomShop.costMultiplier
	local cost = baseCost * (multiplier ^ currentLevel)
	return math.floor(cost * 100 + 0.5) / 100 -- Round to 2 decimals
end

function ShopService:_calculateArea3MushroomShopCost(currentLevel)
	local baseCost = SHOP_CONFIG.Area3MushroomShop.baseCost
	local multiplier = SHOP_CONFIG.Area3MushroomShop.costMultiplier
	local cost = baseCost * (multiplier ^ currentLevel)
	return math.floor(cost * 100 + 0.5) / 100 -- Round to 2 decimals
end

function ShopService:_calculateFastRunnerCost(currentLevel)
	local baseCost = SHOP_CONFIG.FastRunner.baseCost
	local costIncrease = SHOP_CONFIG.FastRunner.costIncrease
	-- Level 1 is the starting level, so cost is based on upgrades beyond level 1
	return baseCost + ((currentLevel - 1) * costIncrease)
end

function ShopService:_calculatePickUpRangeCost(currentLevel)
	local baseCost = SHOP_CONFIG.PickUpRange.baseCost
	local costIncrease = SHOP_CONFIG.PickUpRange.costIncrease
	-- Level 1 is the starting level, so cost is based on upgrades beyond level 1
	return baseCost + ((currentLevel - 1) * costIncrease)
end

function ShopService:_calculatePickUpRange(level, player)
	local baseRange = 6.0 -- Base pickup range in studs
	local rangeBonus = (level - 1) * SHOP_CONFIG.PickUpRange.rangeBonus
	local upgradeRange = baseRange + rangeBonus
	
	-- Apply gamepass multipliers if player provided and gamepass service available
	if player and self._gamepassService then
		local multiplier = self._gamepassService:getCollectionRadiusMultiplier(player)
		local flatBonus = self._gamepassService:getCollectionRadiusBonus(player)
		upgradeRange = (upgradeRange * multiplier) + flatBonus
		
		Logger:Info(string.format("ShopService: PickUpRange for %s - Base: %.2f, Upgrade: %.2f, Multiplier: %.1f, Flat: %.0f, Final: %.2f", 
			player.Name, baseRange, baseRange + rangeBonus, multiplier, flatBonus, upgradeRange))
	end
	
	return upgradeRange
end

function ShopService:_calculateFasterShroomsCost(currentLevel)
	local baseCost = SHOP_CONFIG.FasterShrooms.baseCost
	local costIncrease = SHOP_CONFIG.FasterShrooms.costIncrease
	-- Level 1 is the starting level, so cost is based on upgrades beyond level 1
	return baseCost + ((currentLevel - 1) * costIncrease)
end

function ShopService:_calculateShroomSpeedBonus(level)
	-- Level 1 = 0% bonus, Level 2 = 2% bonus, Level 3 = 4% bonus, etc.
	return (level - 1) * SHOP_CONFIG.FasterShrooms.speedBonus
end

function ShopService:GetSporeMultiplier(player, area)
	area = area or "Area1" -- Default to Area1 for backwards compatibility
	
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 1.0
	end

	-- Get area-specific spore upgrade level
	local upgradeLevel
	if area == "Area2" then
		upgradeLevel = playerUpgrades.area2SporeUpgradeLevel or 0
	else
		upgradeLevel = playerUpgrades.area1SporeUpgradeLevel or playerUpgrades.sporeUpgradeLevel or 0
	end

	-- Base spore upgrade bonus (8% per level)
	local bonusPerLevel = SHOP_CONFIG.SporeUpgrade.upgradeBonus
	local baseMultiplier = 1.0 + (upgradeLevel * bonusPerLevel)

	-- ShinySpore value bonus (2% per level above 1) - applies globally
	local shinySporeLevel = playerUpgrades.shinySporeLevel or 1
	local shinySporeBonus = self:GetShinySporeValueBonus(player)

	-- Combine both bonuses multiplicatively
	return baseMultiplier * (1.0 + shinySporeBonus)
end

function ShopService:GetSporeUpgradeCost(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return SHOP_CONFIG.SporeUpgrade.baseCost
	end

	return self:_calculateSporeUpgradeCost(playerUpgrades.sporeUpgradeLevel)
end

function ShopService:GetMushroomPurchaseCost(player)
	-- Use data service counts for immediate accuracy after purchases
	if not self._dataService then
		Logger:Warn("ShopService: DataService not available yet")
		return 0
	end
	local area1Count = self._dataService:GetArea1MushroomCount(player)
	local area2Count = self._dataService:GetArea2MushroomCount(player)
	local totalCount = area1Count + area2Count
	return self:_calculateMushroomCost(totalCount)
end

function ShopService:GetMushroomCount(player)
	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		return 0
	end

	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		return 0
	end

	local currentMushroomCount = 0

	-- Count Area1 mushrooms
	local mushroomsFolder = playerPlot:FindFirstChild("Mushrooms")
	if mushroomsFolder then
		for _, child in pairs(mushroomsFolder:GetChildren()) do
			if child:IsA("Model") and string.find(child.Name, "MushroomModel_") then
				currentMushroomCount = currentMushroomCount + 1
			end
		end
	end

	-- Count Area2 mushrooms
	local area2 = playerPlot:FindFirstChild("Area2")
	if area2 then
		local area2Mushrooms = area2:FindFirstChild("Mushrooms")
		if area2Mushrooms then
			for _, child in pairs(area2Mushrooms:GetChildren()) do
				if child:IsA("Model") and string.find(child.Name, "MushroomModel_") then
					currentMushroomCount = currentMushroomCount + 1
				end
			end
		end
	end

	return currentMushroomCount
end

function ShopService:GetSporeUpgradeLevel(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 0
	end

	return playerUpgrades.sporeUpgradeLevel
end

function ShopService:_notifyShopDataUpdated(player)
	local shopEvents = ReplicatedStorage:FindFirstChild("Shared")
	if shopEvents then
		shopEvents = shopEvents:FindFirstChild("RemoteEvents")
		if shopEvents then
			shopEvents = shopEvents:FindFirstChild("ShopEvents")
			if shopEvents then
				local shopDataUpdated = shopEvents:FindFirstChild("ShopDataUpdated")
				if shopDataUpdated then
					-- Get minimal shop data for tutorial tracking only
					local playerUpgrades = self._playerUpgrades[player.UserId] or {}
					local minimalShopData = {
						currentMushroomCount = self._dataService:GetArea1MushroomCount(player) + self._dataService:GetArea2MushroomCount(player),
						currentSporeUpgradeLevel = playerUpgrades.sporeUpgradeLevel or 0,
					}
					shopDataUpdated:FireClient(player, minimalShopData)
					Logger:Debug(string.format("Notified %s that shop data was updated", player.Name))
				end
			end
		end
	end
end

function ShopService:_notifyGemShopDataUpdated(player)
	local shopEvents = ReplicatedStorage:FindFirstChild("Shared")
	if shopEvents then
		shopEvents = shopEvents:FindFirstChild("RemoteEvents")
		if shopEvents then
			shopEvents = shopEvents:FindFirstChild("ShopEvents")
			if shopEvents then
				local gemShopDataUpdated = shopEvents:FindFirstChild("GemShopDataUpdated")
				if gemShopDataUpdated then
					gemShopDataUpdated:FireClient(player)
					Logger:Debug(string.format("Notified %s that gem shop data was updated", player.Name))
				end
			end
		end
	end
end

function ShopService:_applySpeedBoost(player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return
	end

	-- Calculate total speed boost
	local newWalkSpeed = self:_calculateWalkSpeed(playerUpgrades.fastRunnerLevel)

	humanoid.WalkSpeed = newWalkSpeed
	Logger:Debug(string.format("Applied speed boost to %s: %.2f", player.Name, newWalkSpeed))
end

function ShopService:_calculateWalkSpeed(level)
	local speedBonus = level * SHOP_CONFIG.FastRunner.speedBonus
	return 16 * (1 + speedBonus) -- Base walkspeed is 16
end

function ShopService:_syncShopData(player)
	local shopData = self:GetShopDataForPlayer(player)

	-- Find and fire sync remote
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if shared then
		local remoteEvents = shared:FindFirstChild("RemoteEvents")
		if remoteEvents then
			local shopEvents = remoteEvents:FindFirstChild("ShopEvents")
			if shopEvents then
				local syncShopData = shopEvents:FindFirstChild("SyncShopData")
				if syncShopData then
					syncShopData:FireClient(player, shopData)
					Logger:Info(string.format("Synced shop data to %s: SporeLevel %d (A1:%d, A2:%d), MushroomCount %d, Multiplier %.2f",
						player.Name, shopData.currentSporeUpgradeLevel, shopData.area1SporeUpgradeLevel or -1, shopData.area2SporeUpgradeLevel or -1, shopData.currentMushroomCount, shopData.sporeMultiplier))
				end
			end
		end
	end
end

function ShopService:_syncFastRunnerData(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Cannot sync FastRunner data - no upgrades found for %s", player.Name))
		return
	end

	local level = playerUpgrades.fastRunnerLevel
	local walkSpeed = self:_calculateWalkSpeed(level)
	local speedPercent = (level * SHOP_CONFIG.FastRunner.speedBonus) * 100
	local cost = self:_calculateFastRunnerCost(level)

	-- Find and fire sync remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local syncFastRunner = gemShopRemotes:FindFirstChild("SyncFastRunner")
		if syncFastRunner then
			syncFastRunner:FireClient(player, level, walkSpeed, speedPercent, cost)
			Logger:Debug(string.format("Synced FastRunner data to %s: Level %d, Speed %.2f (%.0f%%)",
				player.Name, level, walkSpeed, speedPercent))
		end
	end
end

function ShopService:_confirmFastRunnerPurchase(player, newLevel, newWalkSpeed, newSpeedPercent)
	-- Find and fire confirmation remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local fastRunnerConfirm = gemShopRemotes:FindFirstChild("FastRunnerConfirm")
		if fastRunnerConfirm then
			fastRunnerConfirm:FireClient(player, newLevel, newWalkSpeed, newSpeedPercent)
			Logger:Debug(string.format("Confirmed FastRunner purchase to %s: Level %d, Speed %.2f (%.0f%%)",
				player.Name, newLevel, newWalkSpeed, newSpeedPercent))
		end
	end
end

function ShopService:_syncPickUpRangeData(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Cannot sync PickUpRange data - no upgrades found for %s", player.Name))
		return
	end

	local level = playerUpgrades.pickUpRangeLevel
	local range = self:_calculatePickUpRange(level, player)
	local cost = self:_calculatePickUpRangeCost(level)

	-- Find and fire sync remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local syncPickUpRange = gemShopRemotes:FindFirstChild("SyncPickUpRange")
		if syncPickUpRange then
			syncPickUpRange:FireClient(player, level, range, cost)
			Logger:Debug(string.format("Synced PickUpRange data to %s: Level %d, Range %.2f studs, Cost %d",
				player.Name, level, range, cost))
		end
	end
end

function ShopService:_confirmPickUpRangePurchase(player, newLevel, newRange)
	-- Find and fire confirmation remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local pickUpRangeConfirm = gemShopRemotes:FindFirstChild("PickUpRangeConfirm")
		if pickUpRangeConfirm then
			pickUpRangeConfirm:FireClient(player, newLevel, newRange)
			Logger:Debug(string.format("Confirmed PickUpRange purchase to %s: Level %d, Range %.2f studs",
				player.Name, newLevel, newRange))
		end
	end
end

function ShopService:_syncFasterShroomsData(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Cannot sync FasterShrooms data - no upgrades found for %s", player.Name))
		return
	end

	local level = playerUpgrades.fasterShroomsLevel
	local speedBonus = self:_calculateShroomSpeedBonus(level)
	local cost = self:_calculateFasterShroomsCost(level)

	-- Find and fire sync remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local syncFasterShrooms = gemShopRemotes:FindFirstChild("SyncFasterShrooms")
		if syncFasterShrooms then
			syncFasterShrooms:FireClient(player, level, speedBonus, cost)
			Logger:Debug(string.format("Synced FasterShrooms data to %s: Level %d, Speed Bonus %.0f%%",
				player.Name, level, speedBonus * 100))
		end
	end
end

function ShopService:_confirmFasterShroomsPurchase(player, newLevel, newSpeedBonus)
	-- Find and fire confirmation remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local fasterShroomsConfirm = gemShopRemotes:FindFirstChild("FasterShroomsConfirm")
		if fasterShroomsConfirm then
			fasterShroomsConfirm:FireClient(player, newLevel, newSpeedBonus)
			Logger:Debug(string.format("Confirmed FasterShrooms purchase to %s: Level %d, Speed Bonus %.0f%%",
				player.Name, newLevel, newSpeedBonus * 100))
		end
	end
end

function ShopService:_handleShinySporePurchase(player, clientCost, clientLevel)

	if not self._dataService then
		Logger:Error("DataService not available for ShinySpore purchase")
		return
	end

	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Player upgrades not found for %s", player.Name))
		return
	end

	local serverLevel = playerUpgrades.shinySporeLevel
	local serverCost = self:_calculateShinySporeUpgradeCost(serverLevel)

	-- Check level cap
	if serverLevel >= SHOP_CONFIG.ShinySpore.maxLevel then
		Logger:Info(string.format("Player %s has reached ShinySpore level cap (%d/%d)", 
			player.Name, serverLevel, SHOP_CONFIG.ShinySpore.maxLevel))
		return
	end

	-- Security validation: client data must match server
	if clientLevel ~= serverLevel then
		Logger:Warn(string.format("Level mismatch for %s ShinySpore: client=%d, server=%d", 
			player.Name, clientLevel, serverLevel))
		-- Sync correct data to client
		self:_syncShinySporeData(player)
		return
	end

	if clientCost ~= serverCost then
		Logger:Warn(string.format("Cost mismatch for %s ShinySpore: client=%d, server=%d", 
			player.Name, clientCost, serverCost))
		-- Sync correct data to client  
		self:_syncShinySporeData(player)
		return
	end

	-- Check if player has enough gems
	local currentGems = self._dataService:GetGems(player)
	if currentGems < serverCost then
		Logger:Info(string.format("Player %s cannot afford ShinySpore upgrade (need %d, have %d)", 
			player.Name, serverCost, currentGems))
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
		return
	end


	-- Spend gems and apply upgrade
	if self._dataService:SpendGems(player, serverCost) then

		-- Increase upgrade level
		local oldLevel = playerUpgrades.shinySporeLevel
		playerUpgrades.shinySporeLevel = playerUpgrades.shinySporeLevel + 1
		local newLevel = playerUpgrades.shinySporeLevel
		
		-- Track gem upgrade milestone
		if self._robloxAnalyticsService then
			self._robloxAnalyticsService:TrackGemUpgradeMilestone(player, "ShinySpore", newLevel)
		end



		-- Save upgrade level to player data
		local updateSuccess = self._dataService:UpdatePlayerData(player, function(data)
			data.ShinySporeLevel = newLevel
		end)


		if not updateSuccess then
			Logger:Error(string.format("Failed to update player data for %s ShinySpore upgrade", player.Name))
			return
		end


		-- Calculate new values for client
		local newValueBonus = self:_calculateShinySporeValueBonus(newLevel)

		-- Send confirmation to client with new values
		self:_confirmShinySporeUpgrade(player, newLevel, newValueBonus)

		-- Fire tutorial success event for gem shop purchases
		if self._tutorialPurchaseSuccess then
			self._tutorialPurchaseSuccess:FireClient(player, "gemShop", "ShinySpore")
		end

		Logger:Info(string.format("Player %s purchased ShinySpore level %d (%.0f%% value bonus) for %d gems", 
			player.Name, newLevel, newValueBonus * 100, serverCost))

		-- Play purchase success sound
		self:_playPurchaseSuccessSound(player)
	else
		Logger:Error(string.format("Failed to spend gems for player %s ShinySpore upgrade", player.Name))
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
	end
end

function ShopService:_syncShinySporeData(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Cannot sync ShinySpore data - no upgrades found for %s", player.Name))
		return
	end

	local level = playerUpgrades.shinySporeLevel
	local valueBonus = self:_calculateShinySporeValueBonus(level)
	local cost = self:_calculateShinySporeUpgradeCost(level)

	-- Find and fire sync remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local syncShinySpore = gemShopRemotes:FindFirstChild("SyncShinySpore")
		if syncShinySpore then
			syncShinySpore:FireClient(player, level, valueBonus, cost)
			Logger:Debug(string.format("Synced ShinySpore data to %s: Level %d, Value Bonus %.0f%%, Cost %d",
				player.Name, level, valueBonus * 100, cost))
		end
	end
end

function ShopService:_confirmShinySporeUpgrade(player, newLevel, newValueBonus)
	-- Find and fire confirmation remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local shinySporeConfirm = gemShopRemotes:FindFirstChild("ShinySporeConfirm")
		if shinySporeConfirm then
			shinySporeConfirm:FireClient(player, newLevel, newValueBonus)
			Logger:Debug(string.format("Confirmed ShinySpore purchase to %s: Level %d, Value Bonus %.0f%%",
				player.Name, newLevel, newValueBonus * 100))
		end
	end
end

function ShopService:_calculateShinySporeUpgradeCost(currentLevel)
	local baseCost = SHOP_CONFIG.ShinySpore.baseCost
	local costIncrease = SHOP_CONFIG.ShinySpore.costIncrease
	return baseCost + ((currentLevel - 1) * costIncrease)
end

function ShopService:_calculateShinySporeValueBonus(level)
	-- Level 1 = 0% bonus, Level 2 = 2% bonus, Level 3 = 4% bonus, etc.
	return (level - 1) * SHOP_CONFIG.ShinySpore.valueBonus
end

-- GemHunter upgrade functions
function ShopService:_handleGemHunterPurchase(player, clientCost, clientLevel)
	if not self._dataService then
		Logger:Error("DataService not available for GemHunter purchase")
		return
	end

	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Player upgrades not found for %s", player.Name))
		return
	end

	local serverLevel = playerUpgrades.gemHunterLevel
	local serverCost = self:_calculateGemHunterUpgradeCost(serverLevel)

	-- Check level cap
	if serverLevel >= SHOP_CONFIG.GemHunter.maxLevel then
		Logger:Info(string.format("Player %s has reached GemHunter level cap (%d/%d)", 
			player.Name, serverLevel, SHOP_CONFIG.GemHunter.maxLevel))
		return
	end

	-- Security validation: client data must match server
	if clientLevel ~= serverLevel then
		Logger:Warn(string.format("Level mismatch for %s GemHunter: client=%d, server=%d", 
			player.Name, clientLevel, serverLevel))
		-- Sync correct data to client
		self:_syncGemHunterData(player)
		return
	end

	if clientCost ~= serverCost then
		Logger:Warn(string.format("Cost mismatch for %s GemHunter: client=%d, server=%d", 
			player.Name, clientCost, serverCost))
		-- Sync correct data to client  
		self:_syncGemHunterData(player)
		return
	end

	-- Check if player has enough gems
	local currentGems = self._dataService:GetGems(player)
	if currentGems < serverCost then
		Logger:Info(string.format("Player %s cannot afford GemHunter upgrade (need %d, have %d)", 
			player.Name, serverCost, currentGems))
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
		return
	end

	-- Spend gems and apply upgrade
	if self._dataService:SpendGems(player, serverCost) then
		-- Increase upgrade level
		local oldLevel = playerUpgrades.gemHunterLevel
		playerUpgrades.gemHunterLevel = playerUpgrades.gemHunterLevel + 1
		local newLevel = playerUpgrades.gemHunterLevel
		
		-- Track gem upgrade milestone
		if self._robloxAnalyticsService then
			self._robloxAnalyticsService:TrackGemUpgradeMilestone(player, "GemHunter", newLevel)
		end

		-- Save upgrade level to player data
		local updateSuccess = self._dataService:UpdatePlayerData(player, function(data)
			data.GemHunterLevel = newLevel
		end)

		if not updateSuccess then
			Logger:Error(string.format("Failed to update player data for %s GemHunter upgrade", player.Name))
			return
		end

		-- Calculate new values for client
		local newGemDropBonus = self:_calculateGemDropBonus(newLevel)

		-- Send confirmation to client with new values
		self:_confirmGemHunterUpgrade(player, newLevel, newGemDropBonus)

		-- Fire tutorial success event for gem shop purchases
		if self._tutorialPurchaseSuccess then
			self._tutorialPurchaseSuccess:FireClient(player, "gemShop", "GemHunter")
		end

		Logger:Info(string.format("Player %s purchased GemHunter level %d (%.0f%% gem drop bonus) for %d gems", 
			player.Name, newLevel, newGemDropBonus * 100, serverCost))

		-- Play purchase success sound
		self:_playPurchaseSuccessSound(player)
	else
		Logger:Error(string.format("Failed to spend gems for player %s GemHunter upgrade", player.Name))
		
		-- Play purchase fail sound and prompt gem dev product
		self:_playPurchaseFailSound(player)
		self:_promptDevProduct(player, "gems")
	end
end

function ShopService:_syncGemHunterData(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Error(string.format("Cannot sync GemHunter data - no upgrades found for %s", player.Name))
		return
	end

	local level = playerUpgrades.gemHunterLevel
	local gemDropBonus = self:_calculateGemDropBonus(level)
	local cost = self:_calculateGemHunterUpgradeCost(level)

	-- Find and fire sync remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local syncGemHunter = gemShopRemotes:FindFirstChild("SyncGemHunter")
		if syncGemHunter then
			syncGemHunter:FireClient(player, level, gemDropBonus, cost)
			Logger:Debug(string.format("Synced GemHunter data to %s: Level %d, Gem Drop Bonus %.0f%%, Cost %d",
				player.Name, level, gemDropBonus * 100, cost))
		end
	end
end

function ShopService:_confirmGemHunterUpgrade(player, newLevel, newGemDropBonus)
	-- Find and fire confirmation remote
	local gemShopRemotes = ReplicatedStorage:FindFirstChild("GemShopRemotes")
	if gemShopRemotes then
		local gemHunterConfirm = gemShopRemotes:FindFirstChild("GemHunterConfirm")
		if gemHunterConfirm then
			gemHunterConfirm:FireClient(player, newLevel, newGemDropBonus)
			Logger:Debug(string.format("Confirmed GemHunter purchase to %s: Level %d, Gem Drop Bonus %.0f%%",
				player.Name, newLevel, newGemDropBonus * 100))
		end
	end
end

function ShopService:_calculateGemHunterUpgradeCost(currentLevel)
	local baseCost = SHOP_CONFIG.GemHunter.baseCost
	local costIncrease = SHOP_CONFIG.GemHunter.costIncrease
	return baseCost + ((currentLevel - 1) * costIncrease)
end

function ShopService:_calculateGemDropBonus(level)
	-- Level 1 = 0% bonus, Level 2 = 2% bonus, Level 3 = 4% bonus, etc.
	return (level - 1) * SHOP_CONFIG.GemHunter.gemBonus
end

-- Public functions for gem shop data
function ShopService:GetFastRunnerLevel(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 1
	end

	return playerUpgrades.fastRunnerLevel
end

function ShopService:GetFastRunnerCost(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return SHOP_CONFIG.FastRunner.baseCost
	end

	return self:_calculateFastRunnerCost(playerUpgrades.fastRunnerLevel)
end

function ShopService:GetSpeedBonus(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 0
	end

	return (playerUpgrades.fastRunnerLevel * SHOP_CONFIG.FastRunner.speedBonus) * 100
end

function ShopService:GetPickUpRangeLevel(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 1
	end

	return playerUpgrades.pickUpRangeLevel
end

function ShopService:GetPickUpRangeCost(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return SHOP_CONFIG.PickUpRange.baseCost
	end

	return self:_calculatePickUpRangeCost(playerUpgrades.pickUpRangeLevel)
end

function ShopService:GetPickUpRange(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 6.0
	end

	return self:_calculatePickUpRange(playerUpgrades.pickUpRangeLevel, player)
end

function ShopService:GetFasterShroomsLevel(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 1
	end

	return playerUpgrades.fasterShroomsLevel
end

function ShopService:GetFasterShroomsCost(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return SHOP_CONFIG.FasterShrooms.baseCost
	end

	return self:_calculateFasterShroomsCost(playerUpgrades.fasterShroomsLevel)
end

function ShopService:GetShroomSpeedBonus(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 0
	end

	return self:_calculateShroomSpeedBonus(playerUpgrades.fasterShroomsLevel)
end

function ShopService:GetShinySporeLevel(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 1
	end

	return playerUpgrades.shinySporeLevel
end

function ShopService:GetShinySporeUpgradeCost(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return SHOP_CONFIG.ShinySpore.baseCost
	end

	return self:_calculateShinySporeUpgradeCost(playerUpgrades.shinySporeLevel)
end

function ShopService:GetShinySporeValueBonus(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 0
	end

	return self:_calculateShinySporeValueBonus(playerUpgrades.shinySporeLevel)
end

function ShopService:CanPlayerAscend(player)
	return self:_canPlayerAscend(player)
end

-- Debug function to check all ascend requirements
function ShopService:GetAscendRequirements(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return "No player upgrades found"
	end

	local area1SporeLevel = playerUpgrades.area1SporeUpgradeLevel or 0
	local area2SporeLevel = playerUpgrades.area2SporeUpgradeLevel or 0
	local area1MushroomLevel = self._dataService:GetArea1MushroomShopLevel(player)
	local area2MushroomLevel = self._dataService:GetArea2MushroomShopLevel(player)

	return string.format(
		"Ascend Requirements for %s:\n" ..
		"Area1 Spore: %d/100 %s\n" ..
		"Area2 Spore: %d/100 %s\n" ..
		"Area1 Mushroom Shop: %d/49 %s (49 purchases + 1 starting = 50 mushrooms)\n" ..
		"Area2 Mushroom Shop: %d/50 %s\n" ..
		"Can Ascend: %s",
		player.Name,
		area1SporeLevel, area1SporeLevel >= 100 and "✓" or "✗",
		area2SporeLevel, area2SporeLevel >= 100 and "✓" or "✗", 
		area1MushroomLevel, area1MushroomLevel >= 49 and "✓" or "✗",
		area2MushroomLevel, area2MushroomLevel >= 50 and "✓" or "✗",
		self:_canPlayerAscend(player) and "YES" or "NO"
	)
end

function ShopService:GetShopDataForPlayer(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return {
			sporeUpgradeCost = SHOP_CONFIG.SporeUpgrade.baseCost,
			mushroomPurchaseCost = SHOP_CONFIG.MushroomPurchase.baseCost,
			sporeMultiplier = 1.0,
			currentMushroomCount = 1,
			currentSporeUpgradeLevel = 0,
			-- Separate mushroom shop defaults
			area1MushroomShopLevel = 0,
			area1MushroomShopCost = SHOP_CONFIG.Area1MushroomShop.baseCost,
			area1MushroomCount = 0,
			area2MushroomShopLevel = 0,
			area2MushroomShopCost = SHOP_CONFIG.Area2MushroomShop.baseCost,
			area2MushroomCount = 0,
			area2Unlocked = false
		}
	end

	-- Debug log the current in-memory data being used for sync
	Logger:Info(string.format("GetShopDataForPlayer %s: in-memory A1=%d, A2=%d", 
		player.Name, playerUpgrades.area1SporeUpgradeLevel or -1, playerUpgrades.area2SporeUpgradeLevel or -1))

	return {
		sporeUpgradeCost = self:GetSporeUpgradeCost(player),
		mushroomPurchaseCost = self:GetMushroomPurchaseCost(player),
		sporeMultiplier = self:GetSporeMultiplier(player),
		currentMushroomCount = self._dataService:GetArea1MushroomCount(player) + self._dataService:GetArea2MushroomCount(player),
		currentSporeUpgradeLevel = playerUpgrades.sporeUpgradeLevel, -- Legacy field for backwards compatibility
		-- Area-specific spore upgrade data
		area1SporeUpgradeLevel = playerUpgrades.area1SporeUpgradeLevel or 0,
		area1SporeUpgradeCost = self:_calculateSporeUpgradeCost(playerUpgrades.area1SporeUpgradeLevel or 0),
		area1SporeMultiplier = self:GetSporeMultiplier(player, "Area1"),
		area2SporeUpgradeLevel = playerUpgrades.area2SporeUpgradeLevel or 0,
		area2SporeUpgradeCost = self:_calculateSporeUpgradeCost(playerUpgrades.area2SporeUpgradeLevel or 0),
		area2SporeMultiplier = self:GetSporeMultiplier(player, "Area2"),
		-- Separate mushroom shop data
		area1MushroomShopLevel = self._dataService:GetArea1MushroomShopLevel(player),
		area1MushroomShopCost = self:_calculateArea1MushroomShopCost(self._dataService:GetArea1MushroomShopLevel(player)),
		area1MushroomCount = self._dataService:GetArea1MushroomCount(player),
		area2MushroomShopLevel = self._dataService:GetArea2MushroomShopLevel(player),
		area2MushroomShopCost = self:_calculateArea2MushroomShopCost(self._dataService:GetArea2MushroomShopLevel(player)),
		area2MushroomCount = self._dataService:GetArea2MushroomCount(player),
		area2Unlocked = self._dataService:IsArea2Unlocked(player),
		-- Area3 data
		area3MushroomShopLevel = (self._dataService.GetArea3MushroomShopLevel and self._dataService:GetArea3MushroomShopLevel(player)) or 0,
		area3MushroomShopCost = self:_calculateArea3MushroomShopCost((self._dataService.GetArea3MushroomShopLevel and self._dataService:GetArea3MushroomShopLevel(player)) or 0),
		area3MushroomCount = (self._dataService.GetArea3MushroomCount and self._dataService:GetArea3MushroomCount(player)) or 0,
		area3Unlocked = (self._dataService.IsArea3Unlocked and self._dataService:IsArea3Unlocked(player)) or false,
		-- Ascend status
		canAscend = self:_canPlayerAscend(player)
	}
end

function ShopService:GetGemShopDataForPlayer(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		Logger:Warn(string.format("No upgrade data found for player %s when getting gem shop data", player.Name))
		return {
			currentFastRunnerLevel = 1,
			currentSpeedBonus = 0,
			fastRunnerCost = SHOP_CONFIG.FastRunner.baseCost,
			currentPickUpRangeLevel = 1,
			currentPickUpRange = 6.0,
			pickUpRangeCost = SHOP_CONFIG.PickUpRange.baseCost,
			currentFasterShroomsLevel = 1,
			currentShroomSpeedBonus = 0,
			fasterShroomsCost = SHOP_CONFIG.FasterShrooms.baseCost,
			currentShinySporeLevel = 1,
			currentSporeValueBonus = 0,
			shinySporeUpgradeCost = SHOP_CONFIG.ShinySpore.baseCost,
			currentGemHunterLevel = 1,
			currentGemDropBonus = 0,
			gemHunterUpgradeCost = SHOP_CONFIG.GemHunter.baseCost
		}
	end

	local fastRunnerLevel = playerUpgrades.fastRunnerLevel
	local speedBonus = (fastRunnerLevel * SHOP_CONFIG.FastRunner.speedBonus) * 100
	local fastRunnerCost = self:_calculateFastRunnerCost(fastRunnerLevel)

	local pickUpRangeLevel = playerUpgrades.pickUpRangeLevel
	local pickUpRange = self:_calculatePickUpRange(pickUpRangeLevel, player)
	local pickUpRangeCost = self:_calculatePickUpRangeCost(pickUpRangeLevel)

	local fasterShroomsLevel = playerUpgrades.fasterShroomsLevel
	local shroomSpeedBonus = self:_calculateShroomSpeedBonus(fasterShroomsLevel)
	local fasterShroomsCost = self:_calculateFasterShroomsCost(fasterShroomsLevel)

	local shinySporeLevel = playerUpgrades.shinySporeLevel
	local sporeValueBonus = self:_calculateShinySporeValueBonus(shinySporeLevel)
	local shinySporeUpgradeCost = self:_calculateShinySporeUpgradeCost(shinySporeLevel)

	local gemHunterLevel = playerUpgrades.gemHunterLevel
	local gemDropBonus = self:_calculateGemDropBonus(gemHunterLevel)
	local gemHunterUpgradeCost = self:_calculateGemHunterUpgradeCost(gemHunterLevel)

	Logger:Debug(string.format("Providing gem shop data for %s: FastRunner Level %d (%.0f%%, Cost %d), PickUpRange Level %d (%.2f studs, Cost %d), FasterShrooms Level %d (%.0f%%, Cost %d), ShinySpore Level %d (%.0f%%, Cost %d)", 
		player.Name, fastRunnerLevel, speedBonus, fastRunnerCost, pickUpRangeLevel, pickUpRange, pickUpRangeCost, fasterShroomsLevel, shroomSpeedBonus * 100, fasterShroomsCost, shinySporeLevel, sporeValueBonus * 100, shinySporeUpgradeCost))

	return {
		currentFastRunnerLevel = fastRunnerLevel,
		currentSpeedBonus = speedBonus,
		fastRunnerCost = fastRunnerCost,
		currentPickUpRangeLevel = pickUpRangeLevel,
		currentPickUpRange = pickUpRange,
		pickUpRangeCost = pickUpRangeCost,
		currentFasterShroomsLevel = fasterShroomsLevel,
		currentShroomSpeedBonus = shroomSpeedBonus,
		fasterShroomsCost = fasterShroomsCost,
		currentShinySporeLevel = shinySporeLevel,
		currentSporeValueBonus = sporeValueBonus,
		shinySporeUpgradeCost = shinySporeUpgradeCost,
		currentGemHunterLevel = gemHunterLevel,
		currentGemDropBonus = gemDropBonus,
		gemHunterUpgradeCost = gemHunterUpgradeCost
	}
end

function ShopService:Cleanup()
	for connectionName, connection in pairs(self._connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._connections = {}
	self._playerUpgrades = {}

	Logger:Info("ShopService cleaned up")
end

function ShopService:_getTotalGemUpgrades(player)
	local playerUpgrades = self._playerUpgrades[player.UserId]
	if not playerUpgrades then
		return 0
	end
	
	-- Sum all gem upgrade levels (subtract 1 for each since base level is 1)
	local fastRunnerUpgrades = (playerUpgrades.fastRunnerLevel or 1) - 1
	local pickUpRangeUpgrades = (playerUpgrades.pickUpRangeLevel or 1) - 1
	local fasterShroomsUpgrades = (playerUpgrades.fasterShroomsLevel or 1) - 1
	local shinySporeUpgrades = (playerUpgrades.shinySporeLevel or 1) - 1
	local gemHunterUpgrades = (playerUpgrades.gemHunterLevel or 1) - 1
	
	return fastRunnerUpgrades + pickUpRangeUpgrades + fasterShroomsUpgrades + shinySporeUpgrades + gemHunterUpgrades
end

return ShopService