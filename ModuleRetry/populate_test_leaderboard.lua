-- Populate Test Leaderboard Data
-- Run this script in ServerScriptService to add fake players to all leaderboards
-- This will help you test that the leaderboard system is working properly

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

-- Get the same DataStores used by LeaderboardService
local sporesLeaderboard = DataStoreService:GetOrderedDataStore("SporesLeaderboard")
local gemsLeaderboard = DataStoreService:GetOrderedDataStore("GemsLeaderboard") 
local robuxLeaderboard = DataStoreService:GetOrderedDataStore("RobuxLeaderboard")

-- Fake test player data (using real Roblox user IDs for avatar images)
local testPlayers = {
    {userId = 1, name = "TestPlayer1", spores = 1500000, gems = 25000, robux = 1200},
    {userId = 2, name = "TestPlayer2", spores = 890000, gems = 18500, robux = 800},
    {userId = 3, name = "TestPlayer3", spores = 750000, gems = 15200, robux = 600},
    {userId = 4, name = "TestPlayer4", spores = 650000, gems = 12800, robux = 450},
    {userId = 5, name = "TestPlayer5", spores = 540000, gems = 9600, robux = 300},
    {userId = 6, name = "TestPlayer6", spores = 420000, gems = 7800, robux = 250},
    {userId = 7, name = "TestPlayer7", spores = 380000, gems = 6200, robux = 180},
    {userId = 8, name = "TestPlayer8", spores = 290000, gems = 4900, robux = 150},
    {userId = 9, name = "TestPlayer9", spores = 210000, gems = 3600, robux = 120},
    {userId = 10, name = "TestPlayer10", spores = 180000, gems = 2800, robux = 90},
    {userId = 11, name = "TestPlayer11", spores = 150000, gems = 2200, robux = 75},
    {userId = 12, name = "TestPlayer12", spores = 125000, gems = 1800, robux = 60},
    {userId = 13, name = "TestPlayer13", spores = 98000, gems = 1500, robux = 45},
    {userId = 14, name = "TestPlayer14", spores = 87000, gems = 1200, robux = 30},
    {userId = 15, name = "TestPlayer15", spores = 72000, gems = 980, robux = 25}
}

local function populateTestData()
    print("=== POPULATING TEST LEADERBOARD DATA ===")
    print("Adding fake players to test leaderboard functionality...")
    
    local successCount = 0
    local totalCount = #testPlayers
    
    for i, player in ipairs(testPlayers) do
        local allSuccess = true
        
        -- Add to spores leaderboard
        local success = pcall(function()
            sporesLeaderboard:SetAsync(player.userId, player.spores)
        end)
        if not success then
            print("❌ Failed to add " .. player.name .. " to spores leaderboard")
            allSuccess = false
        end
        
        -- Add to gems leaderboard  
        local success = pcall(function()
            gemsLeaderboard:SetAsync(player.userId, player.gems)
        end)
        if not success then
            print("❌ Failed to add " .. player.name .. " to gems leaderboard")
            allSuccess = false
        end
        
        -- Add to robux leaderboard
        local success = pcall(function()
            robuxLeaderboard:SetAsync(player.userId, player.robux)
        end)
        if not success then
            print("❌ Failed to add " .. player.name .. " to robux leaderboard")
            allSuccess = false
        end
        
        if allSuccess then
            successCount = successCount + 1
            print(string.format("✅ Added %s: %d spores, %d gems, %d robux", 
                player.name, player.spores, player.gems, player.robux))
        end
        
        -- Small delay to avoid hitting DataStore limits
        wait(0.1)
    end
    
    print(string.format("=== COMPLETED: %d/%d players added successfully ===", successCount, totalCount))
    
    if successCount == totalCount then
        print("🎉 All test data added! Your leaderboard should now show these fake players.")
        print("📋 Next steps:")
        print("   1. Wait 1-2 minutes for LeaderboardService to fetch the new data")
        print("   2. Check the in-game leaderboard displays")
        print("   3. Run verification script to confirm data is readable")
    else
        print("⚠️ Some players failed to add. This might be due to DataStore rate limits.")
        print("💡 Try running this script again in a few minutes.")
    end
end

-- Function to clear test data (if needed)
local function clearTestData()
    print("=== CLEARING TEST DATA ===")
    
    for i, player in ipairs(testPlayers) do
        pcall(function()
            sporesLeaderboard:RemoveAsync(player.userId)
            gemsLeaderboard:RemoveAsync(player.userId)
            robuxLeaderboard:RemoveAsync(player.userId)
        end)
        print("🗑️ Cleared data for " .. player.name)
        wait(0.1)
    end
    
    print("✅ Test data cleared!")
end

-- Function to add current player to leaderboards with high scores
local function addCurrentPlayerAsTopPlayer()
    local currentPlayer = Players.LocalPlayer
    if currentPlayer then
        local success = pcall(function()
            sporesLeaderboard:SetAsync(currentPlayer.UserId, 2000000) -- Higher than test players
            gemsLeaderboard:SetAsync(currentPlayer.UserId, 30000)
            robuxLeaderboard:SetAsync(currentPlayer.UserId, 1500)
        end)
        
        if success then
            print("✅ Added " .. currentPlayer.Name .. " as #1 on all leaderboards!")
        else
            print("❌ Failed to add current player to leaderboards")
        end
    end
end

-- Run the population script
populateTestData()

-- Uncomment the line below if you want to add yourself as #1:
-- addCurrentPlayerAsTopPlayer()

-- Uncomment the line below if you need to clear the test data:
-- clearTestData()

print("📌 Script completed! Check the output above for results.")