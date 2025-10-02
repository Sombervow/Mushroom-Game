local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local HeartbeatManager = require(script.Parent.Parent.Utilities.HeartbeatManager)
local SignalManager = require(script.Parent.Parent.Utilities.SignalManager)

local LeaderboardService = {}
LeaderboardService.__index = LeaderboardService

local UPDATE_INTERVAL = 60 -- Update player positions every 60 seconds
local GLOBAL_UPDATE_INTERVAL = 300 -- Update global leaderboards every 5 minutes

-- Global leaderboard data stores
local sporesLeaderboard = DataStoreService:GetOrderedDataStore("SporesLeaderboard")
local gemsLeaderboard = DataStoreService:GetOrderedDataStore("GemsLeaderboard") 
local robuxLeaderboard = DataStoreService:GetOrderedDataStore("RobuxLeaderboard")

function LeaderboardService.new()
	local self = setmetatable({}, LeaderboardService)
	self._connections = {}
	self._dataService = nil
	self._updateTimer = 0
	self._globalUpdateTimer = 0
	self._leaderboardData = {
		spores = {},
		gems = {},
		robux = {}
	}
	self:_initialize()
	return self
end

function LeaderboardService:_initialize()
	if RunService:IsServer() then
		self:_setupRemoteEvents()
		
		-- Set up update loop
		-- Use HeartbeatManager with 10 second interval for leaderboard updates
		self._connections.Heartbeat = HeartbeatManager.getInstance():register(function(deltaTime)
			self._updateTimer = self._updateTimer + deltaTime
			self._globalUpdateTimer = self._globalUpdateTimer + deltaTime
			
			-- Update global leaderboards from OrderedDataStore every 5 minutes
			if self._globalUpdateTimer >= GLOBAL_UPDATE_INTERVAL then
				self._globalUpdateTimer = 0
				Logger:Info("Starting global leaderboard update cycle...")
				self:_updateGlobalLeaderboards()
			end
			
			-- Update current players' positions to OrderedDataStore every 60 seconds
			if self._updateTimer >= UPDATE_INTERVAL then
				self._updateTimer = 0
				Logger:Info("Starting player position update cycle...")
				self:_updatePlayerPositions()
			end
		end)
		
		Logger:Info("LeaderboardService initialized successfully")
	end
end

function LeaderboardService:_setupRemoteEvents()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if not shared then
		Logger:Error("Shared folder not found in ReplicatedStorage")
		return
	end
	
	local remoteEvents = shared:FindFirstChild("RemoteEvents")
	if not remoteEvents then
		Logger:Error("RemoteEvents folder not found in Shared")
		return
	end
	
	-- Create LeaderboardEvents folder if it doesn't exist
	local leaderboardEvents = remoteEvents:FindFirstChild("LeaderboardEvents")
	if not leaderboardEvents then
		leaderboardEvents = Instance.new("Folder")
		leaderboardEvents.Name = "LeaderboardEvents"
		leaderboardEvents.Parent = remoteEvents
		Logger:Info("Created LeaderboardEvents folder")
	end
	
	-- Create LeaderboardDataUpdated RemoteEvent
	local leaderboardDataUpdated = leaderboardEvents:FindFirstChild("LeaderboardDataUpdated")
	if not leaderboardDataUpdated then
		leaderboardDataUpdated = Instance.new("RemoteEvent")
		leaderboardDataUpdated.Name = "LeaderboardDataUpdated"
		leaderboardDataUpdated.Parent = leaderboardEvents
		Logger:Info("Created LeaderboardDataUpdated RemoteEvent")
	end
	
	-- Create GetLeaderboardData RemoteFunction
	local getLeaderboardData = leaderboardEvents:FindFirstChild("GetLeaderboardData")
	if not getLeaderboardData then
		getLeaderboardData = Instance.new("RemoteFunction")
		getLeaderboardData.Name = "GetLeaderboardData"
		getLeaderboardData.Parent = leaderboardEvents
		
		getLeaderboardData.OnServerInvoke = function(player, leaderboardType)
			Logger:Debug(string.format("GetLeaderboardData invoked by %s for %s", player.Name, tostring(leaderboardType)))
			return self:GetLeaderboardData(leaderboardType)
		end
		Logger:Info("Created GetLeaderboardData RemoteFunction")
	end
	
	self._leaderboardDataUpdated = leaderboardDataUpdated
	self._getLeaderboardData = getLeaderboardData
	
	Logger:Info("LeaderboardService RemoteEvents set up successfully")
end

-- Update current players' scores to OrderedDataStore (every 60 seconds)
function LeaderboardService:_updatePlayerPositions()
	if not self._dataService then
		Logger:Warn("DataService not available for player position updates")
		return
	end
	
	Logger:Info("Updating player positions to global leaderboards...")
	
	-- Update each current player's score in the OrderedDataStores
	for _, player in pairs(Players:GetPlayers()) do
		local spores = self._dataService:GetSpores(player)
		local gems = self._dataService:GetGems(player)
		local robuxSpent = self._dataService:GetRobuxSpent(player) or 0
		
		-- Update spores leaderboard
		if spores and spores > 0 then
			local integerSpores = math.floor(spores + 0.5) -- Round to nearest integer
			Logger:Debug(string.format("Updating spores leaderboard for %s: %d (original: %s)", player.Name, integerSpores, tostring(spores)))
			local success, err = pcall(function()
				sporesLeaderboard:SetAsync(player.UserId, integerSpores)
			end)
			if not success then
				Logger:Warn("Failed to update spores leaderboard for " .. player.Name .. ": " .. tostring(err))
			else
				Logger:Debug(string.format("✓ Successfully updated spores leaderboard for %s", player.Name))
			end
		else
			Logger:Debug(string.format("Skipping spores leaderboard for %s (spores: %s)", player.Name, tostring(spores)))
		end
		
		-- Update gems leaderboard
		if gems and gems > 0 then
			local integerGems = math.floor(gems + 0.5) -- Round to nearest integer
			Logger:Debug(string.format("Updating gems leaderboard for %s: %d (original: %s)", player.Name, integerGems, tostring(gems)))
			local success, err = pcall(function()
				gemsLeaderboard:SetAsync(player.UserId, integerGems)
			end)
			if not success then
				Logger:Warn("Failed to update gems leaderboard for " .. player.Name .. ": " .. tostring(err))
			else
				Logger:Debug(string.format("✓ Successfully updated gems leaderboard for %s", player.Name))
			end
		else
			Logger:Debug(string.format("Skipping gems leaderboard for %s (gems: %s)", player.Name, tostring(gems)))
		end
		
		-- Update robux leaderboard
		if robuxSpent and robuxSpent > 0 then
			local integerRobux = math.floor(robuxSpent + 0.5) -- Round to nearest integer
			Logger:Debug(string.format("Updating robux leaderboard for %s: %d (original: %s)", player.Name, integerRobux, tostring(robuxSpent)))
			local success, err = pcall(function()
				robuxLeaderboard:SetAsync(player.UserId, integerRobux)
			end)
			if not success then
				Logger:Warn("Failed to update robux leaderboard for " .. player.Name .. ": " .. tostring(err))
			else
				Logger:Debug(string.format("✓ Successfully updated robux leaderboard for %s", player.Name))
			end
		else
			Logger:Debug(string.format("Skipping robux leaderboard for %s (robuxSpent: %s)", player.Name, tostring(robuxSpent)))
		end
	end
	
	Logger:Debug("Player positions updated to global leaderboards")
end

-- Fetch global top players from OrderedDataStore (every 5 minutes)
function LeaderboardService:_updateGlobalLeaderboards()
	Logger:Info("Fetching global leaderboard data...")
	
	-- Fetch top 50 spores players
	local success, sporesPages = pcall(function()
		return sporesLeaderboard:GetSortedAsync(false, 50)
	end)
	
	if success and sporesPages then
		local sporesData = {}
		local currentPage = sporesPages:GetCurrentPage()
		
		for rank, entry in ipairs(currentPage) do
			local success, playerName = pcall(function()
				return Players:GetNameFromUserIdAsync(entry.key)
			end)
			
			if success and playerName then
				table.insert(sporesData, {
					Name = playerName,
					DisplayName = playerName, -- OrderedDataStore doesn't store DisplayName
					UserId = entry.key,
					Amount = entry.value,
					Rank = rank
				})
			end
		end
		
		self._leaderboardData.spores = sporesData
		Logger:Debug("Updated global spores leaderboard: " .. #sporesData .. " players")
	else
		Logger:Warn("Failed to fetch global spores leaderboard: " .. tostring(sporesPages))
	end
	
	-- Fetch top 50 gems players  
	local success, gemsPages = pcall(function()
		return gemsLeaderboard:GetSortedAsync(false, 50)
	end)
	
	if success and gemsPages then
		local gemsData = {}
		local currentPage = gemsPages:GetCurrentPage()
		
		for rank, entry in ipairs(currentPage) do
			local success, playerName = pcall(function()
				return Players:GetNameFromUserIdAsync(entry.key)
			end)
			
			if success and playerName then
				table.insert(gemsData, {
					Name = playerName,
					DisplayName = playerName,
					UserId = entry.key,
					Amount = entry.value,
					Rank = rank
				})
			end
		end
		
		self._leaderboardData.gems = gemsData
		Logger:Debug("Updated global gems leaderboard: " .. #gemsData .. " players")
	else
		Logger:Warn("Failed to fetch global gems leaderboard: " .. tostring(gemsPages))
	end
	
	-- Fetch top 100 robux players
	local success, robuxPages = pcall(function()
		return robuxLeaderboard:GetSortedAsync(false, 100)
	end)
	
	if success and robuxPages then
		local robuxData = {}
		local currentPage = robuxPages:GetCurrentPage()
		
		for rank, entry in ipairs(currentPage) do
			local success, playerName = pcall(function()
				return Players:GetNameFromUserIdAsync(entry.key)
			end)
			
			if success and playerName then
				table.insert(robuxData, {
					Name = playerName,
					DisplayName = playerName,
					UserId = entry.key,
					Amount = entry.value,
					Rank = rank
				})
			end
		end
		
		self._leaderboardData.robux = robuxData
		Logger:Debug("Updated global robux leaderboard: " .. #robuxData .. " players")
	else
		Logger:Warn("Failed to fetch global robux leaderboard: " .. tostring(robuxPages))
	end
	
	-- Fire updated data to all clients
	if self._leaderboardDataUpdated then
		local success, err = pcall(function()
			self._leaderboardDataUpdated:FireAllClients("spores", self._leaderboardData.spores)
			self._leaderboardDataUpdated:FireAllClients("gems", self._leaderboardData.gems)
			self._leaderboardDataUpdated:FireAllClients("robux", self._leaderboardData.robux)
		end)
		
		if success then
			Logger:Info(string.format("✓ Sent global leaderboard data to clients - Spores: %d, Gems: %d, Robux: %d players", 
				#self._leaderboardData.spores, #self._leaderboardData.gems, #self._leaderboardData.robux))
		else
			Logger:Error(string.format("Failed to send leaderboard data to clients: %s", tostring(err)))
		end
	else
		Logger:Warn("LeaderboardDataUpdated RemoteEvent not found - cannot send updates to clients")
	end
end

function LeaderboardService:GetLeaderboardData(leaderboardType)
	if leaderboardType then
		return self._leaderboardData[leaderboardType] or {}
	end
	return self._leaderboardData
end

function LeaderboardService:SetDataService(dataService)
	self._dataService = dataService
	Logger:Debug("LeaderboardService linked with DataService")
	
	-- Initial updates
	self:_updatePlayerPositions()
	self:_updateGlobalLeaderboards()
end

function LeaderboardService:Cleanup()
	for connectionName, connection in pairs(self._connections) do
		if connection then
			if connectionName == "Heartbeat" then
				HeartbeatManager.getInstance():unregister(connection)
			else
				connection:Disconnect()
			end
		end
	end
	self._connections = {}
	
	Logger:Info("LeaderboardService cleaned up")
end

return LeaderboardService