-- Test AddRobux Command Script
-- Place this in ServerScriptService to test the addrobux command

local Players = game:GetService("Players")

-- Wait for game to initialize
wait(10)

print("=== TESTING ADDROBUX COMMAND ===")

-- Test with current player
local testPlayer = Players.LocalPlayer or Players:GetPlayers()[1]
if testPlayer then
    print("Testing with player:", testPlayer.Name)
    
    -- Simulate the admin command
    local success = pcall(function()
        -- Get GameCore
        local gameCore = require(game.ServerScriptService.GameCore.Main)
        local dataService = gameCore:GetService("DataService")
        
        if dataService then
            print("✅ DataService found")
            
            -- Test AddRobuxSpent directly
            local result = dataService:AddRobuxSpent(testPlayer, 500)
            print("AddRobuxSpent result:", result)
            
            -- Check current robux spent
            local playerData = dataService:GetPlayerData(testPlayer)
            if playerData then
                print("Current RobuxSpent:", playerData.RobuxSpent or 0)
            else
                print("❌ No player data found")
            end
        else
            print("❌ DataService not found")
        end
    end)
    
    if not success then
        print("❌ Test failed with error")
    end
else
    print("❌ No test player found")
end

print("=== TEST COMPLETE ===")