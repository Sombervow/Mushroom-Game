local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Logger = require(script.Parent.Parent.Utilities.Logger)

local MushroomService = {}
MushroomService.__index = MushroomService

-- Configuration (from SimpleMushroomAI)
local CONFIG = {
	MIN_MOVE_DISTANCE = 15,
	MAX_MOVE_DISTANCE = 40,
	MOVE_SPEED = 4,
	MIN_PAUSE_TIME = 2.0, -- Increased from 1.0 to reduce movement frequency
	MAX_PAUSE_TIME = 5.0, -- Increased from 2.0 to reduce movement frequency
	SPORE_SPAWN_INTERVAL = 5, -- Back to original for good gameplay
	GEM_CHANCE = 0.01,
	SPORE_LAUNCH_FORCE = 15,
	SPORE_LIFETIME = 600, -- Increased to 10 minutes for better gameplay
	-- Spore combination system
	COMBINATION_THRESHOLD = 100,
	COMBINATION_CHECK_INTERVAL = 5, -- Increased from 3 to reduce frequency
	SPORE_FLY_SPEED = 25, -- Increased speed for faster animations
	BIGSPORE_GROWTH_TIME = 1.0, -- Reduced from 1.5 for faster completion
	-- Animation optimization
	OPTIMIZED_COMBINATION = true, -- Skip individual spore flying animations
	MAX_FLYING_SPORES = 5, -- Only animate a few spores, destroy the rest instantly
	INSTANT_COMBINATION = true, -- RECOMMENDED: Skip all animations for max performance
	-- Gold mushroom system
	GOLD_CHECK_INTERVAL = 600, -- 10 minutes in seconds
	GOLD_CHANCE = 0.05, -- 5% chance per check (pretty rare)
	-- Network optimization (not gameplay limiting)
	MAX_SPORES_PER_PLOT = 200, -- Higher limit - only for extreme cases
	SPORE_CLEANUP_INTERVAL = 60, -- Less frequent cleanup
	SPORE_BATCH_SIZE = 5, -- Batch spore creation for network efficiency
	-- Performance optimization
	OPTIMIZED_MOVEMENT = true, -- Use PrimaryPart-only movement for better performance
	SPORE_PHYSICS_DELAY = 0.5 -- Delay before enabling spore physics
}

-- Counters for unique naming
local mushroomCounter = {}
local sporeCounter = {}

-- Spore combination tracking
local playerCombinationTimers = {}

-- Gold mushroom tracking
local playerGoldTimers = {}
local goldMushrooms = {} -- Track which mushrooms are gold

-- Player click tracking
local playerClickCounts = {}

-- Performance tracking
local playerSporeCounters = {} -- Track spore count per player plot
local lastSporeCleanup = 0

-- Synchronized spawning system
local plotSpawnTimers = {} -- Plot -> {lastSpawn, nextSpawn}
local synchronizedSpawning = true -- Enable synchronized spawning

-- Import HeartbeatManager for synchronized timing
local HeartbeatManager = require(script.Parent.Parent.Utilities.HeartbeatManager)

function MushroomService.new()
	local self = setmetatable({}, MushroomService)
	self._connections = {}
	self._mushrooms = {} -- Track all active mushrooms
	self._dataService = nil
	self._plotService = nil
	self._notificationService = nil
	self._gamepassService = nil
	self._storageService = nil
	self._proximityService = nil
	self._sporeOptimizationService = nil
	self:_initialize()
	return self
end

function MushroomService:_initialize()
	-- FIXED: Set up collision groups for mushrooms
	self:_setupCollisionGroups()

	self._connections.PlayerAdded = Players.PlayerAdded:Connect(function(player)
		self:_onPlayerJoined(player)
	end)

	self._connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerLeaving(player)
	end)

	-- Setup mushroom click handling
	self:_setupMushroomClickHandling()
	
	-- Start synchronized spawning system
	self:_startSynchronizedSpawning()

	Logger:Info("MushroomService initialized successfully")
end

function MushroomService:_setupCollisionGroups()
	local PhysicsService = game:GetService("PhysicsService")

	-- Create collision groups
	local mushroomGroup = "Mushrooms"
	local playerGroup = "Players"
	local sporeGroup = "Spores"

	-- Create the groups (safe to call multiple times)
	pcall(function() PhysicsService:RegisterCollisionGroup(mushroomGroup) end)
	pcall(function() PhysicsService:RegisterCollisionGroup(playerGroup) end)
	pcall(function() PhysicsService:RegisterCollisionGroup(sporeGroup) end)

	-- Set collision relationships
	pcall(function() 
		-- Mushrooms don't collide with Players but remain raycastable
		PhysicsService:CollisionGroupSetCollidable(mushroomGroup, playerGroup, false)
		-- Spores don't collide with Players (prevents pushing) but remain collectible via collision detection events
		PhysicsService:CollisionGroupSetCollidable(sporeGroup, playerGroup, false)
		-- Spores can collide with mushrooms and other spores for natural physics
		PhysicsService:CollisionGroupSetCollidable(sporeGroup, mushroomGroup, true)
		PhysicsService:CollisionGroupSetCollidable(sporeGroup, sporeGroup, true)
	end)

	Logger:Info("Collision groups configured - mushrooms and spores won't collide with players but remain raycastable/collectible")
end

function MushroomService:_setSporeCollisionGroup(spore)
	pcall(function()
		spore.CollisionGroup = "Spores"
	end)
end

function MushroomService:_setPlayerCollisionGroup(player)
	if player.Character then
		for _, part in pairs(player.Character:GetChildren()) do
			if part:IsA("BasePart") then
				pcall(function()
					part.CollisionGroup = "Players"
				end)
			end
		end
	end
	
	-- Set up connection for when character respawns
	if not self._playerCharacterConnections then
		self._playerCharacterConnections = {}
	end
	
	if self._playerCharacterConnections[player] then
		self._playerCharacterConnections[player]:Disconnect()
	end
	
	self._playerCharacterConnections[player] = player.CharacterAdded:Connect(function(character)
		task.wait(1) -- Wait for character to load
		for _, part in pairs(character:GetChildren()) do
			if part:IsA("BasePart") then
				pcall(function()
					part.CollisionGroup = "Players"
				end)
			end
		end
	end)
end

function MushroomService:SetServices(dataService, plotService, shopService, notificationService, gamepassService, robloxAnalyticsService)
	self._dataService = dataService
	self._plotService = plotService
	self._shopService = shopService
	self._notificationService = notificationService
	self._gamepassService = gamepassService
	self._robloxAnalyticsService = robloxAnalyticsService

	-- Listen for when player data is loaded
	if dataService and dataService.PlayerDataLoaded then
		self._connections.PlayerDataLoaded = dataService.PlayerDataLoaded:Connect(function(player, playerData, isNewPlayer)
			self:_onPlayerDataLoaded(player, playerData, isNewPlayer)
		end)
	end

	Logger:Debug("MushroomService linked with DataService, PlotService, ShopService, NotificationService, and GamepassService")
end

function MushroomService:SetStorageService(storageService)
	self._storageService = storageService
	Logger:Debug("MushroomService linked with StorageService")
end

function MushroomService:SetProximityService(proximityService)
	self._proximityService = proximityService
	Logger:Debug("MushroomService linked with ProximityReplicationService")
end

function MushroomService:SetSporeOptimizationService(sporeOptimizationService)
	self._sporeOptimizationService = sporeOptimizationService
	Logger:Debug("MushroomService linked with SporeOptimizationService")
end

function MushroomService:_getEffectiveSporeInterval(plot)
	-- Get player from plot name
	local playerName = plot.Name:match("Plot_(.+)")
	local player = playerName and Players:FindFirstChild(playerName)

	if not player or not self._shopService then
		return CONFIG.SPORE_SPAWN_INTERVAL
	end

	-- Get player's FasterShrooms level from ShopService
	local fasterShroomsLevel = self._shopService:GetFasterShroomsLevel(player)
	if not fasterShroomsLevel or fasterShroomsLevel <= 1 then
		return CONFIG.SPORE_SPAWN_INTERVAL
	end

	-- Calculate speed bonus (2% per level above 1)
	local speedBonus = (fasterShroomsLevel - 1) * 0.02
	
	-- Apply gamepass multiplier if available
	if self._gamepassService then
		local gamepassMultiplier = self._gamepassService:getSporeSpawnRateMultiplier(player)
		speedBonus = speedBonus * gamepassMultiplier
	end
	
	-- Reduce interval = faster production
	local effectiveInterval = CONFIG.SPORE_SPAWN_INTERVAL * (1 - speedBonus)

	-- Minimum interval of 0.1 seconds for instant spawn gamepass
	return math.max(effectiveInterval, 0.1)
end

function MushroomService:_getMushroomCountInPlot(plot)
	local count = 0
	local mushroomsFolder = plot:FindFirstChild("Mushrooms")
	if mushroomsFolder then
		for _, child in pairs(mushroomsFolder:GetChildren()) do
			if child:IsA("Model") and child.Name:match("MushroomModel_") then
				count = count + 1
			end
		end
	end
	
	-- Check Area2 as well
	local area2 = plot:FindFirstChild("Area2")
	if area2 then
		local area2MushroomsFolder = area2:FindFirstChild("Mushrooms")
		if area2MushroomsFolder then
			for _, child in pairs(area2MushroomsFolder:GetChildren()) do
				if child:IsA("Model") and child.Name:match("MushroomModel_") then
					count = count + 1
				end
			end
		end
	end
	
	return count
end

function MushroomService:_getSporeCountInPlot(plot)
	local count = 0
	local sporesFolder = plot:FindFirstChild("Spores")
	if sporesFolder then
		count = count + #sporesFolder:GetChildren()
	end
	
	-- Check Area2 as well
	local area2 = plot:FindFirstChild("Area2")
	if area2 then
		local area2SporesFolder = area2:FindFirstChild("Spores")
		if area2SporesFolder then
			count = count + #area2SporesFolder:GetChildren()
		end
	end
	
	return count
end

function MushroomService:_shouldSpawnSpore(plot)
	-- Check if we're at the spore limit for this plot
	local currentSporeCount = self:_getSporeCountInPlot(plot)
	return currentSporeCount < CONFIG.MAX_SPORES_PER_PLOT
end

function MushroomService:_cleanupOldSpores()
	local currentTime = tick()
	if currentTime - lastSporeCleanup < CONFIG.SPORE_CLEANUP_INTERVAL then
		return
	end
	lastSporeCleanup = currentTime
	
	local sporesRemoved = 0
	local plotsFolder = workspace:FindFirstChild("PlayerPlots")
	if not plotsFolder then return end
	
	for _, plot in pairs(plotsFolder:GetChildren()) do
		if plot.Name:match("^Plot_") then
			-- Clean up Area1 spores
			local sporesFolder = plot:FindFirstChild("Spores")
			if sporesFolder then
				sporesRemoved = sporesRemoved + self:_cleanupSporesInFolder(sporesFolder)
			end
			
			-- Clean up Area2 spores
			local area2 = plot:FindFirstChild("Area2")
			if area2 then
				local area2SporesFolder = area2:FindFirstChild("Spores")
				if area2SporesFolder then
					sporesRemoved = sporesRemoved + self:_cleanupSporesInFolder(area2SporesFolder)
				end
			end
		end
	end
	
	if sporesRemoved > 0 then
		Logger:Debug(string.format("Cleaned up %d old spores", sporesRemoved))
	end
end

function MushroomService:_cleanupSporesInFolder(sporesFolder)
	local currentTime = tick()
	local removed = 0
	
	for _, spore in pairs(sporesFolder:GetChildren()) do
		if spore:IsA("BasePart") then
			local spawnTime = spore:GetAttribute("SpawnTime")
			if spawnTime and (currentTime - spawnTime) > CONFIG.SPORE_LIFETIME then
				spore:Destroy()
				removed = removed + 1
			end
		end
	end
	
	return removed
end

function MushroomService:_initializePlotSpawnTimer(plot)
	-- Initialize synchronized spawn timer for a plot
	if not plotSpawnTimers[plot] then
		local currentTime = tick()
		plotSpawnTimers[plot] = {
			lastSpawn = currentTime,
			nextSpawn = currentTime + self:_getEffectiveSporeInterval(plot)
		}
		Logger:Debug(string.format("Initialized spawn timer for %s", plot.Name))
	end
end

function MushroomService:_updatePlotSpawnTimers()
	-- Update all plot spawn timers and spawn spores when ready
	local currentTime = tick()
	local plotsToRemove = {}
	
	for plot, timer in pairs(plotSpawnTimers) do
		-- Check if plot still exists and is valid
		if not plot.Parent then
			table.insert(plotsToRemove, plot)
		elseif currentTime >= timer.nextSpawn then
			-- Time to spawn spores for all mushrooms in this plot
			self:_spawnSporesForAllMushrooms(plot)
			
			-- Update timer for next spawn
			timer.lastSpawn = currentTime
			timer.nextSpawn = currentTime + self:_getEffectiveSporeInterval(plot)
		end
	end
	
	-- Clean up invalid plots
	for _, plot in pairs(plotsToRemove) do
		plotSpawnTimers[plot] = nil
		Logger:Debug(string.format("Removed timer for invalid plot: %s", plot.Name))
	end
end

function MushroomService:_spawnSporesForAllMushrooms(plot)
	-- Spawn spores from all mushrooms in a plot simultaneously
	local sporeData = {}
	local playerName = plot.Name:match("Plot_(.+)")
	local player = playerName and Players:FindFirstChild(playerName)
	
	if not player then return end
	
	-- Check if we should spawn (limits and cleanup)
	if not self:_shouldSpawnSpore(plot) then
		return -- Skip spawning if at spore limit
	end
	
	-- Run periodic cleanup
	self:_cleanupOldSpores()
	
	-- Get all mushrooms in this plot
	local plotMushrooms = {}
	for mushroom, mushroomData in pairs(self._mushrooms) do
		if mushroomData.plot == plot and mushroom.Parent then
			table.insert(plotMushrooms, {mushroom = mushroom, data = mushroomData})
		end
	end
	
	if #plotMushrooms == 0 then return end
	
	-- Calculate gem chance once for all mushrooms
	local gemChance = CONFIG.GEM_CHANCE
	if self._gamepassService then
		local gemChanceMultiplier = self._gamepassService:getGemChanceMultiplier(player)
		gemChance = math.min(gemChance * gemChanceMultiplier, 1.0)
	end
	
	-- Generate spores for each mushroom
	for _, mushroomInfo in pairs(plotMushrooms) do
		local mushroom = mushroomInfo.mushroom
		local mushroomData = mushroomInfo.data
		local mainPart = mushroomData.mainPart
		
		if mainPart and mainPart.Parent then
			-- Determine spore type
			local isGem = math.random() <= gemChance
			local templateName = isGem and "GemSporePart" or "SporePart"
			
			-- Determine area
			local area = "Area1"
			if mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name == "Area2" then
				area = "Area2"
			elseif mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name == "Area3" then
				area = "Area3"
			end
			
			-- Check storage capacity before spawning
			if self._storageService then
				if not self._storageService:CanSpawnSporeInArea(player, area) then
					Logger:Debug(string.format("Storage full in %s for %s, spore not spawned", area, player.Name))
					continue
				end
			end
			
			-- Generate unique spore ID
			sporeCounter[player.UserId] = sporeCounter[player.UserId] + 1
			local uniqueSporeId = sporeCounter[player.UserId]
			
			-- Check if this came from a gold mushroom
			local isFromGold = goldMushrooms[mushroom] or false
			local sporeName
			if isFromGold then
				sporeName = "Gold" .. templateName .. "_" .. uniqueSporeId
			else
				sporeName = templateName .. "_" .. uniqueSporeId
			end
			
			-- Add spore data to batch
			table.insert(sporeData, {
				name = sporeName,
				template = templateName,
				position = mainPart.Position,
				velocity = Vector3.new(
					(math.random() - 0.5) * 10, -- Random horizontal spread
					35 + math.random() * 15,    -- Much higher 35-50
					(math.random() - 0.5) * 10  -- Random horizontal spread
				),
				area = area,
				isGem = isGem,
				isGold = isFromGold,
				mushroomId = mushroom.Name
			})
		end
	end
	
	-- Spawn all spores at once if we have any
	if #sporeData > 0 then
		self:_createSporeBatch(plot, sporeData)
		Logger:Debug(string.format("Spawned %d spores simultaneously for %s", #sporeData, plot.Name))
	end
end

function MushroomService:_startSynchronizedSpawning()
	-- Start the synchronized spawning timer using HeartbeatManager
	local heartbeatManager = HeartbeatManager.getInstance()
	
	self._connections.SynchronizedSpawning = heartbeatManager:register(function()
		self:_updatePlotSpawnTimers()
	end, 0.5) -- Check every 0.5 seconds
	
	Logger:Info("Synchronized spawning system started")
end

function MushroomService:_createSporeBatch(plot, sporeDataList)
	-- If SporeOptimizationService is available, use it for batched network optimization
	if self._sporeOptimizationService then
		local playerName = plot.Name:match("Plot_(.+)")
		for _, sporeData in pairs(sporeDataList) do
			self._sporeOptimizationService:QueueSporeCreation(playerName, sporeData)
		end
		Logger:Debug(string.format("Queued %d spores for optimized network creation for %s", #sporeDataList, playerName))
		return
	end
	
	-- Fallback: Create all spores locally (original behavior)
	for _, sporeData in pairs(sporeDataList) do
		local sporeTemplate = ReplicatedStorage:FindFirstChild(sporeData.template)
		if sporeTemplate then
			-- Clone and setup spore
			local spore = sporeTemplate:Clone()
			spore.Name = sporeData.name
			
			-- OPTIMIZED: Setup properties with delayed physics
			spore.Anchored = true
			spore.CanCollide = false
			spore:SetAttribute("SpawnTime", tick())
			CollectionService:AddTag(spore, "Spore")
			
			-- Position spore
			spore.Position = sporeData.position
			
			-- Delayed physics activation for batch spawned spores
			task.delay(CONFIG.SPORE_PHYSICS_DELAY, function()
				if spore.Parent then
					spore.Anchored = false
					spore.CanCollide = true
					spore.AssemblyLinearVelocity = sporeData.velocity
				end
			end)
			
			-- Determine target folder
			local targetFolder
			if sporeData.area == "Area2" then
				local area2 = plot:FindFirstChild("Area2")
				if area2 then
					targetFolder = area2:FindFirstChild("Spores")
				end
			elseif sporeData.area == "Area3" then
				local area3 = plot:FindFirstChild("Area3")
				if area3 then
					targetFolder = area3:FindFirstChild("Spores")
				end
			else
				targetFolder = plot:FindFirstChild("Spores")
			end
			
			-- Parent to appropriate folder
			if targetFolder then
				spore.Parent = targetFolder
			else
				spore:Destroy()
				Logger:Warn(string.format("No target folder for %s in %s", sporeData.area, plot.Name))
			end
		end
	end
end

function MushroomService:_onPlayerDataLoaded(player, playerData, isNewPlayer)
	Logger:Info(string.format("MushroomService: Data loaded for %s - isNewPlayer: %s", player.Name, tostring(isNewPlayer)))

	local plotId = self._plotService and self._plotService:GetPlayerPlot(player)
	if plotId then
		self:_setupPlayerPlot(player, plotId, playerData, isNewPlayer)
	else
		Logger:Warn(string.format("No plot found for player %s", player.Name))
	end
end

function MushroomService:_onPlayerJoined(player)
	-- FIXED: Just initialize counters, don't setup plot here
	-- Plot setup now happens when data is loaded

	-- Initialize counters to 0 for new players (will be updated when data loads)
	mushroomCounter[player.UserId] = 0
	sporeCounter[player.UserId] = 0

	-- Set up player collision group to prevent spore pushing
	self:_setPlayerCollisionGroup(player)

	-- Start spore combination checker
	self:_startSporeCombinationChecker(player)

	-- Start gold mushroom checker
	self:_startGoldMushroomChecker(player)

	Logger:Info(string.format("MushroomService: Player %s joined, waiting for data load", player.Name))
end

function MushroomService:_setupPlayerPlot(player, plotId, playerData, isNewPlayer)
	local plot = self:_getPlayerPlot(player)
	if not plot then
		Logger:Error(string.format("Plot not found for player %s", player.Name))
		return
	end

	-- FIXED: Update counters from loaded data
	if playerData and playerData.ObjectCounters then
		mushroomCounter[player.UserId] = playerData.ObjectCounters.MushroomCounter or 0
		sporeCounter[player.UserId] = playerData.ObjectCounters.SporeCounter or 0
		Logger:Debug(string.format("Updated counters for %s from saved data: M%d, S%d", 
			player.Name, mushroomCounter[player.UserId], sporeCounter[player.UserId]))
	end

	Logger:Info(string.format("MushroomService setup for %s - IsNewPlayer: %s", player.Name, tostring(isNewPlayer)))
	
	-- Initialize plot spawn timer for synchronized spawning
	self:_initializePlotSpawnTimer(plot)

	if isNewPlayer then
		-- FIXED: Truly new player - spawn default mushroom
		self:_spawnMushroom(player, plot)
		Logger:Info(string.format("Spawned default mushroom for NEW player %s", player.Name))
	else
		-- FIXED: Returning player - try to load existing objects
		Logger:Info(string.format("AREA2 MUSHROOM DEBUG: About to call LoadPlotObjects for returning player %s", player.Name))
		local hasExistingObjects = false
		if self._dataService then
			hasExistingObjects = self._dataService:LoadPlotObjects(player)
			Logger:Info(string.format("AREA2 MUSHROOM DEBUG: LoadPlotObjects returned %s for returning player %s", tostring(hasExistingObjects), player.Name))

			-- Check what's actually in the world after loading
			Logger:Info(string.format("AREA2 MUSHROOM DEBUG: Checking world after LoadPlotObjects for %s", player.Name))
			self._dataService:DebugCheckWorldData(player)
		end

		-- Always load existing objects if available (spores, etc.)
		if hasExistingObjects then
			Logger:Info(string.format("Loaded existing plot objects for returning player %s", player.Name))

			-- Tag existing spores
			local sporesFolder = plot:FindFirstChild("Spores")
			if sporesFolder then
				for _, spore in pairs(sporesFolder:GetChildren()) do
					if spore:IsA("BasePart") then
						if string.find(spore.Name, "GemSporePart_") then
							CollectionService:AddTag(spore, "Gem")
						elseif string.find(spore.Name, "SporePart_") then
							CollectionService:AddTag(spore, "Spore")
						end
						Logger:Debug(string.format("Tagged existing spore %s in %s's plot", spore.Name, player.Name))
					end
				end
			end

			-- Tag existing Area2 spores (if Area2 is unlocked)
			if self._dataService:IsArea2Unlocked(player) then
				local area2 = plot:FindFirstChild("Area2")
				if area2 then
					local area2SporesFolder = area2:FindFirstChild("Spores")
					if area2SporesFolder then
						for _, spore in pairs(area2SporesFolder:GetChildren()) do
							if spore:IsA("BasePart") then
								if string.find(spore.Name, "GemSporePart_") then
									CollectionService:AddTag(spore, "Gem")
								elseif string.find(spore.Name, "SporePart_") then
									CollectionService:AddTag(spore, "Spore")
								elseif string.find(spore.Name, "BigSpore_") then
									CollectionService:AddTag(spore, "BigSpore")
								end
								Logger:Debug(string.format("Tagged existing Area2 spore %s in %s's plot", spore.Name, player.Name))
							end
						end
					end
				end
			end
		end

		-- ALWAYS check and spawn missing mushrooms based on player counts
		-- This fixes the bug where having saved spores prevented mushroom spawning
		Logger:Info(string.format("Checking mushroom counts for returning player %s", player.Name))

		-- Count existing mushrooms in world
		local existingArea1Mushrooms = 0
		local existingArea2Mushrooms = 0

		local mushroomsFolder = plot:FindFirstChild("Mushrooms")
		if mushroomsFolder then
			for _, mushroom in pairs(mushroomsFolder:GetChildren()) do
				if mushroom:IsA("Model") and string.find(mushroom.Name, "MushroomModel_") then
					existingArea1Mushrooms = existingArea1Mushrooms + 1
					-- Register existing mushroom with AI
					local roamArea = plot:FindFirstChild("RoamArea")
					if roamArea then
						self:_startMushroomAI(mushroom, roamArea, plot)
						CollectionService:AddTag(mushroom, "Mushroom")
						Logger:Debug(string.format("Restored AI for existing mushroom %s in %s's plot", mushroom.Name, player.Name))
					end
				end
			end
		end

		if self._dataService:IsArea2Unlocked(player) then
			local area2 = plot:FindFirstChild("Area2")
			if area2 then
				local area2MushroomsFolder = area2:FindFirstChild("Mushrooms")
				if area2MushroomsFolder then
					for _, mushroom in pairs(area2MushroomsFolder:GetChildren()) do
						if mushroom:IsA("Model") and string.find(mushroom.Name, "MushroomModel_") then
							existingArea2Mushrooms = existingArea2Mushrooms + 1
							-- Register existing mushroom with AI
							local area2RoamArea = area2:FindFirstChild("RoamArea")
							if area2RoamArea then
								self:_startMushroomAI(mushroom, area2RoamArea, plot)
								CollectionService:AddTag(mushroom, "Mushroom")
								Logger:Debug(string.format("Restored AI for existing Area2 mushroom %s in %s's plot", mushroom.Name, player.Name))
							end
						end
					end
				end
			end
		end

		-- Get player's expected mushroom counts
		local expectedArea1Count = self._dataService:GetArea1MushroomCount(player)
		local expectedArea2Count = self._dataService:GetArea2MushroomCount(player)

		Logger:Info(string.format("AREA2 FIX DEBUG: Player %s - Area1: %d existing, %d expected | Area2: %d existing, %d expected", 
			player.Name, existingArea1Mushrooms, expectedArea1Count, existingArea2Mushrooms, expectedArea2Count))

		-- Spawn missing Area 1 mushrooms
		if expectedArea1Count > existingArea1Mushrooms then
			local toSpawn = expectedArea1Count - existingArea1Mushrooms
			for i = 1, toSpawn do
				self:_spawnMushroom(player, plot, "Area1")
				Logger:Info(string.format("Spawned missing Area1 mushroom %d/%d for %s", i, toSpawn, player.Name))
			end
		elseif expectedArea1Count == 0 and existingArea1Mushrooms == 0 then
			-- No Area1 mushrooms at all - spawn default one
			self:_spawnMushroom(player, plot, "Area1")
			Logger:Info(string.format("Spawned default Area1 mushroom for %s", player.Name))
		end

		-- Spawn missing Area 2 mushrooms if Area2 is unlocked
		if self._dataService:IsArea2Unlocked(player) and expectedArea2Count > existingArea2Mushrooms then
			local toSpawn = expectedArea2Count - existingArea2Mushrooms
			for i = 1, toSpawn do
				self:_spawnMushroom(player, plot, "Area2")
				Logger:Info(string.format("Spawned missing Area2 mushroom %d/%d for %s", i, toSpawn, player.Name))
			end
		end
	end
end

function MushroomService:_getPlayerPlot(player)
	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		return nil
	end

	return playerPlots:FindFirstChild("Plot_" .. player.Name)
end

function MushroomService:_getMushroomModelName(player, area)
	if area == "Area1" then
		-- Area1: Shop levels 1-50 = Mushroom_1, 51-100 = Mushroom_2
		local area1ShopLevel = self._dataService:GetArea1MushroomShopLevel(player)
		Logger:Debug(string.format("Area1 mushroom shop level for %s: %d", player.Name, area1ShopLevel))
		if area1ShopLevel < 50 then
			return "Mushroom_1"
		else
			return "Mushroom_2"
		end
	elseif area == "Area2" then
		-- Area2: Shop levels 1-50 = Mushroom_3, 51-100 = Mushroom_4  
		local area2ShopLevel = self._dataService:GetArea2MushroomShopLevel(player)
		Logger:Debug(string.format("Area2 mushroom shop level for %s: %d", player.Name, area2ShopLevel))
		if area2ShopLevel < 50 then
			return "Mushroom_3"
		else
			return "Mushroom_4"
		end
	elseif area == "Area3" then
		-- Area3: Use Mushroom_4 for all levels
		local area3ShopLevel = self._dataService:GetArea3MushroomShopLevel(player)
		Logger:Debug(string.format("Area3 mushroom shop level for %s: %d", player.Name, area3ShopLevel))
		return "Mushroom_4"
	else
		-- Default fallback
		Logger:Warn(string.format("Unknown area '%s' for player %s, using Mushroom_1", tostring(area), player.Name))
		return "Mushroom_1"
	end
end

function MushroomService:_spawnMushroom(player, plot, area)
	area = area or "Area1" -- Default to Area1
	Logger:Debug(string.format("Spawning mushroom for %s in %s", player.Name, area))

	-- Increment the appropriate area's mushroom count FIRST so model selection is accurate
	if area == "Area2" then
		self._dataService:IncrementArea2MushroomCount(player)
	elseif area == "Area3" then
		self._dataService:IncrementArea3MushroomCount(player)
	else
		self._dataService:IncrementArea1MushroomCount(player)
	end

	-- Determine which mushroom model to use based on area and counts (now updated)
	local mushroomModelName = self:_getMushroomModelName(player, area)
	Logger:Debug(string.format("Selected mushroom model: %s for %s in %s", mushroomModelName, player.Name, area))

	-- Check if MODELS folder exists first
	local modelsFolder = ReplicatedStorage:FindFirstChild("MODELS")
	if not modelsFolder then
		Logger:Error("MODELS folder not found in ReplicatedStorage")
		return nil
	end

	local mushroomTemplate = modelsFolder:FindFirstChild(mushroomModelName)
	if not mushroomTemplate then
		Logger:Error(string.format("Mushroom model %s not found in ReplicatedStorage.MODELS", mushroomModelName))
		-- Try Mushroom_1 as fallback
		mushroomTemplate = modelsFolder and modelsFolder:FindFirstChild("Mushroom_1")
		if mushroomTemplate then
			Logger:Warn(string.format("Using fallback Mushroom_1 instead of %s", mushroomModelName))
		else
			Logger:Error("No mushroom models found in MODELS folder")
			return nil
		end
	end

	-- Find the appropriate roam area based on the area parameter
	local roamArea
	if area == "Area2" then
		local area2 = plot:FindFirstChild("Area2")
		if area2 then
			roamArea = area2:FindFirstChild("RoamArea")
		end
		if not roamArea then
			Logger:Error(string.format("Area2 RoamArea not found in plot for player %s", player.Name))
			return nil
		end
	elseif area == "Area3" then
		local area3 = plot:FindFirstChild("Area3")
		if area3 then
			roamArea = area3:FindFirstChild("RoamArea")
		end
		if not roamArea then
			Logger:Error(string.format("Area3 RoamArea not found in plot for player %s", player.Name))
			return nil
		end
	else
		roamArea = plot:FindFirstChild("RoamArea")
		if not roamArea then
			Logger:Error(string.format("RoamArea not found in plot for player %s", player.Name))
			return nil
		end
	end

	-- Generate unique name for this mushroom
	mushroomCounter[player.UserId] = mushroomCounter[player.UserId] + 1
	local uniqueId = mushroomCounter[player.UserId]

	-- Clone and setup mushroom
	local mushroom = mushroomTemplate:Clone()
	mushroom.Name = "MushroomModel_" .. uniqueId
	
	-- Note: Click detection handled by client-side MushroomInteractionService via raycast
	-- No need for server-side ClickDetector which would cause double counting

	-- Position randomly within roam area
	local roamCFrame = roamArea.CFrame
	local roamSize = roamArea.Size
	local randomX = (math.random() - 0.5) * roamSize.X * 0.8
	local randomZ = (math.random() - 0.5) * roamSize.Z * 0.8
	local baseplateY = roamCFrame.Position.Y + roamSize.Y/2
	local spawnPosition = Vector3.new(roamCFrame.Position.X + randomX, baseplateY, roamCFrame.Position.Z + randomZ)

	-- Find main part (PrimaryPart or first BasePart)
	local mainPart = mushroom.PrimaryPart or mushroom:FindFirstChild("Stem") or mushroom:FindFirstChildOfClass("BasePart")
	if mainPart then
		-- Set all parts to be anchored and configure collision properly
		for _, part in pairs(mushroom:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				-- FIXED: Use collision groups to prevent player collision while allowing raycasts
				part.CanCollide = false -- Disable collision
				part.CollisionGroup = "Mushrooms" -- Prevent player collision via collision groups
			end
		end

		-- Position the mushroom
		local offsetCFrame = CFrame.new(spawnPosition)

		if mushroom.PrimaryPart then
			mushroom:SetPrimaryPartCFrame(offsetCFrame)
		else
			Logger:Warn(string.format("Mushroom %s has no PrimaryPart, using fallback positioning", mushroomModelName))
			-- Fallback: try to position the first Part found
			local firstPart = mushroom:FindFirstChildOfClass("BasePart")
			if firstPart then
				firstPart.Position = spawnPosition
			end
		end
	end

	-- Ensure appropriate folders exist based on area
	local mushroomsFolder, sporesFolder
	Logger:Info(string.format("AREA2 SPAWN DEBUG: Setting up folders for %s in %s", player.Name, area))

	if area == "Area2" then
		local area2 = plot:FindFirstChild("Area2")
		Logger:Info(string.format("AREA2 SPAWN DEBUG: Area2 folder found for %s: %s", player.Name, tostring(area2 ~= nil)))

		if area2 then
			mushroomsFolder = area2:FindFirstChild("Mushrooms")
			Logger:Info(string.format("AREA2 SPAWN DEBUG: Area2/Mushrooms folder found for %s: %s", player.Name, tostring(mushroomsFolder ~= nil)))

			if not mushroomsFolder then
				mushroomsFolder = Instance.new("Folder")
				mushroomsFolder.Name = "Mushrooms"
				mushroomsFolder.Parent = area2
				Logger:Info(string.format("AREA2 SPAWN DEBUG: Created Area2/Mushrooms folder for %s", player.Name))
			end

			sporesFolder = area2:FindFirstChild("Spores")
			if not sporesFolder then
				sporesFolder = Instance.new("Folder")
				sporesFolder.Name = "Spores"
				sporesFolder.Parent = area2
				Logger:Info(string.format("AREA2 SPAWN DEBUG: Created Area2/Spores folder for %s", player.Name))
			end
		else
			Logger:Error(string.format("AREA2 SPAWN DEBUG: Area2 folder not found for %s!", player.Name))
		end
	else
		-- Area1 mushrooms and spores
		mushroomsFolder = plot:FindFirstChild("Mushrooms")
		if not mushroomsFolder then
			mushroomsFolder = Instance.new("Folder")
			mushroomsFolder.Name = "Mushrooms"
			mushroomsFolder.Parent = plot
		end

		sporesFolder = plot:FindFirstChild("Spores")
		if not sporesFolder then
			sporesFolder = Instance.new("Folder")
			sporesFolder.Name = "Spores"
			sporesFolder.Parent = plot
		end
	end

	-- Parent mushroom to the appropriate Mushrooms folder
	if not mushroomsFolder then
		Logger:Error(string.format("AREA2 SPAWN DEBUG: No mushrooms folder found for %s in area %s", player.Name, area))
		return nil
	end

	mushroom.Parent = mushroomsFolder
	Logger:Info(string.format("AREA2 SPAWN DEBUG: Mushroom %s parented to %s for %s", 
		mushroom.Name, mushroomsFolder:GetFullName(), player.Name))

	-- Store the model type as an attribute for saving/loading
	mushroom:SetAttribute("ModelType", mushroomModelName)

	-- Tag the mushroom for CollectionService to detect
	CollectionService:AddTag(mushroom, "Mushroom")

	-- Start the AI for this mushroom
	self:_startMushroomAI(mushroom, roamArea, plot)

	Logger:Info(string.format("MUSHROOM SPAWN SUCCESS: Spawned %s mushroom %s in %s for player %s at position %s (Parent: %s)", 
		mushroomModelName, mushroom.Name, area, player.Name, tostring(spawnPosition), mushroom.Parent and mushroom.Parent.Name or "nil"))
	return mushroom
end


-- Start AI for a specific mushroom (based on SimpleMushroomAI)
function MushroomService:_startMushroomAI(mushroom, roamArea, plot)
	local mainPart = mushroom.PrimaryPart or mushroom:FindFirstChild("Stem") or mushroom:FindFirstChildOfClass("BasePart")
	if not mainPart then
		Logger:Error("No main part found in mushroom model")
		return
	end

	local isActive = true
	local currentTween = nil

	-- Store mushroom data (including plot reference for spore spawning)
	local mushroomData = {
		isActive = isActive,
		currentTween = currentTween,
		mainPart = mainPart,
		roamArea = roamArea,
		plot = plot, -- Store plot reference directly
		lastSporeSpawn = tick()
	}
	self._mushrooms[mushroom] = mushroomData

	-- Check if position is within bounds
	local function isPositionInBounds(position)
		if not roamArea then return true end

		local bounds = roamArea.Size / 2
		local center = roamArea.Position
		local buffer = 2

		return math.abs(position.X - center.X) < (bounds.X - buffer) and
			math.abs(position.Z - center.Z) < (bounds.Z - buffer)
	end

	-- Get a position in front of the mushroom within bounds
	local function getForwardPosition()
		local currentPos = mainPart.Position
		local forwardDir = mainPart.CFrame.LookVector

		for distance = CONFIG.MIN_MOVE_DISTANCE, CONFIG.MAX_MOVE_DISTANCE, 1 do
			local targetPos = Vector3.new(
				currentPos.X + forwardDir.X * distance,
				currentPos.Y,
				currentPos.Z + forwardDir.Z * distance
			)

			if isPositionInBounds(targetPos) then
				return targetPos
			end
		end

		return currentPos
	end

	-- Turn to face a random direction
	local function turnToRandomDirection()
		if currentTween then
			currentTween:Cancel()
			if currentTween then
				currentTween:Destroy()
			end
			currentTween = nil
		end

		local randomAngle = math.random() * math.pi * 2
		local rotationTime = 0.5

		local currentCFrame = mainPart.CFrame
		local targetRotation = CFrame.new(currentCFrame.Position) * CFrame.Angles(0, randomAngle, 0)

		if CONFIG.OPTIMIZED_MOVEMENT and mushroom.PrimaryPart then
			-- OPTIMIZED: Use SetPrimaryPartCFrame to move entire model as one unit
			local tweenInfo = TweenInfo.new(rotationTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			
			-- Create a dummy object to tween that will update the model's CFrame
			local dummyValue = Instance.new("CFrameValue")
			dummyValue.Value = mainPart.CFrame
			
			local connection
			connection = dummyValue.Changed:Connect(function(newCFrame)
				if mushroom.Parent and mushroom.PrimaryPart then
					mushroom:SetPrimaryPartCFrame(newCFrame)
				else
					connection:Disconnect()
					dummyValue:Destroy()
				end
			end)
			
			currentTween = TweenService:Create(dummyValue, tweenInfo, {Value = targetRotation})
			currentTween:Play()
			
			-- Clean up when tween completes
			currentTween.Completed:Connect(function()
				connection:Disconnect()
				dummyValue:Destroy()
			end)
			
			mushroomData.currentTween = currentTween
			return currentTween
		else
			-- FALLBACK: Original method for models without PrimaryPart
			local targetCFrames = {}
			local rotationOffset = targetRotation * currentCFrame:Inverse()

			for _, part in pairs(mushroom:GetDescendants()) do
				if part:IsA("BasePart") then
					targetCFrames[part] = rotationOffset * part.CFrame
				end
			end

			local tweenInfo = TweenInfo.new(rotationTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

			local tweens = {}
			for part, targetCFrame in pairs(targetCFrames) do
				local tween = TweenService:Create(part, tweenInfo, {CFrame = targetCFrame})
				table.insert(tweens, tween)
				tween:Play()
			end

			currentTween = tweens[1]
			mushroomData.currentTween = currentTween
			return tweens[1]
		end
	end

	-- Move forward in the direction the mushroom is facing
	local function moveForward()
		if currentTween then
			currentTween:Cancel()
			if currentTween then
				currentTween:Destroy()
			end
			currentTween = nil
		end

		local targetPosition = getForwardPosition()
		local startPosition = mainPart.Position

		if (targetPosition - startPosition).Magnitude < 0.1 then
			return nil
		end

		local distance = (targetPosition - startPosition).Magnitude
		local moveTime = distance / CONFIG.MOVE_SPEED

		if CONFIG.OPTIMIZED_MOVEMENT and mushroom.PrimaryPart then
			-- OPTIMIZED: Use SetPrimaryPartCFrame to move entire model as one unit
			local currentRotation = mainPart.CFrame - mainPart.CFrame.Position
			local targetCFrame = CFrame.new(targetPosition) * currentRotation
			
			local tweenInfo = TweenInfo.new(moveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			
			-- Create a dummy object to tween that will update the model's CFrame
			local dummyValue = Instance.new("CFrameValue")
			dummyValue.Value = mainPart.CFrame
			
			local connection
			connection = dummyValue.Changed:Connect(function(newCFrame)
				if mushroom.Parent and mushroom.PrimaryPart then
					mushroom:SetPrimaryPartCFrame(newCFrame)
				else
					connection:Disconnect()
					dummyValue:Destroy()
				end
			end)
			
			currentTween = TweenService:Create(dummyValue, tweenInfo, {Value = targetCFrame})
			currentTween:Play()
			
			-- Clean up when tween completes
			currentTween.Completed:Connect(function()
				connection:Disconnect()
				dummyValue:Destroy()
			end)
			
			mushroomData.currentTween = currentTween
			return currentTween
		else
			-- FALLBACK: Original method for models without PrimaryPart
			local offset = targetPosition - startPosition

			local targetCFrames = {}
			for _, part in pairs(mushroom:GetDescendants()) do
				if part:IsA("BasePart") then
					local newPosition = part.Position + offset
					local newCFrame = CFrame.new(newPosition) * (part.CFrame - part.CFrame.Position)
					targetCFrames[part] = newCFrame
				end
			end

			local tweenInfo = TweenInfo.new(moveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

			local tweens = {}
			for part, targetCFrame in pairs(targetCFrames) do
				local tween = TweenService:Create(part, tweenInfo, {CFrame = targetCFrame})
				table.insert(tweens, tween)
				tween:Play()
			end

			currentTween = tweens[1]
			mushroomData.currentTween = currentTween
			return tweens[1]
		end
	end

	-- Spawn spores from mushroom
	local function spawnSpore()
		local currentTime = tick()
		-- mushroomData is already available in local scope

		-- Check if we should spawn (limits and cleanup)
		if not self:_shouldSpawnSpore(plot) then
			return -- Skip spawning if at spore limit
		end
		
		-- Run periodic cleanup
		self:_cleanupOldSpores()

		-- Get effective spawn interval with FasterShrooms bonus
		local effectiveInterval = self:_getEffectiveSporeInterval(plot)

		if currentTime - mushroomData.lastSporeSpawn >= effectiveInterval then
			-- Determine if spawning spore or gem
			local gemChance = CONFIG.GEM_CHANCE
			-- Apply gem chance multiplier from gamepass
			local playerName = plot.Name:match("Plot_(.+)")
			local player = playerName and Players:FindFirstChild(playerName)
			if player and self._gamepassService then
				local gemChanceMultiplier = self._gamepassService:getGemChanceMultiplier(player)
				gemChance = math.min(gemChance * gemChanceMultiplier, 1.0) -- Cap at 100%
			end
			
			local isGem = math.random() <= gemChance
			local templateName = isGem and "GemSporePart" or "SporePart"
			local sporeTemplate = ReplicatedStorage:FindFirstChild(templateName)

			if sporeTemplate then
				-- Get player from plot name to generate unique spore name
				local playerName = plot.Name:match("Plot_(.+)")
				local player = playerName and Players:FindFirstChild(playerName) or nil
				local spore

				if player then
					sporeCounter[player.UserId] = sporeCounter[player.UserId] + 1
					local uniqueSporeId = sporeCounter[player.UserId]

					-- Clone and setup spore/gem with unique name
					spore = sporeTemplate:Clone()

					-- Check if this came from a gold mushroom
					local isFromGold = goldMushrooms[mushroom] or false
					if isFromGold then
						spore.Name = "Gold" .. templateName .. "_" .. uniqueSporeId
					else
						spore.Name = templateName .. "_" .. uniqueSporeId
					end
				else
					-- Fallback to generic naming if player can't be found
					spore = sporeTemplate:Clone()
					spore.Name = templateName .. "_" .. tostring(tick())
				end

				-- OPTIMIZED: Start anchored, enable physics after delay
				spore.Anchored = true
				spore.CanCollide = false
				
				-- Set spawn time for cleanup tracking
				spore:SetAttribute("SpawnTime", currentTime)
				
				-- Tag for proximity tracking
				CollectionService:AddTag(spore, "Spore")

				-- Position in center of mushroom
				local mushroomPosition = mainPart.Position
				spore.Position = mushroomPosition

				-- Delayed physics activation to reduce network spam
				task.delay(CONFIG.SPORE_PHYSICS_DELAY, function()
					if spore.Parent then
						spore.Anchored = false
						spore.CanCollide = true
						
						-- Strong pop with good height
						spore.AssemblyLinearVelocity = Vector3.new(
							(math.random() - 0.5) * 10, -- Random horizontal spread
							35 + math.random() * 15,    -- Much higher 35-50
							(math.random() - 0.5) * 10  -- Random horizontal spread
						)
					end
				end)

				-- Add to the Spores folder in the plot (required for collection)
				local plot = mushroomData.plot -- Use stored plot reference
				if plot and plot.Parent then
					-- Determine which area this spore is in by checking mushroom's parent hierarchy
					local area = "Area1" -- Default
					if mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name == "Area2" then
						area = "Area2"
					elseif mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name == "Area3" then
						area = "Area3"
					end
					
					-- Debug log the area detection
					Logger:Debug(string.format("Spore spawned from mushroom %s: detected area = %s (mushroom.Parent=%s, mushroom.Parent.Parent=%s)", 
						mushroom.Name, area, 
						mushroom.Parent and mushroom.Parent.Name or "nil",
						mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name or "nil"))

					-- Check storage capacity before spawning spore
					if self._storageService and player then
						if not self._storageService:CanSpawnSporeInArea(player, area) then
							Logger:Debug(string.format("Storage full in %s for %s, spore not spawned", area, player.Name))
							spore:Destroy()
							mushroomData.lastSporeSpawn = currentTime -- Still update timer to prevent spamming
							return
						end
					end

					local sporesFolder
					if area == "Area2" then
						local area2 = plot:FindFirstChild("Area2")
						if area2 then
							sporesFolder = area2:FindFirstChild("Spores")
							if not sporesFolder then
								sporesFolder = Instance.new("Folder")
								sporesFolder.Name = "Spores"
								sporesFolder.Parent = area2
							end
						end
					else
						sporesFolder = plot:FindFirstChild("Spores")
					end

					if sporesFolder then
						spore.Parent = sporesFolder
					else
						spore.Parent = plot -- Fallback
					end

					-- Set collision group to prevent player pushing
					self:_setSporeCollisionGroup(spore)

					-- Track spore spawning for storage system
					if self._storageService and player then
						self._storageService:OnSporeSpawned(player, area)
					end
				else
					Logger:Warn("Plot reference invalid, cannot spawn spore")
					spore:Destroy()
					return
				end

				-- Tag the spore for CollectionService to detect
				if isGem then
					CollectionService:AddTag(spore, "Gem")
				else
					CollectionService:AddTag(spore, "Spore")
				end

				-- Set up despawn timer
				game:GetService("Debris"):AddItem(spore, CONFIG.SPORE_LIFETIME)

				-- Add the spawned spore to saved data so it can be removed when collected
				if player and self._dataService then
					-- Determine which area this spore is in by checking mushroom's parent hierarchy
					local area = "Area1" -- Default
					if mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name == "Area2" then
						area = "Area2"
					elseif mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name == "Area3" then
						area = "Area3"
					end

					local sporeData = {
						Name = spore.Name,
						Type = templateName,
						Position = {spore.Position.X, spore.Position.Y, spore.Position.Z},
						Velocity = {spore.AssemblyLinearVelocity.X, spore.AssemblyLinearVelocity.Y, spore.AssemblyLinearVelocity.Z}
					}
					self._dataService:AddSporeToSavedData(player, sporeData, area)
				end

				mushroomData.lastSporeSpawn = currentTime
				Logger:Debug(string.format("Spawned %s (%s) from mushroom", isGem and "gem" or "spore", spore.Name))
			end
		end
	end

	-- Main AI loop
	task.spawn(function()
		while isActive and mushroom.Parent and mainPart.Parent do
			local pauseTime = math.random() * (CONFIG.MAX_PAUSE_TIME - CONFIG.MIN_PAUSE_TIME) + CONFIG.MIN_PAUSE_TIME
			task.wait(pauseTime)

			if not isActive then break end

			-- 70% chance turn and move, 30% just turn
			if math.random() < 0.7 then
				-- Turn then move
				local turnTween = turnToRandomDirection()
				if turnTween then
					turnTween.Completed:Wait()
				end

				task.wait(0.2)

				local moveTween = moveForward()
				if moveTween then
					moveTween.Completed:Wait()
				end
			else
				-- Just turn
				local turnTween = turnToRandomDirection()
				if turnTween then
					turnTween.Completed:Wait()
				end
			end

			-- Spore spawning now handled by synchronized system
			-- Individual spawning disabled when synchronized spawning is enabled
			if not synchronizedSpawning then
				spawnSpore()
			end

			task.wait(0.5)
		end
	end)
end

function MushroomService:_onPlayerLeaving(player)
	-- Clean up any mushrooms for leaving player (DataService handles saving)
	for mushroom, data in pairs(self._mushrooms) do
		if mushroom.Parent and string.find(mushroom.Parent.Name or "", "Plot_" .. player.Name, 1, true) then
			data.isActive = false
			if data.currentTween then
				data.currentTween:Cancel()
				data.currentTween:Destroy()
				data.currentTween = nil
			end
			self._mushrooms[mushroom] = nil
		end
	end
	
	-- Clean up plot spawn timer
	local plot = self:_getPlayerPlot(player)
	if plot and plotSpawnTimers[plot] then
		plotSpawnTimers[plot] = nil
		Logger:Debug(string.format("Cleaned up plot spawn timer for %s", player.Name))
	end

	-- Stop spore combination checker
	if playerCombinationTimers[player.UserId] then
		playerCombinationTimers[player.UserId] = nil
	end
	
	-- Clean up click count tracking
	if playerClickCounts[player.UserId] then
		playerClickCounts[player.UserId] = nil
	end

	-- Stop gold mushroom checker
	if playerGoldTimers[player.UserId] then
		playerGoldTimers[player.UserId] = nil
	end

	-- Clean up player collision group connections
	if self._playerCharacterConnections and self._playerCharacterConnections[player] then
		self._playerCharacterConnections[player]:Disconnect()
		self._playerCharacterConnections[player] = nil
	end

	-- Don't clean up counters yet - DataService will need them for final save
	Logger:Debug(string.format("Cleaned up mushroom tracking for leaving player %s", player.Name))
end

-- Public method to cleanup mushrooms for a specific player (called by DataService before plot cleanup)
function MushroomService:CleanupPlayerMushrooms(player)
	self:_onPlayerLeaving(player)
end

-- Public method to get current counters for a player (called by DataService for saving)
function MushroomService:GetPlayerCounters(player)
	return {
		MushroomCounter = mushroomCounter[player.UserId] or 0,
		SporeCounter = sporeCounter[player.UserId] or 0
	}
end

-- Public method to cleanup counters after data is saved
function MushroomService:FinalizePlayerCleanup(player)
	mushroomCounter[player.UserId] = nil
	sporeCounter[player.UserId] = nil
	Logger:Debug(string.format("Finalized cleanup for player %s - removed counters", player.Name))
end

-- Public method to spawn mushroom (for shop purchases)
function MushroomService:SpawnMushroom(player, plot, area)
	return self:_spawnMushroom(player, plot, area)
end

function MushroomService:_setupMushroomClickHandling()
	-- Wait for the remote event to be created
	task.spawn(function()
		local shared = ReplicatedStorage:WaitForChild("Shared", 10)
		if shared then
			local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
			if remoteEvents then
				local mushroomEvents = remoteEvents:WaitForChild("MushroomEvents", 10)
				if mushroomEvents then
					local mushroomClicked = mushroomEvents:WaitForChild("MushroomClicked", 10)
					if mushroomClicked then
						self._connections.MushroomClicked = mushroomClicked.OnServerEvent:Connect(function(player, mushroom)
							self:_onMushroomClicked(player, mushroom)
						end)
						Logger:Debug("Mushroom click handling connected")
					end
				end
			end
		end
	end)
end

function MushroomService:_onMushroomClicked(player, mushroom)
	-- Validate the click
	if not self:_validateMushroomClick(player, mushroom) then
		Logger:Warn(string.format("Invalid mushroom click from %s", player.Name))
		return
	end

	Logger:Info(string.format("Valid mushroom click from %s on %s", player.Name, mushroom and mushroom.Name or "nil"))

	-- Track click count and milestones
	local userId = player.UserId
	playerClickCounts[userId] = (playerClickCounts[userId] or 0) + 1
	local totalClicks = playerClickCounts[userId]
	
	-- Track click milestone analytics
	if self._robloxAnalyticsService then
		self._robloxAnalyticsService:TrackClickMilestone(player, totalClicks)
	end

	-- Force spawn spores from the clicked mushroom
	self:_forceSporeSpawn(player, mushroom)
end

function MushroomService:_validateMushroomClick(player, mushroom)
	-- Basic validation
	if not player or not player.Character then
		return false
	end

	if not mushroom or not mushroom.Parent then
		return false
	end

	-- Check if mushroom belongs to the player's plot
	local playerPlot = self:_getPlayerPlot(player)
	if not playerPlot then
		return false
	end

	if not mushroom:IsDescendantOf(playerPlot) then
		Logger:Debug("Mushroom not in player's plot")
		return false
	end

	-- Check distance (prevent exploiting)
	local character = player.Character
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false
	end

	local mushroomPosition = mushroom.PrimaryPart and mushroom.PrimaryPart.Position or mushroom:FindFirstChildOfClass("BasePart").Position
	local playerPosition = humanoidRootPart.Position
	local distance = (playerPosition - mushroomPosition).Magnitude

	if distance > 50 then -- Max interaction distance
		Logger:Debug(string.format("Player too far from mushroom: %d studs", distance))
		return false
	end

	return true
end

function MushroomService:_forceSporeSpawn(player, mushroom)
	-- Find the mushroom in our tracking
	local mushroomData = self._mushrooms[mushroom]
	if not mushroomData then
		Logger:Debug("Mushroom not found in tracking - attempting to spawn spores anyway")
		-- Try to spawn spores even if mushroom not tracked
		self:_spawnSporesFromMushroom(player, mushroom)
		return
	end

	-- Force immediate spore spawn regardless of timer
	local currentTime = tick()
	mushroomData.lastSporeSpawn = currentTime - CONFIG.SPORE_SPAWN_INTERVAL -- Reset timer

	-- Spawn only ONE spore for click
	self:_spawnSporesFromMushroom(player, mushroom)
end

function MushroomService:_spawnSporesFromMushroom(player, mushroom)
	-- Similar to the spawnSpore function but for any mushroom
	local mainPart = mushroom.PrimaryPart or mushroom:FindFirstChild("Stem") or mushroom:FindFirstChildOfClass("BasePart")
	if not mainPart then
		Logger:Error("No main part found in clicked mushroom")
		return
	end

	local plot = self:_getPlayerPlot(player)
	if not plot then
		Logger:Error("No plot found for player")
		return
	end
	
	-- Check spore limit before spawning
	if not self:_shouldSpawnSpore(plot) then
		return -- Skip spawning if at spore limit
	end

	-- Determine if spawning spore or gem
	local gemChance = CONFIG.GEM_CHANCE
	-- Apply gem chance multiplier from gamepass
	if self._gamepassService then
		local gemChanceMultiplier = self._gamepassService:getGemChanceMultiplier(player)
		gemChance = math.min(gemChance * gemChanceMultiplier, 1.0) -- Cap at 100%
	end
	
	local isGem = math.random() <= gemChance
	local templateName = isGem and "GemSporePart" or "SporePart"
	local sporeTemplate = ReplicatedStorage:FindFirstChild(templateName)

	if not sporeTemplate then
		Logger:Error(string.format("Spore template %s not found", templateName))
		return
	end

	-- Generate unique spore name
	sporeCounter[player.UserId] = sporeCounter[player.UserId] + 1
	local uniqueSporeId = sporeCounter[player.UserId]

	-- Clone and setup spore/gem
	local spore = sporeTemplate:Clone()

	-- Check if this came from a gold mushroom
	local isFromGold = goldMushrooms[mushroom] or false
	if isFromGold then
		spore.Name = "GoldClicked" .. templateName .. "_" .. uniqueSporeId
	else
		spore.Name = "Clicked" .. templateName .. "_" .. uniqueSporeId
	end

	-- OPTIMIZED: Start anchored for clicked spores too
	spore.Anchored = true
	spore.CanCollide = false
	
	-- Set spawn time for cleanup tracking
	spore:SetAttribute("SpawnTime", tick())
	
	-- Tag for proximity tracking
	CollectionService:AddTag(spore, "Spore")

	-- Position in center of mushroom
	local mushroomPosition = mainPart.Position
	spore.Position = mushroomPosition

	-- Delayed physics activation for clicked spores
	task.delay(CONFIG.SPORE_PHYSICS_DELAY, function()
		if spore.Parent then
			spore.Anchored = false
			spore.CanCollide = true
			
			-- Strong pop with good height
			spore.AssemblyLinearVelocity = Vector3.new(
				(math.random() - 0.5) * 10, -- Random horizontal spread
				35 + math.random() * 15,    -- Much higher 35-50
				(math.random() - 0.5) * 10  -- Random horizontal spread
			)
		end
	end)

	-- Add to the Spores folder in the plot
	-- Determine which area this spore is in by checking mushroom's parent hierarchy
	local area = "Area1" -- Default
	if mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name == "Area2" then
		area = "Area2"
	elseif mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name == "Area3" then
		area = "Area3"
	end

	-- Check storage capacity before spawning clicked spore
	if self._storageService then
		if not self._storageService:CanSpawnSporeInArea(player, area) then
			Logger:Debug(string.format("Storage full in %s for %s, clicked spore not spawned", area, player.Name))
			spore:Destroy()
			return
		end
	end

	local sporesFolder
	if area == "Area2" then
		local area2 = plot:FindFirstChild("Area2")
		if area2 then
			sporesFolder = area2:FindFirstChild("Spores")
			if not sporesFolder then
				sporesFolder = Instance.new("Folder")
				sporesFolder.Name = "Spores"
				sporesFolder.Parent = area2
			end
		end
	elseif area == "Area3" then
		local area3 = plot:FindFirstChild("Area3")
		if area3 then
			sporesFolder = area3:FindFirstChild("Spores")
			if not sporesFolder then
				sporesFolder = Instance.new("Folder")
				sporesFolder.Name = "Spores"
				sporesFolder.Parent = area3
			end
		end
	else
		sporesFolder = plot:FindFirstChild("Spores")
	end

	if sporesFolder then
		spore.Parent = sporesFolder
	else
		spore.Parent = plot
	end

	-- Set collision group to prevent player pushing
	self:_setSporeCollisionGroup(spore)

	-- Track spore spawning in storage service
	if self._storageService then
		self._storageService:OnSporeSpawned(player, area)
	end

	-- Tag the spore for CollectionService to detect
	if isGem then
		CollectionService:AddTag(spore, "Gem")
	else
		CollectionService:AddTag(spore, "Spore")
	end

	-- Set up despawn timer
	game:GetService("Debris"):AddItem(spore, CONFIG.SPORE_LIFETIME)

	-- Add the spawned spore to saved data so it can be removed when collected
	if self._dataService then
		-- Determine which area this spore is in by checking mushroom's parent hierarchy
		local area = "Area1" -- Default
		if mushroom.Parent and mushroom.Parent.Parent and mushroom.Parent.Parent.Name == "Area2" then
			area = "Area2"
		end

		local sporeData = {
			Name = spore.Name,
			Type = templateName,
			Position = {spore.Position.X, spore.Position.Y, spore.Position.Z},
			Velocity = {spore.AssemblyLinearVelocity.X, spore.AssemblyLinearVelocity.Y, spore.AssemblyLinearVelocity.Z}
		}
		self._dataService:AddSporeToSavedData(player, sporeData, area)
	end

end

function MushroomService:_startSporeCombinationChecker(player)
	playerCombinationTimers[player.UserId] = true

	task.spawn(function()
		while playerCombinationTimers[player.UserId] do
			if Players:FindFirstChild(player.Name) then -- Check if player still exists
				self:_checkForSporeCombination(player)
			else
				break -- Player left, stop checking
			end
			task.wait(CONFIG.COMBINATION_CHECK_INTERVAL)
		end
	end)

	Logger:Debug(string.format("Started spore combination checker for %s", player.Name))
end

function MushroomService:_startGoldMushroomChecker(player)
	playerGoldTimers[player.UserId] = true

	task.spawn(function()
		while playerGoldTimers[player.UserId] do
			if Players:FindFirstChild(player.Name) then -- Check if player still exists
				self:_checkForGoldMushroom(player)
			else
				break -- Player left, stop checking
			end
			task.wait(CONFIG.GOLD_CHECK_INTERVAL)
		end
	end)

	Logger:Debug(string.format("Started gold mushroom checker for %s", player.Name))
end

function MushroomService:_checkForGoldMushroom(player)
	-- Random chance check
	if math.random() > CONFIG.GOLD_CHANCE then
		return -- No gold mushroom this time
	end

	local plot = self:_getPlayerPlot(player)
	if not plot then return end

	-- Collect all mushrooms from both areas
	local allMushrooms = {}

	-- Area1 mushrooms
	local area1Mushrooms = plot:FindFirstChild("Mushrooms")
	if area1Mushrooms then
		for _, mushroom in pairs(area1Mushrooms:GetChildren()) do
			if mushroom:IsA("Model") and string.find(mushroom.Name, "MushroomModel_") then
				-- Don't convert already gold mushrooms
				if not goldMushrooms[mushroom] then
					table.insert(allMushrooms, mushroom)
				end
			end
		end
	end

	-- Area2 mushrooms (if unlocked)
	if self._dataService:IsArea2Unlocked(player) then
		local area2 = plot:FindFirstChild("Area2")
		if area2 then
			local area2Mushrooms = area2:FindFirstChild("Mushrooms")
			if area2Mushrooms then
				for _, mushroom in pairs(area2Mushrooms:GetChildren()) do
					if mushroom:IsA("Model") and string.find(mushroom.Name, "MushroomModel_") then
						-- Don't convert already gold mushrooms
						if not goldMushrooms[mushroom] then
							table.insert(allMushrooms, mushroom)
						end
					end
				end
			end
		end
	end

	-- If no eligible mushrooms, return
	if #allMushrooms == 0 then
		Logger:Debug(string.format("No eligible mushrooms found for gold conversion for player %s", player.Name))
		return
	end

	-- Pick a random mushroom to turn gold
	local randomMushroom = allMushrooms[math.random(#allMushrooms)]
	self:_convertMushroomToGold(player, randomMushroom)
end

function MushroomService:_convertMushroomToGold(player, mushroom)
	-- Get the Mushroom_Gold template
	local modelsFolder = ReplicatedStorage:FindFirstChild("MODELS")
	local goldMushroomTemplate

	if modelsFolder then
		goldMushroomTemplate = modelsFolder:FindFirstChild("Mushroom_Gold")
	end

	if not goldMushroomTemplate then
		Logger:Warn("Mushroom_Gold template not found in ReplicatedStorage.MODELS, skipping gold conversion")
		return
	end

	-- Store the original mushroom's position and AI data
	local originalPosition = mushroom.PrimaryPart and mushroom.PrimaryPart.CFrame or mushroom:GetPrimaryPartCFrame()
	local mushroomData = self._mushrooms[mushroom]

	-- Stop the original mushroom's AI
	if mushroomData then
		mushroomData.isActive = false
		if mushroomData.currentTween then
			mushroomData.currentTween:Cancel()
			mushroomData.currentTween:Destroy()
			mushroomData.currentTween = nil
		end
		self._mushrooms[mushroom] = nil
	end

	-- Clone the gold mushroom
	local goldMushroom = goldMushroomTemplate:Clone()
	goldMushroom.Name = mushroom.Name -- Keep the same name
	goldMushroom.Parent = mushroom.Parent -- Same parent folder

	-- Set the model type attribute for gold mushrooms
	goldMushroom:SetAttribute("ModelType", "Mushroom_Gold")

	-- Position the gold mushroom where the original was
	if originalPosition and goldMushroom.PrimaryPart then
		goldMushroom:SetPrimaryPartCFrame(originalPosition)

		-- Set all parts to be anchored and non-collidable
		for _, part in pairs(goldMushroom:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
			end
		end
	end

	-- Remove the original mushroom
	mushroom:Destroy()

	-- Tag the gold mushroom
	CollectionService:AddTag(goldMushroom, "Mushroom")

	-- Mark as gold mushroom
	goldMushrooms[goldMushroom] = true

	-- Start AI for the gold mushroom
	if mushroomData and mushroomData.roamArea and mushroomData.plot then
		self:_startMushroomAI(goldMushroom, mushroomData.roamArea, mushroomData.plot)
	else
		-- Fallback: find the appropriate roam area and plot
		local plot = self:_getPlayerPlot(player)
		if plot then
			local roamArea
			if goldMushroom.Parent and goldMushroom.Parent.Parent and goldMushroom.Parent.Parent.Name == "Area2" then
				-- Gold mushroom is in Area2
				local area2 = plot:FindFirstChild("Area2")
				if area2 then
					roamArea = area2:FindFirstChild("RoamArea")
				end
			elseif goldMushroom.Parent and goldMushroom.Parent.Parent and goldMushroom.Parent.Parent.Name == "Area3" then
				-- Gold mushroom is in Area3
				local area3 = plot:FindFirstChild("Area3")
				if area3 then
					roamArea = area3:FindFirstChild("RoamArea")
				end
			else
				-- Gold mushroom is in Area1
				roamArea = plot:FindFirstChild("RoamArea")
			end

			if roamArea then
				self:_startMushroomAI(goldMushroom, roamArea, plot)
			end
		end
	end

	-- Send notification
	if self._notificationService then
		self._notificationService:ShowNotificationToPlayer(player, "✨ One of your mushrooms has mutated into Gold!", "rare")
	end

	Logger:Info(string.format("Converted mushroom %s to gold for player %s", goldMushroom.Name, player.Name))
end

function MushroomService:_checkForSporeCombination(player)
	local plot = self:_getPlayerPlot(player)
	if not plot then return end

	-- Check Area1 spores separately
	self:_checkAreaSporesForCombination(player, plot, "Area1")

	-- Check Area2 spores separately if Area2 is unlocked
	if self._dataService and self._dataService:IsArea2Unlocked(player) then
		self:_checkAreaSporesForCombination(player, plot, "Area2")
	end
	-- Check Area3 spores separately if Area3 is unlocked
	if self._dataService.IsArea3Unlocked and self._dataService:IsArea3Unlocked(player) then
		self:_checkAreaSporesForCombination(player, plot, "Area3")
	end
end

function MushroomService:_checkAreaSporesForCombination(player, plot, area)
	local sporesFolder
	if area == "Area2" then
		local area2 = plot:FindFirstChild("Area2")
		if not area2 then return end
		sporesFolder = area2:FindFirstChild("Spores")
	elseif area == "Area3" then
		local area3 = plot:FindFirstChild("Area3")
		if not area3 then return end
		sporesFolder = area3:FindFirstChild("Spores")
	else
		sporesFolder = plot:FindFirstChild("Spores")
	end

	if not sporesFolder then return end

	-- Count ONLY regular spores (exclude gems and BigSpores)
	local spores = {}
	for _, spore in pairs(sporesFolder:GetChildren()) do
		if spore:IsA("BasePart") then
			-- ONLY include SporePart_ (exclude GemSporePart_ and BigSpore_)
			if string.find(spore.Name, "SporePart_") and not string.find(spore.Name, "GemSporePart_") then
				table.insert(spores, spore)
			end
		end
	end

	-- Check if we have 100 or more regular spores
	if #spores >= CONFIG.COMBINATION_THRESHOLD then
		Logger:Info(string.format("Combining %d regular spores from %s into BigSpore for player %s (excluding gems)", #spores, area, player.Name))
		self:_combineSpores(player, spores, plot, area)
	end
end

function MushroomService:_combineSpores(player, spores, plot, area)
	area = area or "Area1" -- Default to Area1 for backwards compatibility

	-- Get the correct roam area based on the area parameter
	local roamArea
	if area == "Area2" then
		local area2 = plot:FindFirstChild("Area2")
		if area2 then
			roamArea = area2:FindFirstChild("RoamArea")
		end
		if not roamArea then
			Logger:Error("No Area2 RoamArea found for spore combination")
			return
		end
	elseif area == "Area3" then
		local area3 = plot:FindFirstChild("Area3")
		if area3 then
			roamArea = area3:FindFirstChild("RoamArea")
		end
		if not roamArea then
			Logger:Error("No Area3 RoamArea found for spore combination")
			return
		end
	else
		roamArea = plot:FindFirstChild("RoamArea")
		if not roamArea then
			Logger:Error("No Area1 RoamArea found for spore combination")
			return
		end
	end

	local roamCFrame = roamArea.CFrame
	local roamSize = roamArea.Size
	local randomX = (math.random() - 0.5) * roamSize.X * 0.6
	local randomZ = (math.random() - 0.5) * roamSize.Z * 0.6
	local baseplateY = roamCFrame.Position.Y - roamSize.Y/2 + 2
	local combinationPoint = Vector3.new(roamCFrame.Position.X + randomX, baseplateY, roamCFrame.Position.Z + randomZ)

	-- Take exactly 100 spores for combination
	local sporesToCombine = {}
	for i = 1, math.min(CONFIG.COMBINATION_THRESHOLD, #spores) do
		table.insert(sporesToCombine, spores[i])
	end

	if CONFIG.INSTANT_COMBINATION then
		-- ULTRA OPTIMIZED: Skip all animations, instant combination
		local sporeNamesToRemove = {}
		for _, spore in pairs(sporesToCombine) do
			if spore and spore.Name then
				table.insert(sporeNamesToRemove, spore.Name)
			end
			if spore and spore.Parent then
				spore:Destroy()
			end
		end
		
		-- Batch remove spores from saved data
		if self._dataService and #sporeNamesToRemove > 0 then
			self:_batchRemoreSporesFromSavedData(player, sporeNamesToRemove)
		end
		
		-- Spawn BigSpore immediately
		self:_spawnBigSpore(player, plot, combinationPoint, area)
	else
		-- Animate spores flying to combination point
		self:_animateSporeFlying(player, sporesToCombine, combinationPoint, function()
			-- After animation completes, spawn BigSpore in the correct area
			self:_spawnBigSpore(player, plot, combinationPoint, area)
		end)
	end
end

function MushroomService:_animateSporeFlying(player, spores, targetPosition, callback)
	local flyingSpores = {}
	local completedCount = 0
	local sporeNamesToRemove = {} -- Collect all spore names for batch removal

	if CONFIG.OPTIMIZED_COMBINATION then
		-- OPTIMIZED: Only animate a few spores, destroy the rest instantly
		local sporesToAnimate = {}
		local sporesToDestroy = {}
		
		for i, spore in pairs(spores) do
			if i <= CONFIG.MAX_FLYING_SPORES and spore and spore.Parent then
				table.insert(sporesToAnimate, spore)
			else
				table.insert(sporesToDestroy, spore)
			end
			
			if spore and spore.Name then
				table.insert(sporeNamesToRemove, spore.Name)
			end
		end
		
		-- Instantly destroy most spores
		for _, spore in pairs(sporesToDestroy) do
			if spore and spore.Parent then
				spore:Destroy()
			end
		end
		
		-- Only animate a few spores for visual effect
		spores = sporesToAnimate
	end

	-- Start flying animation for selected spores
	for _, spore in pairs(spores) do
		if spore and spore.Parent then
			-- Collect spore name for batch removal later
			table.insert(sporeNamesToRemove, spore.Name)
			
			local startPosition = spore.Position
			local distance = (targetPosition - startPosition).Magnitude
			local flyTime = distance / CONFIG.SPORE_FLY_SPEED

			-- Make spore fly towards target
			spore.Anchored = true
			spore.CanCollide = false

			local flyTween = TweenService:Create(
				spore,
				TweenInfo.new(flyTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{
					Position = targetPosition + Vector3.new(
						(math.random() - 0.5) * 2, -- Small random offset
						(math.random() - 0.5) * 2,
						(math.random() - 0.5) * 2
					),
					Size = spore.Size * 0.1 -- Shrink as they fly
				}
			)

			flyTween:Play()

			flyTween.Completed:Connect(function()
				completedCount = completedCount + 1
				spore:Destroy()
				flyTween:Destroy()

				-- When all spores have finished flying, execute callback
				if completedCount >= #spores then
					-- OPTIMIZED: Batch remove all spores at once instead of individually
					if self._dataService and #sporeNamesToRemove > 0 then
						self:_batchRemoreSporesFromSavedData(player, sporeNamesToRemove)
					end
					-- Clean up any remaining tween references
					for _, tween in pairs(flyingSpores) do
						if tween then
							tween:Destroy()
						end
					end
					callback()
				end
			end)

			table.insert(flyingSpores, flyTween)
		end
	end

	Logger:Debug(string.format("Started flying animation for %d spores", #spores))
end

function MushroomService:_spawnBigSpore(player, plot, position, area)
	area = area or "Area1" -- Default to Area1 for backwards compatibility

	-- Check storage capacity before spawning BigSpore
	if self._storageService then
		if not self._storageService:CanSpawnSporeInArea(player, area) then
			Logger:Debug(string.format("Storage full in %s for %s, BigSpore not spawned", area, player.Name))
			return
		end
	end

	local bigSporeTemplate = ReplicatedStorage:FindFirstChild("BigSpore")
	if not bigSporeTemplate then
		Logger:Error("BigSpore template not found in ReplicatedStorage")
		return
	end

	-- Generate unique name
	sporeCounter[player.UserId] = sporeCounter[player.UserId] + 1
	local uniqueId = sporeCounter[player.UserId]

	local bigSpore = bigSporeTemplate:Clone()
	bigSpore.Name = "BigSpore_" .. uniqueId
	bigSpore.Position = position
	bigSpore.Size = Vector3.new(0.1, 0.1, 0.1) -- Start tiny
	bigSpore.Anchored = true
	bigSpore.CanCollide = true

	-- Add to the correct spores folder based on area
	local sporesFolder
	if area == "Area2" then
		local area2 = plot:FindFirstChild("Area2")
		if area2 then
			sporesFolder = area2:FindFirstChild("Spores")
			if not sporesFolder then
				sporesFolder = Instance.new("Folder")
				sporesFolder.Name = "Spores"
				sporesFolder.Parent = area2
			end
		end
	elseif area == "Area3" then
		local area3 = plot:FindFirstChild("Area3")
		if area3 then
			sporesFolder = area3:FindFirstChild("Spores")
			if not sporesFolder then
				sporesFolder = Instance.new("Folder")
				sporesFolder.Name = "Spores"
				sporesFolder.Parent = area3
			end
		end
	else
		sporesFolder = plot:FindFirstChild("Spores")
		if not sporesFolder then
			sporesFolder = Instance.new("Folder")
			sporesFolder.Name = "Spores"
			sporesFolder.Parent = plot
		end
	end

	if sporesFolder then
		bigSpore.Parent = sporesFolder
	else
		bigSpore.Parent = plot
	end

	-- Track BigSpore spawning for storage system
	if self._storageService then
		self._storageService:OnSporeSpawned(player, area)
	end

	-- Tag for collection system
	CollectionService:AddTag(bigSpore, "BigSpore")

	-- Growth animation
	local originalSize = bigSporeTemplate.Size
	local growTween = TweenService:Create(
		bigSpore,
		TweenInfo.new(CONFIG.BIGSPORE_GROWTH_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = originalSize}
	)

	growTween:Play()

	-- Add to saved data
	if self._dataService then
		local bigSporeData = {
			Name = bigSpore.Name,
			Type = "BigSpore",
			Position = {position.X, position.Y, position.Z},
			Velocity = {0, 0, 0}
		}
		self._dataService:AddSporeToSavedData(player, bigSporeData, area)
	end

	Logger:Info(string.format("Spawned BigSpore %s for player %s", bigSpore.Name, player.Name))
end

function MushroomService:_batchRemoreSporesFromSavedData(player, sporeNames)
	if not self._dataService or #sporeNames == 0 then
		return
	end

	-- Get player data using the proper public method
	local data = self._dataService:GetPlayerData(player)
	if not data or not data.PlotObjects then
		Logger:Warn(string.format("No cached data found for batch spore removal for player %s", player.Name))
		return
	end

	-- Create lookup table for faster name matching
	local nameSet = {}
	for _, name in ipairs(sporeNames) do
		nameSet[name] = true
	end

	local removedCount = 0

	-- Remove from Area3 spores
	if data.PlotObjects.Area3Spores then
		for i = #data.PlotObjects.Area3Spores, 1, -1 do
			local sporeData = data.PlotObjects.Area3Spores[i]
			if nameSet[sporeData.Name] then
				table.remove(data.PlotObjects.Area3Spores, i)
				removedCount = removedCount + 1
			end
		end
	end

	-- Remove from Area2 spores
	if data.PlotObjects.Area2Spores then
		for i = #data.PlotObjects.Area2Spores, 1, -1 do
			local sporeData = data.PlotObjects.Area2Spores[i]
			if nameSet[sporeData.Name] then
				table.remove(data.PlotObjects.Area2Spores, i)
				removedCount = removedCount + 1
			end
		end
	end

	-- Remove from Area1 spores
	if data.PlotObjects.Spores then
		for i = #data.PlotObjects.Spores, 1, -1 do
			local sporeData = data.PlotObjects.Spores[i]
			if nameSet[sporeData.Name] then
				table.remove(data.PlotObjects.Spores, i)
				removedCount = removedCount + 1
			end
		end
	end

	Logger:Debug(string.format("Batch removed %d/%d spores from saved data for %s", removedCount, #sporeNames, player.Name))
	
	-- Save the changes to persist spore removal
	if removedCount > 0 then
		self._dataService:SavePlotObjects(player)
		Logger:Debug(string.format("Saved plot objects after batch spore removal for %s", player.Name))
	end
end

function MushroomService:_removeSporeFromSavedData(player, sporeName)
	if not self._dataService then
		return
	end

	local data = self._dataService:GetPlayerData(player)
	if not data or not data.PlotObjects then
		return
	end

	local found = false

	-- Check Area3 spores first
	if data.PlotObjects.Area3Spores then
		for i = #data.PlotObjects.Area3Spores, 1, -1 do
			local sporeData = data.PlotObjects.Area3Spores[i]
			if sporeData.Name == sporeName then
				table.remove(data.PlotObjects.Area3Spores, i)
				found = true
				Logger:Debug(string.format("Removed spore %s from Area3Spores during combination for %s", sporeName, player.Name))
				break
			end
		end
	end

	-- Check Area2 spores if not found in Area3
	if not found and data.PlotObjects.Area2Spores then
		for i = #data.PlotObjects.Area2Spores, 1, -1 do
			local sporeData = data.PlotObjects.Area2Spores[i]
			if sporeData.Name == sporeName then
				table.remove(data.PlotObjects.Area2Spores, i)
				found = true
				Logger:Debug(string.format("Removed spore %s from Area2Spores during combination for %s", sporeName, player.Name))
				break
			end
		end
	end

	-- Check Area1 spores if not found in Area2 or Area3
	if not found and data.PlotObjects.Spores then
		for i = #data.PlotObjects.Spores, 1, -1 do
			local sporeData = data.PlotObjects.Spores[i]
			if sporeData.Name == sporeName then
				table.remove(data.PlotObjects.Spores, i)
				found = true
				Logger:Debug(string.format("Removed spore %s from Area1 Spores during combination for %s", sporeName, player.Name))
				break
			end
		end
	end

	if found then
		-- Update the player's cached data
		self._dataService:UpdatePlayerData(player, function(playerData)
			if data.PlotObjects.Spores then
				playerData.PlotObjects.Spores = data.PlotObjects.Spores
			end
			if data.PlotObjects.Area2Spores then
				playerData.PlotObjects.Area2Spores = data.PlotObjects.Area2Spores
			end
			if data.PlotObjects.Area3Spores then
				playerData.PlotObjects.Area3Spores = data.PlotObjects.Area3Spores
			end
		end)
		Logger:Debug(string.format("Removed combined spore %s from saved data for %s", sporeName, player.Name))
	else
		Logger:Debug(string.format("Spore %s not found in saved data for %s (may have been newly spawned)", sporeName, player.Name))
	end
end

-- Public method for auto tap to force mushroom clicks
function MushroomService:ForceMushroomClick(player, mushroom)
	-- Validate the click
	if not self:_validateMushroomClick(player, mushroom) then
		Logger:Debug(string.format("GamepassService auto tap: Invalid mushroom click from %s", player.Name))
		return false
	end

	-- Force spawn spores from the clicked mushroom
	self:_forceSporeSpawn(player, mushroom)
	return true
end

-- REMOVED: _addClickDetectorToMushroom method
-- Reason: Caused double counting of tutorial clicks
-- Client-side MushroomInteractionService handles all click detection via raycast

function MushroomService:Cleanup()
	for mushroom, data in pairs(self._mushrooms) do
		data.isActive = false
		if data.currentTween then
			data.currentTween:Cancel()
		end
	end

	for connectionName, connection in pairs(self._connections) do
		if connection then
			if connectionName == "SynchronizedSpawning" then
				-- Use HeartbeatManager for cleanup
				local heartbeatManager = HeartbeatManager.getInstance()
				heartbeatManager:unregister(connection)
			else
				connection:Disconnect()
			end
		end
	end
	self._connections = {}
	self._mushrooms = {}
	plotSpawnTimers = {} -- Clear plot spawn timers

	Logger:Info("MushroomService cleaned up")
end

return MushroomService