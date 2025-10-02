-- Test script to debug robux leaderstats issue
print("=== ROBUX LEADERSTATS DEBUG ===")

-- Simulate the issue we're seeing
local function testRobuxFlow()
    print("1. Command adds robux to data")
    local fakePlayerData = {
        RobuxSpent = 0
    }
    
    -- Add robux (simulating AddRobuxSpent)
    fakePlayerData.RobuxSpent = fakePlayerData.RobuxSpent + 100
    print("   Data after adding 100 robux:", fakePlayerData.RobuxSpent)
    
    -- Simulate leaderstats update
    print("2. Updating leaderstats...")
    local fakeLeaderstat = {Value = 0}
    fakeLeaderstat.Value = fakePlayerData.RobuxSpent
    print("   Leaderstat value:", fakeLeaderstat.Value)
    
    -- Simulate a race condition where leaderstats gets reset
    print("3. Something resets the leaderstat...")
    fakeLeaderstat.Value = 0  -- This is what's happening
    print("   Leaderstat value after reset:", fakeLeaderstat.Value)
    
    return fakeLeaderstat.Value
end

local result = testRobuxFlow()
print("Final leaderstat value:", result)
print("Expected: 100, Actual:", result)

-- Analyze the problem areas
print("\n=== PROBLEM ANALYSIS ===")
print("1. PlayerService:_updateLeaderstats() updates from playerData")
print("2. DataService:_updatePlayerLeaderstats() also updates from data")
print("3. Both can be called at similar times")
print("4. PlayerService gets called when PlayerDataLoaded fires")
print("5. DataService gets called after currency operations")

print("\n=== LIKELY CAUSE ===")
print("PlayerService:_updateLeaderstats() is being called AFTER")
print("DataService:AddRobuxSpent() completes, overwriting the robux value")
print("with potentially stale data from GetPlayerData()")