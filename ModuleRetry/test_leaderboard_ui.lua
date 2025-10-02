-- Client-side Leaderboard UI Testing Script
-- Place this in StarterGui or run in client console

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local function testLeaderboardUI()
    print("=== LEADERBOARD UI TEST ===")
    
    -- Check if MoneyLeaderboard exists in workspace
    local moneyLeaderboard = Workspace:FindFirstChild("MoneyLeaderboard")
    if moneyLeaderboard then
        print("✅ MoneyLeaderboard folder found")
        
        local mostMoneyPart = moneyLeaderboard:FindFirstChild("MostMoney")
        if mostMoneyPart then
            print("✅ MostMoney part found")
            
            -- Check for SurfaceGui
            local surfaceGui = mostMoneyPart:FindFirstChild("LeaderboardGui")
            if surfaceGui then
                print("✅ LeaderboardGui found")
                
                local scrollFrame = surfaceGui:FindFirstChild("ScrollFrame")
                if scrollFrame then
                    print("✅ ScrollFrame found")
                    
                    -- Count leaderboard entries
                    local entryCount = 0
                    for _, child in pairs(scrollFrame:GetChildren()) do
                        if child.Name:match("^Entry_") then
                            entryCount = entryCount + 1
                        end
                    end
                    
                    print(string.format("✅ Found %d leaderboard entries", entryCount))
                    
                    if entryCount > 0 then
                        print("✅ Leaderboard has player data")
                    else
                        print("⚠️ No player entries found - leaderboard may be empty")
                    end
                else
                    print("❌ ScrollFrame not found")
                end
            else
                print("❌ LeaderboardGui not found")
            end
            
            -- Check for title
            local titleGui = mostMoneyPart:FindFirstChild("LeaderboardTitle")
            if titleGui then
                print("✅ LeaderboardTitle found")
                
                local sporesTitle = titleGui:FindFirstChild("SporesTitle")
                if sporesTitle and sporesTitle.Text == "SPORES" then
                    print("✅ Spores title correctly set")
                else
                    print("❌ Spores title missing or incorrect")
                end
            else
                print("❌ LeaderboardTitle not found")
            end
        else
            print("❌ MostMoney part not found")
        end
    else
        print("❌ MoneyLeaderboard folder not found in workspace")
    end
    
    print("=== UI TEST END ===")
end

local function testRemoteEvents()
    print("=== REMOTE EVENTS TEST ===")
    
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared then
        print("✅ Shared folder found")
        
        local remoteEvents = shared:FindFirstChild("RemoteEvents")
        if remoteEvents then
            print("✅ RemoteEvents folder found")
            
            local leaderboardEvents = remoteEvents:FindFirstChild("LeaderboardEvents")
            if leaderboardEvents then
                print("✅ LeaderboardEvents folder found")
                
                local dataUpdated = leaderboardEvents:FindFirstChild("LeaderboardDataUpdated")
                local getData = leaderboardEvents:FindFirstChild("GetLeaderboardData")
                
                if dataUpdated then
                    print("✅ LeaderboardDataUpdated RemoteEvent found")
                else
                    print("❌ LeaderboardDataUpdated RemoteEvent missing")
                end
                
                if getData then
                    print("✅ GetLeaderboardData RemoteFunction found")
                    
                    -- Test getting data
                    local success, data = pcall(function()
                        return getData:InvokeServer("spores")
                    end)
                    
                    if success and data then
                        print(string.format("✅ Successfully retrieved leaderboard data (%d players)", #data))
                    else
                        print("❌ Failed to retrieve leaderboard data:", tostring(data))
                    end
                else
                    print("❌ GetLeaderboardData RemoteFunction missing")
                end
            else
                print("❌ LeaderboardEvents folder missing")
            end
        else
            print("❌ RemoteEvents folder missing")
        end
    else
        print("❌ Shared folder missing")
    end
    
    print("=== REMOTE EVENTS TEST END ===")
end

-- Run tests
testLeaderboardUI()
testRemoteEvents()

print("Client leaderboard test completed! Check the output above for results.")