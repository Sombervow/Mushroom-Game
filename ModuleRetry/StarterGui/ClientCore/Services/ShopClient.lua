local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local ShopClient = {}
ShopClient.__index = ShopClient

function ShopClient.new()
	local self = setmetatable({}, ShopClient)
	self.player = Players.LocalPlayer
	self.playerGui = self.player:WaitForChild("PlayerGui")
	self._connections = {}
	self._remoteEvents = {}
	self._remoteFunctions = {}
	self._uiElements = {}
	self._collectionService = nil
	self:_initialize()
	return self
end

function ShopClient:_initialize()
	Logger:Info("ShopClient initializing...")

	-- Create shop opened bindable event
	local shopOpenedEvent = ReplicatedStorage:FindFirstChild("ShopOpened")
	if not shopOpenedEvent then
		shopOpenedEvent = Instance.new("BindableEvent")
		shopOpenedEvent.Name = "ShopOpened"
		shopOpenedEvent.Parent = ReplicatedStorage
	end

	-- Setup early sync IMMEDIATELY - don't wait for UI
	task.spawn(function()
		self:_setupEarlyShopSync()
		self:_setupEarlyGemShopSync()
	end)

	-- Wait for shop remote events and functions  
	task.spawn(function()
		self:_waitForRemoteFunctions()
		self:_setupShopButtons()
		self:_setupShopUIUpdates()
		self:_setupShopOpenListener()
	end)

	-- Setup gem shop buttons (remotes loaded in early sync)
	task.spawn(function()
		self:_setupAllGemShopButtons()
		self:_setupDevProductButtons()
	end)

	Logger:Info("✓ ShopClient initialized")
end

function ShopClient:_setupEarlyShopSync()
	-- Wait for shop events to be available as early as possible
	local shared = ReplicatedStorage:WaitForChild("Shared", 30)
	if not shared then
		Logger:Error("Shared folder not found for early shop sync")
		return
	end

	local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
	if not remoteEvents then
		Logger:Error("RemoteEvents not found for early shop sync")
		return
	end

	local shopEvents = remoteEvents:WaitForChild("ShopEvents", 10)
	if not shopEvents then
		Logger:Error("ShopEvents not found for early shop sync")
		return
	end

	local syncShopData = shopEvents:WaitForChild("SyncShopData", 10)
	if syncShopData then
		-- Connect sync listener immediately
		self._connections = self._connections or {}
		self._connections.EarlyShopSync = syncShopData.OnClientEvent:Connect(function(shopData)
			Logger:Info(string.format("EARLY shop sync received - SporeLevel: %d, MushroomCount: %d, Multiplier: %.2f", 
				shopData.currentSporeUpgradeLevel, shopData.currentMushroomCount, shopData.sporeMultiplier))

			-- Store the data immediately
			self._lastShopData = shopData

			-- Update UI immediately if elements exist AND shop is open
			if self._uiElements and (self._uiElements.sporeUpgrade or self._uiElements.mushroomPurchase) then
				local shopOpen = self:_isShopOpen()
				Logger:Info(string.format("Early sync check - Shop open: %s, Elements exist: %s", 
					tostring(shopOpen), 
					tostring(self._uiElements.sporeUpgrade ~= nil or self._uiElements.mushroomPurchase ~= nil)))
				if shopOpen then
					Logger:Info("Shop is open - updating UI immediately from early sync")
					self:_updateMushroomShopUI(shopData)
					Logger:Info("Mushroom shop UI updated immediately from early sync (shop is open)")
				else
					Logger:Info("Shop data cached for next UI update (shop is closed)")
				end
			else
				Logger:Info("UI elements not available or shop not open - data cached only")
			end
		end)

		-- Request sync immediately
		Logger:Info("Requesting shop data sync immediately...")
		syncShopData:FireServer()
	else
		Logger:Error("SyncShopData remote not found for early setup")
	end
end

function ShopClient:_setupEarlyFastRunnerSync()
	-- Wait for GemShopRemotes to be available as early as possible
	local gemShopRemotes = ReplicatedStorage:WaitForChild("GemShopRemotes", 30)
	if not gemShopRemotes then
		Logger:Error("GemShopRemotes not found for early sync setup")
		return
	end

	-- Get sync remotes as soon as they're available
	local syncFastRunner = gemShopRemotes:WaitForChild("SyncFastRunner", 10)
	local syncPickUpRange = gemShopRemotes:WaitForChild("SyncPickUpRange", 10)
	local syncFasterShrooms = gemShopRemotes:WaitForChild("SyncFasterShrooms", 10)
	local syncShinySpore = gemShopRemotes:WaitForChild("SyncShinySpore", 10)

	if syncFastRunner then
		-- Connect sync listener immediately
		self._connections = self._connections or {}
		self._connections.EarlySyncFastRunner = syncFastRunner.OnClientEvent:Connect(function(level, walkSpeed, speedPercent, cost)
			Logger:Info(string.format("EARLY FastRunner sync received - Level: %d, Speed: %.2f (%.0f%%), Cost: %d", level, walkSpeed, speedPercent, cost))

			-- Store the data immediately (merge with existing data)
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentFastRunnerLevel = level
			self._lastGemShopData.currentSpeedBonus = speedPercent
			self._lastGemShopData.fastRunnerCost = cost

			-- Update UI immediately if elements exist
			if self._uiElements and self._uiElements.fastRunner then
				self:_updateFastRunnerSection(self._lastGemShopData)
				Logger:Info("FastRunner UI updated immediately from early sync")
			end
		end)

		-- Request sync immediately
		Logger:Info("Requesting FastRunner sync immediately...")
		syncFastRunner:FireServer()
	else
		Logger:Error("SyncFastRunner remote not found for early setup")
	end

	if syncPickUpRange then
		-- Connect PickUpRange sync listener immediately
		self._connections = self._connections or {}
		self._connections.EarlySyncPickUpRange = syncPickUpRange.OnClientEvent:Connect(function(level, range, cost)
			Logger:Info(string.format("EARLY PickUpRange sync received - Level: %d, Range: %.2f studs, Cost: %d", level, range, cost))

			-- Store the data immediately (merge with existing data)
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentPickUpRangeLevel = level
			self._lastGemShopData.currentPickUpRange = range
			self._lastGemShopData.pickUpRangeCost = cost

			-- Update UI immediately if elements exist
			if self._uiElements and self._uiElements.pickUpRange then
				self:_updatePickUpRangeSection(self._lastGemShopData)
				Logger:Info("PickUpRange UI updated immediately from early sync")
			end

			-- Update actual collection radius
			if self._collectionService then
				self._collectionService:SetPickUpRange(range)
			end
		end)

		-- Request sync immediately
		Logger:Info("Requesting PickUpRange sync immediately...")
		syncPickUpRange:FireServer()
	else
		Logger:Error("SyncPickUpRange remote not found for early setup")
	end

	if syncFasterShrooms then
		-- Connect FasterShrooms sync listener immediately
		self._connections = self._connections or {}
		self._connections.EarlySyncFasterShrooms = syncFasterShrooms.OnClientEvent:Connect(function(level, speedBonus, cost)
			Logger:Info(string.format("EARLY FasterShrooms sync received - Level: %d, Speed Bonus: %.0f%%, Cost: %d", level, speedBonus * 100, cost))

			-- Store the data immediately (merge with existing data)
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentFasterShroomsLevel = level
			self._lastGemShopData.currentShroomSpeedBonus = speedBonus
			self._lastGemShopData.fasterShroomsCost = cost

			-- Update UI immediately if elements exist
			if self._uiElements and self._uiElements.fasterShrooms then
				self:_updateFasterShroomsSection(self._lastGemShopData)
				Logger:Info("FasterShrooms UI updated immediately from early sync")
			end
		end)

		-- Request sync immediately
		Logger:Info("Requesting FasterShrooms sync immediately...")
		syncFasterShrooms:FireServer()
	else
		Logger:Error("SyncFasterShrooms remote not found for early setup")
	end

	if syncShinySpore then
		-- Connect ShinySpore sync listener immediately
		self._connections = self._connections or {}
		self._connections.EarlySyncShinySpore = syncShinySpore.OnClientEvent:Connect(function(level, valueBonus, cost)
			Logger:Info(string.format("EARLY ShinySpore sync received - Level: %d, Value Bonus: %.0f%%, Cost: %d", level, valueBonus * 100, cost))

			-- Store the data immediately (merge with existing data)
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentShinySporeLevel = level
			self._lastGemShopData.currentSporeValueBonus = valueBonus
			self._lastGemShopData.shinySporeUpgradeCost = cost

			-- Update UI immediately if elements exist
			if self._uiElements and self._uiElements.shinySpore then
				self:_updateShinySporeSection(self._lastGemShopData)
				Logger:Info("ShinySpore UI updated immediately from early sync")
			end
		end)

		-- Request sync immediately
		Logger:Info("Requesting ShinySpore sync immediately...")
		syncShinySpore:FireServer()
	else
		Logger:Error("SyncShinySpore remote not found for early setup")
	end
end

function ShopClient:_setupAllGemShopButtons()
	-- Wait for GemShop UI (remotes already loaded in early sync)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gemShop = playerGui:WaitForChild("GemShop", 30)
	if not gemShop then
		Logger:Error("GemShop GUI not found for early button setup")
		return
	end

	local container = gemShop:WaitForChild("Container", 10)
	local shopContainer = container:WaitForChild("ShopContainer", 10)
	local gemShopInner = shopContainer:WaitForChild("GemShop", 10)
	local shroomBackground = gemShopInner:WaitForChild("ShroomBackground", 10)
	local scrollingFrame = shroomBackground:WaitForChild("ScrollingFrame", 10)

	if not scrollingFrame then
		Logger:Error("Could not find gem shop UI structure")
		return
	end

	-- Setup all gem upgrades with unified system
	local upgradeConfigs = {
		{
			name = "FastRunner",
			containerName = "FastRunner",
			buttonName = "PurchaseFastRunner",
			purchaseMethod = "_purchaseFastRunner"
		},
		{
			name = "PickUpRange", 
			containerName = "PickUpRange",
			buttonName = "PurchaseRangeBoost",
			purchaseMethod = "_purchasePickUpRange"
		},
		{
			name = "FasterShrooms",
			containerName = "FasterShrooms", 
			buttonName = "FasterShroomsButton",
			purchaseMethod = "_purchaseFasterShrooms"
		},
		{
			name = "ShinySpore",
			containerName = "ShinySpore",
			buttonName = "PurchaseSporeBoost", 
			purchaseMethod = "_purchaseShinySpore"
		},
		{
			name = "GemHunter",
			containerName = "GemHunter",
			buttonName = "PurchaseGemHunter", 
			purchaseMethod = "_purchaseGemHunter"
		}
	}

	-- Initialize UI elements and connections
	self._uiElements = self._uiElements or {}
	self._connections = self._connections or {}
	self._remoteEvents = self._remoteEvents or {}

	for _, config in pairs(upgradeConfigs) do
		local upgradeContainer = scrollingFrame:WaitForChild(config.containerName, 10)
		if upgradeContainer then
			local purchaseButton = upgradeContainer:WaitForChild(config.buttonName, 10)
			if purchaseButton and purchaseButton:IsA("GuiButton") then
				-- Connect button
				self._connections[config.name .. "Button"] = purchaseButton.MouseButton1Click:Connect(function()
					if self[config.purchaseMethod] then
						self[config.purchaseMethod](self)
					else
						Logger:Error(string.format("Purchase method %s not found!", config.purchaseMethod))
					end
				end)

				-- Store UI elements (using camelCase to match existing pattern)
				local elementKey = config.name:sub(1,1):lower() .. config.name:sub(2)
				self._uiElements[elementKey] = {
					container = upgradeContainer,
					button = purchaseButton,
					upgradeLevel = upgradeContainer:FindFirstChild("UpgradeLevel"),
					nextUpgrade = upgradeContainer:FindFirstChild("NextUpgrade"),
					gemCost = purchaseButton:FindFirstChild("GemCost")
				}

				-- If we already have data cached, update UI immediately now that elements exist
				if self._lastGemShopData then
					self:_tryUpdateSingleUpgrade(config.name)
				end

				Logger:Info(string.format("✓ %s button setup complete (early)", config.name))
			else
				Logger:Error(string.format("%s button not found", config.buttonName))
			end
		else
			Logger:Error(string.format("%s container not found", config.containerName))
		end
	end

	Logger:Info("✓ All gem shop buttons setup complete (early)")
end


function ShopClient:_tryUpdateSingleUpgrade(upgradeName)
	-- Helper function to update a single upgrade if both data and UI elements exist
	if not self._lastGemShopData then
		return
	end

	-- Use same key format as UI element storage
	local elementKey = upgradeName:sub(1,1):lower() .. upgradeName:sub(2)
	if not self._uiElements or not self._uiElements[elementKey] then
		return
	end

	-- Map upgrade names to their update functions
	local updateFunctions = {
		FastRunner = "_updateFastRunnerSection",
		PickUpRange = "_updatePickUpRangeSection", 
		FasterShrooms = "_updateFasterShroomsSection",
		ShinySpore = "_updateShinySporeSection",
		GemHunter = "_updateGemHunterSection"
	}

	local updateFunction = updateFunctions[upgradeName]
	if updateFunction and self[updateFunction] then
		self[updateFunction](self, self._lastGemShopData)
		Logger:Info(string.format("%s UI updated immediately after elements created", upgradeName))
	else
		Logger:Warn(string.format("Update function %s not found for %s", updateFunction, upgradeName))
	end
end

function ShopClient:_waitForRemoteEvents()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	if not shared then
		Logger:Error("Shared folder not found")
		return
	end

	local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
	if not remoteEvents then
		Logger:Error("RemoteEvents folder not found")
		return
	end

	local shopEvents = remoteEvents:WaitForChild("ShopEvents", 10)
	if not shopEvents then
		Logger:Error("ShopEvents folder not found")
		return
	end

	-- Get shop remote events
	self._remoteEvents.PurchaseSporeUpgrade = shopEvents:WaitForChild("PurchaseSporeUpgrade", 10)
	self._remoteEvents.PurchaseArea2SporeUpgrade = shopEvents:WaitForChild("PurchaseArea2SporeUpgrade", 10)
	self._remoteEvents.PurchaseMushroom = shopEvents:WaitForChild("PurchaseMushroom", 10)
	self._remoteEvents.PurchaseArea2 = shopEvents:WaitForChild("PurchaseArea2", 10)
	self._remoteEvents.PurchaseArea3 = shopEvents:WaitForChild("PurchaseArea3", 30)
	if not self._remoteEvents.PurchaseArea3 then
		Logger:Error("Failed to find PurchaseArea3 remote event after 30 seconds")
	else
		Logger:Info("Successfully connected to PurchaseArea3 remote event")
	end
	self._remoteEvents.ShopDataUpdated = shopEvents:WaitForChild("ShopDataUpdated", 10)
	-- Separate mushroom shop remote events (optional - fallback to existing PurchaseMushroom)
	self._remoteEvents.PurchaseArea1Mushroom = shopEvents:FindFirstChild("PurchaseArea1Mushroom")
	self._remoteEvents.PurchaseArea2Mushroom = shopEvents:FindFirstChild("PurchaseArea2Mushroom")
	self._remoteEvents.PurchaseArea3Mushroom = shopEvents:FindFirstChild("PurchaseArea3Mushroom")

	-- Get gem shop remote events from GemShopRemotes folder
	local gemShopRemotes = ReplicatedStorage:WaitForChild("GemShopRemotes", 10)
	if gemShopRemotes then
		self._remoteEvents.PurchaseFastRunner = gemShopRemotes:WaitForChild("PurchaseFastRunner", 10)
		self._remoteEvents.SyncFastRunner = gemShopRemotes:WaitForChild("SyncFastRunner", 10)
		self._remoteEvents.FastRunnerConfirm = gemShopRemotes:WaitForChild("FastRunnerConfirm", 10)
		self._remoteEvents.PurchasePickUpRange = gemShopRemotes:WaitForChild("PurchasePickUpRange", 10)
		self._remoteEvents.SyncPickUpRange = gemShopRemotes:WaitForChild("SyncPickUpRange", 10)
		self._remoteEvents.PickUpRangeConfirm = gemShopRemotes:WaitForChild("PickUpRangeConfirm", 10)
		self._remoteEvents.PurchaseFasterShrooms = gemShopRemotes:WaitForChild("PurchaseFasterShrooms", 10)
		self._remoteEvents.SyncFasterShrooms = gemShopRemotes:WaitForChild("SyncFasterShrooms", 10)
		self._remoteEvents.FasterShroomsConfirm = gemShopRemotes:WaitForChild("FasterShroomsConfirm", 10)
		self._remoteEvents.PurchaseShinySpore = gemShopRemotes:WaitForChild("PurchaseShinySpore", 10)
		self._remoteEvents.SyncShinySpore = gemShopRemotes:WaitForChild("SyncShinySpore", 10)
		self._remoteEvents.ShinySporeConfirm = gemShopRemotes:WaitForChild("ShinySporeConfirm", 10)
		self._remoteEvents.PurchaseGemHunter = gemShopRemotes:WaitForChild("PurchaseGemHunter", 10)
		self._remoteEvents.SyncGemHunter = gemShopRemotes:WaitForChild("SyncGemHunter", 10)
		self._remoteEvents.GemHunterConfirm = gemShopRemotes:WaitForChild("GemHunterConfirm", 10)
		Logger:Info("✓ Gem shop remote events connected")
	else
		Logger:Error("GemShopRemotes folder not found")
	end

	self._remoteEvents.GemShopDataUpdated = shopEvents:WaitForChild("GemShopDataUpdated", 10)

	if self._remoteEvents.PurchaseSporeUpgrade and self._remoteEvents.PurchaseMushroom and self._remoteEvents.ShopDataUpdated then
		Logger:Info("✓ Shop remote events connected")

		-- Listen for shop data updates
		self._connections.ShopDataUpdated = self._remoteEvents.ShopDataUpdated.OnClientEvent:Connect(function(shopData)
			Logger:Info("Received shop data update")
			
			-- Only refresh UI if shop is open and we received full shop data (not minimal tutorial data)
			if self:_isShopOpen() and shopData and shopData.sporeUpgradeCost then
				Logger:Info("Refreshing shop UI...")
				self:_updateShopUI()
			end
			
			-- Forward shopData to tutorial system if it exists (for tutorial tracking)
			if _G.TutorialSystem and _G.TutorialSystem.onShopDataUpdate and shopData then
				_G.TutorialSystem.onShopDataUpdate(shopData)
			end
		end)

		-- Listen for gem shop data updates
		if self._remoteEvents.GemShopDataUpdated then
			self._connections.GemShopDataUpdated = self._remoteEvents.GemShopDataUpdated.OnClientEvent:Connect(function()
				Logger:Info("Received gem shop data update, refreshing UI...")
				if self:_isGemShopOpen() then
					self:_updateGemShopUI()
				end
				
				-- Forward gem shop data update to tutorial system
				if _G.TutorialSystem and _G.TutorialSystem.onGemShopDataUpdate and self._lastGemShopData then
					_G.TutorialSystem.onGemShopDataUpdate(self._lastGemShopData)
				end
			end)
		end

		-- Listen for FastRunner sync and confirm events (skip if early sync already connected)
		if self._remoteEvents.SyncFastRunner and not self._connections.EarlySyncFastRunner then
			self._connections.SyncFastRunner = self._remoteEvents.SyncFastRunner.OnClientEvent:Connect(function(level, walkSpeed, speedPercent, cost)
				Logger:Info(string.format("FastRunner sync received - Level: %d, Speed: %.2f (%.0f%%), Cost: %d", level, walkSpeed, speedPercent, cost))

				-- Update gem shop data with FastRunner info (merge with existing data)
				self._lastGemShopData = self._lastGemShopData or {}
				self._lastGemShopData.currentFastRunnerLevel = level
				self._lastGemShopData.currentSpeedBonus = speedPercent
				self._lastGemShopData.fastRunnerCost = cost

				-- Always update UI immediately when sync is received, regardless of shop state
				if self._uiElements.fastRunner then
					self:_updateFastRunnerSection(self._lastGemShopData)
					Logger:Info("FastRunner UI updated immediately after sync")
				end
			end)
		end

		if self._remoteEvents.FastRunnerConfirm then
			self._connections.FastRunnerConfirm = self._remoteEvents.FastRunnerConfirm.OnClientEvent:Connect(function(newLevel, newWalkSpeed, newSpeedPercent)
				Logger:Info(string.format("FastRunner purchase confirmed! Level: %d, Speed: %.2f (%.0f%%)", newLevel, newWalkSpeed, newSpeedPercent))

				-- Update gem shop data with new FastRunner info (merge with existing data)
				self._lastGemShopData = self._lastGemShopData or {}
				self._lastGemShopData.currentFastRunnerLevel = newLevel
				self._lastGemShopData.currentSpeedBonus = newSpeedPercent
				-- Cost will be updated by next sync

				-- Always update UI immediately when purchase is confirmed
				if self._uiElements.fastRunner then
					self:_updateFastRunnerSection(self._lastGemShopData)
					Logger:Info("FastRunner UI updated immediately after purchase confirmation")
				end

				-- Request fresh sync to get updated cost
				if self._remoteEvents.SyncFastRunner then
					self._remoteEvents.SyncFastRunner:FireServer()
				end
			end)
		end

		-- Listen for PickUpRange sync and confirm events (skip if early sync already connected)
		if self._remoteEvents.SyncPickUpRange and not self._connections.EarlySyncPickUpRange then
			self._connections.SyncPickUpRange = self._remoteEvents.SyncPickUpRange.OnClientEvent:Connect(function(level, range, cost)
				Logger:Info(string.format("PickUpRange sync received - Level: %d, Range: %.2f studs, Cost: %d", level, range, cost))

				-- Update gem shop data with PickUpRange info (merge with existing data)
				self._lastGemShopData = self._lastGemShopData or {}
				self._lastGemShopData.currentPickUpRangeLevel = level
				self._lastGemShopData.currentPickUpRange = range
				self._lastGemShopData.pickUpRangeCost = cost

				-- Always update UI immediately when sync is received
				if self._uiElements.pickUpRange then
					self:_updatePickUpRangeSection(self._lastGemShopData)
					Logger:Info("PickUpRange UI updated immediately after sync")
				end

				-- Update actual collection radius
				if self._collectionService then
					self._collectionService:SetPickUpRange(range)
				end
			end)
		end

		if self._remoteEvents.PickUpRangeConfirm then
			self._connections.PickUpRangeConfirm = self._remoteEvents.PickUpRangeConfirm.OnClientEvent:Connect(function(newLevel, newRange)
				Logger:Info(string.format("PickUpRange purchase confirmed! Level: %d, Range: %.2f studs", newLevel, newRange))

				-- Update gem shop data with new PickUpRange info (merge with existing data)
				self._lastGemShopData = self._lastGemShopData or {}
				self._lastGemShopData.currentPickUpRangeLevel = newLevel
				self._lastGemShopData.currentPickUpRange = newRange
				-- Cost will be updated by next sync

				-- Always update UI immediately when purchase is confirmed
				if self._uiElements.pickUpRange then
					self:_updatePickUpRangeSection(self._lastGemShopData)
					Logger:Info("PickUpRange UI updated immediately after purchase confirmation")
				end

				-- Request fresh sync to get updated cost
				if self._remoteEvents.SyncPickUpRange then
					self._remoteEvents.SyncPickUpRange:FireServer()
				end

				-- Update actual collection radius
				if self._collectionService then
					self._collectionService:SetPickUpRange(newRange)
				end
			end)
		end

		-- Listen for FasterShrooms sync and confirm events (skip if early sync already connected)
		if self._remoteEvents.SyncFasterShrooms and not self._connections.EarlySyncFasterShrooms then
			self._connections.SyncFasterShrooms = self._remoteEvents.SyncFasterShrooms.OnClientEvent:Connect(function(level, speedBonus, cost)
				Logger:Info(string.format("FasterShrooms sync received - Level: %d, Speed Bonus: %.0f%%, Cost: %d", level, speedBonus * 100, cost))

				-- Update gem shop data with FasterShrooms info (merge with existing data)
				self._lastGemShopData = self._lastGemShopData or {}
				self._lastGemShopData.currentFasterShroomsLevel = level
				self._lastGemShopData.currentShroomSpeedBonus = speedBonus
				self._lastGemShopData.fasterShroomsCost = cost

				-- Always update UI immediately when sync is received
				if self._uiElements.fasterShrooms then
					self:_updateFasterShroomsSection(self._lastGemShopData)
					Logger:Info("FasterShrooms UI updated immediately after sync")
				end
			end)
		end

		if self._remoteEvents.FasterShroomsConfirm then
			self._connections.FasterShroomsConfirm = self._remoteEvents.FasterShroomsConfirm.OnClientEvent:Connect(function(newLevel, newSpeedBonus)
				Logger:Info(string.format("FasterShrooms purchase confirmed! Level: %d, Speed Bonus: %.0f%%", newLevel, newSpeedBonus * 100))

				-- Update gem shop data with new FasterShrooms info (merge with existing data)
				self._lastGemShopData = self._lastGemShopData or {}
				self._lastGemShopData.currentFasterShroomsLevel = newLevel
				self._lastGemShopData.currentShroomSpeedBonus = newSpeedBonus
				-- Cost will be updated by next sync

				-- Always update UI immediately when purchase is confirmed
				if self._uiElements.fasterShrooms then
					self:_updateFasterShroomsSection(self._lastGemShopData)
					Logger:Info("FasterShrooms UI updated immediately after purchase confirmation")
				end

				-- Request fresh sync to get updated cost
				if self._remoteEvents.SyncFasterShrooms then
					self._remoteEvents.SyncFasterShrooms:FireServer()
				end
			end)
		end

		-- Listen for ShinySpore sync and confirm events (skip if early sync already connected)
		if self._remoteEvents.SyncShinySpore and not self._connections.EarlySyncShinySpore then
			self._connections.SyncShinySpore = self._remoteEvents.SyncShinySpore.OnClientEvent:Connect(function(level, valueBonus, cost)
				Logger:Info(string.format("ShinySpore sync received - Level: %d, Value Bonus: %.0f%%, Cost: %d", level, valueBonus * 100, cost))

				-- Update gem shop data with ShinySpore info (merge with existing data)
				self._lastGemShopData = self._lastGemShopData or {}
				self._lastGemShopData.currentShinySporeLevel = level
				self._lastGemShopData.currentSporeValueBonus = valueBonus
				self._lastGemShopData.shinySporeUpgradeCost = cost

				-- Always update UI immediately when sync is received
				if self._uiElements.shinySpore then
					self:_updateShinySporeSection(self._lastGemShopData)
					Logger:Info("ShinySpore UI updated immediately after sync")
				end
			end)
		end

		if self._remoteEvents.ShinySporeConfirm then
			self._connections.ShinySporeConfirm = self._remoteEvents.ShinySporeConfirm.OnClientEvent:Connect(function(newLevel, newValueBonus)
				Logger:Info(string.format("ShinySpore purchase confirmed! Level: %d, Value Bonus: %.0f%%", newLevel, newValueBonus * 100))

				-- Update gem shop data with new ShinySpore info (merge with existing data)
				self._lastGemShopData = self._lastGemShopData or {}
				self._lastGemShopData.currentShinySporeLevel = newLevel
				self._lastGemShopData.currentSporeValueBonus = newValueBonus
				-- Cost will be updated by next sync

				-- Always update UI immediately when purchase is confirmed
				if self._uiElements.shinySpore then
					self:_updateShinySporeSection(self._lastGemShopData)
					Logger:Info("ShinySpore UI updated immediately after purchase confirmation")
				end

				-- Request fresh sync to get updated cost
				if self._remoteEvents.SyncShinySpore then
					self._remoteEvents.SyncShinySpore:FireServer()
				end
			end)
		end
	else
		Logger:Error("Failed to connect to shop remote events")
	end
end

function ShopClient:_waitForRemoteFunctions()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	if not shared then
		Logger:Error("Shared folder not found")
		return
	end

	local remoteFunctions = shared:WaitForChild("RemoteFunctions", 10)
	if not remoteFunctions then
		Logger:Error("RemoteFunctions folder not found")
		return
	end

	-- Get shop data remote function
	self._remoteFunctions.GetShopData = remoteFunctions:WaitForChild("GetShopData", 30)
	self._remoteFunctions.GetGemShopData = remoteFunctions:WaitForChild("GetGemShopData", 30)

	if self._remoteFunctions.GetShopData and self._remoteFunctions.GetGemShopData then
		Logger:Info("✓ Shop remote functions connected")
	else
		Logger:Error("Failed to connect to shop remote functions")
		-- Log which specific functions failed
		if not self._remoteFunctions.GetShopData then
			Logger:Error("GetShopData remote function not found")
		end
		if not self._remoteFunctions.GetGemShopData then
			Logger:Error("GetGemShopData remote function not found")
		end
	end

	-- Also load RemoteEvents for spore shop
	local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
	if not remoteEvents then
		Logger:Error("RemoteEvents folder not found")
		return
	end

	local shopEvents = remoteEvents:WaitForChild("ShopEvents", 10)
	if not shopEvents then
		Logger:Error("ShopEvents folder not found")
		return
	end

	-- Get spore shop remote events
	self._remoteEvents.PurchaseSporeUpgrade = shopEvents:WaitForChild("PurchaseSporeUpgrade", 10)
	self._remoteEvents.PurchaseArea2SporeUpgrade = shopEvents:WaitForChild("PurchaseArea2SporeUpgrade", 10)
	self._remoteEvents.PurchaseMushroom = shopEvents:WaitForChild("PurchaseMushroom", 10)
	self._remoteEvents.PurchaseArea2 = shopEvents:WaitForChild("PurchaseArea2", 10)
	self._remoteEvents.PurchaseArea3 = shopEvents:WaitForChild("PurchaseArea3", 30)
	self._remoteEvents.ShopDataUpdated = shopEvents:WaitForChild("ShopDataUpdated", 10)

	if self._remoteEvents.PurchaseSporeUpgrade and self._remoteEvents.PurchaseMushroom then
		Logger:Info("✓ Spore shop remote events connected")
	else
		Logger:Error("Failed to connect to spore shop remote events")
	end
end

function ShopClient:_setupShopButtons()
	-- Wait for MushroomShop GUI
	local mushroomShop = self.playerGui:WaitForChild("MushroomShop", 30)
	if not mushroomShop then
		Logger:Error("MushroomShop GUI not found")
		return
	end

	Logger:Info("MushroomShop GUI found, setting up buttons...")

	-- Navigate to the spore upgrade button: Container > ShopContainer > ShroomShop > ShroomBackground > ScrollingFrame > BuxLevel > PurchaseSporeUpgrade
	local container = mushroomShop:WaitForChild("Container", 5)
	if not container then
		Logger:Error("Container not found in MushroomShop")
		return
	end

	local shopContainer = container:WaitForChild("ShopContainer", 5)
	if not shopContainer then
		Logger:Error("ShopContainer not found")
		return
	end

	local shroomShop = shopContainer:WaitForChild("ShroomShop", 5)
	if not shroomShop then
		Logger:Error("ShroomShop not found")
		return
	end

	local shroomBackground = shroomShop:WaitForChild("ShroomBackground", 5)
	if not shroomBackground then
		Logger:Error("ShroomBackground not found")
		return
	end

	local scrollingFrame = shroomBackground:WaitForChild("ScrollingFrame", 5)
	if not scrollingFrame then
		Logger:Error("ScrollingFrame not found")
		return
	end

	-- Setup spore upgrade button and store UI references
	local buxLevel = scrollingFrame:WaitForChild("BuxLevel", 5)
	if buxLevel then
		local purchaseSporeUpgrade = buxLevel:WaitForChild("PurchaseSporeUpgrade", 5)
		if purchaseSporeUpgrade and purchaseSporeUpgrade:IsA("GuiButton") then
			Logger:Info("Found PurchaseSporeUpgrade button, connecting...")
			local connection = purchaseSporeUpgrade.MouseButton1Click:Connect(function()
				self:_purchaseSporeUpgrade()
			end)
			table.insert(self._connections, connection)

			-- Store UI element references for spore upgrade section
			self._uiElements.sporeUpgrade = {
				container = buxLevel,
				button = purchaseSporeUpgrade,
				sporeLevel = buxLevel:FindFirstChild("SporeLevel"),
				sporeTracker = buxLevel:FindFirstChild("SporeTracker"),
				sporeCost = purchaseSporeUpgrade:FindFirstChild("SporeCost")
			}

			Logger:Info("✓ PurchaseSporeUpgrade button connected")
		else
			Logger:Error("PurchaseSporeUpgrade button not found or not a GuiButton")
		end
	else
		Logger:Error("BuxLevel not found")
	end

	-- Setup mushroom purchase button and store UI references
	local shroomLevelBox = scrollingFrame:WaitForChild("ShroomLevelBox", 5)
	if shroomLevelBox then
		local purchaseShroom = shroomLevelBox:WaitForChild("PurchaseShroom", 5)
		if purchaseShroom and purchaseShroom:IsA("GuiButton") then
			Logger:Info("Found PurchaseShroom button, connecting...")
			local connection = purchaseShroom.MouseButton1Click:Connect(function()
				-- Determine which area's shop is being used based on player position
				local area = self:_determineCurrentShopArea()
				self:_purchaseMushroom(area)
			end)
			table.insert(self._connections, connection)

			-- Store UI element references for mushroom purchase section
			self._uiElements.mushroomPurchase = {
				container = shroomLevelBox,
				button = purchaseShroom,
				shroomLevel = shroomLevelBox:FindFirstChild("ShroomLevel"),
				shroomTracker = shroomLevelBox:FindFirstChild("ShroomTracker"),
				shroomCost = purchaseShroom:FindFirstChild("ShroomCost")
			}

			Logger:Info("✓ PurchaseShroom button connected")
		else
			Logger:Error("PurchaseShroom button not found or not a GuiButton")
		end
	else
		Logger:Error("ShroomLevelBox not found")
	end

	-- Setup Area2 purchase button
	self:_setupArea2PurchaseButton()

	-- Setup Area3 purchase button
	self:_setupArea3PurchaseButton()

	-- Setup separate mushroom shop buttons
	self:_setupMushroomShop2Buttons()
	self:_setupMushroomShop3Buttons()

	Logger:Info("Shop button setup complete")
end

function ShopClient:_setupMushroomShop2Buttons()
	-- Wait for MushroomShop2 GUI
	local mushroomShop2 = self.playerGui:WaitForChild("MushroomShop2", 5)
	if not mushroomShop2 then
		Logger:Warn("MushroomShop2 GUI not found - separate mushroom shops will not work")
		return
	end

	Logger:Info("MushroomShop2 GUI found, setting up buttons...")

	-- Navigate to the same structure as the original shop
	local container = mushroomShop2:WaitForChild("Container", 5)
	if not container then
		Logger:Error("Container not found in MushroomShop2")
		return
	end

	local shopContainer = container:WaitForChild("ShopContainer", 5)
	if not shopContainer then
		Logger:Error("ShopContainer not found in MushroomShop2")
		return
	end

	local shroomShop = shopContainer:WaitForChild("ShroomShop", 5)
	if not shroomShop then
		Logger:Error("ShroomShop not found in MushroomShop2")
		return
	end

	local shroomBackground = shroomShop:WaitForChild("ShroomBackground", 5)
	if not shroomBackground then
		Logger:Error("ShroomBackground not found in MushroomShop2")
		return
	end

	local scrollingFrame = shroomBackground:WaitForChild("ScrollingFrame", 5)
	if not scrollingFrame then
		Logger:Error("ScrollingFrame not found in MushroomShop2")
		return
	end

	-- Setup Area2 spore upgrade button (MushroomShop2 uses Area2 spore upgrades)
	local buxLevel = scrollingFrame:WaitForChild("BuxLevel", 5)
	if buxLevel then
		local purchaseSporeUpgrade = buxLevel:WaitForChild("PurchaseSporeUpgrade", 5)
		if purchaseSporeUpgrade and purchaseSporeUpgrade:IsA("GuiButton") then
			Logger:Info("Found MushroomShop2 spore upgrade button, connecting to Area2 spore purchases...")
			local connection = purchaseSporeUpgrade.MouseButton1Click:Connect(function()
				self:_purchaseArea2SporeUpgrade()
			end)
			table.insert(self._connections, connection)

			-- Store UI element references for area2 spore upgrade section
			self._uiElements.area2SporeUpgrade = {
				container = buxLevel,
				button = purchaseSporeUpgrade,
				sporeLevel = buxLevel:FindFirstChild("SporeLevel"),
				sporeTracker = buxLevel:FindFirstChild("SporeTracker"),
				sporeCost = purchaseSporeUpgrade:FindFirstChild("SporeCost")
			}

			Logger:Info("✓ MushroomShop2 spore upgrade button connected to Area2 purchases")
		else
			Logger:Error("MushroomShop2 spore upgrade button not found or not a GuiButton")
		end
	else
		Logger:Error("BuxLevel not found in MushroomShop2")
	end

	-- Setup Area2 mushroom purchase button (MushroomShop2 only buys Area2 mushrooms)
	local shroomLevelBox = scrollingFrame:WaitForChild("ShroomLevelBox", 5)
	if shroomLevelBox then
		local purchaseShroom = shroomLevelBox:WaitForChild("PurchaseShroom", 5)
		if purchaseShroom and purchaseShroom:IsA("GuiButton") then
			Logger:Info("Found MushroomShop2 purchase button, connecting to Area2 purchases...")
			local connection = purchaseShroom.MouseButton1Click:Connect(function()
				self:_purchaseArea2Mushroom()
			end)
			table.insert(self._connections, connection)

			-- Store UI element references for area2 mushroom purchase section
			self._uiElements.area2MushroomPurchase = {
				container = shroomLevelBox,
				button = purchaseShroom,
				shroomLevel = shroomLevelBox:FindFirstChild("ShroomLevel"),
				shroomTracker = shroomLevelBox:FindFirstChild("ShroomTracker"),
				shroomCost = purchaseShroom:FindFirstChild("ShroomCost")
			}

			Logger:Info("✓ MushroomShop2 button connected to Area2 purchases")
		else
			Logger:Error("MushroomShop2 purchase button not found or not a GuiButton")
		end
	else
		Logger:Error("ShroomLevelBox not found in MushroomShop2")
	end

	Logger:Info("✓ MushroomShop2 buttons setup complete")
end

function ShopClient:_setupMushroomShop3Buttons()
	-- Wait for MushroomShop3 GUI
	local mushroomShop3 = self.playerGui:WaitForChild("MushroomShop3", 5)
	if not mushroomShop3 then
		Logger:Warn("MushroomShop3 GUI not found - Area3 mushroom shop will not work")
		return
	end

	Logger:Info("MushroomShop3 GUI found, setting up buttons...")

	-- Navigate to the same structure as the original shop
	local container = mushroomShop3:WaitForChild("Container", 5)
	if not container then
		Logger:Error("Container not found in MushroomShop3")
		return
	end

	local shopContainer = container:WaitForChild("ShopContainer", 5)
	if not shopContainer then
		Logger:Error("ShopContainer not found in MushroomShop3")
		return
	end

	local shroomShop = shopContainer:WaitForChild("ShroomShop", 5)
	if not shroomShop then
		Logger:Error("ShroomShop not found in MushroomShop3")
		return
	end

	local shroomBackground = shroomShop:WaitForChild("ShroomBackground", 5)
	if not shroomBackground then
		Logger:Error("ShroomBackground not found in MushroomShop3")
		return
	end

	local scrollingFrame = shroomBackground:WaitForChild("ScrollingFrame", 5)
	if not scrollingFrame then
		Logger:Error("ScrollingFrame not found in MushroomShop3")
		return
	end

	-- Setup Area3 spore upgrade button (MushroomShop3 uses Area3 spore upgrades - if they exist)
	local buxLevel = scrollingFrame:WaitForChild("BuxLevel", 5)
	if buxLevel then
		local purchaseSporeUpgrade = buxLevel:WaitForChild("PurchaseSporeUpgrade", 5)
		if purchaseSporeUpgrade and purchaseSporeUpgrade:IsA("GuiButton") then
			Logger:Info("Found MushroomShop3 spore upgrade button, connecting to Area3 spore purchases...")
			local connection = purchaseSporeUpgrade.MouseButton1Click:Connect(function()
				-- For now, Area3 doesn't have separate spore upgrades, so this might not be used
				Logger:Info("Area3 spore upgrade clicked (not implemented yet)")
			end)
			table.insert(self._connections, connection)

			-- Store UI element references for area3 spore upgrade section (if needed)
			self._uiElements.area3SporeUpgrade = {
				container = buxLevel,
				button = purchaseSporeUpgrade,
				sporeLevel = buxLevel:FindFirstChild("SporeLevel"),
				sporeBonus = buxLevel:FindFirstChild("SporeBonus"),
				sporeCost = buxLevel:FindFirstChild("SporeCost")
			}

			Logger:Info("✓ MushroomShop3 spore upgrade button connected to Area3 purchases")
		else
			Logger:Error("MushroomShop3 spore upgrade button not found or not a GuiButton")
		end
	else
		Logger:Error("BuxLevel not found in MushroomShop3")
	end

	-- Setup Area3 mushroom purchase button (MushroomShop3 only buys Area3 mushrooms)
	local shroomLevelBox = scrollingFrame:WaitForChild("ShroomLevelBox", 5)
	if shroomLevelBox then
		local purchaseShroom = shroomLevelBox:WaitForChild("PurchaseShroom", 5)
		if purchaseShroom and purchaseShroom:IsA("GuiButton") then
			Logger:Info("Found MushroomShop3 purchase button, connecting to Area3 purchases...")
			local connection = purchaseShroom.MouseButton1Click:Connect(function()
				self:_purchaseArea3Mushroom()
			end)
			table.insert(self._connections, connection)

			-- Store UI element references for area3 mushroom purchase section
			self._uiElements.area3MushroomPurchase = {
				container = shroomLevelBox,
				button = purchaseShroom,
				shroomLevel = shroomLevelBox:FindFirstChild("ShroomLevel"),
				shroomTracker = shroomLevelBox:FindFirstChild("ShroomTracker"),
				shroomCost = shroomLevelBox:FindFirstChild("ShroomCost")
			}

			Logger:Info("✓ MushroomShop3 button connected to Area3 purchases")
		else
			Logger:Error("MushroomShop3 purchase button not found or not a GuiButton")
		end
	else
		Logger:Error("ShroomLevelBox not found in MushroomShop3")
	end

	Logger:Info("✓ MushroomShop3 buttons setup complete")
end

function ShopClient:_setupShopUIUpdates()
	-- Listen for shop opening to update UI
	local clientCore = self.playerGui.Parent:FindFirstChild("ClientCore")
	local uiManager = nil
	if clientCore then
		local services = clientCore:FindFirstChild("Services")
		if services then
			uiManager = services:FindFirstChild("UIManager")
		end
	end

	-- Set up currency update listener
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	if shared then
		local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
		if remoteEvents then
			local dataEvents = remoteEvents:WaitForChild("DataEvents", 10)
			if dataEvents then
				local currencyUpdated = dataEvents:WaitForChild("CurrencyUpdated", 10)
				if currencyUpdated then
					self._connections.CurrencyUpdated = currencyUpdated.OnClientEvent:Connect(function(currencyType, newAmount)
						-- Update UI when currency changes
						if self:_isShopOpen() then
							self:_updateShopUI()
						end
						-- Update gem shop UI when gems change
						if currencyType == "Gems" and self:_isGemShopOpen() then
							self:_updateGemShopUI()
						end
					end)
				end
			end
		end
	end

	-- Also listen directly to gems leaderstats for immediate gem shop updates
	task.spawn(function()
		local leaderstats = self.player:WaitForChild("leaderstats", 10)
		if leaderstats then
			local gems = leaderstats:WaitForChild("Gems", 10)
			if gems then
				self._connections.GemsChanged = gems.Changed:Connect(function()
					-- Update gem shop affordability immediately when gems change
					if self:_isGemShopOpen() then
						self:_updateGemShopAffordability()
					end
				end)
				Logger:Info("✓ Direct gems listener connected")
			end
			
			-- Also listen to spores for mushroom shop affordability
			local spores = leaderstats:WaitForChild("Spores", 10)
			if spores then
				self._connections.SporesChanged = spores.Changed:Connect(function()
					-- Update mushroom shop affordability immediately when spores change
					if self:_isShopOpen() then
						self:_updateMushroomShopAffordability()
					end
				end)
				Logger:Info("✓ Direct spores listener connected")
			end
		end
	end)

	Logger:Info("✓ Shop UI update system configured")
end

function ShopClient:_setupEarlyGemShopSync()
	-- Wait for GemShopRemotes and setup ALL early sync in one place
	local gemShopRemotes = ReplicatedStorage:WaitForChild("GemShopRemotes", 30)
	if not gemShopRemotes then
		Logger:Error("GemShopRemotes not found for early sync setup")
		return
	end

	-- Initialize remote events table
	self._remoteEvents = self._remoteEvents or {}

	-- Load ALL gem shop remotes at once
	local syncFastRunner = gemShopRemotes:WaitForChild("SyncFastRunner", 10)
	local syncPickUpRange = gemShopRemotes:WaitForChild("SyncPickUpRange", 10)
	local syncFasterShrooms = gemShopRemotes:WaitForChild("SyncFasterShrooms", 10)
	local syncShinySpore = gemShopRemotes:WaitForChild("SyncShinySpore", 10)
	local syncGemHunter = gemShopRemotes:WaitForChild("SyncGemHunter", 10)

	local purchaseFastRunner = gemShopRemotes:WaitForChild("PurchaseFastRunner", 10)
	local purchasePickUpRange = gemShopRemotes:WaitForChild("PurchasePickUpRange", 10)
	local purchaseFasterShrooms = gemShopRemotes:WaitForChild("PurchaseFasterShrooms", 10)
	local purchaseShinySpore = gemShopRemotes:WaitForChild("PurchaseShinySpore", 10)
	local purchaseGemHunter = gemShopRemotes:WaitForChild("PurchaseGemHunter", 10)

	local fastRunnerConfirm = gemShopRemotes:WaitForChild("FastRunnerConfirm", 10)
	local pickUpRangeConfirm = gemShopRemotes:WaitForChild("PickUpRangeConfirm", 10)
	local fasterShroomsConfirm = gemShopRemotes:WaitForChild("FasterShroomsConfirm", 10)
	local shinySporeConfirm = gemShopRemotes:WaitForChild("ShinySporeConfirm", 10)
	local gemHunterConfirm = gemShopRemotes:WaitForChild("GemHunterConfirm", 10)

	-- Store all remotes
	self._remoteEvents.SyncFastRunner = syncFastRunner
	self._remoteEvents.SyncPickUpRange = syncPickUpRange
	self._remoteEvents.SyncFasterShrooms = syncFasterShrooms
	self._remoteEvents.SyncShinySpore = syncShinySpore
	self._remoteEvents.SyncGemHunter = syncGemHunter

	self._remoteEvents.PurchaseFastRunner = purchaseFastRunner
	self._remoteEvents.PurchasePickUpRange = purchasePickUpRange  
	self._remoteEvents.PurchaseFasterShrooms = purchaseFasterShrooms
	self._remoteEvents.PurchaseShinySpore = purchaseShinySpore
	self._remoteEvents.PurchaseGemHunter = purchaseGemHunter

	self._remoteEvents.FastRunnerConfirm = fastRunnerConfirm
	self._remoteEvents.PickUpRangeConfirm = pickUpRangeConfirm
	self._remoteEvents.FasterShroomsConfirm = fasterShroomsConfirm
	self._remoteEvents.ShinySporeConfirm = shinySporeConfirm
	self._remoteEvents.GemHunterConfirm = gemHunterConfirm

	-- Setup early sync connections for ALL upgrades
	if syncFastRunner then
		self._connections.EarlySyncFastRunner = syncFastRunner.OnClientEvent:Connect(function(level, walkSpeed, speedPercent, cost)
			Logger:Info(string.format("EARLY FastRunner sync received - Level: %d, Speed: %.2f (%.0f%%), Cost: %d", level, walkSpeed, speedPercent, cost))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentFastRunnerLevel = level
			self._lastGemShopData.currentSpeedBonus = speedPercent
			self._lastGemShopData.fastRunnerCost = cost
			if self._uiElements and self._uiElements.fastRunner then
				self:_updateFastRunnerSection(self._lastGemShopData)
				Logger:Info("FastRunner UI updated immediately from early sync")
			end
		end)
		syncFastRunner:FireServer()
	end

	if syncPickUpRange then
		self._connections.EarlySyncPickUpRange = syncPickUpRange.OnClientEvent:Connect(function(level, range, cost)
			Logger:Info(string.format("EARLY PickUpRange sync received - Level: %d, Range: %.2f studs, Cost: %d", level, range, cost))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentPickUpRangeLevel = level
			self._lastGemShopData.currentPickUpRange = range
			self._lastGemShopData.pickUpRangeCost = cost
			if self._uiElements and self._uiElements.pickUpRange then
				self:_updatePickUpRangeSection(self._lastGemShopData)
				Logger:Info("PickUpRange UI updated immediately from early sync")
			end

			-- Apply to CollectionService if it's linked and we have a flag set
			if self._collectionService and self._applyRangeWhenAvailable then
				Logger:Info(string.format("Applying PickUpRange from early sync: %.2f studs", range))
				self._collectionService:SetPickUpRange(range)
				self._applyRangeWhenAvailable = false
			end
		end)
		syncPickUpRange:FireServer()
	end

	if syncFasterShrooms then
		self._connections.EarlySyncFasterShrooms = syncFasterShrooms.OnClientEvent:Connect(function(level, speedBonus, cost)
			Logger:Info(string.format("EARLY FasterShrooms sync received - Level: %d, Speed Bonus: %.0f%%, Cost: %d", level, speedBonus * 100, cost))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentFasterShroomsLevel = level
			self._lastGemShopData.currentShroomSpeedBonus = speedBonus
			self._lastGemShopData.fasterShroomsCost = cost
			if self._uiElements and self._uiElements.fasterShrooms then
				self:_updateFasterShroomsSection(self._lastGemShopData)
				Logger:Info("FasterShrooms UI updated immediately from early sync")
			end
		end)
		syncFasterShrooms:FireServer()
	end

	if syncShinySpore then
		self._connections.EarlySyncShinySpore = syncShinySpore.OnClientEvent:Connect(function(level, valueBonus, cost)
			Logger:Info(string.format("EARLY ShinySpore sync received - Level: %d, Value Bonus: %.0f%%, Cost: %d", level, valueBonus * 100, cost))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentShinySporeLevel = level
			self._lastGemShopData.currentSporeValueBonus = valueBonus
			self._lastGemShopData.shinySporeUpgradeCost = cost
			if self._uiElements and self._uiElements.shinySpore then
				self:_updateShinySporeSection(self._lastGemShopData)
				Logger:Info("ShinySpore UI updated immediately from early sync")
			end
		end)
		syncShinySpore:FireServer()
	end

	if syncGemHunter then
		self._connections.EarlySyncGemHunter = syncGemHunter.OnClientEvent:Connect(function(level, gemDropBonus, cost)
			Logger:Info(string.format("EARLY GemHunter sync received - Level: %d, Gem Drop Bonus: %.0f%%, Cost: %d", level, gemDropBonus * 100, cost))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentGemHunterLevel = level
			self._lastGemShopData.currentGemDropBonus = gemDropBonus
			self._lastGemShopData.gemHunterUpgradeCost = cost
			if self._uiElements and self._uiElements.gemHunter then
				self:_updateGemHunterSection(self._lastGemShopData)
				Logger:Info("GemHunter UI updated immediately from early sync")
			end
		end)
		syncGemHunter:FireServer()
	end

	-- Setup confirm handlers for ALL upgrades
	if fastRunnerConfirm then
		self._connections.FastRunnerConfirm = fastRunnerConfirm.OnClientEvent:Connect(function(newLevel, newWalkSpeed, newSpeedPercent)
			Logger:Info(string.format("FastRunner purchase confirmed - Level: %d, Speed: %.2f (%.0f%%)", newLevel, newWalkSpeed, newSpeedPercent))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentFastRunnerLevel = newLevel
			self._lastGemShopData.currentSpeedBonus = newSpeedPercent
			if self._uiElements.fastRunner then
				self:_updateFastRunnerSection(self._lastGemShopData)
				Logger:Info("FastRunner UI updated immediately after purchase confirmation")
			end
			if self._remoteEvents.SyncFastRunner then
				self._remoteEvents.SyncFastRunner:FireServer()
			end
		end)
	end

	if pickUpRangeConfirm then
		self._connections.PickUpRangeConfirm = pickUpRangeConfirm.OnClientEvent:Connect(function(newLevel, newRange)
			Logger:Info(string.format("PickUpRange purchase confirmed - Level: %d, Range: %.2f studs", newLevel, newRange))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentPickUpRangeLevel = newLevel
			self._lastGemShopData.currentPickUpRange = newRange
			if self._uiElements.pickUpRange then
				self:_updatePickUpRangeSection(self._lastGemShopData)
				Logger:Info("PickUpRange UI updated immediately after purchase confirmation")
			end

			-- Apply to CollectionService immediately after purchase
			if self._collectionService then
				Logger:Info(string.format("Applying PickUpRange from purchase confirmation: %.2f studs", newRange))
				self._collectionService:SetPickUpRange(newRange)
			end

			if self._remoteEvents.SyncPickUpRange then
				self._remoteEvents.SyncPickUpRange:FireServer()
			end
		end)
	end

	if fasterShroomsConfirm then
		self._connections.FasterShroomsConfirm = fasterShroomsConfirm.OnClientEvent:Connect(function(newLevel, newSpeedBonus)
			Logger:Info(string.format("FasterShrooms purchase confirmed - Level: %d, Speed Bonus: %.0f%%", newLevel, newSpeedBonus * 100))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentFasterShroomsLevel = newLevel
			self._lastGemShopData.currentShroomSpeedBonus = newSpeedBonus
			if self._uiElements.fasterShrooms then
				self:_updateFasterShroomsSection(self._lastGemShopData)
				Logger:Info("FasterShrooms UI updated immediately after purchase confirmation")
			end
			if self._remoteEvents.SyncFasterShrooms then
				self._remoteEvents.SyncFasterShrooms:FireServer()
			end
		end)
	end

	if shinySporeConfirm then
		self._connections.ShinySporeConfirm = shinySporeConfirm.OnClientEvent:Connect(function(newLevel, newValueBonus)
			Logger:Info(string.format("ShinySpore purchase confirmed - Level: %d, Value Bonus: %.0f%%", newLevel, newValueBonus * 100))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentShinySporeLevel = newLevel
			self._lastGemShopData.currentSporeValueBonus = newValueBonus
			if self._uiElements.shinySpore then
				self:_updateShinySporeSection(self._lastGemShopData)
				Logger:Info("ShinySpore UI updated immediately after purchase confirmation")
			end
			if self._remoteEvents.SyncShinySpore then
				self._remoteEvents.SyncShinySpore:FireServer()
			end
		end)
	end

	if gemHunterConfirm then
		self._connections.GemHunterConfirm = gemHunterConfirm.OnClientEvent:Connect(function(newLevel, newGemDropBonus)
			Logger:Info(string.format("GemHunter purchase confirmed - Level: %d, Gem Drop Bonus: %.0f%%", newLevel, newGemDropBonus * 100))
			self._lastGemShopData = self._lastGemShopData or {}
			self._lastGemShopData.currentGemHunterLevel = newLevel
			self._lastGemShopData.currentGemDropBonus = newGemDropBonus
			if self._uiElements.gemHunter then
				self:_updateGemHunterSection(self._lastGemShopData)
				Logger:Info("GemHunter UI updated immediately after purchase confirmation")
			end
			if self._remoteEvents.SyncGemHunter then
				self._remoteEvents.SyncGemHunter:FireServer()
			end
		end)
	end

	Logger:Info("✓ Early gem shop sync system setup complete")
end

function ShopClient:_setupShopOpenListener()
	local shopOpenedEvent = ReplicatedStorage:FindFirstChild("ShopOpened")
	if shopOpenedEvent then
		self._connections.ShopOpened = shopOpenedEvent.Event:Connect(function(shopType)
			if shopType == "mushroom" or shopType == "mushroom2" or shopType == "mushroom3" then
				Logger:Info("Shop opened, requesting fresh data...")
				task.wait(0.1) -- Small delay for UI to fully load

				-- Always request fresh sync data when shop opens to ensure accuracy
				local shared = ReplicatedStorage:FindFirstChild("Shared")
				if shared then
					local remoteEvents = shared:FindFirstChild("RemoteEvents")
					if remoteEvents then
						local shopEvents = remoteEvents:FindFirstChild("ShopEvents")
						if shopEvents then
							local syncShopData = shopEvents:FindFirstChild("SyncShopData")
							if syncShopData then
								Logger:Info("Requesting fresh shop sync on open")
								syncShopData:FireServer()
							end
						end
					end
				end

				-- Use cached data if available, otherwise fallback to remote function
				if self._lastShopData then
					Logger:Info("Using cached shop data for immediate UI update")
					self:_updateMushroomShopUI(self._lastShopData)
				else
					Logger:Info("No cached shop data, requesting from server")
					self:_updateShopUI()
				end
			elseif shopType == "gem_shop" then
				Logger:Info("Gem shop opened, updating UI...")
				task.wait(0.1) -- Small delay for UI to fully load
				self:_updateGemShopUI()
			end
		end)
		Logger:Info("✓ Shop open listener configured")
	end
end

function ShopClient:_isShopOpen()
	local mushroomShop = self.playerGui:FindFirstChild("MushroomShop")
	local mushroomShop2 = self.playerGui:FindFirstChild("MushroomShop2")
	local mushroomShop3 = self.playerGui:FindFirstChild("MushroomShop3")
	return (mushroomShop and mushroomShop.Enabled) or (mushroomShop2 and mushroomShop2.Enabled) or (mushroomShop3 and mushroomShop3.Enabled)
end

function ShopClient:_getShopData()
	if not self._remoteFunctions.GetShopData then
		Logger:Error("GetShopData remote function not available")
		return nil
	end

	local success, result = pcall(function()
		return self._remoteFunctions.GetShopData:InvokeServer()
	end)

	if success then
		return result
	else
		Logger:Error("Failed to get shop data from server: " .. tostring(result))
		return nil
	end
end

function ShopClient:_updateShopUI()
	-- Use cached data if available, otherwise request fresh data
	local shopData = self._lastShopData or self:_getShopData()
	if not shopData then
		Logger:Info("No shop data available for UI update")
		return
	end

	self:_updateMushroomSection(shopData)
	self:_updateSporeUpgradeSection(shopData)
end

function ShopClient:_updateMushroomShopUI(shopData)
	Logger:Info("=== _updateMushroomShopUI called ===")
	if shopData then
		Logger:Info(string.format("Calling mushroom/spore section updates with: MushroomCount=%d, SporeLevel=%d", 
			shopData.currentMushroomCount or -1, shopData.currentSporeUpgradeLevel or -1))
		self:_updateMushroomSection(shopData)
		self:_updateSporeUpgradeSection(shopData)

		-- Update MushroomShop2 (Area2 only) if data is available
		if shopData.area2MushroomShopLevel ~= nil then
			self:_updateArea2MushroomSection(shopData)
		end

		-- Update MushroomShop3 (Area3 only) if data is available AND GUI exists
		if shopData.area3MushroomShopLevel ~= nil then
			local mushroomShop3 = self.playerGui:FindFirstChild("MushroomShop3")
			if mushroomShop3 and mushroomShop3.Enabled then
				local success, err = pcall(function()
					self:_updateArea3MushroomSection(shopData)
				end)
				if not success then
					Logger:Warn("Failed to update Area3 mushroom section: " .. tostring(err))
				end
			else
				Logger:Debug("MushroomShop3 GUI not found or not enabled - skipping Area3 UI update")
			end
		end

		Logger:Info("=== _updateMushroomShopUI complete ===")
	else
		Logger:Error("_updateMushroomShopUI called with nil shopData!")
	end
end

function ShopClient:_updateMushroomSection(shopData)
	Logger:Info("=== _updateMushroomSection called ===")
	Logger:Info(string.format("Shop data received: MushroomCount=%d, Cost=%.2f", 
		shopData.currentMushroomCount or -1, shopData.mushroomPurchaseCost or -1))

	local elements = self._uiElements.mushroomPurchase
	if not elements then
		Logger:Error("No mushroomPurchase UI elements found!")
		return
	end

	Logger:Info("UI elements found - proceeding with updates")

	-- Determine which area this shop is for based on UI location
	local currentLevel = 0 -- Will be set based on area detection
	local currentCount = 0
	local cost = 0
	local isArea2 = false

	-- Check if this is MushroomShop2 (Area2 shop) by checking UI hierarchy
	if elements.shroomLevel and elements.shroomLevel.Parent and 
		string.find(tostring(elements.shroomLevel.Parent.Parent), "MushroomShop2") then
		-- This is Area2 shop, use Area2 shop level and count
		currentLevel = shopData.area2MushroomShopLevel or 0
		currentCount = shopData.area2MushroomCount or 0
		cost = shopData.area2MushroomShopCost or 0
		isArea2 = true
		Logger:Info(string.format("Using Area2 mushroom shop level: %d, count: %d", currentLevel, currentCount))
	else
		-- This is Area1 shop, use Area1 shop level and count  
		currentLevel = shopData.area1MushroomShopLevel or 0
		currentCount = shopData.area1MushroomCount or 0
		cost = shopData.area1MushroomShopCost or shopData.mushroomPurchaseCost or 0
		isArea2 = false
		Logger:Info(string.format("Using Area1 mushroom shop level: %d, count: %d", currentLevel, currentCount))
	end
	
	-- Check if at level cap (Area1: 49 purchases + 1 starting = 50 mushrooms, Area2: 50 purchases = 50 mushrooms)
	local levelCap = isArea2 and 50 or 49
	local atLevelCap = currentLevel >= levelCap
	local nextLevel = currentLevel + 1
	local nextLevelText = atLevelCap and "MAX" or tostring(nextLevel)

	-- Update ShroomLevel: "Lv. 1", "Lv. 2", etc. or "MAX" if at cap
	if elements.shroomLevel and elements.shroomLevel:IsA("TextLabel") then
		local oldText = elements.shroomLevel.Text
		elements.shroomLevel.Text = "Lv. " .. nextLevelText
		Logger:Info(string.format("ShroomLevel updated: '%s' -> '%s'", oldText, elements.shroomLevel.Text))
	else
		Logger:Error("ShroomLevel element not found or not a TextLabel")
	end

	-- Update ShroomTracker: "1x -> 2x", "2x -> 3x", etc. or "50x MAX" if at cap
	if elements.shroomTracker and elements.shroomTracker:IsA("TextLabel") then
		local oldText = elements.shroomTracker.Text
		if atLevelCap then
			elements.shroomTracker.Text = currentCount .. "x MAX"
		else
			elements.shroomTracker.Text = currentCount .. "x -> " .. (currentCount + 1) .. "x"
		end
		Logger:Info(string.format("ShroomTracker updated: '%s' -> '%s'", oldText, elements.shroomTracker.Text))
	else
		Logger:Error("ShroomTracker element not found or not a TextLabel")
	end

	-- Update ShroomCost: show cost or "MAX" if at cap
	if elements.shroomCost and elements.shroomCost:IsA("TextLabel") then
		local oldText = elements.shroomCost.Text
		if atLevelCap then
			elements.shroomCost.Text = "MAX"
		else
			elements.shroomCost.Text = string.format("%.2f", cost)
		end
		Logger:Info(string.format("ShroomCost updated: '%s' -> '%s'", oldText, elements.shroomCost.Text))
	else
		Logger:Error("ShroomCost element not found or not a TextLabel")
	end

	Logger:Info(string.format("=== Mushroom section update complete: %s, %dx, Cost:%s, Area:%s ===", 
		nextLevelText, currentCount, 
		atLevelCap and "MAX" or string.format("%.2f", cost),
		isArea2 and "Area2" or "Area1"))
end

function ShopClient:_updateSporeUpgradeSection(shopData)
	Logger:Info("=== _updateSporeUpgradeSection called ===")
	Logger:Info(string.format("Shop data: area1SporeUpgradeLevel=%s, area2SporeUpgradeLevel=%s, area1SporeUpgradeCost=%s, area2SporeUpgradeCost=%s", 
		tostring(shopData.area1SporeUpgradeLevel), tostring(shopData.area2SporeUpgradeLevel), 
		tostring(shopData.area1SporeUpgradeCost), tostring(shopData.area2SporeUpgradeCost)))
	
	-- Update Area1 spore upgrade section (MushroomShop)
	local elements = self._uiElements.sporeUpgrade
	Logger:Info(string.format("Area1 spore elements found: %s", tostring(elements ~= nil)))
	if elements then
		local currentLevel = shopData.area1SporeUpgradeLevel or shopData.currentSporeUpgradeLevel or 0
		local currentBonus = math.floor(((shopData.area1SporeMultiplier or shopData.sporeMultiplier or 1.0) - 1) * 100)
		local upgradeCost = shopData.area1SporeUpgradeCost or shopData.sporeUpgradeCost or 0
		local nextLevel = currentLevel + 1
		local nextBonus = currentBonus + 8 -- 8% per level

		-- Check if at level cap (spore upgrade maxes at level 100)
		local atLevelCap = currentLevel >= 100
		local nextLevelText = atLevelCap and "MAX" or tostring(nextLevel)

		-- Update SporeLevel: "Lv. 1", "Lv. 2", etc. or "MAX" if at cap
		if elements.sporeLevel and elements.sporeLevel:IsA("TextLabel") then
			elements.sporeLevel.Text = "Lv. " .. nextLevelText
		end

		-- Update SporeTracker: "0% -> 8%", "8% -> 16%", etc.
		if elements.sporeTracker and elements.sporeTracker:IsA("TextLabel") then
			elements.sporeTracker.Text = currentBonus .. "% -> " .. nextBonus .. "%"
		end

		-- Update SporeCost
		if elements.sporeCost and elements.sporeCost:IsA("TextLabel") then
			elements.sporeCost.Text = string.format("%.2f", upgradeCost)
		end

		Logger:Info(string.format("Updated Area1 spore upgrade section: Lv.%d, %d%%->%d%%, Cost:%.2f", 
			nextLevel, currentBonus, nextBonus, upgradeCost))
	end

	-- Update Area2 spore upgrade section (MushroomShop2)
	local area2Elements = self._uiElements.area2SporeUpgrade
	Logger:Info(string.format("Area2 spore elements found: %s", tostring(area2Elements ~= nil)))
	if area2Elements then
		local currentLevel = shopData.area2SporeUpgradeLevel or 0
		local currentBonus = math.floor(((shopData.area2SporeMultiplier or 1.0) - 1) * 100)
		local upgradeCost = shopData.area2SporeUpgradeCost or 0
		local nextLevel = currentLevel + 1
		local nextBonus = currentBonus + 8 -- 8% per level

		-- Check if at level cap (spore upgrade maxes at level 100)
		local atLevelCap = currentLevel >= 100
		local nextLevelText = atLevelCap and "MAX" or tostring(nextLevel)

		-- Update SporeLevel: "Lv. 1", "Lv. 2", etc. or "MAX" if at cap
		if area2Elements.sporeLevel and area2Elements.sporeLevel:IsA("TextLabel") then
			area2Elements.sporeLevel.Text = "Lv. " .. nextLevelText
		end

		-- Update SporeTracker: "0% -> 8%", "8% -> 16%", etc.
		if area2Elements.sporeTracker and area2Elements.sporeTracker:IsA("TextLabel") then
			area2Elements.sporeTracker.Text = currentBonus .. "% -> " .. nextBonus .. "%"
		end

		-- Update SporeCost
		if area2Elements.sporeCost and area2Elements.sporeCost:IsA("TextLabel") then
			area2Elements.sporeCost.Text = string.format("%.2f", upgradeCost)
		end

		Logger:Info(string.format("Updated Area2 spore upgrade section: Lv.%d, %d%%->%d%%, Cost:%.2f", 
			nextLevel, currentBonus, nextBonus, upgradeCost))
	end
end

-- Removed _updateArea1MushroomSection since MushroomShop2 only handles Area2

function ShopClient:_updateArea2MushroomSection(shopData)
	Logger:Info("=== _updateArea2MushroomSection called ===")
	Logger:Info(string.format("Area2 shop data received: Level=%d, Count=%d, Cost=%.2f, Unlocked=%s", 
		shopData.area2MushroomShopLevel or -1, shopData.area2MushroomCount or -1, shopData.area2MushroomShopCost or -1, tostring(shopData.area2Unlocked)))

	local elements = self._uiElements.area2MushroomPurchase
	if not elements then
		Logger:Info("No area2MushroomPurchase UI elements found - skipping update")
		return
	end

	Logger:Info("Area2 UI elements found - proceeding with updates")

	local currentLevel = shopData.area2MushroomShopLevel
	local nextLevel = currentLevel + 1
	local currentCount = shopData.area2MushroomCount
	local isUnlocked = shopData.area2Unlocked

	-- Check if at level cap (Area2 cap is 50 since no starting mushroom)
	local atLevelCap = currentLevel >= 50
	local nextLevelText = atLevelCap and "MAX" or tostring(nextLevel)

	-- Update ShroomLevel: "Lv. 1", "Lv. 2", etc.
	if elements.shroomLevel and elements.shroomLevel:IsA("TextLabel") then
		local oldText = elements.shroomLevel.Text
		if not isUnlocked then
			elements.shroomLevel.Text = "LOCKED"
		else
			elements.shroomLevel.Text = "Lv. " .. nextLevelText
		end
		Logger:Info(string.format("Area2 ShroomLevel updated: '%s' -> '%s'", oldText, elements.shroomLevel.Text))
	else
		Logger:Error("Area2 ShroomLevel element not found or not a TextLabel")
	end

	-- Update ShroomTracker: "0x -> 1x", "1x -> 2x", etc.
	if elements.shroomTracker and elements.shroomTracker:IsA("TextLabel") then
		local oldText = elements.shroomTracker.Text
		if not isUnlocked then
			elements.shroomTracker.Text = "Unlock Area2 First"
		elseif atLevelCap then
			elements.shroomTracker.Text = string.format("%dx (MAX)", currentCount)
		else
			elements.shroomTracker.Text = string.format("%dx -> %dx", currentCount, currentCount + 1)
		end
		Logger:Info(string.format("Area2 ShroomTracker updated: '%s' -> '%s'", oldText, elements.shroomTracker.Text))
	else
		Logger:Error("Area2 ShroomTracker element not found or not a TextLabel")
	end

	-- Update ShroomCost
	if elements.shroomCost and elements.shroomCost:IsA("TextLabel") then
		local oldText = elements.shroomCost.Text
		if not isUnlocked then
			elements.shroomCost.Text = "LOCKED"
			elements.shroomCost.TextColor3 = Color3.fromRGB(200, 200, 200)  -- Gray when locked
		elseif atLevelCap then
			elements.shroomCost.Text = "MAX"
			elements.shroomCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when maxed
		else
			elements.shroomCost.Text = string.format("%.2f", shopData.area2MushroomShopCost)
			
			-- Update text color based on affordability
			local currentSpores = self:_getCurrentSpores()
			if currentSpores >= shopData.area2MushroomShopCost then
				elements.shroomCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
			else
				elements.shroomCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
			end
		end
		Logger:Info(string.format("Area2 ShroomCost updated: '%s' -> '%s'", oldText, elements.shroomCost.Text))
	else
		Logger:Error("Area2 ShroomCost element not found or not a TextLabel")
	end

	-- Update button enabled state
	if elements.button then
		elements.button.Active = isUnlocked and not atLevelCap
		elements.button.Interactable = isUnlocked and not atLevelCap
	end

	Logger:Info(string.format("=== Area2 mushroom section update complete: Lv.%s, %dx, Cost:%s, Unlocked:%s ===", 
		nextLevelText, currentCount, 
		not isUnlocked and "LOCKED" or (atLevelCap and "MAX" or string.format("%.2f", shopData.area2MushroomShopCost)),
		tostring(isUnlocked)))
end

function ShopClient:_updateArea3MushroomSection(shopData)
	Logger:Info("=== _updateArea3MushroomSection called ===")
	Logger:Info(string.format("Area3 shop data received: Level=%d, Count=%d, Cost=%.2f, Unlocked=%s", 
		shopData.area3MushroomShopLevel or -1, shopData.area3MushroomCount or -1, shopData.area3MushroomShopCost or -1, tostring(shopData.area3Unlocked)))

	local elements = self._uiElements.area3MushroomPurchase
	if not elements then
		Logger:Info("No area3MushroomPurchase UI elements found - skipping update")
		return
	end

	Logger:Info("Area3 UI elements found - proceeding with updates")

	local currentLevel = shopData.area3MushroomShopLevel
	local nextLevel = currentLevel + 1
	local currentCount = shopData.area3MushroomCount
	local isUnlocked = shopData.area3Unlocked

	-- Check if at level cap (Area3 cap is 50 since no starting mushroom)
	local atLevelCap = currentLevel >= 50
	local nextLevelText = atLevelCap and "MAX" or tostring(nextLevel)

	-- Update ShroomLevel: "Lv. 1", "Lv. 2", etc.
	if elements.shroomLevel and elements.shroomLevel:IsA("TextLabel") then
		local oldText = elements.shroomLevel.Text
		if not isUnlocked then
			elements.shroomLevel.Text = "LOCKED"
		else
			elements.shroomLevel.Text = "Lv. " .. nextLevelText
		end
		Logger:Info(string.format("Area3 ShroomLevel updated: '%s' -> '%s'", oldText, elements.shroomLevel.Text))
	else
		Logger:Error("Area3 ShroomLevel element not found or not a TextLabel")
	end

	-- Update ShroomTracker: "0x -> 1x", "1x -> 2x", etc.
	if elements.shroomTracker and elements.shroomTracker:IsA("TextLabel") then
		local oldText = elements.shroomTracker.Text
		if not isUnlocked then
			elements.shroomTracker.Text = "LOCKED"
		elseif atLevelCap then
			elements.shroomTracker.Text = currentCount .. "x MAX"
		else
			elements.shroomTracker.Text = currentCount .. "x -> " .. (currentCount + 1) .. "x"
		end
		Logger:Info(string.format("Area3 ShroomTracker updated: '%s' -> '%s'", oldText, elements.shroomTracker.Text))
	else
		Logger:Error("Area3 ShroomTracker element not found or not a TextLabel")
	end

	-- Update ShroomCost
	if elements.shroomCost and elements.shroomCost:IsA("TextLabel") then
		local oldText = elements.shroomCost.Text
		if not isUnlocked then
			elements.shroomCost.Text = "LOCKED"
			elements.shroomCost.TextColor3 = Color3.fromRGB(200, 200, 200)  -- Gray when locked
		elseif atLevelCap then
			elements.shroomCost.Text = "MAX"
			elements.shroomCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when maxed
		else
			elements.shroomCost.Text = string.format("%.2f", shopData.area3MushroomShopCost)
			
			-- Update text color based on affordability
			local currentSpores = self:_getCurrentSpores()
			if currentSpores >= shopData.area3MushroomShopCost then
				elements.shroomCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
			else
				elements.shroomCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
			end
		end
		Logger:Info(string.format("Area3 ShroomCost updated: '%s' -> '%s'", oldText, elements.shroomCost.Text))
	else
		Logger:Error("Area3 ShroomCost element not found or not a TextLabel")
	end

	-- Update button enabled state
	if elements.button then
		elements.button.Active = isUnlocked and not atLevelCap
		elements.button.Interactable = isUnlocked and not atLevelCap
	end

	Logger:Info(string.format("=== Area3 mushroom section update complete: Lv.%s, %dx, Cost:%s, Unlocked:%s ===", 
		nextLevelText, currentCount, 
		not isUnlocked and "LOCKED" or (atLevelCap and "MAX" or string.format("%.2f", shopData.area3MushroomShopCost)),
		tostring(isUnlocked)))
end

function ShopClient:_purchaseSporeUpgrade()
	Logger:Info("Area1 spore upgrade button clicked")

	if self._remoteEvents.PurchaseSporeUpgrade then
		-- Clear cached data to force fresh update on next UI refresh
		self._lastShopData = nil
		Logger:Info("Cleared cached shop data for fresh update")

		self._remoteEvents.PurchaseSporeUpgrade:FireServer()
		Logger:Info("Area1 spore upgrade purchase request sent to server")
	else
		Logger:Error("Area1 spore upgrade remote event not available")
	end
end

function ShopClient:_purchaseArea2SporeUpgrade()
	Logger:Info("Area2 spore upgrade button clicked")

	if self._remoteEvents.PurchaseArea2SporeUpgrade then
		-- Clear cached data to force fresh update on next UI refresh
		self._lastShopData = nil
		Logger:Info("Cleared cached shop data for fresh update")

		self._remoteEvents.PurchaseArea2SporeUpgrade:FireServer()
		Logger:Info("Area2 spore upgrade purchase request sent to server")
	else
		Logger:Error("Area2 spore upgrade remote event not available")
	end
end

function ShopClient:_purchaseMushroom(area)
	area = area or "Area1" -- Default to Area1
	Logger:Info(string.format("Mushroom purchase button clicked for %s", area))

	if self._remoteEvents.PurchaseMushroom then
		-- Clear cached data to force fresh update on next UI refresh
		self._lastShopData = nil
		Logger:Info("Cleared cached shop data for fresh update")

		self._remoteEvents.PurchaseMushroom:FireServer(area)
		Logger:Info(string.format("Mushroom purchase request sent to server for %s", area))
	else
		Logger:Error("PurchaseMushroom remote event not available")
	end
end

-- Removed _purchaseArea1Mushroom since MushroomShop2 only handles Area2

function ShopClient:_purchaseArea2Mushroom()
	Logger:Info("Area2 mushroom purchase button clicked (separate shop)")

	if self._remoteEvents.PurchaseArea2Mushroom then
		-- Use new separate remote event
		self._lastShopData = nil
		Logger:Info("Using separate Area2 mushroom remote")
		self._remoteEvents.PurchaseArea2Mushroom:FireServer()
	elseif self._remoteEvents.PurchaseMushroom then
		-- Fallback to existing system with Area2 parameter
		self._lastShopData = nil
		Logger:Info("Falling back to existing mushroom purchase system for Area2")
		self._remoteEvents.PurchaseMushroom:FireServer("Area2")
	else
		Logger:Error("No mushroom purchase remote events available")
	end
end

function ShopClient:_purchaseArea3Mushroom()
	Logger:Info("Area3 mushroom purchase button clicked (separate shop)")

	if self._remoteEvents.PurchaseArea3Mushroom then
		-- Use new separate remote event
		self._lastShopData = nil
		Logger:Info("Using separate Area3 mushroom remote")
		self._remoteEvents.PurchaseArea3Mushroom:FireServer()
	elseif self._remoteEvents.PurchaseMushroom then
		-- Fallback to existing system with Area3 parameter
		self._lastShopData = nil
		Logger:Info("Falling back to existing mushroom purchase system for Area3")
		self._remoteEvents.PurchaseMushroom:FireServer("Area3")
	else
		Logger:Error("No mushroom purchase remote events available")
	end
end

function ShopClient:_setupArea2PurchaseButton()
	Logger:Info("Setting up Area2 purchase button...")

	-- Wait for the button to exist (PlayerPlots/PlotTemplate/Area2/PurchaseWall/SurfaceGui/Frame/ImageLabel/PurchaseArea2)
	task.spawn(function()
		local workspace = game:GetService("Workspace")
		local player = Players.LocalPlayer

		-- Wait for player's plot
		local playerPlots = workspace:WaitForChild("PlayerPlots", 10)
		if not playerPlots then
			Logger:Error("PlayerPlots not found for Area2 button setup")
			return
		end

		local playerPlot = playerPlots:WaitForChild("Plot_" .. player.Name, 10)
		if not playerPlot then
			Logger:Error("Player plot not found for Area2 button setup")
			return
		end

		local area2 = playerPlot:WaitForChild("Area2", 10)
		if not area2 then
			Logger:Error("Area2 not found in player plot")
			return
		end

		-- Check if PurchaseWall exists (it won't if Area2 is already unlocked)
		local purchaseWall = area2:FindFirstChild("PurchaseWall")
		if not purchaseWall then
			Logger:Info("PurchaseWall not found in Area2 - Area2 is already unlocked, no setup needed")
			return
		end

		local surfaceGui = purchaseWall:WaitForChild("SurfaceGui", 10)
		if not surfaceGui then
			Logger:Error("SurfaceGui not found on PurchaseWall")
			return
		end

		local frame = surfaceGui:WaitForChild("Frame", 10)
		if not frame then
			Logger:Error("Frame not found in SurfaceGui")
			return
		end

		local imageLabel = frame:WaitForChild("ImageLabel", 10)
		if not imageLabel then
			Logger:Error("ImageLabel not found in Frame")
			return
		end

		local purchaseArea2Button = imageLabel:WaitForChild("PurchaseArea2", 10)
		if not purchaseArea2Button or not purchaseArea2Button:IsA("GuiButton") then
			Logger:Error("PurchaseArea2 button not found or not a GuiButton")
			return
		end

		-- Connect the button
		local connection = purchaseArea2Button.MouseButton1Click:Connect(function()
			self:_purchaseArea2()
		end)

		-- Store connection for cleanup
		self._connections = self._connections or {}
		self._connections.PurchaseArea2 = connection

		Logger:Info("✓ Area2 purchase button connected successfully")
	end)
end

function ShopClient:_purchaseArea2()
	Logger:Info("Area2 purchase button clicked")

	if self._remoteEvents.PurchaseArea2 then
		self._remoteEvents.PurchaseArea2:FireServer()
		Logger:Info("Area2 purchase request sent to server")
	else
		Logger:Error("PurchaseArea2 remote event not available")
	end
end

function ShopClient:_determineCurrentShopArea()
	local workspace = game:GetService("Workspace")
	local player = Players.LocalPlayer

	Logger:Debug("Determining current shop area...")

	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		Logger:Debug("No PlayerPlots found")
		return "Area1"
	end

	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		Logger:Debug("No player plot found")
		return "Area1"
	end

	local area2 = playerPlot:FindFirstChild("Area2")
	if not area2 then
		Logger:Debug("No Area2 found")
		return "Area1"
	end

	local area2Shop = area2:FindFirstChild("Area2Shop")
	if not area2Shop then
		Logger:Debug("No Area2Shop found")
		return "Area1"
	end

	if not (player.Character and player.Character.PrimaryPart) then
		Logger:Debug("No character/PrimaryPart found")
		return "Area1"
	end

	-- Check if player is close to Area2Shop
	local playerPos = player.Character.PrimaryPart.Position
	local area2ShopPos = area2Shop.Position
	local distance = (playerPos - area2ShopPos).Magnitude

	Logger:Debug(string.format("Distance to Area2Shop: %.1f studs", distance))

	-- If player is very close to Area2Shop, they likely just stepped on it
	if distance < 20 then -- Increased from 15 to 20 for more leeway
		Logger:Info("Player is close to Area2Shop, using Area2")
		return "Area2"
	end

	Logger:Info(string.format("Player too far from Area2Shop (%.1f studs), using Area1", distance))
	return "Area1"
end

-- Public method to update shop UI when opened
function ShopClient:UpdateShopUI()
	if self:_isShopOpen() then
		self:_updateShopUI()
	end
end

-- Gem shop functions
function ShopClient:_isGemShopOpen()
	local gemShop = self.playerGui:FindFirstChild("GemShop")
	return gemShop and gemShop.Enabled
end

function ShopClient:_updateGemShopUI()
	-- Use cached data if available
	if self._lastGemShopData then
		Logger:Info("Using cached gem shop data for UI update")
		self:_updateFastRunnerSection(self._lastGemShopData)
		self:_updatePickUpRangeSection(self._lastGemShopData)
		self:_updateFasterShroomsSection(self._lastGemShopData)
		self:_updateShinySporeSection(self._lastGemShopData)
	else
		Logger:Info("No gem shop data cached yet - UI will update when sync is received")
	end
end

function ShopClient:_updateGemShopAffordability()
	-- Update affordability colors for all gem upgrades based on current gems
	if self._lastGemShopData then
		self:_updateFastRunnerAffordability(self._lastGemShopData)
		self:_updatePickUpRangeAffordability(self._lastGemShopData)
		self:_updateFasterShroomsAffordability(self._lastGemShopData)
		self:_updateShinySporeAffordability(self._lastGemShopData)
	end
end

function ShopClient:_updateMushroomShopAffordability()
	-- Update affordability colors for all mushroom shop costs based on current spores
	if self._lastShopData then
		self:_updateArea2MushroomAffordability(self._lastShopData)
		self:_updateArea3MushroomAffordability(self._lastShopData)
	else
		Logger:Info("No mushroom shop data cached yet - UI will update when sync is received")
	end
end

function ShopClient:_getGemShopData()
	-- For now, we'll need to create a remote function for gem shop data
	-- This is a placeholder - you'll need to add GetGemShopData remote function
	if not self._remoteFunctions.GetGemShopData then
		Logger:Warn("GetGemShopData remote function not available")
		return nil
	end

	local success, result = pcall(function()
		return self._remoteFunctions.GetGemShopData:InvokeServer()
	end)

	if success then
		return result
	else
		Logger:Error("Failed to get gem shop data from server: " .. tostring(result))
		return nil
	end
end

function ShopClient:_updateFastRunnerSection(gemShopData)
	local elements = self._uiElements.fastRunner
	if not elements then
		return
	end

	-- Store gem shop data for purchase validation
	self._lastGemShopData = gemShopData

	local currentLevel = gemShopData.currentFastRunnerLevel or 1  -- Server starts at 1
	local nextLevel = currentLevel + 1
	local currentSpeedBonus = gemShopData.currentSpeedBonus or 0
	local nextSpeedBonus = currentSpeedBonus + 4 -- 4% per level

	-- Check if at level cap (gem upgrades max at level 20)
	local atLevelCap = currentLevel >= 20
	local currentLevelText = atLevelCap and "MAX" or tostring(currentLevel)

	-- Update UpgradeLevel: Show current level "Lv. 1", "Lv. 2", etc. or "MAX" if at cap
	if elements.upgradeLevel and elements.upgradeLevel:IsA("TextLabel") then
		elements.upgradeLevel.Text = "Lv. " .. currentLevelText
	end

	-- Update NextUpgrade: Show what you'll get after purchase
	if elements.nextUpgrade and elements.nextUpgrade:IsA("TextLabel") then
		elements.nextUpgrade.Text = math.floor(currentSpeedBonus) .. "%+ -> " .. math.floor(nextSpeedBonus) .. "%+"
	end

	-- Update GemCost: "10", "12", "14", etc.
	if elements.gemCost and elements.gemCost:IsA("TextLabel") then
		local cost = gemShopData.fastRunnerCost or 10
		elements.gemCost.Text = tostring(cost)

		-- Update text color based on affordability
		local currentGems = self:_getCurrentGems()
		if currentGems >= cost then
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
		else
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
		end
	end

	Logger:Debug(string.format("Updated FastRunner section: Current Lv.%d, %d%%->%d%%, Cost:%d", 
		currentLevel, currentSpeedBonus, nextSpeedBonus, gemShopData.fastRunnerCost or 10))
end

function ShopClient:_updatePickUpRangeSection(gemShopData)
	local elements = self._uiElements.pickUpRange
	if not elements then
		return
	end

	local currentLevel = gemShopData.currentPickUpRangeLevel or 1
	local nextLevel = currentLevel + 1
	local currentRange = gemShopData.currentPickUpRange or 6.0
	local nextRange = currentRange + 0.25 -- +0.25 studs per level

	-- Check if at level cap (gem upgrades max at level 20)
	local atLevelCap = currentLevel >= 20
	local currentLevelText = atLevelCap and "MAX" or tostring(currentLevel)

	-- Update UpgradeLevel: Show current level "Lv. 1", "Lv. 2", etc. or "MAX" if at cap
	if elements.upgradeLevel and elements.upgradeLevel:IsA("TextLabel") then
		elements.upgradeLevel.Text = "Lv. " .. currentLevelText
	end

	-- Update NextUpgrade: Show range improvement "6Studs -> 6.25Studs"
	if elements.nextUpgrade and elements.nextUpgrade:IsA("TextLabel") then
		elements.nextUpgrade.Text = string.format("%.2fStuds -> %.2fStuds", currentRange, nextRange)
	end

	-- Update GemCost
	if elements.gemCost and elements.gemCost:IsA("TextLabel") then
		local cost = gemShopData.pickUpRangeCost or 10
		elements.gemCost.Text = tostring(cost)

		-- Update text color based on affordability
		local currentGems = self:_getCurrentGems()
		if currentGems >= cost then
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
		else
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
		end
	end

	Logger:Debug(string.format("Updated PickUpRange section: Current Lv.%d, %.2f->%.2f studs, Cost:%d", 
		currentLevel, currentRange, nextRange, gemShopData.pickUpRangeCost or 10))
end

function ShopClient:_updateFasterShroomsSection(gemShopData)
	local elements = self._uiElements.fasterShrooms
	if not elements then
		return
	end

	local currentLevel = gemShopData.currentFasterShroomsLevel or 1
	local nextLevel = currentLevel + 1
	local currentSpeedBonus = (gemShopData.currentShroomSpeedBonus or 0) * 100 -- Convert to percentage
	local nextSpeedBonus = currentSpeedBonus + 2 -- +2% per level

	-- Check if at level cap (gem upgrades max at level 20)
	local atLevelCap = currentLevel >= 20
	local currentLevelText = atLevelCap and "MAX" or tostring(currentLevel)

	-- Update UpgradeLevel: Show current level "Lv. 1", "Lv. 2", etc. or "MAX" if at cap
	if elements.upgradeLevel and elements.upgradeLevel:IsA("TextLabel") then
		elements.upgradeLevel.Text = "Lv. " .. currentLevelText
	end

	-- Update NextUpgrade: Show speed improvement "0% -> 2%", "2% -> 4%", etc.
	if elements.nextUpgrade and elements.nextUpgrade:IsA("TextLabel") then
		elements.nextUpgrade.Text = math.floor(currentSpeedBonus) .. "% -> " .. math.floor(nextSpeedBonus) .. "%"
	end

	-- Update GemCost
	if elements.gemCost and elements.gemCost:IsA("TextLabel") then
		local cost = gemShopData.fasterShroomsCost or 10
		elements.gemCost.Text = tostring(cost)

		-- Update text color based on affordability
		local currentGems = self:_getCurrentGems()
		if currentGems >= cost then
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
		else
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
		end
	end

	Logger:Debug(string.format("Updated FasterShrooms section: Current Lv.%d, %.0f%%->%.0f%%, Cost:%d", 
		currentLevel, currentSpeedBonus, nextSpeedBonus, gemShopData.fasterShroomsCost or 10))
end

function ShopClient:_updateShinySporeSection(gemShopData)
	local elements = self._uiElements.shinySpore
	if not elements then
		Logger:Debug("ShinySpore UI elements not found - skipping update")
		return
	end

	Logger:Debug("Updating ShinySpore UI with data: " .. tostring(gemShopData and "available" or "nil"))

	local currentLevel = gemShopData.currentShinySporeLevel or 1
	local nextLevel = currentLevel + 1
	local currentValueBonus = (gemShopData.currentSporeValueBonus or 0) * 100 -- Convert to percentage
	local nextValueBonus = currentValueBonus + 2 -- +2% per level

	-- Check if at level cap (gem upgrades max at level 20)
	local atLevelCap = currentLevel >= 20
	local currentLevelText = atLevelCap and "MAX" or tostring(currentLevel)

	Logger:Debug(string.format("ShinySpore data: Level=%d, ValueBonus=%.0f%%, Cost=%d", 
		currentLevel, currentValueBonus, gemShopData.shinySporeUpgradeCost or 10))

	-- Update UpgradeLevel: Show current level "Lv. 1", "Lv. 2", etc. or "MAX" if at cap
	if elements.upgradeLevel and elements.upgradeLevel:IsA("TextLabel") then
		elements.upgradeLevel.Text = "Lv. " .. currentLevelText
	end

	-- Update NextUpgrade: Show value bonus improvement "0% -> 2%", "2% -> 4%", etc.
	if elements.nextUpgrade and elements.nextUpgrade:IsA("TextLabel") then
		elements.nextUpgrade.Text = math.floor(currentValueBonus) .. "% -> " .. math.floor(nextValueBonus) .. "%"
	end

	-- Update GemCost
	if elements.gemCost and elements.gemCost:IsA("TextLabel") then
		local cost = gemShopData.shinySporeUpgradeCost or 10
		Logger:Debug(string.format("Setting ShinySpore cost to: %d (was: %s)", cost, elements.gemCost.Text))
		elements.gemCost.Text = tostring(cost)

		-- Update text color based on affordability
		local currentGems = self:_getCurrentGems()
		if currentGems >= cost then
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
		else
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
		end
	else
		Logger:Warn("ShinySpore gemCost element not found or not a TextLabel")
		if elements.gemCost then
			Logger:Warn(string.format("gemCost element type: %s", elements.gemCost.ClassName))
		end
	end

	Logger:Debug(string.format("Updated ShinySpore section: Current Lv.%d, %.0f%%->%.0f%%, Cost:%d", 
		currentLevel, currentValueBonus, nextValueBonus, gemShopData.shinySporeUpgradeCost or 10))
end

function ShopClient:_updateFastRunnerAffordability(gemShopData)
	local elements = self._uiElements.fastRunner
	if not elements or not elements.gemCost then return end

	local cost = gemShopData.fastRunnerCost or 10
	local currentGems = self:_getCurrentGems()

	if currentGems >= cost then
		elements.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
	else
		elements.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
	end
end

function ShopClient:_updatePickUpRangeAffordability(gemShopData)
	local elements = self._uiElements.pickUpRange
	if not elements or not elements.gemCost then return end

	local cost = gemShopData.pickUpRangeCost or 10
	local currentGems = self:_getCurrentGems()

	if currentGems >= cost then
		elements.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
	else
		elements.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
	end
end

function ShopClient:_updateFasterShroomsAffordability(gemShopData)
	local elements = self._uiElements.fasterShrooms
	if not elements or not elements.gemCost then return end

	local cost = gemShopData.fasterShroomsCost or 10
	local currentGems = self:_getCurrentGems()

	if currentGems >= cost then
		elements.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
	else
		elements.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
	end
end

function ShopClient:_updateShinySporeAffordability(gemShopData)
	local elements = self._uiElements.shinySpore
	if not elements or not elements.gemCost then return end

	local cost = gemShopData.shinySporeUpgradeCost or 10
	local currentGems = self:_getCurrentGems()

	if currentGems >= cost then
		elements.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
	else
		elements.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
	end
end

function ShopClient:_getCurrentGems()
	local leaderstats = self.player:FindFirstChild("leaderstats")
	if not leaderstats then return 0 end

	local gems = leaderstats:FindFirstChild("Gems")
	if not gems then return 0 end

	return gems.Value
end

function ShopClient:_getCurrentSpores()
	local leaderstats = self.player:FindFirstChild("leaderstats")
	if not leaderstats then return 0 end

	local spores = leaderstats:FindFirstChild("Spores")
	if not spores then return 0 end

	return spores.Value
end

function ShopClient:_updateArea2MushroomAffordability(shopData)
	local elements = self._uiElements.area2MushroomPurchase
	if not elements or not elements.shroomCost then return end

	local cost = shopData.area2MushroomShopCost or 0
	local currentSpores = self:_getCurrentSpores()
	local isUnlocked = shopData.area2Unlocked or false
	local atLevelCap = (shopData.area2MushroomShopLevel or 0) >= 50

	if not isUnlocked then
		elements.shroomCost.TextColor3 = Color3.fromRGB(200, 200, 200)  -- Gray when locked
	elseif atLevelCap then
		elements.shroomCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when maxed
	else
		if currentSpores >= cost then
			elements.shroomCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
		else
			elements.shroomCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
		end
	end
end

function ShopClient:_updateArea3MushroomAffordability(shopData)
	local elements = self._uiElements.area3MushroomPurchase
	if not elements or not elements.shroomCost then return end

	local cost = shopData.area3MushroomShopCost or 0
	local currentSpores = self:_getCurrentSpores()
	local isUnlocked = shopData.area3Unlocked or false
	local atLevelCap = (shopData.area3MushroomShopLevel or 0) >= 50

	if not isUnlocked then
		elements.shroomCost.TextColor3 = Color3.fromRGB(200, 200, 200)  -- Gray when locked
	elseif atLevelCap then
		elements.shroomCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when maxed
	else
		if currentSpores >= cost then
			elements.shroomCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
		else
			elements.shroomCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
		end
	end
end

function ShopClient:_purchaseFastRunner()
	Logger:Info("FastRunner upgrade button clicked!")

	if self._remoteEvents.PurchaseFastRunner then
		-- Get current cost and level from stored gem shop data
		local clientCost = self._lastGemShopData and self._lastGemShopData.fastRunnerCost or 10
		local clientLevel = self._lastGemShopData and self._lastGemShopData.currentFastRunnerLevel or 1

		self._remoteEvents.PurchaseFastRunner:FireServer(clientCost, clientLevel)
		Logger:Info(string.format("FastRunner upgrade purchase request sent to server - Cost: %d, Level: %d", clientCost, clientLevel))
		
	else
		Logger:Error("PurchaseFastRunner remote event not available")
	end
end

function ShopClient:_purchasePickUpRange()
	Logger:Info("PickUpRange upgrade button clicked!")

	if self._remoteEvents.PurchasePickUpRange then
		-- Get current cost and level from stored gem shop data
		local clientCost = self._lastGemShopData and self._lastGemShopData.pickUpRangeCost or 10
		local clientLevel = self._lastGemShopData and self._lastGemShopData.currentPickUpRangeLevel or 1

		self._remoteEvents.PurchasePickUpRange:FireServer(clientCost, clientLevel)
		Logger:Info(string.format("PickUpRange upgrade purchase request sent to server - Cost: %d, Level: %d", clientCost, clientLevel))
		
	else
		Logger:Error("PurchasePickUpRange remote event not available")
	end
end

function ShopClient:_purchaseFasterShrooms()
	Logger:Info("FasterShrooms upgrade button clicked!")

	if self._remoteEvents.PurchaseFasterShrooms then
		-- Get current cost and level from stored gem shop data
		local clientCost = self._lastGemShopData and self._lastGemShopData.fasterShroomsCost or 10
		local clientLevel = self._lastGemShopData and self._lastGemShopData.currentFasterShroomsLevel or 1

		self._remoteEvents.PurchaseFasterShrooms:FireServer(clientCost, clientLevel)
		Logger:Info(string.format("FasterShrooms upgrade purchase request sent to server - Cost: %d, Level: %d", clientCost, clientLevel))
		
	else
		Logger:Error("PurchaseFasterShrooms remote event not available")
	end
end

function ShopClient:_purchaseShinySpore()

	if not self._remoteEvents then
		Logger:Error("Remote events not loaded yet for ShinySpore purchase")
		return
	end


	if self._remoteEvents.PurchaseShinySpore then
		-- Get current cost and level from stored gem shop data
		local clientCost = self._lastGemShopData and self._lastGemShopData.shinySporeUpgradeCost or 10
		local clientLevel = self._lastGemShopData and self._lastGemShopData.currentShinySporeLevel or 1


		self._remoteEvents.PurchaseShinySpore:FireServer(clientCost, clientLevel)
		
	else
		Logger:Error("PurchaseShinySpore remote event not available")
	end
end

function ShopClient:_purchaseGemHunter()

	if not self._remoteEvents then
		Logger:Error("Remote events not loaded yet for GemHunter purchase")
		return
	end


	if self._remoteEvents.PurchaseGemHunter then
		-- Get current cost and level from stored gem shop data
		local clientCost = self._lastGemShopData and self._lastGemShopData.gemHunterUpgradeCost or 15
		local clientLevel = self._lastGemShopData and self._lastGemShopData.currentGemHunterLevel or 1


		self._remoteEvents.PurchaseGemHunter:FireServer(clientCost, clientLevel)
		
	else
		Logger:Error("PurchaseGemHunter remote event not available")
	end
end

function ShopClient:_updateGemHunterSection(gemShopData)
	local elements = self._uiElements.gemHunter
	if not elements then
		Logger:Debug("GemHunter UI elements not found - skipping update")
		return
	end

	Logger:Debug("Updating GemHunter UI with data: " .. tostring(gemShopData and "available" or "nil"))

	local currentLevel = gemShopData.currentGemHunterLevel or 1
	local nextLevel = currentLevel + 1
	local currentGemDropBonus = (gemShopData.currentGemDropBonus or 0) * 100 -- Convert to percentage
	local nextGemDropBonus = currentGemDropBonus + 2 -- +2% per level

	-- Check if at level cap (gem upgrades max at level 20)
	local atLevelCap = currentLevel >= 20
	local currentLevelText = atLevelCap and "MAX" or tostring(currentLevel)

	Logger:Debug(string.format("GemHunter data: Level=%d, GemDropBonus=%.0f%%, Cost=%d", 
		currentLevel, currentGemDropBonus, gemShopData.gemHunterUpgradeCost or 15))

	-- Update UpgradeLevel: Show current level "Lv. 1", "Lv. 2", etc. or "MAX" if at cap
	if elements.upgradeLevel and elements.upgradeLevel:IsA("TextLabel") then
		elements.upgradeLevel.Text = "Lv. " .. currentLevelText
	end

	-- Update NextUpgrade: Show gem drop bonus improvement "0% -> 5%", "5% -> 10%", etc.
	if elements.nextUpgrade and elements.nextUpgrade:IsA("TextLabel") then
		elements.nextUpgrade.Text = math.floor(currentGemDropBonus) .. "% -> " .. math.floor(nextGemDropBonus) .. "%"
	end

	-- Update GemCost
	if elements.gemCost and elements.gemCost:IsA("TextLabel") then
		local cost = gemShopData.gemHunterUpgradeCost or 15
		Logger:Debug(string.format("Setting GemHunter cost to: %d (was: %s)", cost, elements.gemCost.Text))
		elements.gemCost.Text = tostring(cost)

		-- Update text color based on affordability
		local currentGems = self:_getCurrentGems()
		if currentGems >= cost then
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White when affordable
		else
			elements.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)  -- Red when not affordable
		end
	else
		Logger:Warn("GemHunter gemCost element not found or not a TextLabel")
	end
end

function ShopClient:SetCollectionService(collectionService)
	self._collectionService = collectionService
	Logger:Info("ShopClient linked with CollectionService")

	-- Apply any stored PickUpRange data that was received before linking
	if self._lastGemShopData and self._lastGemShopData.currentPickUpRange then
		local range = self._lastGemShopData.currentPickUpRange
		Logger:Info(string.format("Applying stored PickUpRange: %.2f studs", range))
		collectionService:SetPickUpRange(range)
	else
		Logger:Info("No PickUpRange data available yet - will apply when sync is received")

		-- Set up a flag to apply range when data becomes available
		self._applyRangeWhenAvailable = true
	end
end

function ShopClient:Cleanup()
	Logger:Info("ShopClient shutting down...")

	-- Disconnect all connections
	for _, connection in pairs(self._connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end

	-- Clear references
	self._connections = {}
	self._remoteEvents = {}
	self._remoteFunctions = {}
	self._uiElements = {}

	Logger:Info("✓ ShopClient shutdown complete")
end

function ShopClient:_setupArea3PurchaseButton()
	Logger:Info("Setting up Area3 purchase button...")
	-- Wait for the button to exist (PlayerPlots/PlotTemplate/Area3/PurchaseWall/SurfaceGui/Frame/ImageLabel/PurchaseArea3)
	task.spawn(function()
		Logger:Debug("AREA3 PURCHASE BUTTON: Starting setup task")
		local workspace = game:GetService("Workspace")
		local player = Players.LocalPlayer
		-- Wait for player's plot
		local playerPlots = workspace:WaitForChild("PlayerPlots", 30)
		if not playerPlots then
			Logger:Error("PlayerPlots not found for Area3 button setup")
			return
		end
		local plotName = "Plot_" .. player.Name
		local playerPlot = playerPlots:WaitForChild(plotName, 30)
		if not playerPlot then
			Logger:Error("Player plot not found for Area3 button setup")
			return
		end
		local area3 = playerPlot:WaitForChild("Area3", 10)
		if not area3 then
			Logger:Error("Area3 not found in player plot")
			return
		end
		-- Check if PurchaseWall exists (it won't if Area3 is already unlocked)
		local purchaseWall = area3:FindFirstChild("PurchaseWall")
		if not purchaseWall then
			Logger:Info("PurchaseWall not found in Area3 - Area3 is already unlocked, no setup needed")
			return
		end
		local surfaceGui = purchaseWall:WaitForChild("SurfaceGui", 10)
		if not surfaceGui then
			Logger:Error("SurfaceGui not found in PurchaseWall")
			return
		end
		local frame = surfaceGui:WaitForChild("Frame", 10)
		if not frame then
			Logger:Error("Frame not found in SurfaceGui")
			return
		end
		local imageLabel = frame:WaitForChild("ImageLabel", 10)
		if not imageLabel then
			Logger:Error("ImageLabel not found in Frame")
			return
		end
		local purchaseArea3Button = imageLabel:WaitForChild("PurchaseArea3", 10)
		if not purchaseArea3Button or not purchaseArea3Button:IsA("GuiButton") then
			Logger:Error("PurchaseArea3 button not found or not a GuiButton")
			return
		end
		-- Connect the button
		local connection = purchaseArea3Button.MouseButton1Click:Connect(function()
			self:_purchaseArea3()
		end)
		-- Store connection for cleanup
		self._connections = self._connections or {}
		self._connections.PurchaseArea3 = connection
		Logger:Info("✓ Area3 purchase button connected successfully")
	end)
end

function ShopClient:_purchaseArea3()
	Logger:Info("Area3 purchase (Ascend) button clicked")
	
	-- Check if remote exists, if not try to get it
	if not self._remoteEvents.PurchaseArea3 then
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		if shared then
			local remoteEvents = shared:FindFirstChild("RemoteEvents")
			if remoteEvents then
				local shopEvents = remoteEvents:FindFirstChild("ShopEvents")
				if shopEvents then
					self._remoteEvents.PurchaseArea3 = shopEvents:FindFirstChild("PurchaseArea3")
				end
			end
		end
	end
	
	if self._remoteEvents.PurchaseArea3 then
		self._remoteEvents.PurchaseArea3:FireServer()
		Logger:Info("Area3 purchase (Ascend) request sent to server")
	else
		Logger:Error("PurchaseArea3 remote event not available - server may not have created it yet")
	end
end

function ShopClient:_setupDevProductButtons()
	Logger:Info("Setting up developer product buttons...")
	
	-- Setup gem pack buttons
	self:_setupGemPackButtons()
	
	-- Setup spore pack buttons  
	self:_setupSporePackButtons()
	
	Logger:Info("✓ Developer product buttons setup complete")
end

function ShopClient:_setupGemPackButtons()
	task.spawn(function()
		-- Wait for GemShop UI: GemShop → Container → GemPackContainer → Small, Medium, Big, Large
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local gemShop = playerGui:WaitForChild("GemShop", 30)
		if not gemShop then
			Logger:Error("GemShop GUI not found for gem pack buttons")
			return
		end

		local container = gemShop:WaitForChild("Container", 10)
		if not container then
			Logger:Error("Container not found in GemShop")
			return
		end

		local gemPackContainer = container:WaitForChild("GemPackContainer", 10)
		if not gemPackContainer then
			Logger:Error("GemPackContainer not found in GemShop")
			return
		end

		-- Setup gem pack buttons: Small = GEM_PACK_SMALL, Medium = GEM_PACK_MEDIUM, Big = GEM_PACK_LARGE, Large = GEM_PACK_MEGA
		local gemPacks = {
			{buttonName = "Small", productName = "GEM_PACK_SMALL"},
			{buttonName = "Medium", productName = "GEM_PACK_MEDIUM"}, 
			{buttonName = "Big", productName = "GEM_PACK_LARGE"},
			{buttonName = "Large", productName = "GEM_PACK_MEGA"}
		}

		for _, pack in ipairs(gemPacks) do
			local button = gemPackContainer:FindFirstChild(pack.buttonName)
			if button and button:IsA("GuiButton") then
				self._connections[pack.buttonName .. "GemPack"] = button.MouseButton1Click:Connect(function()
					Logger:Info(string.format("Gem pack button clicked: %s (%s)", pack.buttonName, pack.productName))
					self:_purchaseDevProduct(pack.productName)
				end)
				Logger:Info(string.format("✓ Connected gem pack button: %s", pack.buttonName))
			else
				Logger:Warn(string.format("Gem pack button not found: %s", pack.buttonName))
			end
		end
	end)
end

function ShopClient:_setupSporePackButtons()
	task.spawn(function()
		-- Wait for MushroomShop UI: MushroomShop → Container → SporePackContainer → Bag, Chest, Handful, Vault
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local mushroomShop = playerGui:WaitForChild("MushroomShop", 30)
		if not mushroomShop then
			Logger:Error("MushroomShop GUI not found for spore pack buttons")
			return
		end

		local container = mushroomShop:WaitForChild("Container", 10)
		if not container then
			Logger:Error("Container not found in MushroomShop")
			return
		end

		local sporePackContainer = container:WaitForChild("SporePackContainer", 10)
		if not sporePackContainer then
			Logger:Error("SporePackContainer not found in MushroomShop")
			return
		end

		-- Setup spore pack buttons: Handful = SPORE_PACK_SMALL, Bag = SPORE_PACK_MEDIUM, Chest = SPORE_PACK_LARGE, Vault = SPORE_PACK_MEGA
		local sporePacks = {
			{buttonName = "Handful", productName = "SPORE_PACK_SMALL"},
			{buttonName = "Bag", productName = "SPORE_PACK_MEDIUM"},
			{buttonName = "Chest", productName = "SPORE_PACK_LARGE"},
			{buttonName = "Vault", productName = "SPORE_PACK_MEGA"}
		}

		for _, pack in ipairs(sporePacks) do
			local button = sporePackContainer:FindFirstChild(pack.buttonName)
			if button and button:IsA("GuiButton") then
				self._connections[pack.buttonName .. "SporePack"] = button.MouseButton1Click:Connect(function()
					Logger:Info(string.format("Spore pack button clicked: %s (%s)", pack.buttonName, pack.productName))
					self:_purchaseDevProduct(pack.productName)
				end)
				Logger:Info(string.format("✓ Connected spore pack button: %s", pack.buttonName))
			else
				Logger:Warn(string.format("Spore pack button not found: %s", pack.buttonName))
			end
		end
	end)
end

function ShopClient:SetGamepassClient(gamepassClient)
	self.gamepassClient = gamepassClient
	Logger:Info("ShopClient: GamepassClient linked for dev product purchases")
end

function ShopClient:_purchaseDevProduct(productName)
	Logger:Info(string.format("Attempting to purchase dev product: %s", productName))
	
	-- Use the linked GamepassClient if available
	if self.gamepassClient and self.gamepassClient.PurchaseProduct then
		self.gamepassClient:PurchaseProduct(productName)
		Logger:Info(string.format("Delegated purchase to GamepassClient: %s", productName))
	else
		-- Fallback to direct MarketplaceService call
		Logger:Info("GamepassClient not available, using direct MarketplaceService call")
		
		local MarketplaceService = game:GetService("MarketplaceService")
		local productIds = {
			GEM_PACK_SMALL = 3413686220,
			GEM_PACK_MEDIUM = 3413686218, 
			GEM_PACK_LARGE = 3413686217,
			GEM_PACK_MEGA = 3413686216,
			SPORE_PACK_SMALL = 3413686214,
			SPORE_PACK_MEDIUM = 3413686213,
			SPORE_PACK_LARGE = 3413686212,
			SPORE_PACK_MEGA = 3413686211,
			STARTER_PACK = 3413686209
		}
		
		local productId = productIds[productName]
		if not productId then
			Logger:Error(string.format("Unknown product name: %s", productName))
			return
		end
		
		local success, result = pcall(function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
		end)
		
		if success then
			Logger:Info(string.format("Prompted purchase for %s (ID: %d)", productName, productId))
		else
			Logger:Error(string.format("Failed to prompt purchase for %s: %s", productName, tostring(result)))
		end
	end
end

return ShopClient