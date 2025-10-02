-- Leaderboard Testing Script
-- Place this in ServerScriptService to test leaderboard functionality

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for services to initialize
wait(5)

-- Test functions
local function testLeaderboardData()
    print("=== LEADERBOARD TEST START ===")
    
    -- Get the LeaderboardService (assuming it's initialized in Main.lua)
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local remoteEvents = shared:WaitForChild("RemoteEvents") 
    local leaderboardEvents = remoteEvents:WaitForChild("LeaderboardEvents")
    local getLeaderboardData = leaderboardEvents:WaitForChild("GetLeaderboardData")
    
    -- Test getting spores leaderboard data
    local success, sporesData = pcall(function()
        return getLeaderboardData:InvokeServer(Players.LocalPlayer, "spores")
    end)
    
    if success then
        print("✅ Spores leaderboard data retrieved:")
        for i, player in ipairs(sporesData) do
            print(string.format("  #%d: %s - %d spores", i, player.Name, player.Amount))
        end
    else
        print("❌ Failed to get spores leaderboard:", sporesData)
    end
    
    -- Test getting gems leaderboard data  
    local success, gemsData = pcall(function()
        return getLeaderboardData:InvokeServer(Players.LocalPlayer, "gems")
    end)
    
    if success then
        print("✅ Gems leaderboard data retrieved:")
        for i, player in ipairs(gemsData) do
            print(string.format("  #%d: %s - %d gems", i, player.Name, player.Amount))
        end
    else
        print("❌ Failed to get gems leaderboard:", gemsData)
    end
    
    print("=== LEADERBOARD TEST END ===")
end

-- Test leaderboard data
testLeaderboardData()

-- Test periodic updates (run every 30 seconds)
spawn(function()
    while true do
        wait(30)
        print("--- Periodic Leaderboard Check ---")
        testLeaderboardData()
    end
end)

print("Leaderboard test script loaded! Check output for results.")