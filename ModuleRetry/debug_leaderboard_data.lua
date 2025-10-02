-- Debug Leaderboard Data Script
-- Place this in ServerScriptService to check actual player data vs leaderboard data

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- Wait for game to initialize
wait(5)

local function debugPlayerData()
    print("=== LEADERBOARD DEBUG ===")
    
    -- Find dressedpanther
    local targetPlayer = nil
    for _, player in pairs(Players:GetPlayers()) do
        if player.Name == "dressedpanther" then
            targetPlayer = player
            break
        end
    end
    
    if not targetPlayer then
        print("❌ dressedpanther not found in game")
        return
    end
    
    print("✅ Found player:", targetPlayer.Name, "UserId:", targetPlayer.UserId)
    
    -- Get GameCore services
    local success, gameCore = pcall(function()
        return require(game.ServerScriptService.GameCore.Main)
    end)
    
    if not success then
        print("❌ Could not access GameCore")
        return
    end
    
    local dataService = gameCore:GetService("DataService")
    local leaderboardService = gameCore:GetService("LeaderboardService")
    
    if dataService then
        print("✅ DataService found")
        
        -- Get actual player data
        local playerData = dataService:GetPlayerData(targetPlayer)
        if playerData then
            print("=== ACTUAL PLAYER DATA ===")
            print("Spores:", dataService:GetSpores(targetPlayer) or "nil")
            print("Gems:", dataService:GetGems(targetPlayer) or "nil") 
            print("RobuxSpent:", dataService:GetRobuxSpent(targetPlayer) or "nil")
            print("Raw RobuxSpent from data:", playerData.RobuxSpent or "nil")
        else
            print("❌ No player data found")
        end
    end
    
    if leaderboardService then
        print("✅ LeaderboardService found")
        
        -- Get leaderboard data
        local sporesData = leaderboardService:GetLeaderboardData("spores")
        local gemsData = leaderboardService:GetLeaderboardData("gems") 
        local robuxData = leaderboardService:GetLeaderboardData("robux")
        
        print("=== LEADERBOARD DATA ===")
        print("Spores leaderboard entries:", #sporesData)
        print("Gems leaderboard entries:", #gemsData)
        print("Robux leaderboard entries:", #robuxData)
        
        -- Check if dressedpanther is in any leaderboards
        local function findPlayerInLeaderboard(data, userId)
            for i, entry in ipairs(data) do
                if entry.UserId == userId then
                    return i, entry
                end
            end
            return nil
        end
        
        local sporesRank, sporesEntry = findPlayerInLeaderboard(sporesData, targetPlayer.UserId)
        local gemsRank, gemsEntry = findPlayerInLeaderboard(gemsData, targetPlayer.UserId)
        local robuxRank, robuxEntry = findPlayerInLeaderboard(robuxData, targetPlayer.UserId)
        
        print("=== PLAYER IN LEADERBOARDS ===")
        if sporesEntry then
            print("Spores: Rank", sporesRank, "Amount", sporesEntry.Amount)
        else
            print("Spores: NOT FOUND")
        end
        
        if gemsEntry then
            print("Gems: Rank", gemsRank, "Amount", gemsEntry.Amount)
        else
            print("Gems: NOT FOUND")
        end
        
        if robuxEntry then
            print("Robux: Rank", robuxRank, "Amount", robuxEntry.Amount)
        else
            print("Robux: NOT FOUND")
        end
    end
    
    -- Check OrderedDataStores directly
    print("=== CHECKING DATASTORES DIRECTLY ===")
    local sporesLeaderboard = DataStoreService:GetOrderedDataStore("SporesLeaderboard")
    local gemsLeaderboard = DataStoreService:GetOrderedDataStore("GemsLeaderboard")
    local robuxLeaderboard = DataStoreService:GetOrderedDataStore("RobuxLeaderboard")
    
    -- Check what's stored for this user
    local function checkDataStore(store, name, userId)
        local success, pages = pcall(function()
            return store:GetSortedAsync(false, 50)
        end)
        
        if success and pages then
            local currentPage = pages:GetCurrentPage()
            for rank, entry in ipairs(currentPage) do
                if entry.key == userId then
                    print(string.format("%s DataStore: Found at rank %d with value %d", name, rank, entry.value))
                    return
                end
            end
            print(string.format("%s DataStore: User not found in top 50", name))
        else
            print(string.format("%s DataStore: Error reading - %s", name, tostring(pages)))
        end
    end
    
    checkDataStore(sporesLeaderboard, "Spores", targetPlayer.UserId)
    checkDataStore(gemsLeaderboard, "Gems", targetPlayer.UserId) 
    checkDataStore(robuxLeaderboard, "Robux", targetPlayer.UserId)
    
    print("=== DEBUG COMPLETE ===")
end

debugPlayerData()