-- Admin Commands System
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

-- Configuration
local ADMINS = {
    ["dressedpanther"] = true,
    -- Add more admin usernames here
}

local AdminCommands = {}

-- Store reference to running GameCore
local gameCore = nil

local function isAdmin(player)
    return ADMINS[player.Name] or player.UserId == game.CreatorId
end

local function getDataService()
    if gameCore then
        return gameCore:GetService("DataService")
    end
    return nil
end

local function getWishService()
    if gameCore then
        return gameCore:GetService("WishService")
    end
    return nil
end

local function getDaylightService()
    if gameCore then
        return gameCore:GetService("DaylightService")
    end
    return nil
end

local function getNotificationService()
    if gameCore then
        return gameCore:GetService("NotificationService")
    end
    return nil
end

local function getSystemChatService()
    if gameCore then
        return gameCore:GetService("SystemChatService")
    end
    return nil
end

local function getRobloxAnalyticsService()
    if gameCore then
        return gameCore:GetService("RobloxAnalyticsService")
    end
    return nil
end

local function getShopService()
    if gameCore then
        return gameCore:GetService("ShopService")
    end
    return nil
end

local function getStorageService()
    if gameCore then
        return gameCore:GetService("StorageService")
    end
    return nil
end

local function getLeaderboardService()
    if gameCore then
        return gameCore:GetService("LeaderboardService")
    end
    return nil
end

local function getTutorialService()
    if gameCore then
        return gameCore:GetService("TutorialService")
    end
    return nil
end

local function findPlayer(partialName, sender)
    if partialName:lower() == "me" then
        return sender
    end
    
    for _, player in pairs(Players:GetPlayers()) do
        if player.Name:lower():find(partialName:lower(), 1, true) then
            return player
        end
    end
    return nil
end

-- Command: /addgems [player] [amount]
local function addGemsCommand(sender, args)
    if #args < 2 then
        print("[ADMIN] Usage: /addgems [player] [amount]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    local amount = tonumber(args[2])
    if not amount or amount <= 0 then
        print("[ADMIN] Invalid amount: " .. args[2])
        return
    end
    
    local dataService = getDataService()
    if dataService then
        local success = dataService:AddGems(targetPlayer, amount)
        if success then
            print(string.format("[ADMIN] %s added %d gems to %s", sender.Name, amount, targetPlayer.Name))
        else
            print(string.format("[ADMIN] Failed to add gems to %s", targetPlayer.Name))
        end
    else
        print("[ADMIN] DataService not available")
    end
end

-- Command: /addspores [player] [amount]
local function addSporesCommand(sender, args)
    if #args < 2 then
        print("[ADMIN] Usage: /addspores [player] [amount]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    local amount = tonumber(args[2])
    if not amount or amount <= 0 then
        print("[ADMIN] Invalid amount: " .. args[2])
        return
    end
    
    local dataService = getDataService()
    if dataService then
        local success = dataService:AddSpores(targetPlayer, amount)
        if success then
            print(string.format("[ADMIN] %s added %d spores to %s", sender.Name, amount, targetPlayer.Name))
        else
            print(string.format("[ADMIN] Failed to add spores to %s", targetPlayer.Name))
        end
    else
        print("[ADMIN] DataService not available")
    end
end

-- Command: /addrobux [player] [amount]
local function addRobuxCommand(sender, args)
    if #args < 2 then
        print("[ADMIN] Usage: /addrobux [player] [amount]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    local amount = tonumber(args[2])
    if not amount or amount <= 0 then
        print("[ADMIN] Invalid amount: " .. args[2])
        return
    end
    
    local dataService = getDataService()
    if dataService then
        print(string.format("[ADMIN DEBUG] Attempting to add %d robux to %s", amount, targetPlayer.Name))
        
        -- Check current robux before
        local currentRobux = dataService:GetRobuxSpent(targetPlayer) or 0
        print(string.format("[ADMIN DEBUG] Current robux spent: %d", currentRobux))
        
        local success = dataService:AddRobuxSpent(targetPlayer, amount)
        if success then
            -- Check robux after
            wait(0.1) -- Small delay to ensure data is updated
            local newRobux = dataService:GetRobuxSpent(targetPlayer) or 0
            
            -- Also check raw player data
            local playerData = dataService:GetPlayerData(targetPlayer)
            local rawRobux = playerData and playerData.RobuxSpent or "nil"
            
            -- Note: RobuxSpent is no longer in Roblox leaderstats (only in custom leaderboards)
            
            print(string.format("[ADMIN] %s added %d robux spent to %s (was: %d, now: %d, raw: %s)", sender.Name, amount, targetPlayer.Name, currentRobux, newRobux, tostring(rawRobux)))
            print("[ADMIN] Note: RobuxSpent is only tracked in custom leaderboards, not Roblox leaderstats")
        else
            print(string.format("[ADMIN] Failed to add robux spent to %s", targetPlayer.Name))
        end
    else
        print("[ADMIN] DataService not available")
    end
end

-- Command: /setlevel [player] [level]
local function setLevelCommand(sender, args)
    if #args < 2 then
        print("[ADMIN] Usage: /setlevel [player] [level]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    local level = tonumber(args[2])
    if not level or level < 1 then
        print("[ADMIN] Invalid level: " .. args[2])
        return
    end
    
    local dataService = getDataService()
    if dataService then
        local success = dataService:UpdatePlayerData(targetPlayer, function(data)
            data.FastRunnerLevel = level
        end)
        if success then
            print(string.format("[ADMIN] %s set %s's FastRunner level to %d", sender.Name, targetPlayer.Name, level))
        else
            print(string.format("[ADMIN] Failed to set FastRunner level for %s", targetPlayer.Name))
        end
    else
        print("[ADMIN] DataService not available")
    end
end

-- Command: /resetdata [player]
local function resetDataCommand(sender, args)
    if #args < 1 then
        print("Usage: /resetdata [player]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("Player '" .. args[1] .. "' not found")
        return
    end
    
    -- Get GameCore services
    local success, gameCore = pcall(function()
        return require(game.ServerScriptService.GameCore.Main)
    end)
    
    if not success then
        print("[ADMIN] Could not access GameCore")
        return
    end
    
    local dataService = gameCore:GetService("DataService")
    local plotService = gameCore:GetService("PlotService")
    
    if not dataService then
        print("[ADMIN] DataService not available")
        return
    end
    
    -- Reset player data using the proper DataService method
    local resetSuccess = dataService:ResetPlayerData(targetPlayer)
    
    if resetSuccess then
        -- Reassign plot if PlotService is available
        if plotService then
            task.spawn(function()
                task.wait(1) -- Wait for data reset to propagate
                plotService:AssignPlotToPlayer(targetPlayer)
            end)
        end
        
        print(string.format("[ADMIN] %s successfully reset data for %s", sender.Name, targetPlayer.Name))
    else
        print(string.format("[ADMIN] Failed to reset data for %s", targetPlayer.Name))
    end
end

-- Command: /checkdata [player] - Check saved data in DataStore
local function checkDataCommand(sender, args)
    local dataService = getDataService()
    if not dataService then
        print("DataService not available")
        return
    end
    
    local targetPlayer = sender
    if #args > 0 then
        local targetName = args[1]
        targetPlayer = Players:FindFirstChild(targetName)
        if not targetPlayer then
            print("Player not found:", targetName)
            return
        end
    end
    
    print(string.format("Checking saved data for %s...", targetPlayer.Name))
    dataService:DebugCheckSavedData(targetPlayer)
end

-- Command: /checkworld [player] - Check what's in the world
local function checkWorldCommand(sender, args)
    local dataService = getDataService()
    if not dataService then
        print("DataService not available")
        return
    end
    
    local targetPlayer = sender
    if #args > 0 then
        local targetName = args[1]
        targetPlayer = Players:FindFirstChild(targetName)
        if not targetPlayer then
            print("Player not found:", targetName)
            return
        end
    end
    
    print(string.format("Checking world data for %s...", targetPlayer.Name))
    dataService:DebugCheckWorldData(targetPlayer)
end

-- Command: /debugarea2 [player] - Complete Area2 debug check
local function debugArea2Command(sender, args)
    local dataService = getDataService()
    if not dataService then
        print("DataService not available")
        return
    end
    
    local targetPlayer = sender
    if #args > 0 then
        local targetName = args[1]
        targetPlayer = Players:FindFirstChild(targetName)
        if not targetPlayer then
            print("Player not found:", targetName)
            return
        end
    end
    
    print(string.format("=== COMPLETE AREA2 DEBUG FOR %s ===", targetPlayer.Name))
    print("1. Checking world data...")
    dataService:DebugCheckWorldData(targetPlayer)
    
    print("2. Checking saved data...")
    dataService:DebugCheckSavedData(targetPlayer)
    
    print("3. Forcing save to see what happens...")
    local saveSuccess = dataService:SavePlotObjects(targetPlayer)
    print(string.format("SavePlotObjects result: %s", tostring(saveSuccess)))
    
    print("4. Checking saved data again after forced save...")
    dataService:DebugCheckSavedData(targetPlayer)
    
    print("=== AREA2 DEBUG COMPLETE ===")
end

-- Command: /debugascend [player] - Debug ascend requirements
local function debugAscendCommand(sender, args)
    local shopService = getShopService()
    if not shopService then
        print("ShopService not available")
        return
    end
    
    local targetPlayer = sender
    if #args > 0 then
        local targetName = args[1]
        targetPlayer = Players:FindFirstChild(targetName)
        if not targetPlayer then
            print("Player not found:", targetName)
            return
        end
    end
    
    print(string.format("=== ASCEND REQUIREMENTS DEBUG FOR %s ===", targetPlayer.Name))
    local requirements = shopService:GetAscendRequirements(targetPlayer)
    print(requirements)
    
    -- Additional detailed debug info
    local dataService = getDataService()
    if dataService then
        print("=== DETAILED DATA DEBUG ===")
        print(string.format("Area1 Mushroom Shop Level: %d", dataService:GetArea1MushroomShopLevel(targetPlayer)))
        print(string.format("Area1 Mushroom Count: %d", dataService:GetArea1MushroomCount(targetPlayer)))
        print(string.format("Area2 Mushroom Shop Level: %d", dataService:GetArea2MushroomShopLevel(targetPlayer)))
        print(string.format("Area2 Mushroom Count: %d", dataService:GetArea2MushroomCount(targetPlayer)))
        print("=== DETAILED DATA DEBUG COMPLETE ===")
    end
    
    print("=== ASCEND DEBUG COMPLETE ===")
end

local function helpCommand(sender, args)
    local helpText = [[
=== ADMIN COMMANDS ===
PLAYER COMMANDS:
/addgems [player] [amount] - Add gems to player
/addspores [player] [amount] - Add spores to player  
/setlevel [player] [level] - Set FastRunner level
/addwishes [player] [amount] - Add wishes to player (max 5)
/resetdata [player] - Reset player data to defaults

DAYLIGHT COMMANDS:
/night - Force transition to night time
/day - Force transition to day time
/timeinfo - Show current day/night cycle information

NOTIFICATION COMMANDS:
/notify [message] - Send notification to all players

CHAT TIP COMMANDS:
/tip [message] - Send custom tip to chat
/forcetip - Force the next scheduled tip to appear
/tipstatus - Show tip system status

ROBLOX ANALYTICS COMMANDS:
/testfunnel [player] - Test funnel tracking for a player

STORAGE TESTING COMMANDS:
/teststorage [player] [area] - Check storage capacity for player's area

LEADERBOARD COMMANDS:
/updateleaderboards - Force update global leaderboards

TUTORIAL COMMANDS:
/checktutorial [player] - Check tutorial completion status
/resettutorial [player] - Reset tutorial for a player

/help - Show this help

Use 'me' as player name to target yourself
Examples:
/addgems me 100
/addspores dressedpanther 1000
/setlevel me 5
/addwishes me 3
/night
/day
/timeinfo
/notify Hello everyone!
/tip Remember to upgrade your mushrooms!
/forcetip
/tipstatus
]]
    print(helpText)
end

-- Command: /addwishes [player] [amount]
local function addWishesCommand(sender, args)
    if #args < 2 then
        print("Usage: /addwishes [player] [amount]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("Player '" .. args[1] .. "' not found")
        return
    end
    
    local amount = tonumber(args[2])
    if not amount or amount < 0 then
        print("Invalid amount. Must be a positive number.")
        return
    end
    
    local dataService = getDataService()
    if not dataService then
        print("[ADMIN] Could not access DataService")
        return
    end
    
    -- Update player's wish count
    dataService:UpdatePlayerData(targetPlayer, function(data)
        if not data.WishData then
            data.WishData = {
                wishes = 0,
                lastWishTime = os.time(),
                inventory = {}
            }
        end
        local oldWishes = data.WishData.wishes
        data.WishData.wishes = math.min(data.WishData.wishes + amount, 5) -- Cap at MAX_WISHES
        print(string.format("[ADMIN DEBUG] Updated %s wishes from %d to %d", targetPlayer.Name, oldWishes, data.WishData.wishes))
    end)
    
    -- Get fresh data after update
    local playerData = dataService:GetPlayerData(targetPlayer)
    if playerData and playerData.WishData then
        print(string.format("[ADMIN] Verified: %s now has %d wishes", targetPlayer.Name, playerData.WishData.wishes))
        
        -- Trigger GUI update using WishService
        local wishService = getWishService()
        if wishService then
            wishService:UpdatePlayerWishGUI(targetPlayer)
            print(string.format("[ADMIN] Sent GUI update via WishService to %s", targetPlayer.Name))
        else
            print("[ADMIN] Could not access WishService for GUI update")
        end
    end
    
    print(string.format("[ADMIN] Added %d wishes to %s", amount, targetPlayer.Name))
end

-- Command: /night - Force transition to night
local function forceNightCommand(sender, args)
    local daylightService = getDaylightService()
    if not daylightService then
        print("[ADMIN] DaylightService not available")
        return
    end
    
    if daylightService:IsNight() then
        print("[ADMIN] It's already night time")
        return
    end
    
    daylightService:ForceTransitionToNight()
    print(string.format("[ADMIN] %s forced transition to night time", sender.Name))
end

-- Command: /day - Force transition to day
local function forceDayCommand(sender, args)
    local daylightService = getDaylightService()
    if not daylightService then
        print("[ADMIN] DaylightService not available")
        return
    end
    
    if daylightService:IsDay() then
        print("[ADMIN] It's already day time")
        return
    end
    
    daylightService:ForceTransitionToDay()
    print(string.format("[ADMIN] %s forced transition to day time", sender.Name))
end

-- Command: /timeinfo - Show current day/night info
local function timeInfoCommand(sender, args)
    local daylightService = getDaylightService()
    if not daylightService then
        print("[ADMIN] DaylightService not available")
        return
    end
    
    local timeOfDay = daylightService:GetCurrentTimeOfDay()
    local gemBoost = daylightService:GetGemProductionBoost()
    local timeLeft = daylightService:GetTimeUntilNextCycle()
    local progress = daylightService:GetCycleProgress()
    
    print(string.format("[ADMIN] === Day/Night Cycle Info ==="))
    print(string.format("[ADMIN] Current Time: %s", timeOfDay))
    print(string.format("[ADMIN] Gem Production Boost: %.1fx", gemBoost))
    print(string.format("[ADMIN] Time Until Next Cycle: %.1f seconds", timeLeft))
    print(string.format("[ADMIN] Cycle Progress: %.1f%%", progress * 100))
end

-- Command: /notify [message] - Send notification to all players
local function notifyAllCommand(sender, args)
    if #args < 1 then
        print("[ADMIN] Usage: /notify [message]")
        return
    end
    
    local message = table.concat(args, " ")
    local notificationService = getNotificationService()
    if not notificationService then
        print("[ADMIN] NotificationService not available")
        return
    end
    
    notificationService:ShowNotificationToAll("📢 " .. message, "wishEarned")
    print(string.format("[ADMIN] %s sent notification to all players: %s", sender.Name, message))
end

-- Command: /tip [message] - Send custom tip to chat
local function customTipCommand(sender, args)
    if #args < 1 then
        print("[ADMIN] Usage: /tip [message]")
        return
    end
    
    local message = table.concat(args, " ")
    local systemChatService = getSystemChatService()
    if not systemChatService then
        print("[ADMIN] SystemChatService not available")
        return
    end
    
    local success = systemChatService:SendCustomTip(message)
    if success then
        print(string.format("[ADMIN] %s sent custom tip: %s", sender.Name, message))
    else
        print(string.format("[ADMIN] Failed to send custom tip"))
    end
end

-- Command: /forcetip - Force the next scheduled tip to appear
local function forceTipCommand(sender, args)
    local systemChatService = getSystemChatService()
    if not systemChatService then
        print("[ADMIN] SystemChatService not available")
        return
    end
    
    systemChatService:ForceNextTip()
    print(string.format("[ADMIN] %s forced the next system tip", sender.Name))
end

-- Command: /tipstatus - Show tip system status
local function tipStatusCommand(sender, args)
    local systemChatService = getSystemChatService()
    if not systemChatService then
        print("[ADMIN] SystemChatService not available")
        return
    end
    
    local totalTips = systemChatService:GetTipCount()
    local currentIndex = systemChatService:GetCurrentTipIndex()
    local nextTipIn = systemChatService:GetNextTipIn()
    
    print(string.format("[ADMIN] === Tip System Status ==="))
    print(string.format("[ADMIN] Total Tips: %d", totalTips))
    print(string.format("[ADMIN] Current Tip Index: %d", currentIndex))
    print(string.format("[ADMIN] Next Tip In: %.1f seconds", nextTipIn))
end

-- Command: /resetdaily [player] - Reset daily rewards for a player
local function resetDailyCommand(sender, args)
    if #args < 1 then
        print("[ADMIN] Usage: /resetdaily [player]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    local dataService = getDataService()
    if not dataService then
        print("[ADMIN] DataService not available")
        return
    end
    
    local success = dataService:UpdatePlayerData(targetPlayer, function(data)
        data.DailyRewards = {
            startDay = 0,  -- Will be reset to current day on next access
            lastClaimDay = 0,
            claimedDays = {}
        }
    end)
    
    if success then
        print(string.format("[ADMIN] %s reset daily rewards for %s", sender.Name, targetPlayer.Name))
    else
        print(string.format("[ADMIN] Failed to reset daily rewards for %s", targetPlayer.Name))
    end
end

-- Command: /dailyinfo [player] - Show daily reward debug info
local function dailyInfoCommand(sender, args)
    if #args < 1 then
        print("[ADMIN] Usage: /dailyinfo [player]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    -- Get DailyRewardService through gameCore
    local dailyRewardService = gameCore and gameCore:GetService("DailyRewardService")
    if not dailyRewardService then
        print("[ADMIN] DailyRewardService not available")
        return
    end
    
    local dailyData = dailyRewardService:GetDailyRewardData(targetPlayer)
    if not dailyData then
        print("[ADMIN] No daily reward data for " .. targetPlayer.Name)
        return
    end
    
    print(string.format("[ADMIN] === Daily Rewards Debug for %s ===", targetPlayer.Name))
    print(string.format("[ADMIN] Current Day: %d", dailyData.currentDay))
    print(string.format("[ADMIN] Can Claim: %s", tostring(dailyData.canClaim)))
    print(string.format("[ADMIN] Next Claim Time: %d (in %d seconds)", dailyData.nextClaimTime, dailyData.nextClaimTime - os.time()))
    
    print(string.format("[ADMIN] Claimed Days:"))
    for day = 1, 15 do
        local status = dailyData.claimedDays[day] and "✓ CLAIMED" or "○ Available"
        print(string.format("[ADMIN]   Day %d: %s", day, status))
    end
    
    print(string.format("[ADMIN] Current Day %d Rewards:", dailyData.currentDay))
    local rewards = dailyData.rewards[dailyData.currentDay] or {}
    for i, reward in ipairs(rewards) do
        print(string.format("[ADMIN]   %d %s", reward.amount, reward.type))
    end
end

-- Command: /checktutorial [player] - Check tutorial completion status
local function checkTutorialCommand(sender, args)
    if #args < 1 then
        print("[ADMIN] Usage: /checktutorial [player]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    local dataService = getDataService()
    local tutorialService = getTutorialService()
    
    if not dataService then
        print("[ADMIN] DataService not available")
        return
    end
    
    print(string.format("=== TUTORIAL STATUS FOR %s ===", targetPlayer.Name))
    
    -- Check DataService data
    local playerData = dataService:GetPlayerData(targetPlayer)
    if playerData then
        print(string.format("DataService TutorialCompleted: %s (type: %s)", 
            tostring(playerData.TutorialCompleted), type(playerData.TutorialCompleted)))
    else
        print("No player data found in DataService")
    end
    
    -- Check TutorialService status
    if tutorialService then
        local tutorialCompleted = tutorialService:IsPlayerTutorialCompleted(targetPlayer)
        print(string.format("TutorialService status: %s", tutorialCompleted and "COMPLETED" or "NOT COMPLETED"))
    else
        print("TutorialService not available")
    end
    
    print("============================")
end

-- Command: /resettutorial [player] - Reset tutorial for a player
local function resetTutorialCommand(sender, args)
    if #args < 1 then
        print("[ADMIN] Usage: /resettutorial [player]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    local tutorialService = getTutorialService()
    if not tutorialService then
        print("[ADMIN] TutorialService not available")
        return
    end
    
    tutorialService:ResetPlayerTutorial(targetPlayer)
    print(string.format("[ADMIN] %s reset tutorial for %s", sender.Name, targetPlayer.Name))
end

-- Command: /updateleaderboards - Force update global leaderboards
local function updateLeaderboardsCommand(sender, args)
    local leaderboardService = getLeaderboardService()
    if not leaderboardService then
        print("[ADMIN] LeaderboardService not available")
        return
    end
    
    print("[ADMIN] Forcing leaderboard updates...")
    
    -- Force update player positions
    leaderboardService:_updatePlayerPositions()
    print("[ADMIN] ✓ Player positions updated")
    
    -- Force update global leaderboards
    leaderboardService:_updateGlobalLeaderboards()
    print("[ADMIN] ✓ Global leaderboards updated")
    
    print("[ADMIN] Leaderboard update complete")
end

-- Command: /teststorage [player] [area] - Test storage system for a player
local function testStorageCommand(sender, args)
    if #args < 1 then
        print("[ADMIN] Usage: /teststorage [player] [area]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    local area = args[2] or "Area1"
    
    local storageService = getStorageService()
    if not storageService then
        print("[ADMIN] StorageService not available")
        return
    end
    
    print(string.format("=== STORAGE TEST FOR %s in %s ===", targetPlayer.Name, area))
    
    local storageInfo = storageService:GetAreaStorageInfo(targetPlayer, area)
    print(string.format("Current: %d/%d spores (%.1f%%)", storageInfo.current, storageInfo.max, storageInfo.percentage))
    print(string.format("Is Full: %s", tostring(storageInfo.isFull)))
    print(string.format("Can Spawn: %s", tostring(storageService:CanSpawnSporeInArea(targetPlayer, area))))
    
    print("=========================")
end

-- Command: /recountspores [player] - Recount spores for a player to fix sync issues
local function recountSporesCommand(sender, args)
    if #args < 1 then
        print("[ADMIN] Usage: /recountspores [player]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        return
    end
    
    local storageService = getStorageService()
    if not storageService then
        print("[ADMIN] ❌ StorageService not available")
        return
    end
    
    print(string.format("[ADMIN] Recounting spores for %s...", targetPlayer.Name))
    storageService:RecountPlayerSpores(targetPlayer)
    print("[ADMIN] ✓ Spore recount complete")
end

-- Command: /testfunnel [player] - Test funnel tracking for a player
local function testFunnelCommand(sender, args)
    if #args < 1 then
        print("[ADMIN] Usage: /testfunnel [player]")
        return
    end
    
    local targetPlayer = findPlayer(args[1], sender)
    if not targetPlayer then
        print("[ADMIN] Player '" .. args[1] .. "' not found")
        return
    end
    
    local robloxAnalyticsService = getRobloxAnalyticsService()
    if not robloxAnalyticsService then
        print("[ADMIN] RobloxAnalyticsService not available")
        return
    end
    
    print(string.format("=== TESTING FUNNEL FOR %s ===", targetPlayer.Name))
    
    -- Test onboarding funnel steps
    robloxAnalyticsService:TrackPlayerSpawned(targetPlayer)
    print("✓ Tracked: Player Spawned")
    
    robloxAnalyticsService:TrackFirstMushroomClick(targetPlayer)
    print("✓ Tracked: First Mushroom Click")
    
    robloxAnalyticsService:TrackFirstSporeCollection(targetPlayer)
    print("✓ Tracked: First Spore Collection")
    
    -- Test shop funnel
    local sessionId = robloxAnalyticsService:TrackShopOpened(targetPlayer, "Spore")
    if sessionId then
        print("✓ Tracked: Shop Opened (Session: " .. sessionId:sub(1, 8) .. "...)")
        
        robloxAnalyticsService:TrackItemViewed(targetPlayer, "Spore", sessionId, "SporeUpgrade")
        print("✓ Tracked: Item Viewed")
        
        robloxAnalyticsService:TrackPurchaseCompleted(targetPlayer, "Spore", sessionId, "SporeUpgrade", 100)
        print("✓ Tracked: Purchase Completed")
    end
    
    print("=========================")
    print("Check Creator Hub Analytics for funnel data!")
end

-- Command registry
local commands = {
    addgems = addGemsCommand,
    addspores = addSporesCommand,
    addrobux = addRobuxCommand,
    setlevel = setLevelCommand,
    resetdata = resetDataCommand,
    addwishes = addWishesCommand,
    night = forceNightCommand,
    day = forceDayCommand,
    timeinfo = timeInfoCommand,
    notify = notifyAllCommand,
    resetdaily = resetDailyCommand,
    dailyinfo = dailyInfoCommand,
    tip = customTipCommand,
    forcetip = forceTipCommand,
    tipstatus = tipStatusCommand,
    checkdata = checkDataCommand,
    checkworld = checkWorldCommand,
    debugarea2 = debugArea2Command,
    debugascend = debugAscendCommand,
    checktutorial = checkTutorialCommand,
    resettutorial = resetTutorialCommand,
    teststorage = testStorageCommand,
    recountspores = recountSporesCommand,
    updateleaderboards = updateLeaderboardsCommand,
    testfunnel = testFunnelCommand,
    help = helpCommand,
}

-- Chat command handler
local function onChatted(player, message)
    if not isAdmin(player) then
        return
    end
    
    print(string.format("[ADMIN DEBUG] Chat from %s: %s", player.Name, message))
    
    if message:sub(1, 1) ~= "/" then
        return
    end
    
    local args = {}
    for word in message:gmatch("%S+") do
        table.insert(args, word)
    end
    
    if #args == 0 then
        print("[ADMIN DEBUG] No args found")
        return
    end
    
    local command = args[1]:sub(2):lower() -- Remove the '/' and make lowercase
    table.remove(args, 1) -- Remove command from args
    
    print(string.format("[ADMIN DEBUG] Command: '%s', Args: %s", command, table.concat(args, ", ")))
    
    -- Debug: List all available commands
    local availableCommands = {}
    for cmdName in pairs(commands) do
        table.insert(availableCommands, cmdName)
    end
    print(string.format("[ADMIN DEBUG] Available commands: %s", table.concat(availableCommands, ", ")))
    
    -- Debug: Check if command exists
    local commandExists = commands[command] ~= nil
    print(string.format("[ADMIN DEBUG] Command '%s' exists: %s", command, tostring(commandExists)))
    
    if commands[command] then
        print(string.format("[ADMIN DEBUG] Executing command: %s", command))
        commands[command](player, args)
    else
        print(string.format("[ADMIN DEBUG] Unknown command: %s", command))
    end
end

function AdminCommands:Initialize(gameCoreInstance)
    gameCore = gameCoreInstance
    
    print("[ADMIN DEBUG] AdminCommands initializing with GameCore reference")
    
    -- Connect chat events
    Players.PlayerAdded:Connect(function(player)
        print(string.format("[ADMIN DEBUG] Connecting chat for new player: %s", player.Name))
        player.Chatted:Connect(function(message)
            onChatted(player, message)
        end)
    end)

    -- Handle players already in game
    for _, player in pairs(Players:GetPlayers()) do
        print(string.format("[ADMIN DEBUG] Connecting chat for existing player: %s", player.Name))
        player.Chatted:Connect(function(message)
            onChatted(player, message)
        end)
    end

    print("Admin Commands loaded. Type /help for commands.")
    local adminList = {}
    for name in pairs(ADMINS) do
        table.insert(adminList, name)
    end
    print("Current admins:", table.concat(adminList, ", "))
    
    -- Test admin status for current players
    for _, player in pairs(Players:GetPlayers()) do
        local adminStatus = isAdmin(player) and "ADMIN" or "NOT ADMIN"
        print(string.format("[ADMIN DEBUG] Player %s is %s", player.Name, adminStatus))
    end
end

return AdminCommands