local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local SignalManager = require(script.Parent.Parent.Utilities.SignalManager)

local DailyRewardService = {}
DailyRewardService.__index = DailyRewardService

local DAILY_REWARDS = {
	[1] = {{type = "shroom_food", amount = 1}},
	[2] = {{type = "gems", amount = 250}},
	[3] = {{type = "gems", amount = 750}, {type = "shroom_food", amount = 1}},
	[4] = {{type = "gems", amount = 250}},
	[5] = {{type = "gems", amount = 1000}},
	[6] = {{type = "gems", amount = 250}},
	[7] = {{type = "gems", amount = 2500}, {type = "shroom_food", amount = 1}},
	[8] = {{type = "gems", amount = 250}},
	[9] = {{type = "gems", amount = 250}},
	[10] = {{type = "gems", amount = 1000}, {type = "shroom_food", amount = 1}},
	[11] = {{type = "gems", amount = 250}},
	[12] = {{type = "gems", amount = 500}},
	[13] = {{type = "shroom_food", amount = 1}},
	[14] = {{type = "gems", amount = 250}},
	[15] = {{type = "gems", amount = 9500}, {type = "shroom_food", amount = 1}}
}

local SECONDS_IN_DAY = 24 * 60 * 60

function DailyRewardService.new()
	local self = setmetatable({}, DailyRewardService)
	self._connections = {}
	self._dataService = nil
	self._notificationService = nil
	self._inventoryService = nil
	self:_initialize()
	return self
end

function DailyRewardService:_initialize()
	self:_setupRemoteEvents()
	Logger:Info("DailyRewardService initialized")
end

function DailyRewardService:_setupRemoteEvents()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if shared then
		local remoteEvents = shared:FindFirstChild("RemoteEvents")
		if remoteEvents then
			local dailyRewardEvents = remoteEvents:FindFirstChild("DailyRewardEvents")
			if dailyRewardEvents then
				local claimRewardEvent = dailyRewardEvents:FindFirstChild("ClaimReward")
				if claimRewardEvent then
					claimRewardEvent.OnServerEvent:Connect(function(player)
						self:ClaimReward(player)
					end)
				end

				local getDailyDataEvent = dailyRewardEvents:FindFirstChild("GetDailyData")
				if getDailyDataEvent then
					getDailyDataEvent.OnServerInvoke = function(player)
						return self:GetDailyRewardData(player)
					end
				end
			end
		end
	end
end

function DailyRewardService:GetDailyRewardData(player)
	if not self._dataService then
		Logger:Warn("DataService not linked to DailyRewardService")
		return nil
	end

	local playerData = self._dataService:GetPlayerData(player)
	if not playerData then
		Logger:Warn(string.format("No player data found for %s", player.Name))
		return nil
	end

	local dailyData = playerData.DailyRewards or {}
	local currentTime = os.time()
	local daysSinceEpoch = math.floor(currentTime / SECONDS_IN_DAY)

	-- Calculate current day (1-15, cycling)
	local startDay = dailyData.startDay

	-- Initialize startDay if it's not set (new player or migrated data)
	if not startDay or startDay == 0 then
		startDay = daysSinceEpoch
		-- Update the startDay in player data immediately
		local success = self._dataService:UpdatePlayerData(player, function(data)
			if not data.DailyRewards then
				data.DailyRewards = {
					startDay = startDay,
					lastClaimDay = 0,
					claimedDays = {}
				}
			else
				data.DailyRewards.startDay = startDay
			end
		end)
		Logger:Info(string.format("Initialized startDay for %s to %d", player.Name, startDay))
	end

	local daysDifference = daysSinceEpoch - startDay
	local currentDay = (daysDifference % 15) + 1

	Logger:Info(string.format("Daily reward calculation for %s: daysSinceEpoch=%d, startDay=%d, daysDifference=%d, currentDay=%d", 
		player.Name, daysSinceEpoch, startDay, daysDifference, currentDay))

	-- Check if player can claim today
	local lastClaimDay = dailyData.lastClaimDay or 0
	local canClaim = lastClaimDay < daysSinceEpoch

	Logger:Info(string.format("Claim check for %s: lastClaimDay=%d, daysSinceEpoch=%d, canClaim=%s", 
		player.Name, lastClaimDay, daysSinceEpoch, tostring(canClaim)))

	-- Calculate next claim time if already claimed today
	local nextClaimTime = 0
	if not canClaim then
		nextClaimTime = (daysSinceEpoch + 1) * SECONDS_IN_DAY
	end

	return {
		currentDay = currentDay,
		canClaim = canClaim,
		nextClaimTime = nextClaimTime,
		claimedDays = dailyData.claimedDays or {},
		rewards = DAILY_REWARDS
	}
end

function DailyRewardService:ClaimReward(player)
	Logger:Info(string.format("ClaimReward called for player %s", player.Name))

	if not self._dataService then
		Logger:Warn("DataService not linked to DailyRewardService")
		return false
	end

	local dailyData = self:GetDailyRewardData(player)
	if not dailyData then
		Logger:Error("Failed to get daily reward data")
		return false
	end

	Logger:Info(string.format("Player %s claim attempt - canClaim: %s, currentDay: %d", 
		player.Name, tostring(dailyData.canClaim), dailyData.currentDay))

	if not dailyData.canClaim then
		-- Send notification for early claim attempt
		if self._notificationService then
			local hoursLeft = math.ceil((dailyData.nextClaimTime - os.time()) / 3600)
			Logger:Info(string.format("Sending early claim notification to %s: %d hours left", player.Name, hoursLeft))
			self._notificationService:ShowNotificationToPlayer(player, string.format("Come back in %d hours!", hoursLeft), "warning")
		end
		return false
	end

	local currentDay = dailyData.currentDay
	local rewards = DAILY_REWARDS[currentDay]

	if not rewards then
		Logger:Error(string.format("No rewards defined for day %d", currentDay))
		return false
	end

	-- Award all rewards for this day
	local allSuccessful = true
	local awardedRewards = {}

	for _, reward in ipairs(rewards) do
		local success = false
		if reward.type == "gems" then
			Logger:Info(string.format("Awarding %d gems to %s", reward.amount, player.Name))
			success = self._dataService:AddGems(player, reward.amount)
			Logger:Info(string.format("Gem award result: %s", tostring(success)))
		elseif reward.type == "shroom_food" then
			Logger:Info(string.format("Awarding %d Shroom Food to %s", reward.amount, player.Name))
			-- Add shroom food to inventory
			if self._inventoryService then
				success = self._inventoryService:AddToInventory(player, "Shroom Food", reward.amount)
				Logger:Info(string.format("Shroom Food award result: %s", tostring(success)))
			else
				Logger:Warn("InventoryService not available for Shroom Food reward")
				success = false
			end
		end

		if success then
			table.insert(awardedRewards, reward)
		else
			allSuccessful = false
			Logger:Error(string.format("Failed to award %d %s to player %s", reward.amount, reward.type, player.Name))
		end
	end

	if allSuccessful then
		-- Update player's daily reward data
		local updateSuccess = self._dataService:UpdatePlayerData(player, function(data)
			if not data.DailyRewards then
				data.DailyRewards = {
					startDay = math.floor(os.time() / SECONDS_IN_DAY),
					lastClaimDay = 0,
					claimedDays = {}
				}
			end

			data.DailyRewards.lastClaimDay = math.floor(os.time() / SECONDS_IN_DAY)

			-- Mark current day as claimed
			if not data.DailyRewards.claimedDays then
				data.DailyRewards.claimedDays = {}
			end
			data.DailyRewards.claimedDays[currentDay] = true
		end)

		if updateSuccess then
			-- Create summary for logging and notifications
			local rewardSummary = {}
			for _, reward in ipairs(awardedRewards) do
				table.insert(rewardSummary, string.format("%d %s", reward.amount, reward.type:gsub("_", " ")))
			end
			local summaryText = table.concat(rewardSummary, " + ")

			Logger:Info(string.format("Player %s claimed day %d rewards: %s - sending client notification", player.Name, currentDay, summaryText))

			-- Send notification for successful claim
			if self._notificationService then
				self._notificationService:ShowNotificationToPlayer(player, string.format("Claimed %s!", summaryText), "itemReceived")
			end

			-- Notify client that reward was claimed
			local shared = ReplicatedStorage:FindFirstChild("Shared")
			if shared then
				local remoteEvents = shared:FindFirstChild("RemoteEvents")
				if remoteEvents then
					local dailyRewardEvents = remoteEvents:FindFirstChild("DailyRewardEvents")
					if dailyRewardEvents then
						local rewardClaimedEvent = dailyRewardEvents:FindFirstChild("RewardClaimed")
						if rewardClaimedEvent then
							Logger:Info(string.format("Firing RewardClaimed event to client for day %d", currentDay))
							rewardClaimedEvent:FireClient(player, currentDay, awardedRewards)
						else
							Logger:Warn("RewardClaimed RemoteEvent not found")
						end
					else
						Logger:Warn("DailyRewardEvents folder not found for client notification")
					end
				else
					Logger:Warn("RemoteEvents folder not found for client notification")
				end
			else
				Logger:Warn("Shared folder not found for client notification")
			end

			return true
		else
			Logger:Error(string.format("Failed to update daily reward data for player %s", player.Name))
		end
	else
		Logger:Error(string.format("Failed to award some rewards to player %s", player.Name))
	end

	return false
end

function DailyRewardService:SetDataService(dataService)
	self._dataService = dataService
	Logger:Debug("DailyRewardService linked with DataService")
end

function DailyRewardService:SetNotificationService(notificationService)
	self._notificationService = notificationService
	Logger:Debug("DailyRewardService linked with NotificationService")
end

function DailyRewardService:SetInventoryService(inventoryService)
	self._inventoryService = inventoryService
	Logger:Debug("DailyRewardService linked with InventoryService")
end

function DailyRewardService:Cleanup()
	for connectionName, connection in pairs(self._connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._connections = {}

	Logger:Info("DailyRewardService cleaned up")
end

return DailyRewardService