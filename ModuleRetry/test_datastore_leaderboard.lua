-- DataStore Leaderboard Testing Script
-- Tests the underlying OrderedDataStore functionality

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

-- Get the same DataStores used by LeaderboardService
local sporesLeaderboard = DataStoreService:GetOrderedDataStore("SporesLeaderboard")
local gemsLeaderboard = DataStoreService:GetOrderedDataStore("GemsLeaderboard") 
local robuxLeaderboard = DataStoreService:GetOrderedDataStore("RobuxLeaderboard")

local function testDataStoreReads()
    print("=== DATASTORE LEADERBOARD TEST ===")
    
    -- Test reading spores leaderboard
    local success, sporesPages = pcall(function()
        return sporesLeaderboard:GetSortedAsync(false, 10)
    end)
    
    if success and sporesPages then
        print("✅ Spores DataStore accessible:")
        local currentPage = sporesPages:GetCurrentPage()
        for rank, entry in ipairs(currentPage) do
            local success, playerName = pcall(function()
                return Players:GetNameFromUserIdAsync(entry.key)
            end)
            
            if success then
                print(string.format("  #%d: %s (ID: %s) - %d spores", 
                    rank, playerName, tostring(entry.key), entry.value))
            else
                print(string.format("  #%d: Unknown (ID: %s) - %d spores", 
                    rank, tostring(entry.key), entry.value))
            end
        end
    else
        print("❌ Failed to read spores DataStore:", tostring(sporesPages))
    end
    
    -- Test reading gems leaderboard
    local success, gemsPages = pcall(function()
        return gemsLeaderboard:GetSortedAsync(false, 10)
    end)
    
    if success and gemsPages then
        print("✅ Gems DataStore accessible:")
        local currentPage = gemsPages:GetCurrentPage()
        for rank, entry in ipairs(currentPage) do
            local success, playerName = pcall(function()
                return Players:GetNameFromUserIdAsync(entry.key)
            end)
            
            if success then
                print(string.format("  #%d: %s (ID: %s) - %d gems", 
                    rank, playerName, tostring(entry.key), entry.value))
            end
        end
    else
        print("❌ Failed to read gems DataStore:", tostring(gemsPages))
    end
    
    print("=== DATASTORE TEST END ===")
end

-- Run the test
testDataStoreReads()

-- Function to manually add test data (for testing purposes)
local function addTestData()
    local testPlayer = Players.LocalPlayer
    if testPlayer then
        local success = pcall(function()
            sporesLeaderboard:SetAsync(testPlayer.UserId, 50000)
            gemsLeaderboard:SetAsync(testPlayer.UserId, 1000) 
        end)
        
        if success then
            print("✅ Test data added for", testPlayer.Name)
        else
            print("❌ Failed to add test data")
        end
    end
end

-- Uncomment to add test data:
-- addTestData()