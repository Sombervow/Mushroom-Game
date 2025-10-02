local Players = game:GetService("Players")
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)

local RobloxAnalyticsService = {}
RobloxAnalyticsService.__index = RobloxAnalyticsService

function RobloxAnalyticsService.new()
	local self = setmetatable({}, RobloxAnalyticsService)
	
	-- Track player funnel sessions
	self._playerFunnelSessions = {}
	self._playerOnboardingProgress = {}
	
	-- Services
	self._dataService = nil
	
	self:_initialize()
	return self
end

function RobloxAnalyticsService:_initialize()
	Logger:Info("RobloxAnalyticsService initializing...")
	
	self:_setupRemoteEvents()
	self:_connectPlayerEvents()
	
	Logger:Info("✓ RobloxAnalyticsService initialized")
end

function RobloxAnalyticsService:SetServices(dataService)
	self._dataService = dataService
	Logger:Debug("RobloxAnalyticsService linked with DataService")
end

function RobloxAnalyticsService:_setupRemoteEvents()
	-- Create analytics remote events
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	if not shared then
		Logger:Error("Shared folder not found in ReplicatedStorage")
		return
	end
	
	local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
	if not remoteEvents then
		Logger:Error("RemoteEvents folder not found")
		return
	end
	
	-- Create Analytics folder
	local analyticsFolder = remoteEvents:FindFirstChild("Analytics")
	if not analyticsFolder then
		analyticsFolder = Instance.new("Folder")
		analyticsFolder.Name = "Analytics"
		analyticsFolder.Parent = remoteEvents
	end
	
	-- Create funnel step remote
	local funnelStepEvent = analyticsFolder:FindFirstChild("FunnelStepEvent")
	if not funnelStepEvent then
		funnelStepEvent = Instance.new("RemoteEvent")
		funnelStepEvent.Name = "FunnelStepEvent"
		funnelStepEvent.Parent = analyticsFolder
	end
	
	-- Connect remote events
	funnelStepEvent.OnServerEvent:Connect(function(player, funnelName, step, stepName, customData)
		self:_validateAndLogFunnelStep(player, funnelName, step, stepName, customData)
	end)
	
	Logger:Info("✓ Roblox Analytics remote events created and connected")
end

function RobloxAnalyticsService:_connectPlayerEvents()
	-- Track player join for onboarding funnel
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerJoined(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerLeaving(player)
	end)
end

function RobloxAnalyticsService:_onPlayerJoined(player)
	Logger:Info(string.format("Starting onboarding funnel for %s", player.Name))
	
	-- Initialize player tracking
	self._playerOnboardingProgress[player.UserId] = {}
	self._playerFunnelSessions[player.UserId] = {}
	
	-- Start onboarding funnel immediately
	self:LogOnboardingStep(player, 1, "Player Joined")
end

function RobloxAnalyticsService:_onPlayerLeaving(player)
	-- Cleanup player data
	self._playerOnboardingProgress[player.UserId] = nil
	self._playerFunnelSessions[player.UserId] = nil
	
	Logger:Info(string.format("Cleaned up analytics data for %s", player.Name))
end

-- ONBOARDING FUNNEL (One-time funnel)
function RobloxAnalyticsService:LogOnboardingStep(player, step, stepName)
	if not player or not step or not stepName then
		Logger:Warn("Invalid onboarding step parameters")
		return
	end
	
	-- Check if player already completed this step
	local playerProgress = self._playerOnboardingProgress[player.UserId]
	if playerProgress and playerProgress[step] then
		Logger:Debug(string.format("Player %s already completed onboarding step %d", player.Name, step))
		return
	end
	
	-- Log the onboarding step
	local success, error = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
	
	if success then
		-- Mark step as completed
		if not playerProgress then
			self._playerOnboardingProgress[player.UserId] = {}
		end
		self._playerOnboardingProgress[player.UserId][step] = true
		
		Logger:Info(string.format("Onboarding: %s completed step %d - %s", player.Name, step, stepName))
	else
		Logger:Error(string.format("Failed to log onboarding step for %s: %s", player.Name, tostring(error)))
	end
end

-- SHOP FUNNEL (Recurring funnel)
function RobloxAnalyticsService:StartShopFunnel(player, shopType)
	if not player or not shopType then
		Logger:Warn("Invalid shop funnel parameters")
		return nil
	end
	
	-- Generate unique session ID
	local sessionId = HttpService:GenerateGUID()
	
	-- Store session
	if not self._playerFunnelSessions[player.UserId] then
		self._playerFunnelSessions[player.UserId] = {}
	end
	self._playerFunnelSessions[player.UserId][sessionId] = {
		funnelName = shopType .. "Shop",
		startTime = tick(),
		currentStep = 0
	}
	
	-- Log first step
	self:LogFunnelStep(player, shopType .. "Shop", sessionId, 1, "Opened Shop")
	
	return sessionId
end

-- Helper function to ensure session exists
function RobloxAnalyticsService:_ensureSessionExists(player, sessionId, funnelName)
	if not self._playerFunnelSessions[player.UserId] then
		self._playerFunnelSessions[player.UserId] = {}
	end
	
	if not self._playerFunnelSessions[player.UserId][sessionId] then
		self._playerFunnelSessions[player.UserId][sessionId] = {
			funnelName = funnelName,
			startTime = tick(),
			currentStep = 0
		}
	end
end

function RobloxAnalyticsService:LogFunnelStep(player, funnelName, sessionId, step, stepName, customData)
	if not player or not funnelName or not sessionId or not step or not stepName then
		Logger:Warn("Invalid funnel step parameters")
		return
	end
	
	-- Ensure session exists (auto-create if missing)
	self:_ensureSessionExists(player, sessionId, funnelName)
	
	-- Validate session exists
	local playerSessions = self._playerFunnelSessions[player.UserId]
	if not playerSessions or not playerSessions[sessionId] then
		Logger:Warn(string.format("Failed to create session for player %s: %s", player.Name, sessionId))
		return
	end
	
	-- Check if step is in sequence
	local session = playerSessions[sessionId]
	if step <= session.currentStep then
		Logger:Debug(string.format("Player %s already completed step %d in funnel %s", player.Name, step, funnelName))
		return
	end
	
	-- Log the funnel step
	local success, error = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName)
	end)
	
	if success then
		-- Update session progress
		session.currentStep = step
		session.lastStepTime = tick()
		
		Logger:Info(string.format("Funnel: %s completed %s step %d - %s", player.Name, funnelName, step, stepName))
		
		-- Log custom data if provided
		if customData then
			Logger:Debug(string.format("Custom data: %s", HttpService:JSONEncode(customData)))
		end
	else
		Logger:Error(string.format("Failed to log funnel step for %s: %s", player.Name, tostring(error)))
	end
end

-- UPGRADE FUNNEL (Recurring funnel with item-based session IDs)
function RobloxAnalyticsService:LogUpgradeFunnel(player, itemType, itemId, step, stepName)
	if not player or not itemType or not itemId or not step or not stepName then
		Logger:Warn("Invalid upgrade funnel parameters")
		return
	end
	
	-- Create session ID based on player and item
	local sessionId = string.format("%d-%s-%s", player.UserId, itemType, itemId)
	
	-- Store session if new
	if not self._playerFunnelSessions[player.UserId] then
		self._playerFunnelSessions[player.UserId] = {}
	end
	
	if not self._playerFunnelSessions[player.UserId][sessionId] then
		self._playerFunnelSessions[player.UserId][sessionId] = {
			funnelName = itemType .. "Upgrade",
			startTime = tick(),
			currentStep = 0,
			itemId = itemId
		}
	end
	
	-- Log funnel step
	self:LogFunnelStep(player, itemType .. "Upgrade", sessionId, step, stepName)
end

-- Validation function for client requests
function RobloxAnalyticsService:_validateAndLogFunnelStep(player, funnelName, step, stepName, customData)
	-- Basic validation
	if not player or not funnelName or not step or not stepName then
		Logger:Warn(string.format("Invalid funnel step from client: %s", player.Name))
		return
	end
	
	-- Validate step numbers for known funnels
	local maxSteps = {
		["Onboarding"] = 10,
		["SporeShop"] = 5,
		["GemShop"] = 5,
		["GamepassShop"] = 4,
		["SporeUpgrade"] = 6,
		["MushroomUpgrade"] = 6
	}
	
	if maxSteps[funnelName] and step > maxSteps[funnelName] then
		Logger:Warn(string.format("Invalid step %d for funnel %s from %s (max: %d)", 
			step, funnelName, player.Name, maxSteps[funnelName]))
		return
	end
	
	-- Route to appropriate function based on funnel type
	if funnelName == "Onboarding" then
		self:LogOnboardingStep(player, step, stepName)
	else
		-- For other funnels, we need a session ID from the client
		Logger:Warn(string.format("Recurring funnel %s requires session ID", funnelName))
	end
end

-- Public API for game services to use

-- Onboarding Funnel Steps (1-15) - Extended for more milestones
function RobloxAnalyticsService:TrackPlayerSpawned(player)
	self:LogOnboardingStep(player, 2, "Player Spawned")
end

function RobloxAnalyticsService:TrackFirstMushroomClick(player)
	self:LogOnboardingStep(player, 3, "First Mushroom Click")
end

function RobloxAnalyticsService:TrackFirstSporeCollection(player)
	self:LogOnboardingStep(player, 4, "First Spore Collection")
end

function RobloxAnalyticsService:TrackFirstShopOpen(player)
	self:LogOnboardingStep(player, 5, "First Shop Open")
end

function RobloxAnalyticsService:TrackFirstSporeUpgrade(player)
	self:LogOnboardingStep(player, 6, "First Spore Upgrade")
end

function RobloxAnalyticsService:TrackFirstMushroomPurchase(player)
	self:LogOnboardingStep(player, 7, "First Mushroom Purchase")
end

function RobloxAnalyticsService:TrackTutorialComplete(player)
	self:LogOnboardingStep(player, 8, "Tutorial Complete")
end

function RobloxAnalyticsService:TrackArea2Unlock(player)
	self:LogOnboardingStep(player, 9, "Area2 Unlocked")
end

function RobloxAnalyticsService:TrackFirstGemUpgrade(player)
	self:LogOnboardingStep(player, 10, "First Gem Upgrade")
end

function RobloxAnalyticsService:TrackFirstRebirth(player)
	self:LogOnboardingStep(player, 11, "First Rebirth")
end

function RobloxAnalyticsService:TrackArea3Unlock(player)
	self:LogOnboardingStep(player, 12, "Area3 Unlocked")
end

function RobloxAnalyticsService:TrackFirstMaxUpgrade(player)
	self:LogOnboardingStep(player, 13, "First Max Upgrade")
end

function RobloxAnalyticsService:TrackHundredClicks(player)
	self:LogOnboardingStep(player, 14, "100 Mushroom Clicks")
end

function RobloxAnalyticsService:TrackMidGameComplete(player)
	self:LogOnboardingStep(player, 15, "Mid Game Complete")
end

-- Shop Funnels
function RobloxAnalyticsService:TrackShopOpened(player, shopType)
	return self:StartShopFunnel(player, shopType)
end

function RobloxAnalyticsService:TrackItemViewed(player, shopType, sessionId, itemName)
	self:LogFunnelStep(player, shopType .. "Shop", sessionId, 2, "Item Viewed", {item = itemName})
end

function RobloxAnalyticsService:TrackPurchaseAttempted(player, shopType, sessionId, itemName, cost)
	self:LogFunnelStep(player, shopType .. "Shop", sessionId, 3, "Purchase Attempted", {
		item = itemName,
		cost = cost
	})
end

function RobloxAnalyticsService:TrackPurchaseCompleted(player, shopType, sessionId, itemName, cost)
	self:LogFunnelStep(player, shopType .. "Shop", sessionId, 4, "Purchase Completed", {
		item = itemName,
		cost = cost,
		success = true
	})
end

function RobloxAnalyticsService:TrackPurchaseFailed(player, shopType, sessionId, itemName, cost, reason)
	self:LogFunnelStep(player, shopType .. "Shop", sessionId, 5, "Purchase Failed", {
		item = itemName,
		cost = cost,
		reason = reason,
		success = false
	})
end

-- Upgrade Funnels
function RobloxAnalyticsService:TrackUpgradeViewed(player, upgradeType, upgradeId)
	self:LogUpgradeFunnel(player, upgradeType, upgradeId, 1, "Upgrade Viewed")
end

function RobloxAnalyticsService:TrackUpgradeConsidered(player, upgradeType, upgradeId, currentLevel, cost)
	self:LogUpgradeFunnel(player, upgradeType, upgradeId, 2, "Upgrade Considered")
end

function RobloxAnalyticsService:TrackUpgradeAttempted(player, upgradeType, upgradeId, currentLevel, cost)
	self:LogUpgradeFunnel(player, upgradeType, upgradeId, 3, "Upgrade Attempted")
end

function RobloxAnalyticsService:TrackUpgradeCompleted(player, upgradeType, upgradeId, newLevel, cost)
	self:LogUpgradeFunnel(player, upgradeType, upgradeId, 4, "Upgrade Completed")
end

function RobloxAnalyticsService:TrackUpgradeFailed(player, upgradeType, upgradeId, reason)
	self:LogUpgradeFunnel(player, upgradeType, upgradeId, 5, "Upgrade Failed")
end

function RobloxAnalyticsService:TrackUpgradeMaxed(player, upgradeType, upgradeId, maxLevel)
	self:LogUpgradeFunnel(player, upgradeType, upgradeId, 6, "Upgrade Maxed")
end

-- ========================================
-- DETAILED PROGRESSION MILESTONE FUNNELS
-- ========================================

-- Mushroom Purchase Milestones Funnel
function RobloxAnalyticsService:TrackMushroomMilestone(player, area, mushroomCount)
	local funnelName = area .. "MushroomMilestones"
	local sessionId = string.format("%d-%s-mushrooms", player.UserId, area:lower())
	
	local step, stepName
	if mushroomCount == 5 then
		step, stepName = 1, "5 Mushrooms"
	elseif mushroomCount == 10 then
		step, stepName = 2, "10 Mushrooms"
	elseif mushroomCount == 25 then
		step, stepName = 3, "25 Mushrooms"
	elseif mushroomCount == 50 then
		step, stepName = 4, "50 Mushrooms (Max)"
	else
		return -- Not a milestone
	end
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		area = area,
		mushroom_count = mushroomCount
	})
	
	Logger:Info(string.format("Mushroom milestone: %s reached %s in %s", player.Name, stepName, area))
end

-- Spore Upgrade Level Milestones Funnel
function RobloxAnalyticsService:TrackSporeUpgradeMilestone(player, area, level)
	local funnelName = area .. "SporeUpgradeMilestones"
	local sessionId = string.format("%d-%s-spore-levels", player.UserId, area:lower())
	
	local step, stepName
	if level == 10 then
		step, stepName = 1, "Level 10"
	elseif level == 25 then
		step, stepName = 2, "Level 25"
	elseif level == 50 then
		step, stepName = 3, "Level 50"
	elseif level == 75 then
		step, stepName = 4, "Level 75"
	elseif level == 100 then
		step, stepName = 5, "Level 100 (Max)"
	else
		return -- Not a milestone
	end
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		area = area,
		upgrade_level = level
	})
	
	-- Track first max upgrade for onboarding
	if level == 100 then
		self:TrackFirstMaxUpgrade(player)
	end
	
	Logger:Info(string.format("Spore upgrade milestone: %s reached %s %s", player.Name, area, stepName))
end

-- Gem Upgrade Milestones Funnel
function RobloxAnalyticsService:TrackGemUpgradeMilestone(player, upgradeCount)
	local funnelName = "GemUpgradeMilestones"
	local sessionId = string.format("%d-gem-purchases", player.UserId)
	
	local step, stepName
	if upgradeCount == 1 then
		step, stepName = 1, "First Gem Upgrade"
		self:TrackFirstGemUpgrade(player) -- Also track in onboarding
	elseif upgradeCount == 5 then
		step, stepName = 2, "5 Gem Upgrades"
	elseif upgradeCount == 10 then
		step, stepName = 3, "10 Gem Upgrades"
	elseif upgradeCount == 20 then
		step, stepName = 4, "20 Gem Upgrades"
	elseif upgradeCount == 50 then
		step, stepName = 5, "50 Gem Upgrades"
	else
		return -- Not a milestone
	end
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		total_gem_upgrades = upgradeCount
	})
	
	Logger:Info(string.format("Gem upgrade milestone: %s reached %s", player.Name, stepName))
end

-- Mushroom Click Milestones Funnel
function RobloxAnalyticsService:TrackClickMilestone(player, totalClicks)
	local funnelName = "MushroomClickMilestones"
	local sessionId = string.format("%d-clicks", player.UserId)
	
	local step, stepName
	if totalClicks == 10 then
		step, stepName = 1, "10 Clicks"
	elseif totalClicks == 50 then
		step, stepName = 2, "50 Clicks"
	elseif totalClicks == 100 then
		step, stepName = 3, "100 Clicks"
		self:TrackHundredClicks(player) -- Also track in onboarding
	elseif totalClicks == 500 then
		step, stepName = 4, "500 Clicks"
	elseif totalClicks == 1000 then
		step, stepName = 5, "1000 Clicks"
	else
		return -- Not a milestone
	end
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		total_clicks = totalClicks
	})
	
	Logger:Info(string.format("Click milestone: %s reached %s", player.Name, stepName))
end

-- Spore Collection Milestones Funnel
function RobloxAnalyticsService:TrackSporeCollectionMilestone(player, totalSpores)
	local funnelName = "SporeCollectionMilestones"
	local sessionId = string.format("%d-spore-collection", player.UserId)
	
	local step, stepName
	if totalSpores >= 1000 and totalSpores < 10000 then
		step, stepName = 1, "1K Spores"
	elseif totalSpores >= 10000 and totalSpores < 100000 then
		step, stepName = 2, "10K Spores"
	elseif totalSpores >= 100000 and totalSpores < 1000000 then
		step, stepName = 3, "100K Spores"
	elseif totalSpores >= 1000000 and totalSpores < 10000000 then
		step, stepName = 4, "1M Spores"
	elseif totalSpores >= 10000000 then
		step, stepName = 5, "10M+ Spores"
	else
		return -- Not a milestone
	end
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		total_spores = totalSpores
	})
	
	Logger:Info(string.format("Spore collection milestone: %s reached %s", player.Name, stepName))
end

-- Gem Collection Milestones Funnel
function RobloxAnalyticsService:TrackGemCollectionMilestone(player, totalGems)
	local funnelName = "GemCollectionMilestones"
	local sessionId = string.format("%d-gem-collection", player.UserId)
	
	local step, stepName
	if totalGems >= 10 and totalGems < 50 then
		step, stepName = 1, "10 Gems"
	elseif totalGems >= 50 and totalGems < 100 then
		step, stepName = 2, "50 Gems"
	elseif totalGems >= 100 and totalGems < 500 then
		step, stepName = 3, "100 Gems"
	elseif totalGems >= 500 and totalGems < 1000 then
		step, stepName = 4, "500 Gems"
	elseif totalGems >= 1000 then
		step, stepName = 5, "1000+ Gems"
	else
		return -- Not a milestone
	end
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		total_gems = totalGems
	})
	
	Logger:Info(string.format("Gem collection milestone: %s reached %s", player.Name, stepName))
end

-- Playtime Milestones Funnel
function RobloxAnalyticsService:TrackPlaytimeMilestone(player, sessionMinutes)
	local funnelName = "PlaytimeMilestones"
	local sessionId = string.format("%d-playtime", player.UserId)
	
	local step, stepName
	if sessionMinutes >= 5 and sessionMinutes < 15 then
		step, stepName = 1, "5 Minutes"
	elseif sessionMinutes >= 15 and sessionMinutes < 30 then
		step, stepName = 2, "15 Minutes"
	elseif sessionMinutes >= 30 and sessionMinutes < 60 then
		step, stepName = 3, "30 Minutes"
	elseif sessionMinutes >= 60 and sessionMinutes < 120 then
		step, stepName = 4, "1 Hour"
	elseif sessionMinutes >= 120 then
		step, stepName = 5, "2+ Hours"
	else
		return -- Not a milestone
	end
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		session_minutes = sessionMinutes
	})
	
	Logger:Info(string.format("Playtime milestone: %s reached %s", player.Name, stepName))
end

-- Comprehensive Game Progression Funnel
function RobloxAnalyticsService:TrackGameProgressionMilestone(player, milestone)
	local funnelName = "GameProgressionMilestones"
	local sessionId = string.format("%d-game-progression", player.UserId)
	
	local milestones = {
		["first_purchase"] = {1, "First Purchase"},
		["area1_complete"] = {2, "Area1 Complete"},
		["area2_unlocked"] = {3, "Area2 Unlocked"},
		["area2_complete"] = {4, "Area2 Complete"},
		["ready_for_rebirth"] = {5, "Ready for Rebirth"},
		["first_rebirth"] = {6, "First Rebirth"},
		["area3_unlocked"] = {7, "Area3 Unlocked"},
		["area3_active"] = {8, "Area3 Active"},
		["endgame_player"] = {9, "Endgame Player"}
	}
	
	local milestoneData = milestones[milestone]
	if not milestoneData then
		Logger:Warn("Unknown progression milestone: " .. tostring(milestone))
		return
	end
	
	local step, stepName = milestoneData[1], milestoneData[2]
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		milestone_type = milestone
	})
	
	-- Track special onboarding milestones
	if milestone == "first_rebirth" then
		self:TrackFirstRebirth(player)
	elseif milestone == "area2_complete" and milestone == "area1_complete" then
		self:TrackMidGameComplete(player)
	end
	
	Logger:Info(string.format("Game progression milestone: %s reached %s", player.Name, stepName))
end

-- Area-specific Completion Funnel
function RobloxAnalyticsService:TrackAreaCompletion(player, area, completionPercent)
	local funnelName = area .. "Completion"
	local sessionId = string.format("%d-%s-completion", player.UserId, area:lower())
	
	local step, stepName
	if completionPercent >= 25 and completionPercent < 50 then
		step, stepName = 1, "25% Complete"
	elseif completionPercent >= 50 and completionPercent < 75 then
		step, stepName = 2, "50% Complete"
	elseif completionPercent >= 75 and completionPercent < 100 then
		step, stepName = 3, "75% Complete"
	elseif completionPercent >= 100 then
		step, stepName = 4, "100% Complete"
	else
		return -- Not a milestone
	end
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		area = area,
		completion_percent = completionPercent
	})
	
	-- Track progression milestones
	if completionPercent >= 100 then
		if area == "Area1" then
			self:TrackGameProgressionMilestone(player, "area1_complete")
		elseif area == "Area2" then
			self:TrackGameProgressionMilestone(player, "area2_complete")
		end
	end
	
	Logger:Info(string.format("Area completion: %s reached %s %s", player.Name, area, stepName))
end

-- Collection Milestones Funnel
function RobloxAnalyticsService:TrackCollectionMilestone(player, itemType, totalCollected)
	local funnelName = itemType .. "CollectionMilestones"
	local sessionId = string.format("%d-%s-collection", player.UserId, itemType:lower())
	
	local step, stepName
	if itemType == "Spore" then
		if totalCollected == 100 then
			step, stepName = 1, "100 Spores"
		elseif totalCollected == 500 then
			step, stepName = 2, "500 Spores"
		elseif totalCollected == 1000 then
			step, stepName = 3, "1,000 Spores"
		elseif totalCollected == 5000 then
			step, stepName = 4, "5,000 Spores"
		elseif totalCollected == 10000 then
			step, stepName = 5, "10,000 Spores"
		elseif totalCollected == 50000 then
			step, stepName = 6, "50,000 Spores"
		elseif totalCollected == 100000 then
			step, stepName = 7, "100,000 Spores"
		else
			return -- Not a milestone
		end
	elseif itemType == "Gem" then
		if totalCollected == 10 then
			step, stepName = 1, "10 Gems"
		elseif totalCollected == 50 then
			step, stepName = 2, "50 Gems"
		elseif totalCollected == 100 then
			step, stepName = 3, "100 Gems"
		elseif totalCollected == 500 then
			step, stepName = 4, "500 Gems"
		elseif totalCollected == 1000 then
			step, stepName = 5, "1,000 Gems"
		elseif totalCollected == 5000 then
			step, stepName = 6, "5,000 Gems"
		else
			return -- Not a milestone
		end
	else
		return -- Unknown item type
	end
	
	self:LogFunnelStep(player, funnelName, sessionId, step, stepName, {
		item_type = itemType,
		total_collected = totalCollected
	})
	
	Logger:Info(string.format("Collection milestone: %s collected %s %ss total", player.Name, totalCollected, itemType:lower()))
end

function RobloxAnalyticsService:Cleanup()
	Logger:Info("RobloxAnalyticsService shutting down...")
	
	-- Clear player data
	self._playerFunnelSessions = {}
	self._playerOnboardingProgress = {}
	
	Logger:Info("✓ RobloxAnalyticsService shutdown complete")
end

return RobloxAnalyticsService