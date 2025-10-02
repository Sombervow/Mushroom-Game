local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local Validator = require(script.Parent.Parent.Utilities.Validator)
local SignalManager = require(script.Parent.Parent.Utilities.SignalManager)

local DataService = {}
DataService.__index = DataService

local DATASTORE_NAME = "TestingData_3"
local RETRY_ATTEMPTS = 3
local RETRY_DELAY = 1

local playerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)
local playerDataCache = {}
local saveQueue = {}
local playerHasLoadedData = {} -- Track which players have loaded data

-- Collection tracking for milestones
local playerCollectionCounts = {}

local currencyUpdatedEvent = nil

local DEFAULT_PLAYER_DATA = {
	Spores = 16,
	Gems = 50,
	RobuxSpent = 0, -- Total robux spent by player
	LastSave = 0, -- Will be set to current time for new players
	Version = 1,
	AssignedPlot = nil,
	TutorialCompleted = false, -- Tutorial status
	SporeUpgradeLevel = 0,  -- Legacy global spore upgrade (backwards compatibility)
	Area1SporeUpgradeLevel = 0,  -- Area1-specific spore upgrade level
	Area2SporeUpgradeLevel = 0,  -- Area2-specific spore upgrade level
	FastRunnerLevel = 1,  -- Default to level 1 for FastRunner upgrade
	PickUpRangeLevel = 1,  -- Default to level 1 for PickUpRange upgrade
	FasterShroomsLevel = 1,  -- Default to level 1 for FasterShrooms upgrade
	ShinySporeLevel = 1,  -- Default to level 1 for ShinySpore upgrade
	GemHunterLevel = 1,  -- Default to level 1 for GemHunter upgrade
	-- Area system data
	Area2Unlocked = false,
	Area3Unlocked = false,
	Area1MushroomCount = 0,  -- Separate mushroom count for Area1
	Area2MushroomCount = 0,  -- Separate mushroom count for Area2
	Area3MushroomCount = 0,  -- Separate mushroom count for Area3
	-- Separate mushroom shop levels
	Area1MushroomShopLevel = 0,  -- Area1 mushroom shop level (starts at 0)
	Area2MushroomShopLevel = 0,  -- Area2 mushroom shop level (starts at 0, base price 10000)
	Area3MushroomShopLevel = 0,  -- Area3 mushroom shop level (starts at 0)
	GroupRewards = {
		claimed = false,
		claimTime = 0
	},
	WishData = {
		wishes = 0,  -- Start with 0 wishes
		lastWishTime = os.time(), -- Set to current time to prevent immediate wish spam
		inventory = {}
	},
	DailyRewards = {
		startDay = 0,  -- Day when player first started daily rewards (days since epoch)
		lastClaimDay = 0,  -- Last day player claimed reward (days since epoch)
		claimedDays = {}  -- Table of claimed days {[1] = true, [3] = true, etc.}
	},
	PlotObjects = {
		Mushrooms = {},
		Spores = {},
		Area2Mushrooms = {},  -- Separate storage for Area2 mushrooms
		Area2Spores = {},     -- Separate storage for Area2 spores
		Area3Mushrooms = {},  -- Separate storage for Area3 mushrooms
		Area3Spores = {}      -- Separate storage for Area3 spores
	},
	ObjectCounters = {
		MushroomCounter = 0,
		SporeCounter = 0
	},
}

function DataService.new()
	local self = setmetatable({}, DataService)
	self._connections = {}
	self._plotService = nil
	self._mushroomService = nil
	self._shopService = nil
	self._gamepassService = nil
	self._storageService = nil
	self.PlayerDataLoaded = SignalManager.new()
	self:_initialize()
	return self
end

function DataService:_initialize()
	if RunService:IsServer() then
		self:_setupRemoteEvents()

		self._connections.PlayerAdded = Players.PlayerAdded:Connect(function(player)
			self:_loadPlayerData(player)
		end)

		self._connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
			Logger:Info(string.format("Player %s leaving, saving data...", player.Name))

			-- Player leaving - should cleanup plot
			local success = self:_savePlayerData(player, true)
			if success then
				Logger:Info(string.format("Successfully saved data for %s", player.Name))
			else
				Logger:Error(string.format("FAILED to save data for %s", player.Name))
			end

			-- Clean up collection count tracking
			if playerCollectionCounts[player.UserId] then
				playerCollectionCounts[player.UserId] = nil
			end

			-- DON'T cleanup tracking here - shutdown might still need it
			-- The cleanup will happen in shutdown or when the player object is destroyed
		end)

		game:BindToClose(function()
			self:_saveAllPlayerData()
		end)

		Logger:Info("DataService initialized successfully")
	end
end

function DataService:_setupRemoteEvents()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if shared then
		local remoteEvents = shared:FindFirstChild("RemoteEvents")
		if remoteEvents then
			local dataEvents = remoteEvents:FindFirstChild("DataEvents")
			if dataEvents then
				currencyUpdatedEvent = dataEvents:FindFirstChild("CurrencyUpdated")

				-- Set up collection event handler
				local itemCollectedEvent = dataEvents:FindFirstChild("ItemCollected")
				if itemCollectedEvent then
					itemCollectedEvent.OnServerEvent:Connect(function(player, item, itemType, itemName)
						self:_handleItemCollection(player, item, itemType, itemName)
					end)
					Logger:Debug("ItemCollected event handler connected")
				end
			end
		end
	end

	if not currencyUpdatedEvent then
		Logger:Warn("CurrencyUpdated RemoteEvent not found - currency updates will not be sent to client")
	end
end

function DataService:_handleItemCollection(player, item, itemType, itemName)

	-- Validate player is on their own plot
	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		Logger:Warn(string.format("Player %s tried to collect item but no PlayerPlots found", player.Name))
		return
	end

	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		Logger:Warn(string.format("Player %s tried to collect item but their plot not found", player.Name))
		return
	end

	-- Use passed itemName or get from item if available
	if not itemName and item then
		itemName = item.Name
	else
	end

	-- Initialize collectionArea with default value
	local collectionArea = "Area1" -- Default

	-- If item exists, validate it's in the right place
	if item then
		-- Check if item still exists and is in player's plot
		if not item.Parent or not item:IsDescendantOf(playerPlot) then
			Logger:Warn(string.format("Player %s tried to collect item not in their plot", player.Name))
			return
		end

		-- Validate item is in a Spores folder and determine area
		local validLocation = false
		local sporesFolder = playerPlot:FindFirstChild("Spores")
		local area2 = playerPlot:FindFirstChild("Area2")
		local area2SporesFolder = area2 and area2:FindFirstChild("Spores")
		local area3 = playerPlot:FindFirstChild("Area3")
		local area3SporesFolder = area3 and area3:FindFirstChild("Spores")

		if sporesFolder and item:IsDescendantOf(sporesFolder) then
			validLocation = true
			collectionArea = "Area1"
			Logger:Debug(string.format("Item %s collected from Area1 Spores", itemName or "unknown"))
		elseif area2SporesFolder and item:IsDescendantOf(area2SporesFolder) then
			validLocation = true
			collectionArea = "Area2"
			Logger:Debug(string.format("Item %s collected from Area2 Spores", itemName or "unknown"))
		elseif area3SporesFolder and item:IsDescendantOf(area3SporesFolder) then
			validLocation = true
			collectionArea = "Area3"
			Logger:Debug(string.format("Item %s collected from Area3 Spores", itemName or "unknown"))
		end

		if not validLocation then
			Logger:Warn(string.format("Player %s tried to collect item from invalid location: %s", player.Name, item.Parent and item.Parent.Name or "unknown"))
			return
		end
	end

	-- Determine which area the spore is from
	local isArea2 = false
	local isGoldMushroom = false
	local isClicked = false
	if item then
		-- Check if spore is in Area2 by checking if it's a descendant of Area2
		local area2 = playerPlot:FindFirstChild("Area2")
		if area2 and item:IsDescendantOf(area2) then
			isArea2 = true
		end

		-- Check if spore came from a gold mushroom (indicated by special naming)
		if item and item.Name then
			if string.find(item.Name, "Gold") then
				isGoldMushroom = true
			end
			-- Check if spore came from clicking (indicated by "Clicked" in name)
			if string.find(item.Name, "Clicked") then
				isClicked = true
			end
		end
	elseif itemName then
		-- If item is nil but we have itemName, try to determine area from name patterns
		-- Area2 spores might have different naming conventions
		if string.find(itemName, "Area2") then
			isArea2 = true
		end

		-- Check for gold mushroom spores
		if string.find(itemName, "Gold") then
			isGoldMushroom = true
		end
		
		-- Check for clicked spores
		if string.find(itemName, "Clicked") then
			isClicked = true
		end
	end


	-- Award currency based on item type
	local success = false
	local awardedValue = 0
	if itemType == "spore" then
		-- Apply spore multiplier from shop upgrades
		local baseAmount = 1
		local multiplier = 1.0
		if self._shopService then
			multiplier = self._shopService:GetSporeMultiplier(player)
		end

		-- Apply Area2 bonus (1.5x)
		if isArea2 then
			multiplier = multiplier * 1.5
		end

		-- Apply gold mushroom bonus (2x) - will be implemented later
		if isGoldMushroom then
			multiplier = multiplier * 2.0
		end
		
		-- Apply click multiplier (2x) for spores from clicked mushrooms
		if isClicked and self._gamepassService then
			local clickMultiplier = self._gamepassService:getClickMultiplier(player)
			multiplier = multiplier * clickMultiplier
		end

		local finalAmount = math.floor((baseAmount * multiplier) * 100 + 0.5) / 100 -- Round to 2 decimals
		
		-- Apply gamepass multiplier to the awarded value for UI display
		local gamepassMultiplier = 1
		if self._gamepassService then
			gamepassMultiplier = self._gamepassService:getSporeMultiplier(player)
		end
		
		success = self:AddSpores(player, finalAmount)
		awardedValue = finalAmount * gamepassMultiplier
	elseif itemType == "bigspore" then
		-- BigSpore is worth 100 spores with multiplier applied
		local baseAmount = 100
		local multiplier = 1.0
		if self._shopService then
			multiplier = self._shopService:GetSporeMultiplier(player)
		end

		-- Apply Area2 bonus (1.5x)
		if isArea2 then
			multiplier = multiplier * 1.5
		end

		-- Apply gold mushroom bonus (2x) - will be implemented later
		if isGoldMushroom then
			multiplier = multiplier * 2.0
		end

		local finalAmount = math.floor((baseAmount * multiplier) * 100 + 0.5) / 100 -- Round to 2 decimals
		
		-- Apply gamepass multiplier to the awarded value for UI display
		local gamepassMultiplier = 1
		if self._gamepassService then
			gamepassMultiplier = self._gamepassService:getSporeMultiplier(player)
		end
		
		success = self:AddSpores(player, finalAmount)
		awardedValue = finalAmount * gamepassMultiplier
		Logger:Info(string.format("Player %s collected BigSpore with %.1f%% multiplier (base:%d, final:%d, area2:%s, gold:%s)", 
			player.Name, (multiplier - 1) * 100, baseAmount, finalAmount, tostring(isArea2), tostring(isGoldMushroom)))
	elseif itemType == "gem" then
		success = self:AddGems(player, 1)
		awardedValue = 1
	else
		Logger:Warn(string.format("Player %s tried to collect unknown item type: %s", player.Name, tostring(itemType)))
		return
	end

	if success then
		-- Remove the item from the server if it still exists
		if item and item.Parent then
			item:Destroy()
		end

		-- Remove the collected item from saved data
		if itemName then
			local data = playerDataCache[player.UserId]

			if data and data.PlotObjects then
				local found = false

				-- Check all areas for spore removal (Area3, Area2, Area1)
				-- Check Area3 spores first
				if data.PlotObjects.Area3Spores then
					for i = #data.PlotObjects.Area3Spores, 1, -1 do
						local sporeData = data.PlotObjects.Area3Spores[i]
						if sporeData.Name == itemName then
							table.remove(data.PlotObjects.Area3Spores, i)
							found = true
							Logger:Debug(string.format("Removed spore %s from Area3Spores array for %s", itemName, player.Name))
							break
						end
					end
				end

				-- Check Area2 spores if not found in Area3
				if not found and data.PlotObjects.Area2Spores then
					for i = #data.PlotObjects.Area2Spores, 1, -1 do
						local sporeData = data.PlotObjects.Area2Spores[i]
						if sporeData.Name == itemName then
							table.remove(data.PlotObjects.Area2Spores, i)
							found = true
							Logger:Debug(string.format("Removed spore %s from Area2Spores array for %s", itemName, player.Name))
							break
						end
					end
				end

				-- Check Area1 spores if not found in Area3 or Area2
				if not found and data.PlotObjects.Spores then
					for i = #data.PlotObjects.Spores, 1, -1 do
						local sporeData = data.PlotObjects.Spores[i]
						if sporeData.Name == itemName then
							table.remove(data.PlotObjects.Spores, i)
							found = true
							Logger:Debug(string.format("Removed spore %s from Area1 Spores array for %s", itemName, player.Name))
							break
						end
					end
				end

				if found then
					-- Save the plot objects immediately after successful removal to ensure persistence
					self:SavePlotObjects(player)
				end
			end
		end

		-- Fire CollectionConfirmed event to notify client for counter UI
		local collectionPosition = Vector3.new(0, 0, 0) -- Default position
		if item and item.Position then
			collectionPosition = item.Position
		elseif player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			collectionPosition = player.Character.HumanoidRootPart.Position
		end

		-- Get the CollectionConfirmed remote event
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		if shared then
			local remoteEvents = shared:FindFirstChild("RemoteEvents")
			if remoteEvents then
				local dataEvents = remoteEvents:FindFirstChild("DataEvents")
				if dataEvents then
					local collectionConfirmed = dataEvents:FindFirstChild("CollectionConfirmed")
					if collectionConfirmed then
						collectionConfirmed:FireClient(player, itemType, awardedValue, collectionPosition)
						Logger:Debug(string.format("Fired CollectionConfirmed for %s: %s (%.2f value)", player.Name, itemType, awardedValue))
					end
				end
			end
		end

		-- Track spore collection for storage system
		if self._storageService then
			self._storageService:OnSporeCollected(player, collectionArea)
		end

	else
		Logger:Error(string.format("Failed to award %s to player %s", itemType, player.Name))
	end
end

function DataService:_retryOperation(operation, operationName, ...)
	local args = {...}

	for attempt = 1, RETRY_ATTEMPTS do
		local success, result = pcall(operation, unpack(args))

		if success then
			if attempt > 1 then
				Logger:Info(string.format("%s succeeded on attempt %d", operationName, attempt))
			end
			return true, result
		else
			Logger:Warn(string.format("%s failed on attempt %d: %s", operationName, attempt, tostring(result)))

			if attempt < RETRY_ATTEMPTS then
				wait(RETRY_DELAY * attempt)
			else
				Logger:Error(string.format("%s failed after %d attempts: %s", operationName, RETRY_ATTEMPTS, tostring(result)))
				return false, result
			end
		end
	end

	return false, "Max retry attempts exceeded"
end

function DataService:_loadPlayerData(player)
	local userId = player.UserId
	local playerKey = "Player_" .. userId

	Logger:Info(string.format("Loading data for player %s (ID: %d)", player.Name, userId))

	local success, data = self:_retryOperation(function()
		return playerDataStore:GetAsync(playerKey)
	end, "LoadPlayerData", playerKey)

	Logger:Debug(string.format("DataStore load result for %s - Success: %s, Data exists: %s", 
		player.Name, tostring(success), tostring(data ~= nil)))

	local isNewPlayer = false

	if success then
		if data then
			local validatedData = Validator:ValidatePlayerData(data, DEFAULT_PLAYER_DATA)
			playerDataCache[userId] = validatedData

			-- Debug logging for loaded data
			local plotObjCount = 0
			if validatedData.PlotObjects then
				local mushrooms = validatedData.PlotObjects.Mushrooms and #validatedData.PlotObjects.Mushrooms or 0
				local spores = validatedData.PlotObjects.Spores and #validatedData.PlotObjects.Spores or 0
				plotObjCount = mushrooms + spores
			else
				Logger:Debug(string.format("Loaded data for %s has no PlotObjects field", player.Name))
			end

			-- validatedData.LastSave remains what was loaded from datastore

			Logger:Info(string.format("Successfully loaded EXISTING data for player %s (%d plot objects)", player.Name, plotObjCount))
		else
			playerDataCache[userId] = Validator:DeepCopy(DEFAULT_PLAYER_DATA)
			playerDataCache[userId].LastSave = tick() -- Set to current time for new players
			isNewPlayer = true
			Logger:Info(string.format("NEW PLAYER: %s - no existing data found, using defaults", player.Name))
		end
	else
		playerDataCache[userId] = Validator:DeepCopy(DEFAULT_PLAYER_DATA)
		playerDataCache[userId].LastSave = tick() -- Set to current time for new players
		isNewPlayer = true
		Logger:Error(string.format("Failed to load data for player %s, treating as NEW PLAYER", player.Name))
	end

	playerHasLoadedData[player] = not isNewPlayer

	-- Debug what data was loaded
	Logger:Info(string.format("Data loaded for %s (new player: %s)", player.Name, tostring(isNewPlayer)))

	self.PlayerDataLoaded:Fire(player, playerDataCache[userId], isNewPlayer)
	
	-- Initialize mushrooms for the player with a small delay to ensure plot is ready
	if self._mushroomService and self._mushroomService.InitializePlayerMushrooms then
		task.spawn(function()
			task.wait(3) -- Wait for plot creation to complete
			self._mushroomService:InitializePlayerMushrooms(player)
		end)
	end
end

-- Collect current player data from the game world (like reference implementation)
function DataService:_collectCurrentPlayerData(player)
	-- Start with cached data or defaults
	local baseData = playerDataCache[player.UserId] or Validator:DeepCopy(DEFAULT_PLAYER_DATA)

	-- Collect fresh plot objects BEFORE cleanup happens
	Logger:Info(string.format("Collecting fresh plot objects for leaving player %s", player.Name))
	local saveSuccess = self:SavePlotObjects(player)
	Logger:Info(string.format("Plot object collection returned %s for %s", tostring(saveSuccess), player.Name))

	-- Get the updated data after SavePlotObjects (it updates the cache)
	local updatedData = playerDataCache[player.UserId] or baseData
	updatedData.LastSave = tick()



	return updatedData
end

function DataService:_savePlayerData(player, shouldCleanup)
	-- shouldCleanup defaults to false for manual saves, true for player leaving
	shouldCleanup = shouldCleanup ~= false -- Default to true unless explicitly false
	
	local userId = player.UserId
	local playerKey = "Player_" .. userId
	local data = playerDataCache[userId]

	if not data then
		Logger:Warn(string.format("No data to save for player %s", player.Name))
		return false
	end

	if saveQueue[userId] then
		Logger:Warn(string.format("Save already in progress for player %s", player.Name))
		return false
	end

	saveQueue[userId] = true
	data.LastSave = tick()

	-- Save plot objects before cleanup
	local saveSuccess = self:SavePlotObjects(player)

	-- FIXED: Only cleanup services if player is leaving, not for manual saves
	if shouldCleanup then
		Logger:Info(string.format("Cleaning up services for departing player %s", player.Name))
		
		-- Player cleanup is handled by client-side services now

		if self._plotService then
			self._plotService:CleanupPlayerPlot(player)
		end
	else
		Logger:Debug(string.format("Manual save for %s - skipping cleanup", player.Name))
	end

	-- Save to DataStore

	local success, result = self:_retryOperation(function()
		return playerDataStore:SetAsync(playerKey, data)
	end, "SavePlayerData", playerKey, data)

	saveQueue[userId] = nil

	if success then
		Logger:Info(string.format("Successfully saved data for player %s", player.Name))
		-- Don't cleanup counters here - let PlayerRemoving connection handle final cleanup
		return true
	else
		Logger:Error(string.format("Failed to save data for player %s: %s", player.Name, tostring(result)))
		return false
	end
end

function DataService:_saveAllPlayerData()
	Logger:Info("Saving all player data before shutdown")

	-- Save all players who have loaded data (like reference implementation)
	local playersList = {}
	local playersToCleanup = {}
	local skipCount = 0

	for player, hasData in pairs(playerHasLoadedData) do
		if hasData then -- Player has data (don't check parent - they might be leaving)
			-- Check if save is already in progress for this player
			if saveQueue[player.UserId] then
				Logger:Info(string.format("Skipping shutdown save for %s - PlayerRemoving save in progress", player.Name))
				skipCount = skipCount + 1
				table.insert(playersToCleanup, player) -- Still need cleanup
			else
				table.insert(playersList, player.Name)
				table.insert(playersToCleanup, player)

				spawn(function() -- Use spawn like reference implementation
					-- Save player data (includes collecting fresh plot objects)
					-- Shutdown save - should cleanup plot
					local success = self:_savePlayerData(player, true)

					if success then
						Logger:Info(string.format("Shutdown save successful for %s", player.Name))
					else
						Logger:Error(string.format("Shutdown save FAILED for %s", player.Name))
					end

					-- Final cleanup handled client-side
				end)
			end
		end
	end

	if #playersList > 0 then
		Logger:Info(string.format("Started shutdown saves for %d players: %s", #playersList, table.concat(playersList, ", ")))
	end

	if skipCount > 0 then
		Logger:Info(string.format("Skipped %d players (already saving via PlayerRemoving)", skipCount))
	end

	-- Wait for shutdown saves (like reference implementation)
	wait(5)

	-- Clean up tracking after shutdown saves
	for _, player in ipairs(playersToCleanup) do
		playerHasLoadedData[player] = nil
		playerDataCache[player.UserId] = nil
	end

	Logger:Info("Shutdown saves complete")
end

-- Function to reset player's mushroom data to new system (for players with old saves)
function DataService:ResetPlayerMushrooms(player)
	local userId = player.UserId
	local data = playerDataCache[userId]
	if not data then
		Logger:Warn(string.format("No cached data found for player %s", player.Name))
		return false
	end

	-- Clear all mushroom data
	if data.PlotObjects then
		data.PlotObjects.Mushrooms = {}
		data.PlotObjects.Area2Mushrooms = {}
	end

	-- Reset mushroom counts
	data.Area1MushroomCount = 0
	data.Area2MushroomCount = 0

	-- Update counters
	if data.ObjectCounters then
		data.ObjectCounters.MushroomCounter = 0
	end

	Logger:Info(string.format("Reset mushroom data for player %s - they will start fresh with new models", player.Name))
	return true
end

function DataService:GetPlayerData(player)
	local userId = player.UserId
	local data = playerDataCache[userId]

	if not data then
		Logger:Warn(string.format("No cached data found for player %s", player.Name))
		return nil
	end

	return Validator:DeepCopy(data)
end

-- PERFORMANCE: Direct cache access for internal optimization (no deep copy)
-- WARNING: Only use this when you need to modify the cache directly!
function DataService:_getPlayerDataCache(userId)
	return playerDataCache[userId]
end

function DataService:UpdatePlayerData(player, updateFunction)
	local userId = player.UserId
	local data = playerDataCache[userId]

	if not data then
		Logger:Error(string.format("Cannot update data for player %s - no cached data found", player.Name))
		return false
	end


	local success, result = pcall(updateFunction, data)
	if not success then
		Logger:Error(string.format("Failed to update data for player %s: %s", player.Name, tostring(result)))
		return false
	end


	local validatedData = Validator:ValidatePlayerData(data, DEFAULT_PLAYER_DATA)


	playerDataCache[userId] = validatedData

	return true
end

function DataService:AddSpores(player, amount)
	if not Validator:IsValidDecimalCurrency(amount) then
		Logger:Warn(string.format("Invalid spore amount for player %s: %s", player.Name, tostring(amount)))
		return false
	end

	local originalAmount = amount
	
	-- Apply gamepass multiplier if available
	if self._gamepassService then
		local multiplier = self._gamepassService:getSporeMultiplier(player)
		amount = amount * multiplier
	else
		Logger:Warn(string.format("DataService: GamepassService not available for %s", player.Name))
	end

	local success = self:UpdatePlayerData(player, function(data)
		data.Spores = Validator:RoundToTwoDecimals(data.Spores + amount)
	end)

	if success then
		-- Track spore collection for milestones
		local userId = player.UserId
		if not playerCollectionCounts[userId] then
			playerCollectionCounts[userId] = {spores = 0, gems = 0}
		end
		playerCollectionCounts[userId].spores = playerCollectionCounts[userId].spores + originalAmount
		
		-- Track collection milestone analytics
		if self._robloxAnalyticsService then
			self._robloxAnalyticsService:TrackCollectionMilestone(player, "Spore", playerCollectionCounts[userId].spores)
		end
		
		if currencyUpdatedEvent then
			currencyUpdatedEvent:FireClient(player, "Spores", self:GetSpores(player))
		end
		self:_updatePlayerLeaderstats(player)
	end

	return success
end

function DataService:AddGems(player, amount)
	if not Validator:IsPositiveNumber(amount) then
		Logger:Warn(string.format("Invalid gem amount for player %s: %s", player.Name, tostring(amount)))
		return false
	end

	local originalAmount = amount
	
	-- Apply gamepass multiplier if available
	if self._gamepassService then
		local multiplier = self._gamepassService:getGemMultiplier(player)
		amount = amount * multiplier
	end

	local success = self:UpdatePlayerData(player, function(data)
		data.Gems = data.Gems + amount
	end)

	if success then
		-- Track gem collection for milestones
		local userId = player.UserId
		if not playerCollectionCounts[userId] then
			playerCollectionCounts[userId] = {spores = 0, gems = 0}
		end
		playerCollectionCounts[userId].gems = playerCollectionCounts[userId].gems + originalAmount
		
		-- Track collection milestone analytics
		if self._robloxAnalyticsService then
			self._robloxAnalyticsService:TrackCollectionMilestone(player, "Gem", playerCollectionCounts[userId].gems)
		end
		
		if currencyUpdatedEvent then
			currencyUpdatedEvent:FireClient(player, "Gems", self:GetGems(player))
		end
		self:_updatePlayerLeaderstats(player)
	end

	return success
end

function DataService:SpendSpores(player, amount)
	if not Validator:IsValidDecimalCurrency(amount) then
		Logger:Warn(string.format("Invalid spore amount for player %s: %s", player.Name, tostring(amount)))
		return false
	end

	local data = self:GetPlayerData(player)
	if not data or data.Spores < amount then
		Logger:Warn(string.format("Player %s does not have enough spores (%.2f required, %.2f available)", 
			player.Name, amount, data and data.Spores or 0))
		return false
	end

	local success = self:UpdatePlayerData(player, function(playerData)
		playerData.Spores = Validator:RoundToTwoDecimals(playerData.Spores - amount)
	end)

	if success then
		if currencyUpdatedEvent then
			currencyUpdatedEvent:FireClient(player, "Spores", self:GetSpores(player))
		end
		self:_updatePlayerLeaderstats(player)
	end

	return success
end

function DataService:SpendGems(player, amount)
	if not Validator:IsPositiveNumber(amount) then
		Logger:Warn(string.format("Invalid gem amount for player %s: %s", player.Name, tostring(amount)))
		return false
	end

	local data = self:GetPlayerData(player)
	if not data or data.Gems < amount then
		Logger:Warn(string.format("Player %s does not have enough gems (%d required, %d available)", 
			player.Name, amount, data and data.Gems or 0))
		return false
	end

	local success = self:UpdatePlayerData(player, function(playerData)
		playerData.Gems = playerData.Gems - amount
	end)

	if success then
		if currencyUpdatedEvent then
			currencyUpdatedEvent:FireClient(player, "Gems", self:GetGems(player))
		end
		self:_updatePlayerLeaderstats(player)
	end

	return success
end

function DataService:GetSpores(player)
	local data = self:GetPlayerData(player)
	return data and data.Spores or 0
end

function DataService:GetGems(player)
	local data = self:GetPlayerData(player)
	return data and data.Gems or 0
end

function DataService:GetRobuxSpent(player)
	local data = self:GetPlayerData(player)
	local robuxSpent = data and data.RobuxSpent or 0
	Logger:Debug(string.format("GetRobuxSpent for %s: data exists=%s, RobuxSpent=%s", 
		player.Name, tostring(data ~= nil), tostring(robuxSpent)))
	return robuxSpent
end

function DataService:AddRobuxSpent(player, amount)
	if not player or not amount or amount <= 0 then
		Logger:Warn("Invalid parameters for AddRobuxSpent")
		return false
	end
	
	Logger:Debug(string.format("AddRobuxSpent called for %s: adding %d robux", player.Name, amount))
	
	local success = self:UpdatePlayerData(player, function(data)
		local oldAmount = data.RobuxSpent or 0
		data.RobuxSpent = oldAmount + amount
		Logger:Info(string.format("Added %d robux to %s's total (was: %d, now: %d robux spent)", amount, player.Name, oldAmount, data.RobuxSpent))
	end)
	
	if success then
		-- Verify the cache was updated correctly
		local cachedData = playerDataCache[player.UserId]
		local cachedRobux = cachedData and cachedData.RobuxSpent or 0
		Logger:Debug(string.format("Cache verification for %s: RobuxSpent = %d", player.Name, cachedRobux))
		
		-- Update leaderstats if they exist
		self:_updatePlayerLeaderstats(player)
		Logger:Debug(string.format("✓ Successfully updated robux data in cache for %s", player.Name))
	else
		Logger:Error(string.format("❌ Failed to update robux data for %s", player.Name))
	end
	
	return success
end

function DataService:SetAssignedPlot(player, plotId)
	if not Validator:IsValidPlotId(plotId) then
		Logger:Warn(string.format("Invalid plot ID for player %s: %s", player.Name, tostring(plotId)))
		return false
	end

	return self:UpdatePlayerData(player, function(data)
		data.AssignedPlot = plotId
	end)
end

function DataService:GetAssignedPlot(player)
	local data = self:GetPlayerData(player)
	return data and data.AssignedPlot or nil
end

-- Area2 system methods
function DataService:IsArea2Unlocked(player)
	local data = self:GetPlayerData(player)
	return data and data.Area2Unlocked or false
end

function DataService:UnlockArea2(player)
	return self:UpdatePlayerData(player, function(data)
		data.Area2Unlocked = true
	end)
end

-- Area3 system methods
function DataService:IsArea3Unlocked(player)
	local data = self:GetPlayerData(player)
	return data and data.Area3Unlocked or false
end

function DataService:UnlockArea3(player)
	return self:UpdatePlayerData(player, function(data)
		data.Area3Unlocked = true
	end)
end

function DataService:GetArea1MushroomCount(player)
	-- Get count from MushroomDataService if available, otherwise fall back to saved data
	if self._mushroomService and self._mushroomService.GetMushroomCount then
		return self._mushroomService:GetMushroomCount(player, "Area1")
	end
	local data = self:GetPlayerData(player)
	return data and data.Area1MushroomCount or 0
end

function DataService:GetArea2MushroomCount(player)
	-- Get count from MushroomDataService if available, otherwise fall back to saved data
	if self._mushroomService and self._mushroomService.GetMushroomCount then
		return self._mushroomService:GetMushroomCount(player, "Area2")
	end
	local data = self:GetPlayerData(player)
	return data and data.Area2MushroomCount or 0
end

function DataService:GetArea3MushroomCount(player)
	-- Get count from MushroomDataService if available, otherwise fall back to saved data
	if self._mushroomService and self._mushroomService.GetMushroomCount then
		return self._mushroomService:GetMushroomCount(player, "Area3")
	end
	local data = self:GetPlayerData(player)
	return data and data.Area3MushroomCount or 0
end

function DataService:IncrementArea1MushroomCount(player)
	return self:UpdatePlayerData(player, function(data)
		data.Area1MushroomCount = (data.Area1MushroomCount or 0) + 1
	end)
end

function DataService:IncrementArea2MushroomCount(player)
	return self:UpdatePlayerData(player, function(data)
		data.Area2MushroomCount = (data.Area2MushroomCount or 0) + 1
	end)
end

function DataService:IncrementArea3MushroomCount(player)
	return self:UpdatePlayerData(player, function(data)
		data.Area3MushroomCount = (data.Area3MushroomCount or 0) + 1
	end)
end

-- Mushroom Shop Level functions
function DataService:GetArea1MushroomShopLevel(player)
	local data = self:GetPlayerData(player)
	return data and data.Area1MushroomShopLevel or 0
end

function DataService:GetArea2MushroomShopLevel(player)
	local data = self:GetPlayerData(player)
	return data and data.Area2MushroomShopLevel or 0
end

function DataService:GetArea3MushroomShopLevel(player)
	local data = self:GetPlayerData(player)
	return data and data.Area3MushroomShopLevel or 0
end

function DataService:IncrementArea1MushroomShopLevel(player)
	return self:UpdatePlayerData(player, function(data)
		data.Area1MushroomShopLevel = (data.Area1MushroomShopLevel or 0) + 1
	end)
end

function DataService:IncrementArea2MushroomShopLevel(player)
	return self:UpdatePlayerData(player, function(data)
		data.Area2MushroomShopLevel = (data.Area2MushroomShopLevel or 0) + 1
	end)
end

function DataService:IncrementArea3MushroomShopLevel(player)
	return self:UpdatePlayerData(player, function(data)
		data.Area3MushroomShopLevel = (data.Area3MushroomShopLevel or 0) + 1
	end)
end

function DataService:_updatePlayerLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	-- Use cached data directly to avoid race conditions with deep copies
	local data = playerDataCache[player.UserId]
	if not data then
		Logger:Warn(string.format("No cached data found for leaderstats update: %s", player.Name))
		return
	end

	local spores = leaderstats:FindFirstChild("Spores")
	if spores then
		spores.Value = data.Spores or 0
	end

	local gems = leaderstats:FindFirstChild("Gems")
	if gems then
		gems.Value = data.Gems or 0
	end

	-- RobuxSpent no longer displayed in Roblox leaderstats - only tracked in custom leaderboards
	Logger:Debug(string.format("Updated Roblox leaderstats for %s: %d spores, %d gems", player.Name, data.Spores or 0, data.Gems or 0))
end

function DataService:ManualSave(player)
	Logger:Info(string.format("Manual save requested for player %s", player.Name))
	-- FIXED: Manual saves should NOT cleanup plot - use shouldCleanup = false
	return self:_savePlayerData(player, false)
end

function DataService:ResetPlayerData(player)
	Logger:Info(string.format("Resetting data for player %s", player.Name))

	local userId = player.UserId

	-- Replace cached data with fresh defaults
	playerDataCache[userId] = Validator:DeepCopy(DEFAULT_PLAYER_DATA)

	-- Update leaderstats immediately
	self:_updatePlayerLeaderstats(player)

	-- Save the reset data without cleanup
	self:_savePlayerData(player, false)

	-- Signal that data was reset
	self.PlayerDataLoaded:Fire(player, playerDataCache[userId], true)
	
	-- Initialize mushrooms for the player with a small delay to ensure plot is ready
	if self._mushroomService and self._mushroomService.InitializePlayerMushrooms then
		task.spawn(function()
			task.wait(3) -- Wait for plot creation to complete
			self._mushroomService:InitializePlayerMushrooms(player)
		end)
	end

	Logger:Info(string.format("Successfully reset data for player %s", player.Name))
	return true
end

-- Save plot objects (mushrooms and spores) to player data
function DataService:SavePlotObjects(player)
	Logger:Debug(string.format("SavePlotObjects called for player %s", player.Name))

	local data = playerDataCache[player.UserId]
	if not data then
		Logger:Warn(string.format("No data found for player %s when saving plot objects", player.Name))
		return false
	end

	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		Logger:Warn("PlayerPlots not found in workspace")
		return false
	end

	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		Logger:Warn(string.format("Plot not found for player %s - cannot save plot objects", player.Name))
		return false
	end

	Logger:Debug(string.format("Found player plot for %s, scanning for objects...", player.Name))
	local folderNames = {}
	for _, child in pairs(playerPlot:GetChildren()) do
		table.insert(folderNames, child.Name)
	end
	Logger:Debug(string.format("Plot %s has these folders: %s", player.Name, table.concat(folderNames, ", ")))

	-- Save mushrooms
	local mushroomsFolder = playerPlot:FindFirstChild("Mushrooms")
	local mushroomData = {}
	if mushroomsFolder then
		Logger:Debug(string.format("Found Mushrooms folder for %s with %d children", player.Name, #mushroomsFolder:GetChildren()))
		for _, mushroom in pairs(mushroomsFolder:GetChildren()) do
			Logger:Debug(string.format("Checking mushroom: %s (%s) - matches pattern: %s", 
				mushroom.Name, mushroom.ClassName, tostring(string.find(mushroom.Name, "MushroomModel_") ~= nil)))
			if mushroom:IsA("Model") and string.find(mushroom.Name, "MushroomModel_") then
				local position = mushroom.PrimaryPart and mushroom.PrimaryPart.Position or Vector3.new(0, 0, 0)
				local cframe = mushroom.PrimaryPart and mushroom.PrimaryPart.CFrame or CFrame.new()

				-- Convert absolute position to relative position within the plot
				local plotCenter = playerPlot.PrimaryPart and playerPlot.PrimaryPart.Position or Vector3.new(0, 0, 0)
				local relativePosition = position - plotCenter
				
				-- Convert absolute CFrame to relative CFrame within the plot
				local plotCFrame = playerPlot.PrimaryPart and playerPlot.PrimaryPart.CFrame or CFrame.new()
				local relativeCFrame = plotCFrame:Inverse() * cframe

				-- Determine the model type from the mushroom's appearance/data
				-- We can infer this from the mushroom's model structure or store it as an attribute
				local modelType = mushroom:GetAttribute("ModelType") or "Mushroom_1" -- Fallback to Mushroom_1

				local mushroomInfo = {
					Name = mushroom.Name,
					Position = {relativePosition.X, relativePosition.Y, relativePosition.Z},
					Rotation = {relativeCFrame:GetComponents()},
					ModelType = modelType -- Store the model type used
				}
				table.insert(mushroomData, mushroomInfo)
				Logger:Debug(string.format("Saved mushroom %s at position %s", mushroom.Name, tostring(position)))
			end
		end
	else
		Logger:Debug(string.format("No Mushrooms folder found for %s", player.Name))
	end

	-- Save Area2 mushrooms separately
	local area2MushroomData = {}
	local area2 = playerPlot:FindFirstChild("Area2")
	if area2 then
		local area2MushroomsFolder = area2:FindFirstChild("Mushrooms")
		if area2MushroomsFolder then
			for _, mushroom in pairs(area2MushroomsFolder:GetChildren()) do
				if mushroom:IsA("Model") and string.find(mushroom.Name, "MushroomModel_") then
					local position = mushroom.PrimaryPart and mushroom.PrimaryPart.Position or Vector3.new(0, 0, 0)
					local cframe = mushroom.PrimaryPart and mushroom.PrimaryPart.CFrame or CFrame.new()

					-- Convert absolute position to relative position within the plot
					local plotCenter = playerPlot.PrimaryPart and playerPlot.PrimaryPart.Position or Vector3.new(0, 0, 0)
					local relativePosition = position - plotCenter
					
					-- Convert absolute CFrame to relative CFrame within the plot
					local plotCFrame = playerPlot.PrimaryPart and playerPlot.PrimaryPart.CFrame or CFrame.new()
					local relativeCFrame = plotCFrame:Inverse() * cframe

					local modelType = mushroom:GetAttribute("ModelType") or "Mushroom_3"

					local mushroomInfo = {
						Name = mushroom.Name,
						Position = {relativePosition.X, relativePosition.Y, relativePosition.Z},
						Rotation = {relativeCFrame:GetComponents()},
						ModelType = modelType
					}
					table.insert(area2MushroomData, mushroomInfo)
				end
			end
		end
	end

	-- Use cached spore data (with collected spores already removed) instead of scanning world
	local sporeData = data.PlotObjects.Spores or {}
	local area2SporeData = data.PlotObjects.Area2Spores or {}


	-- Counters not needed in new client-side system
	local counters = {MushroomCounter = 0, SporeCounter = 0}

	data.PlotObjects = {
		Mushrooms = mushroomData,
		Spores = sporeData,
		Area2Mushrooms = area2MushroomData,
		Area2Spores = area2SporeData
	}
	data.ObjectCounters = counters

	-- Verify the data was stored correctly
	local storedArea2Count = data.PlotObjects.Area2Mushrooms and #data.PlotObjects.Area2Mushrooms or 0

	return true
end

-- Load plot objects (mushrooms and spores) from player data
function DataService:LoadPlotObjects(player)
	local data = playerDataCache[player.UserId]
	if not data then
		Logger:Debug(string.format("No cached data found for player %s", player.Name))
		return false
	end

	Logger:Debug(string.format("Checking plot objects for %s - PlotObjects exists: %s", 
		player.Name, tostring(data.PlotObjects ~= nil)))

	if not data.PlotObjects then
		Logger:Debug(string.format("No PlotObjects field for player %s", player.Name))
		return false
	end

	local mushroomCount = data.PlotObjects.Mushrooms and #data.PlotObjects.Mushrooms or 0
	local sporeCount = data.PlotObjects.Spores and #data.PlotObjects.Spores or 0
	local area2MushroomCount = data.PlotObjects.Area2Mushrooms and #data.PlotObjects.Area2Mushrooms or 0

	-- Return false if there are no objects to load at all
	if mushroomCount == 0 and sporeCount == 0 and area2MushroomCount == 0 then
		Logger:Debug(string.format("No plot objects to load for player %s", player.Name))
		return false
	end


	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		Logger:Warn("PlayerPlots not found in workspace")
		return false
	end

	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		Logger:Warn(string.format("Plot not found for player %s", player.Name))
		return false
	end

	local plotObjects = data.PlotObjects
	local sporeTemplate = game.ReplicatedStorage:FindFirstChild("SporePart")
	local gemTemplate = game.ReplicatedStorage:FindFirstChild("GemSporePart")
	local bigSporeTemplate = game.ReplicatedStorage:FindFirstChild("BigSpore")

	-- We'll get mushroom templates dynamically based on saved model type

	-- Ensure folders exist
	local mushroomsFolder = playerPlot:FindFirstChild("Mushrooms")
	if not mushroomsFolder then
		mushroomsFolder = Instance.new("Folder")
		mushroomsFolder.Name = "Mushrooms"
		mushroomsFolder.Parent = playerPlot
	end

	local sporesFolder = playerPlot:FindFirstChild("Spores")
	if not sporesFolder then
		sporesFolder = Instance.new("Folder")
		sporesFolder.Name = "Spores"
		sporesFolder.Parent = playerPlot
	end

	-- Check if this is old save data without ModelType - if so, reset everything
	local hasOldMushrooms = false
	if plotObjects.Mushrooms then
		for _, mushroomInfo in pairs(plotObjects.Mushrooms) do
			if not mushroomInfo.ModelType then
				hasOldMushrooms = true
				break
			end
		end
	end

	if hasOldMushrooms then
		Logger:Info(string.format("Player %s has old mushroom save data - resetting to new model system", player.Name))
		self:ResetPlayerMushrooms(player)
		return false -- Return false so player gets a fresh default mushroom
	end

	-- Load mushrooms (all should have ModelType at this point)
	if plotObjects.Mushrooms then
		for _, mushroomInfo in pairs(plotObjects.Mushrooms) do
			local modelType = mushroomInfo.ModelType or "Mushroom_1" -- Default if missing
			local mushroomTemplate

			-- Check MODELS folder first for new models
			local modelsFolder = game.ReplicatedStorage:FindFirstChild("MODELS")
			if modelsFolder then
				mushroomTemplate = modelsFolder:FindFirstChild(modelType)
			end

			-- If not found, try to find any mushroom template as fallback
			if not mushroomTemplate and modelsFolder then
				Logger:Warn(string.format("Mushroom template %s not found, trying Mushroom_1 for player %s", modelType, player.Name))
				mushroomTemplate = modelsFolder:FindFirstChild("Mushroom_1")
				modelType = "Mushroom_1" -- Update to correct type
			end

			if not mushroomTemplate then
				Logger:Error(string.format("No mushroom templates found in MODELS folder for player %s, skipping", player.Name))
				continue
			end

			local mushroom = mushroomTemplate:Clone()
			mushroom.Name = mushroomInfo.Name or "MushroomModel_1"

			-- Restore the model type attribute
			mushroom:SetAttribute("ModelType", modelType)

			-- Make all parts anchored and non-collidable
			for _, part in pairs(mushroom:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
				end
			end
			
			-- Add ClickDetector for mobile and desktop interaction
			self:_addClickDetectorToMushroom(mushroom)

			-- Position the mushroom relative to the plot
			if mushroom.PrimaryPart then
				local relativePosition
				if type(mushroomInfo.Position) == "table" then
					-- New format: array of numbers (relative to plot)
					relativePosition = Vector3.new(
						mushroomInfo.Position[1] or 0,
						mushroomInfo.Position[2] or 0, 
						mushroomInfo.Position[3] or 0
					)
				else
					-- Old format: absolute position - convert to relative
					local absolutePosition = mushroomInfo.Position or Vector3.new(0, 0, 0)
					local plotCenter = playerPlot.PrimaryPart and playerPlot.PrimaryPart.Position or Vector3.new(0, 0, 0)
					relativePosition = absolutePosition - plotCenter
				end

				-- Convert relative position to absolute position for current plot
				local plotCenter = playerPlot.PrimaryPart and playerPlot.PrimaryPart.Position or Vector3.new(0, 0, 0)
				local absolutePosition = plotCenter + relativePosition

				local targetCFrame
				if mushroomInfo.Rotation then
					if type(mushroomInfo.Rotation) == "table" and #mushroomInfo.Rotation == 12 then
						-- New format: relative CFrame components array
						local relativeCFrame = CFrame.new(unpack(mushroomInfo.Rotation))
						local plotCFrame = playerPlot.PrimaryPart and playerPlot.PrimaryPart.CFrame or CFrame.new()
						targetCFrame = plotCFrame * relativeCFrame
					else
						-- Old format: absolute CFrame (backward compatibility) 
						targetCFrame = CFrame.new(absolutePosition) * (mushroomInfo.Rotation or CFrame.new())
					end
				else
					-- No rotation data, just use position
					targetCFrame = CFrame.new(absolutePosition)
				end

				mushroom:SetPrimaryPartCFrame(targetCFrame)
			end

			mushroom.Parent = mushroomsFolder
		end
		Logger:Debug(string.format("Loaded %d mushrooms for player %s", #plotObjects.Mushrooms, player.Name))
	end

	-- Load Area2 mushrooms
	if plotObjects.Area2Mushrooms then

		-- Ensure Area2/Mushrooms folder exists
		local area2 = playerPlot:FindFirstChild("Area2")

		if area2 then
			local area2MushroomsFolder = area2:FindFirstChild("Mushrooms")

			if not area2MushroomsFolder then
				area2MushroomsFolder = Instance.new("Folder")
				area2MushroomsFolder.Name = "Mushrooms"
				area2MushroomsFolder.Parent = area2
			end

			local loadedCount = 0
			for i, mushroomInfo in pairs(plotObjects.Area2Mushrooms) do

				local modelType = mushroomInfo.ModelType or "Mushroom_3" -- Default for Area2
				local mushroomTemplate

				-- Check MODELS folder first for new models
				local modelsFolder = game.ReplicatedStorage:FindFirstChild("MODELS")
				if modelsFolder then
					mushroomTemplate = modelsFolder:FindFirstChild(modelType)
				else
				end

				-- If not found, try to find any area2 template as fallback
				if not mushroomTemplate and modelsFolder then
					mushroomTemplate = modelsFolder:FindFirstChild("Mushroom_3")
					if not mushroomTemplate then
						mushroomTemplate = modelsFolder:FindFirstChild("Mushroom_1") -- Last fallback
					end
					modelType = mushroomTemplate and mushroomTemplate.Name or "Mushroom_1"
				end

				if mushroomTemplate then
					local mushroom = mushroomTemplate:Clone()
					mushroom.Name = mushroomInfo.Name or "MushroomModel_1"
					mushroom:SetAttribute("ModelType", modelType)

					-- Make all parts anchored and non-collidable
					for _, part in pairs(mushroom:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
						end
					end
					
					-- Add ClickDetector for mobile and desktop interaction
					self:_addClickDetectorToMushroom(mushroom)

					-- Set position and rotation relative to the plot
					if mushroom.PrimaryPart then
						local relativePosition
						if type(mushroomInfo.Position) == "table" then
							-- New format: relative position array
							relativePosition = Vector3.new(
								mushroomInfo.Position[1] or 0,
								mushroomInfo.Position[2] or 0, 
								mushroomInfo.Position[3] or 0
							)
						else
							-- Old format: absolute position - convert to relative
							local absolutePosition = mushroomInfo.Position or Vector3.new(0, 0, 0)
							local plotCenter = playerPlot.PrimaryPart and playerPlot.PrimaryPart.Position or Vector3.new(0, 0, 0)
							relativePosition = absolutePosition - plotCenter
						end

						-- Convert relative position to absolute position for current plot
						local plotCenter = playerPlot.PrimaryPart and playerPlot.PrimaryPart.Position or Vector3.new(0, 0, 0)
						local absolutePosition = plotCenter + relativePosition

						local targetCFrame
						if mushroomInfo.Rotation then
							if type(mushroomInfo.Rotation) == "table" and #mushroomInfo.Rotation == 12 then
								-- New format: relative CFrame components
								local relativeCFrame = CFrame.new(unpack(mushroomInfo.Rotation))
								local plotCFrame = playerPlot.PrimaryPart and playerPlot.PrimaryPart.CFrame or CFrame.new()
								targetCFrame = plotCFrame * relativeCFrame
							else
								-- Old format: absolute CFrame (backward compatibility)
								targetCFrame = CFrame.new(absolutePosition) * (mushroomInfo.Rotation or CFrame.new())
							end
						else
							-- No rotation data, just use position
							targetCFrame = CFrame.new(absolutePosition)
						end

						mushroom:SetPrimaryPartCFrame(targetCFrame)
					end

					mushroom.Parent = area2MushroomsFolder
					loadedCount = loadedCount + 1
				else
				end
			end
			Logger:Debug(string.format("Loaded %d Area2 mushrooms for player %s", loadedCount, player.Name))
		else
		end
	else
	end

	-- Load spores
	if plotObjects.Spores then
		for _, sporeInfo in pairs(plotObjects.Spores) do
			local template = nil
			if sporeInfo.Type == "SporePart" and sporeTemplate then
				template = sporeTemplate
			elseif sporeInfo.Type == "GemSporePart" and gemTemplate then
				template = gemTemplate
			elseif sporeInfo.Type == "BigSpore" and bigSporeTemplate then
				template = bigSporeTemplate
			end

			if template then
				local spore = template:Clone()
				spore.Name = sporeInfo.Name or (sporeInfo.Type .. "_1")

				-- Restore position (with backward compatibility)
				local position
				if type(sporeInfo.Position) == "table" then
					-- New format: array of numbers
					position = Vector3.new(
						sporeInfo.Position[1] or 0,
						sporeInfo.Position[2] or 0,
						sporeInfo.Position[3] or 0
					)
				else
					-- Old format: Vector3 object
					position = sporeInfo.Position or Vector3.new(0, 0, 0)
				end
				spore.Position = position

				-- Handle BigSpore differently (always anchored)
				if sporeInfo.Type == "BigSpore" then
					spore.Anchored = true
					spore.CanCollide = true
					-- Tag for collection system
					CollectionService:AddTag(spore, "BigSpore")
				else
					spore.Anchored = false
					spore.CanCollide = true

					-- Restore velocity if it had any (with backward compatibility)
					if sporeInfo.Velocity then
						local velocity
						if type(sporeInfo.Velocity) == "table" then
							-- New format: array of numbers
							velocity = Vector3.new(
								sporeInfo.Velocity[1] or 0,
								sporeInfo.Velocity[2] or 0,
								sporeInfo.Velocity[3] or 0
							)
						else
							-- Old format: Vector3 object
							velocity = sporeInfo.Velocity or Vector3.new(0, 0, 0)
						end
						if velocity.Magnitude > 0.1 then
							spore.AssemblyLinearVelocity = velocity
						end
					end
				end

				spore.Parent = sporesFolder
				
				-- Collision groups handled client-side now
			end
		end
		Logger:Debug(string.format("Loaded %d spores for player %s", #plotObjects.Spores, player.Name))
	end

	-- Load Area2 spores
	if plotObjects.Area2Spores then
		local area2 = playerPlot:FindFirstChild("Area2")
		if area2 then
			local area2SporesFolder = area2:FindFirstChild("Spores")
			if not area2SporesFolder then
				area2SporesFolder = Instance.new("Folder")
				area2SporesFolder.Name = "Spores"
				area2SporesFolder.Parent = area2
			end

			for _, sporeInfo in pairs(plotObjects.Area2Spores) do
				local template = nil
				if sporeInfo.Type == "SporePart" and sporeTemplate then
					template = sporeTemplate
				elseif sporeInfo.Type == "GemSporePart" and gemTemplate then
					template = gemTemplate
				elseif sporeInfo.Type == "BigSpore" and bigSporeTemplate then
					template = bigSporeTemplate
				end

				if template then
					local spore = template:Clone()
					spore.Name = sporeInfo.Name or (sporeInfo.Type .. "_1")

					-- Restore position (with backward compatibility)
					local position
					if type(sporeInfo.Position) == "table" then
						-- New format: array of numbers
						position = Vector3.new(
							sporeInfo.Position[1] or 0,
							sporeInfo.Position[2] or 0,
							sporeInfo.Position[3] or 0
						)
					else
						-- Old format: Vector3 object
						position = sporeInfo.Position or Vector3.new(0, 0, 0)
					end
					spore.Position = position

					-- Handle BigSpore differently (always anchored)
					if sporeInfo.Type == "BigSpore" then
						spore.Anchored = true
						spore.CanCollide = true
						-- Tag for collection system
						CollectionService:AddTag(spore, "BigSpore")
					else
						spore.Anchored = false
						spore.CanCollide = true

						-- Restore velocity if it had any (with backward compatibility)
						if sporeInfo.Velocity then
							local velocity
							if type(sporeInfo.Velocity) == "table" then
								-- New format: array of numbers
								velocity = Vector3.new(
									sporeInfo.Velocity[1] or 0,
									sporeInfo.Velocity[2] or 0,
									sporeInfo.Velocity[3] or 0
								)
							else
								-- Old format: Vector3 object
								velocity = sporeInfo.Velocity or Vector3.new(0, 0, 0)
							end
							if velocity.Magnitude > 0.1 then
								spore.AssemblyLinearVelocity = velocity
							end
						end
					end

					spore.Parent = area2SporesFolder
					
					-- Collision groups handled client-side now
				end
			end
			Logger:Debug(string.format("Loaded %d Area2 spores for player %s", #plotObjects.Area2Spores, player.Name))
		else
			Logger:Warn(string.format("Area2 not found for player %s - cannot load Area2 spores", player.Name))
		end
	end

	-- Return true only if we actually loaded some objects
	local loadedMushrooms = plotObjects.Mushrooms and #plotObjects.Mushrooms or 0
	local loadedSpores = plotObjects.Spores and #plotObjects.Spores or 0
	local loadedArea2Mushrooms = plotObjects.Area2Mushrooms and #plotObjects.Area2Mushrooms or 0
	local loadedArea2Spores = plotObjects.Area2Spores and #plotObjects.Area2Spores or 0
	return loadedMushrooms > 0 or loadedSpores > 0 or loadedArea2Mushrooms > 0 or loadedArea2Spores > 0
end

-- Get plot objects data for inspection
function DataService:GetPlotObjects(player)
	local data = playerDataCache[player.UserId]
	return data and data.PlotObjects or nil
end

function DataService:SetPlotService(plotService)
	self._plotService = plotService
	Logger:Debug("DataService linked with PlotService")
end

function DataService:SetMushroomService(mushroomService)
	self._mushroomService = mushroomService
	Logger:Debug("DataService linked with MushroomService")
end

function DataService:SetShopService(shopService)
	self._shopService = shopService
	Logger:Debug("DataService linked with ShopService")
end

function DataService:SetGamepassService(gamepassService)
	self._gamepassService = gamepassService
	Logger:Debug("DataService linked with GamepassService")
end

function DataService:SetStorageService(storageService)
	self._storageService = storageService
	Logger:Debug("DataService linked with StorageService")
end

function DataService:SetRobloxAnalyticsService(robloxAnalyticsService)
	self._robloxAnalyticsService = robloxAnalyticsService
	Logger:Debug("DataService linked with RobloxAnalyticsService")
end

function DataService:AddSporeToSavedData(player, sporeData, area)
	area = area or "Area1" -- Default to Area1 for backwards compatibility

	local data = playerDataCache[player.UserId]
	if data and data.PlotObjects then
		if area == "Area2" then
			if not data.PlotObjects.Area2Spores then
				data.PlotObjects.Area2Spores = {}
			end
			table.insert(data.PlotObjects.Area2Spores, sporeData)
			Logger:Debug(string.format("Added spore %s to Area2 saved data for %s", sporeData.Name, player.Name))
		else
			if not data.PlotObjects.Spores then
				data.PlotObjects.Spores = {}
			end
			table.insert(data.PlotObjects.Spores, sporeData)
			Logger:Debug(string.format("Added spore %s to Area1 saved data for %s", sporeData.Name, player.Name))
		end
	else
		Logger:Warn(string.format("Cannot add spore to saved data - no data structure for player %s", player.Name))
	end
end


function DataService:_collectPlotObjectsOnly(player)
	-- This method updates the cache with fresh world data for both mushrooms and spores
	local data = playerDataCache[player.UserId]
	if not data or not data.PlotObjects then
		Logger:Warn(string.format("No data structure for player %s to update", player.Name))
		return false
	end

	-- Collect fresh data from the world
	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		Logger:Warn("No PlayerPlots found in workspace")
		return false
	end

	local plot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not plot then
		Logger:Warn(string.format("Plot not found for player %s", player.Name))
		return false
	end

	-- Update Area 1 mushroom data from world
	local mushroomData = {}
	local mushrooms = plot:FindFirstChild("Mushrooms")
	if mushrooms then
		for _, mushroom in pairs(mushrooms:GetChildren()) do
			if mushroom:IsA("Model") and mushroom.Name:find("MushroomModel_") then
				local mushroomInfo = {
					Name = mushroom.Name,
					Position = {},
					Rotation = {},
					ModelType = mushroom:GetAttribute("ModelType") or "Mushroom_1"
				}

				-- Store position and rotation data as relative to plot
				local primaryPart = mushroom.PrimaryPart
				if primaryPart then
					local pos = primaryPart.Position
					local cframe = primaryPart.CFrame

					-- Convert absolute position to relative position within the plot
					local plotCenter = plot.PrimaryPart and plot.PrimaryPart.Position or Vector3.new(0, 0, 0)
					local relativePosition = pos - plotCenter
					
					-- Convert absolute CFrame to relative CFrame within the plot
					local plotCFrame = plot.PrimaryPart and plot.PrimaryPart.CFrame or CFrame.new()
					local relativeCFrame = plotCFrame:Inverse() * cframe

					mushroomInfo.Position = {relativePosition.X, relativePosition.Y, relativePosition.Z}
					mushroomInfo.Rotation = {relativeCFrame:GetComponents()}
				end

				table.insert(mushroomData, mushroomInfo)
			end
		end
	end

	-- Update Area 2 mushroom data from world
	local area2MushroomData = {}
	local area2 = plot:FindFirstChild("Area2")
	if area2 then
		Logger:Debug(string.format("Found Area2 folder for %s", player.Name))
		local area2Mushrooms = area2:FindFirstChild("Mushrooms")
		if area2Mushrooms then
			Logger:Debug(string.format("Found Area2/Mushrooms folder for %s with %d children", player.Name, #area2Mushrooms:GetChildren()))
			for _, mushroom in pairs(area2Mushrooms:GetChildren()) do
				Logger:Debug(string.format("Found Area2 child: %s (%s)", mushroom.Name, mushroom.ClassName))
				if mushroom:IsA("Model") and mushroom.Name:find("MushroomModel_") then
					local mushroomInfo = {
						Name = mushroom.Name,
						Position = {},
						Rotation = {},
						ModelType = mushroom:GetAttribute("ModelType") or "Mushroom_3"
					}

					-- Store position and rotation data as relative to plot
					local primaryPart = mushroom.PrimaryPart
					if primaryPart then
						local pos = primaryPart.Position
						local cframe = primaryPart.CFrame

						-- Convert absolute position to relative position within the plot
						local plotCenter = plot.PrimaryPart and plot.PrimaryPart.Position or Vector3.new(0, 0, 0)
						local relativePosition = pos - plotCenter
						
						-- Convert absolute CFrame to relative CFrame within the plot
						local plotCFrame = plot.PrimaryPart and plot.PrimaryPart.CFrame or CFrame.new()
						local relativeCFrame = plotCFrame:Inverse() * cframe

						mushroomInfo.Position = {relativePosition.X, relativePosition.Y, relativePosition.Z}
						mushroomInfo.Rotation = {relativeCFrame:GetComponents()}
					end

					table.insert(area2MushroomData, mushroomInfo)
					Logger:Debug(string.format("Added Area2 mushroom %s to save data", mushroom.Name))
				end
			end
		else
			Logger:Debug(string.format("No Area2/Mushrooms folder found for %s", player.Name))
		end
	else
		Logger:Debug(string.format("No Area2 folder found for %s", player.Name))
	end

	-- Update spore data from world - collect fresh spore positions
	local sporeData = {}
	local sporesFolder = plot:FindFirstChild("Spores")
	if sporesFolder then
		for _, spore in pairs(sporesFolder:GetChildren()) do
			if spore:IsA("BasePart") then
				local sporeInfo = {
					Name = spore.Name,
					Type = "SporePart", -- Default type
					Position = {spore.Position.X, spore.Position.Y, spore.Position.Z},
					Velocity = {0, 0, 0} -- Default velocity
				}

				-- Determine spore type from name
				if string.find(spore.Name, "GemSporePart_") then
					sporeInfo.Type = "GemSporePart"
				elseif string.find(spore.Name, "BigSpore_") then
					sporeInfo.Type = "BigSpore"
				elseif string.find(spore.Name, "SporePart_") then
					sporeInfo.Type = "SporePart"
				end

				-- Get velocity if not anchored
				if not spore.Anchored and spore.AssemblyLinearVelocity then
					local vel = spore.AssemblyLinearVelocity
					sporeInfo.Velocity = {vel.X, vel.Y, vel.Z}
				end

				table.insert(sporeData, sporeInfo)
			end
		end
	end

	-- Update Area2 spore data from world
	local area2SporeData = {}
	if area2 then
		local area2SporesFolder = area2:FindFirstChild("Spores")
		if area2SporesFolder then
			for _, spore in pairs(area2SporesFolder:GetChildren()) do
				if spore:IsA("BasePart") then
					local sporeInfo = {
						Name = spore.Name,
						Type = "SporePart", -- Default type
						Position = {spore.Position.X, spore.Position.Y, spore.Position.Z},
						Velocity = {0, 0, 0} -- Default velocity
					}

					-- Determine spore type from name
					if string.find(spore.Name, "GemSporePart_") then
						sporeInfo.Type = "GemSporePart"
					elseif string.find(spore.Name, "BigSpore_") then
						sporeInfo.Type = "BigSpore"
					elseif string.find(spore.Name, "SporePart_") then
						sporeInfo.Type = "SporePart"
					end

					-- Get velocity if not anchored
					if not spore.Anchored and spore.AssemblyLinearVelocity then
						local vel = spore.AssemblyLinearVelocity
						sporeInfo.Velocity = {vel.X, vel.Y, vel.Z}
					end

					table.insert(area2SporeData, sporeInfo)
				end
			end
		end
	end

	-- Update all plot object data
	data.PlotObjects.Mushrooms = mushroomData
	data.PlotObjects.Area2Mushrooms = area2MushroomData
	data.PlotObjects.Spores = sporeData
	data.PlotObjects.Area2Spores = area2SporeData

	Logger:Info(string.format("COLLECT PLOT OBJECTS: Updated plot data for %s: %d Area1 mushrooms, %d Area2 mushrooms, %d Area1 spores, %d Area2 spores", 
		player.Name, #mushroomData, #area2MushroomData, #sporeData, #area2SporeData))
	return true
end

-- DEBUG: Manual function to check what's actually saved in DataStore
-- DEBUG: Check what's currently in the world
function DataService:DebugCheckWorldData(player)

	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		return
	end

	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		return
	end

	-- Check Area1 mushrooms
	local mushroomsFolder = playerPlot:FindFirstChild("Mushrooms")
	if mushroomsFolder then
		local mushrooms = mushroomsFolder:GetChildren()
		for i, mushroom in pairs(mushrooms) do
			if mushroom:IsA("Model") and string.find(mushroom.Name, "MushroomModel_") then
				Logger:Info(string.format("  World Area1[%d] %s (Type: %s)", i, mushroom.Name, mushroom:GetAttribute("ModelType")))
			end
		end
	else
	end

	-- Check Area2
	local area2 = playerPlot:FindFirstChild("Area2")
	if area2 then
		local area2MushroomsFolder = area2:FindFirstChild("Mushrooms")
		if area2MushroomsFolder then
			local mushrooms = area2MushroomsFolder:GetChildren()
			for i, mushroom in pairs(mushrooms) do
				if mushroom:IsA("Model") and string.find(mushroom.Name, "MushroomModel_") then
					Logger:Info(string.format("  World Area2[%d] %s (Type: %s)", i, mushroom.Name, mushroom:GetAttribute("ModelType")))
				else
					Logger:Info(string.format("  World Area2[%d] %s (%s) - NOT a valid mushroom", i, mushroom.Name, mushroom.ClassName))
				end
			end
		else
		end
	else
	end
end

function DataService:DebugCheckSavedData(player)
	local userId = player.UserId
	local playerKey = "Player_" .. userId


	local success, data = self:_retryOperation(function()
		return playerDataStore:GetAsync(playerKey)
	end, "DebugCheckSavedData", playerKey)

	if success and data then
		local mushroomCount = data.PlotObjects and data.PlotObjects.Mushrooms and #data.PlotObjects.Mushrooms or 0
		local area2MushroomCount = data.PlotObjects and data.PlotObjects.Area2Mushrooms and #data.PlotObjects.Area2Mushrooms or 0
		local sporeCount = data.PlotObjects and data.PlotObjects.Spores and #data.PlotObjects.Spores or 0
		local area2SporeCount = data.PlotObjects and data.PlotObjects.Area2Spores and #data.PlotObjects.Area2Spores or 0

		if data.PlotObjects and data.PlotObjects.Area2Mushrooms then
			for i, mushroom in pairs(data.PlotObjects.Area2Mushrooms) do
				Logger:Info(string.format("  DataStore[%d] %s (Type: %s, Pos: %.1f,%.1f,%.1f)", 
					i, mushroom.Name, mushroom.ModelType, mushroom.Position[1], mushroom.Position[2], mushroom.Position[3]))
			end
		else
		end

		-- Check cached data too
		local cachedData = playerDataCache[userId]
		if cachedData and cachedData.PlotObjects and cachedData.PlotObjects.Area2Mushrooms then
			for i, mushroom in pairs(cachedData.PlotObjects.Area2Mushrooms) do
				Logger:Info(string.format("  Cache[%d] %s (Type: %s)", i, mushroom.Name, mushroom.ModelType))
			end
		else
		end
	else
	end
end

function DataService:_addClickDetectorToMushroom(mushroom)
	-- Use the MushroomService method if available, otherwise implement directly
	-- Click detection handled client-side now
	if false then -- Disabled for client-side system
	else
		-- Fallback implementation
		local targetPart = mushroom.PrimaryPart
		if not targetPart then
			for _, child in pairs(mushroom:GetChildren()) do
				if child:IsA("BasePart") then
					targetPart = child
					break
				end
			end
		end
		
		if targetPart and not targetPart:FindFirstChild("ClickDetector") then
			local clickDetector = Instance.new("ClickDetector")
			clickDetector.MaxActivationDistance = 50
			clickDetector.Parent = targetPart
			
			-- This will need to be connected when MushroomService is available
			Logger:Debug(string.format("Added ClickDetector to %s (no connection yet)", mushroom.Name))
		end
	end
end

function DataService:Cleanup()
	for connectionName, connection in pairs(self._connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._connections = {}

	Logger:Info("DataService cleaned up")
end

return DataService