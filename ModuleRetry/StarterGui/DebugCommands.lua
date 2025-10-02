-- Debug Commands Module
-- Can be accessed from console with: require(game.StarterGui.DebugCommands)

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local DebugCommands = {}

function DebugCommands.CheckHighlights()
    print("[DEBUG] Checking mushroom highlights...")
    
    -- First check the new hover service
    local clientMain = game.StarterGui:FindFirstChild("ClientCore")
    if clientMain then
        local clientMainScript = clientMain:FindFirstChild("ClientMain")
        if clientMainScript then
            local success, clientCore = pcall(function()
                return require(clientMainScript)
            end)
            
            if success then
                local hoverService = clientCore:GetService("MushroomHoverService")
                if hoverService and hoverService.GetStatus then
                    local status = hoverService:GetStatus()
                    print(string.format("[DEBUG] NEW HOVER SERVICE: %d tracked, current: %s, initialized: %s", 
                        status.trackedMushrooms, status.currentHovered, tostring(status.isInitialized)))
                end
            end
        end
    end
    
    -- Direct approach - check highlights in workspace
    local playerPlots = workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then
        print("[DEBUG] No PlayerPlots found")
        return
    end
    
    local totalMushrooms = 0
    local mushroomsWithHighlights = 0
    local totalHighlights = 0
    local newHighlights = 0 -- Count new "HoverHighlight" style
    local oldHighlights = 0 -- Count old "MushroomHighlight" style
    
    for _, plot in pairs(playerPlots:GetChildren()) do
        if plot.Name:match("^Plot_") then
            local mushroomsFolder = plot:FindFirstChild("Mushrooms")
            if mushroomsFolder then
                for _, mushroom in pairs(mushroomsFolder:GetChildren()) do
                    if mushroom:IsA("Model") and mushroom.Name:match("MushroomModel_") then
                        totalMushrooms = totalMushrooms + 1
                        
                        -- Count highlights
                        local highlights = 0
                        for _, part in pairs(mushroom:GetDescendants()) do
                            if part:IsA("Highlight") then
                                if part.Name == "HoverHighlight" then
                                    highlights = highlights + 1
                                    totalHighlights = totalHighlights + 1
                                    newHighlights = newHighlights + 1
                                    print(string.format("[DEBUG] %s - NEW Highlight on %s: OutlineTransparency=%.1f, FillTransparency=%.1f", 
                                        mushroom.Name, part.Parent.Name, part.OutlineTransparency, part.FillTransparency))
                                elseif part.Name == "MushroomHighlight" then
                                    highlights = highlights + 1
                                    totalHighlights = totalHighlights + 1
                                    oldHighlights = oldHighlights + 1
                                    print(string.format("[DEBUG] %s - OLD Highlight on %s: OutlineTransparency=%.1f, FillTransparency=%.1f", 
                                        mushroom.Name, part.Parent.Name, part.OutlineTransparency, part.FillTransparency))
                                end
                            end
                        end
                        
                        if highlights > 0 then
                            mushroomsWithHighlights = mushroomsWithHighlights + 1
                        else
                            print(string.format("[DEBUG] %s - NO HIGHLIGHTS FOUND", mushroom.Name))
                        end
                    end
                end
            end
        end
    end
    
    print(string.format("[DEBUG] SUMMARY: %d mushrooms, %d with highlights (%d new, %d old), %d total highlights", 
        totalMushrooms, mushroomsWithHighlights, newHighlights, oldHighlights, totalHighlights))
end

function DebugCommands.RescanMushrooms()
    print("[DEBUG] Rescanning mushrooms...")
    
    -- Try to find the ClientCore services
    local clientMain = game.StarterGui:FindFirstChild("ClientCore")
    if not clientMain then
        print("[DEBUG] ERROR: ClientCore not found")
        return
    end
    
    local clientMainScript = clientMain:FindFirstChild("ClientMain")
    if not clientMainScript then
        print("[DEBUG] ERROR: ClientMain script not found")
        return
    end
    
    -- Access the services through require
    local success, clientCore = pcall(function()
        return require(clientMainScript)
    end)
    
    if not success then
        print("[DEBUG] ERROR: Could not require ClientMain:", clientCore)
        return
    end
    
    -- Try new hover service first
    local hoverService = clientCore:GetService("MushroomHoverService")
    if hoverService and hoverService.ForceRescan then
        print("[DEBUG] Using new MushroomHoverService...")
        local result = hoverService:ForceRescan()
        print(string.format("[DEBUG] Rescan result: %d -> %d mushrooms (+%d)", result.before, result.after, result.found))
        return
    end
    
    -- Fallback to old service
    local mushroomService = clientCore:GetService("MushroomInteractionService")
    if mushroomService and mushroomService.ForceRescanMushrooms then
        print("[DEBUG] Using old MushroomInteractionService...")
        mushroomService:ForceRescanMushrooms()
    else
        print("[DEBUG] ERROR: No mushroom services available")
    end
end

function DebugCommands.FixCanCollide()
    print("[DEBUG] Fixing CanCollide on ALL mushroom parts...")
    
    local playerPlots = workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then
        print("[DEBUG] No PlayerPlots found")
        return
    end
    
    local fixedParts = 0
    local fixedMushrooms = 0
    
    for _, plot in pairs(playerPlots:GetChildren()) do
        if plot.Name:match("^Plot_") then
            local mushroomsFolder = plot:FindFirstChild("Mushrooms")
            if mushroomsFolder then
                for _, mushroom in pairs(mushroomsFolder:GetChildren()) do
                    if mushroom:IsA("Model") and mushroom.Name:match("MushroomModel_") then
                        fixedMushrooms = fixedMushrooms + 1
                        for _, part in pairs(mushroom:GetDescendants()) do
                            if part:IsA("BasePart") then
                                part.CanCollide = true
                                fixedParts = fixedParts + 1
                            end
                        end
                        print(string.format("[DEBUG] Fixed CanCollide for %s", mushroom.Name))
                    end
                end
            end
        end
    end
    
    print(string.format("[DEBUG] Fixed CanCollide on %d parts across %d mushrooms", fixedParts, fixedMushrooms))
    print("[DEBUG] Try hovering over mushrooms now!")
end

function DebugCommands.CheckCanCollide()
    print("[DEBUG] Checking CanCollide on mushroom parts...")
    
    local playerPlots = workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then
        print("[DEBUG] No PlayerPlots found")
        return
    end
    
    local canCollideFalse = {}
    local canCollideTrue = {}
    
    for _, plot in pairs(playerPlots:GetChildren()) do
        if plot.Name:match("^Plot_") then
            local mushroomsFolder = plot:FindFirstChild("Mushrooms")
            if mushroomsFolder then
                for _, mushroom in pairs(mushroomsFolder:GetChildren()) do
                    if mushroom:IsA("Model") and mushroom.Name:match("MushroomModel_") then
                        local hasCanCollide = false
                        for _, part in pairs(mushroom:GetDescendants()) do
                            if part:IsA("BasePart") then
                                if part.CanCollide then
                                    hasCanCollide = true
                                    break
                                end
                            end
                        end
                        
                        if hasCanCollide then
                            table.insert(canCollideTrue, mushroom.Name)
                        else
                            table.insert(canCollideFalse, mushroom.Name)
                        end
                    end
                end
            end
        end
    end
    
    print(string.format("[DEBUG] Mushrooms with CanCollide=true parts (%d): %s", 
        #canCollideTrue, table.concat(canCollideTrue, ", ")))
    print(string.format("[DEBUG] Mushrooms with NO CanCollide=true parts (%d): %s", 
        #canCollideFalse, table.concat(canCollideFalse, ", ")))
end

function DebugCommands.TestHighlightVisibility()
    print("[DEBUG] Testing highlight visibility...")
    
    -- Direct approach - check highlights in workspace and manually make them visible
    local playerPlots = workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then
        print("[DEBUG] No PlayerPlots found")
        return
    end
    
    local testedHighlights = 0
    local visibleHighlights = 0
    local mushroomsWithoutHighlights = {}
    local highlightsWorking = {}
    local highlightsBroken = {}
    
    for _, plot in pairs(playerPlots:GetChildren()) do
        if plot.Name:match("^Plot_") then
            local mushroomsFolder = plot:FindFirstChild("Mushrooms")
            if mushroomsFolder then
                for _, mushroom in pairs(mushroomsFolder:GetChildren()) do
                    if mushroom:IsA("Model") and mushroom.Name:match("MushroomModel_") then
                        local foundHighlights = false
                        
                        -- Find and manually activate highlights
                        for _, part in pairs(mushroom:GetDescendants()) do
                            if part:IsA("Highlight") and part.Name == "MushroomHighlight" then
                                foundHighlights = true
                                testedHighlights = testedHighlights + 1
                                
                                -- Force highlight to be visible
                                part.OutlineTransparency = 0
                                part.FillTransparency = 0.7
                                part.OutlineColor = Color3.fromRGB(255, 0, 0) -- Red for testing
                                part.FillColor = Color3.fromRGB(255, 0, 0)
                                
                                visibleHighlights = visibleHighlights + 1
                                table.insert(highlightsWorking, mushroom.Name .. " on " .. part.Parent.Name)
                                
                                -- Test if it becomes invisible again
                                wait(0.1)
                                if part.OutlineTransparency ~= 0 or part.FillTransparency ~= 0.7 then
                                    table.insert(highlightsBroken, string.format("%s (reverted to %.1f/%.1f)", 
                                        mushroom.Name, part.OutlineTransparency, part.FillTransparency))
                                end
                            end
                        end
                        
                        if not foundHighlights then
                            table.insert(mushroomsWithoutHighlights, mushroom.Name)
                        end
                    end
                end
            end
        end
    end
    
    print(string.format("[DEBUG] RESULTS: %d total highlights tested, %d forced visible", testedHighlights, visibleHighlights))
    
    if #mushroomsWithoutHighlights > 0 then
        print(string.format("[DEBUG] MUSHROOMS WITHOUT HIGHLIGHTS (%d): %s", 
            #mushroomsWithoutHighlights, table.concat(mushroomsWithoutHighlights, ", ")))
    end
    
    if #highlightsBroken > 0 then
        print(string.format("[DEBUG] HIGHLIGHTS THAT REVERTED (%d): %s", 
            #highlightsBroken, table.concat(highlightsBroken, ", ")))
    end
    
    print(string.format("[DEBUG] WORKING HIGHLIGHTS (%d): %s", 
        #highlightsWorking, table.concat(highlightsWorking, ", ")))
end

function DebugCommands.CheckMouseHover()
    print("[DEBUG] Checking mushroom hover detection...")
    
    -- Get the services
    local clientMain = game.StarterGui:FindFirstChild("ClientCore")
    if not clientMain then
        print("[DEBUG] ERROR: ClientCore not found")
        return
    end
    
    local clientMainScript = clientMain:FindFirstChild("ClientMain")
    if not clientMainScript then
        print("[DEBUG] ERROR: ClientMain script not found")
        return
    end
    
    local success, clientCore = pcall(function()
        return require(clientMainScript)
    end)
    
    if not success then
        print("[DEBUG] ERROR: Could not require ClientMain:", clientCore)
        return
    end
    
    local hoverService = clientCore:GetService("MushroomHoverService")
    if not hoverService then
        print("[DEBUG] ERROR: MushroomHoverService not available")
        return
    end
    
    -- Test real-time hover detection
    print("[DEBUG] STARTING REAL-TIME HOVER TEST - Move your mouse over mushrooms...")
    print("[DEBUG] This will run for 10 seconds...")
    
    local startTime = tick()
    local lastHovered = nil
    local hoverCount = 0
    
    local connection
    connection = game:GetService("RunService").Heartbeat:Connect(function()
        if tick() - startTime > 10 then
            connection:Disconnect()
            print(string.format("[DEBUG] HOVER TEST COMPLETE - Detected %d hover changes", hoverCount))
            return
        end
        
        local currentHovered = hoverService:GetHoveredMushroom()
        if currentHovered ~= lastHovered then
            if currentHovered then
                print(string.format("[DEBUG] HOVER DETECTED: %s", currentHovered.Name))
                hoverCount = hoverCount + 1
            elseif lastHovered then
                print(string.format("[DEBUG] HOVER ENDED: %s", lastHovered.Name))
            end
            lastHovered = currentHovered
        end
    end)
end

function DebugCommands.TestSingleMushroom()
    print("[DEBUG] Testing single mushroom hover...")
    
    local mouse = game.Players.LocalPlayer:GetMouse()
    local camera = workspace.CurrentCamera
    
    if not mouse or not camera then
        print("[DEBUG] ERROR: Mouse or camera not found")
        return
    end
    
    -- Do a raycast at current mouse position
    local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local raycastParams = RaycastParams.new()
    local raycastResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)
    
    if raycastResult then
        local hitPart = raycastResult.Instance
        print(string.format("[DEBUG] Mouse hit: %s (Parent: %s)", hitPart.Name, hitPart.Parent.Name))
        
        -- Check if it's part of a mushroom
        local current = hitPart
        while current do
            if current:IsA("Model") and current.Name:match("MushroomModel_") then
                print(string.format("[DEBUG] ✓ Found mushroom: %s", current.Name))
                
                -- Check if it has highlights
                local highlights = 0
                for _, descendant in pairs(current:GetDescendants()) do
                    if descendant:IsA("Highlight") and descendant.Name == "HoverHighlight" then
                        highlights = highlights + 1
                        print(string.format("[DEBUG] Highlight: %s, Outline: %.1f, Fill: %.1f", 
                            descendant.Name, descendant.OutlineTransparency, descendant.FillTransparency))
                    end
                end
                
                if highlights == 0 then
                    print("[DEBUG] ✗ NO HIGHLIGHTS FOUND")
                end
                
                return
            end
            current = current.Parent
        end
        
        print("[DEBUG] ✗ Hit part is not part of a mushroom")
    else
        print("[DEBUG] No raycast hit")
    end
end

-- Quick access functions
DebugCommands.check = DebugCommands.CheckHighlights
DebugCommands.rescan = DebugCommands.RescanMushrooms
DebugCommands.test = DebugCommands.TestHighlightVisibility
DebugCommands.hover = DebugCommands.CheckMouseHover
DebugCommands.collide = DebugCommands.CheckCanCollide
DebugCommands.fix = DebugCommands.FixCanCollide
DebugCommands.single = DebugCommands.TestSingleMushroom

return DebugCommands