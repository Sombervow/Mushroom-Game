local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(game.ReplicatedStorage.Shared.Modules.ClientLogger)
local HeartbeatManager = require(game.ReplicatedStorage.Shared.Modules.HeartbeatManager)

local MushroomHoverService = {}
MushroomHoverService.__index = MushroomHoverService

local player = Players.LocalPlayer

-- Clean, simple configuration
local CONFIG = {
    HOVER_FILL_TRANSPARENCY = 0.7,
    HOVER_OUTLINE_TRANSPARENCY = 0,
    HIDDEN_TRANSPARENCY = 1,
    ANIMATION_TIME = 0.15,
    HIGHLIGHT_COLOR = Color3.fromRGB(255, 255, 255),
    OUTLINE_COLOR = Color3.fromRGB(255, 255, 255),
    SCAN_INTERVAL = 1, -- Scan every 1 second instead of every frame
    INITIAL_SCAN_DELAY = 3 -- Wait 3 seconds before starting
}

function MushroomHoverService.new()
    local self = setmetatable({}, MushroomHoverService)
    
    -- Core state
    self._mushrooms = {} -- mushroom -> {highlight, isHovered}
    self._currentHovered = nil
    self._connections = {}
    self._isInitialized = false
    self._isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    
    Logger:Info("[MushroomHover] Creating new MushroomHoverService")
    
    self:_initialize()
    return self
end

function MushroomHoverService:_initialize()
    Logger:Info("[MushroomHover] Initializing hover service...")
    
    -- FIXED: Better timing coordination with server
    spawn(function()
        -- Wait for player to have a plot assigned
        local playerPlots = workspace:WaitForChild("PlayerPlots", 30)
        if not playerPlots then
            Logger:Error("[MushroomHover] PlayerPlots folder not found!")
            return
        end
        
        local playerPlot = nil
        local waitTime = 0
        while not playerPlot and waitTime < 30 do
            playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
            if not playerPlot then
                wait(1)
                waitTime = waitTime + 1
            end
        end
        
        if not playerPlot then
            Logger:Error("[MushroomHover] Player plot not found after 30 seconds!")
            return
        end
        
        Logger:Info(string.format("[MushroomHover] Found player plot: %s", playerPlot.Name))
        
        -- Additional wait for mushrooms to be spawned by server
        wait(CONFIG.INITIAL_SCAN_DELAY)
        
        self:_startMushroomScanning()
        self:_setupMouseTracking()
        self._isInitialized = true
        Logger:Info("[MushroomHover] ✓ Hover service fully initialized")
    end)
end

function MushroomHoverService:_startMushroomScanning()
    Logger:Info("[MushroomHover] Starting mushroom scanning...")
    
    -- Initial scan
    self:_scanForMushrooms()
    
    -- Periodic scanning using HeartbeatManager with 1 second interval
    self._connections.PeriodicScan = HeartbeatManager.getInstance():register(function()
        self:_scanForMushrooms()
    end, CONFIG.SCAN_INTERVAL)
    
    Logger:Info("[MushroomHover] Mushroom scanning started")
end

function MushroomHoverService:_scanForMushrooms()
    local playerPlots = workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then return end
    
    local newMushrooms = 0
    local totalFound = 0
    
    -- Scan all plots for mushroom models
    for _, plot in pairs(playerPlots:GetChildren()) do
        if plot.Name:match("^Plot_") then
            self:_scanPlotForMushrooms(plot, function() 
                newMushrooms = newMushrooms + 1 
            end, function() 
                totalFound = totalFound + 1 
            end)
        end
    end
    
    -- Removed spam logging
end

function MushroomHoverService:_scanPlotForMushrooms(plot, onNewMushroom, onFoundMushroom)
    -- Scan Area1
    local mushroomsFolder = plot:FindFirstChild("Mushrooms")
    if mushroomsFolder then
        for _, item in pairs(mushroomsFolder:GetChildren()) do
            if self:_isMushroomModel(item) then
                onFoundMushroom()
                if not self._mushrooms[item] then
                    self:_addMushroom(item)
                    onNewMushroom()
                end
            end
        end
    end
    
    -- Scan Area2 if it exists
    local area2 = plot:FindFirstChild("Area2")
    if area2 then
        local area2MushroomsFolder = area2:FindFirstChild("Mushrooms")
        if area2MushroomsFolder then
            for _, item in pairs(area2MushroomsFolder:GetChildren()) do
                if self:_isMushroomModel(item) then
                    onFoundMushroom()
                    if not self._mushrooms[item] then
                        self:_addMushroom(item)
                        onNewMushroom()
                    end
                end
            end
        end
    end
end

function MushroomHoverService:_isMushroomModel(item)
    return item:IsA("Model") and 
           item.Name:match("MushroomModel_") and 
           item.Parent and 
           #item:GetChildren() > 0
end

function MushroomHoverService:_addMushroom(mushroom)
    -- FIXED: Don't attempt to add same mushroom twice
    if self._mushrooms[mushroom] then
        return
    end
    
    -- FIXED: Validate mushroom is fully loaded before adding
    local validParts = 0
    for _, child in pairs(mushroom:GetChildren()) do
        if child:IsA("BasePart") then
            validParts = validParts + 1
        end
    end
    
    if validParts == 0 then
        -- Try again in 1 second
        spawn(function()
            wait(1)
            if mushroom.Parent then
                self:_addMushroom(mushroom)
            end
        end)
        return
    end
    
    -- Create highlight for the mushroom
    local highlight = self:_createHighlight(mushroom)
    if not highlight then
        return
    end
    
    -- Store mushroom data
    self._mushrooms[mushroom] = {
        highlight = highlight,
        isHovered = false,
        currentTween = nil -- Track current animation
    }
    
    -- Clean up when mushroom is removed
    local cleanupConnection
    cleanupConnection = mushroom.AncestryChanged:Connect(function()
        if not mushroom.Parent then
            self:_removeMushroom(mushroom)
            cleanupConnection:Disconnect()
        end
    end)
    
    -- Added mushroom successfully
end

function MushroomHoverService:_createHighlight(mushroom)
    -- FIXED: Ensure mushroom model is fully loaded before highlighting
    if not mushroom or not mushroom.Parent or #mushroom:GetChildren() == 0 then
        return nil
    end
    
    -- Wait a frame to ensure all parts are fully initialized
    wait(0.1)
    
    -- FIXED: More robust part detection with validation
    local targetPart = nil
    
    -- Try PrimaryPart first
    if mushroom.PrimaryPart and mushroom.PrimaryPart.Parent == mushroom then
        targetPart = mushroom.PrimaryPart
    else
        -- Try common part names for different mushroom models
        local partNames = {"Stem", "Base", "Body", "Part", "Main", "Root"}
        for _, partName in pairs(partNames) do
            local part = mushroom:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                targetPart = part
                break
            end
        end
        
        -- Last resort: any BasePart
        if not targetPart then
            for _, child in pairs(mushroom:GetChildren()) do
                if child:IsA("BasePart") and child.Parent == mushroom then
                    targetPart = child
                    break
                end
            end
        end
    end
    
    if not targetPart then
        return nil
    end
    
    local success, highlight = pcall(function()
        local h = Instance.new("Highlight")
        h.Name = "HoverHighlight"
        -- FIXED: Highlight the entire model consistently
        h.Adornee = mushroom
        h.FillColor = CONFIG.HIGHLIGHT_COLOR
        h.OutlineColor = CONFIG.OUTLINE_COLOR
        h.FillTransparency = CONFIG.HIDDEN_TRANSPARENCY
        h.OutlineTransparency = CONFIG.HIDDEN_TRANSPARENCY
        -- FIXED: Parent to workspace for more reliable rendering
        h.Parent = workspace
        return h
    end)
    
    if success and highlight then
        return highlight
    else
        return nil
    end
end

function MushroomHoverService:_removeMushroom(mushroom)
    local data = self._mushrooms[mushroom]
    if not data then return end
    
    -- Clear hover state
    if self._currentHovered == mushroom then
        self._currentHovered = nil
    end
    
    -- FIXED: Cancel any running animation
    if data.currentTween then
        data.currentTween:Cancel()
        data.currentTween = nil
    end
    
    -- Clean up highlight
    if data.highlight then
        data.highlight:Destroy()
    end
    
    self._mushrooms[mushroom] = nil
end

function MushroomHoverService:_setupMouseTracking()
    if self._isMobile then
        Logger:Info("[MushroomHover] Mobile device detected - hover disabled")
        return
    end
    
    Logger:Info("[MushroomHover] Setting up mouse tracking...")
    
    -- Track mouse movement with reduced frequency (10 FPS instead of 60)
    self._connections.MouseMove = HeartbeatManager.getInstance():register(function()
        self:_updateMouseHover()
    end, 0.1)
    
    Logger:Info("[MushroomHover] ✓ Mouse tracking active")
end

function MushroomHoverService:_updateMouseHover()
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local mouse = player:GetMouse()
    if not mouse then return end
    
    -- FIXED: Multiple raycast approach to catch more mushrooms
    local hoveredMushroom = nil
    
    -- Method 1: Standard screen-to-world raycast
    local success, unitRay = pcall(function()
        return camera:ScreenPointToRay(mouse.X, mouse.Y)
    end)
    
    if success then
        local raycastParams = RaycastParams.new()
        -- FIXED: Allow hitting non-collidable parts (mushrooms have CanCollide = false)
        raycastParams.IgnoreWater = true
        
        local raycastResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)
        
        if raycastResult then
            local hitPart = raycastResult.Instance
            
            -- Check if hit part belongs to any tracked mushroom
            for mushroom, _ in pairs(self._mushrooms) do
                if hitPart:IsDescendantOf(mushroom) then
                    hoveredMushroom = mushroom
                    break
                end
            end
        end
    end
    
    -- Method 2: If raycast failed, try mouse.Target fallback
    if not hoveredMushroom and mouse.Target then
        local target = mouse.Target
        
        -- Check if target belongs to any tracked mushroom
        for mushroom, _ in pairs(self._mushrooms) do
            if target:IsDescendantOf(mushroom) then
                hoveredMushroom = mushroom
                break
            end
        end
    end
    
    -- Method 3: If both failed, try proximity-based detection for very close mushrooms
    if not hoveredMushroom and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        local playerPosition = player.Character.HumanoidRootPart.Position
        local mouseWorldPos = mouse.Hit.Position
        
        -- Find closest mushroom to mouse world position within reasonable range
        local closestMushroom = nil
        local closestDistance = math.huge
        
        for mushroom, _ in pairs(self._mushrooms) do
            local mushroomPos = mushroom.PrimaryPart and mushroom.PrimaryPart.Position or 
                               (mushroom:FindFirstChildOfClass("BasePart") and mushroom:FindFirstChildOfClass("BasePart").Position)
            
            if mushroomPos then
                local distanceToMouse = (mouseWorldPos - mushroomPos).Magnitude
                local distanceToPlayer = (playerPosition - mushroomPos).Magnitude
                
                -- Only consider mushrooms that are close to mouse and within interaction range
                if distanceToMouse < 5 and distanceToPlayer < 30 and distanceToMouse < closestDistance then
                    closestDistance = distanceToMouse
                    closestMushroom = mushroom
                end
            end
        end
        
        if closestMushroom then
            hoveredMushroom = closestMushroom
        end
    end
    
    -- Update hover state if changed
    if hoveredMushroom ~= self._currentHovered then
        self:_setHoveredMushroom(hoveredMushroom)
    end
end

function MushroomHoverService:_setHoveredMushroom(mushroom)
    -- Clear previous hover
    if self._currentHovered then
        self:_setMushroomHoverState(self._currentHovered, false)
    end
    
    -- Set new hover
    self._currentHovered = mushroom
    if mushroom then
        self:_setMushroomHoverState(mushroom, true)
    end
end

function MushroomHoverService:_setMushroomHoverState(mushroom, isHovered)
    local data = self._mushrooms[mushroom]
    if not data then 
        return 
    end
    
    if data.isHovered == isHovered then 
        return 
    end -- No change needed
    
    data.isHovered = isHovered
    
    -- FIXED: Cancel any existing animation to prevent state corruption
    if data.currentTween then
        data.currentTween:Cancel()
        data.currentTween:Destroy()
        data.currentTween = nil
    end
    
    local targetFillTransparency = isHovered and CONFIG.HOVER_FILL_TRANSPARENCY or CONFIG.HIDDEN_TRANSPARENCY
    local targetOutlineTransparency = isHovered and CONFIG.HOVER_OUTLINE_TRANSPARENCY or CONFIG.HIDDEN_TRANSPARENCY
    
    -- Animate the highlight
    if data.highlight and data.highlight.Parent then
        -- FIXED: Ensure highlight is valid before animating
        if not data.highlight.Adornee or data.highlight.Adornee ~= mushroom then
            -- Recreate the highlight
            local newHighlight = self:_createHighlight(mushroom)
            if newHighlight then
                data.highlight:Destroy()
                data.highlight = newHighlight
            else
                return
            end
        end
        
        local tween = TweenService:Create(
            data.highlight,
            TweenInfo.new(CONFIG.ANIMATION_TIME, Enum.EasingStyle.Quad),
            {
                FillTransparency = targetFillTransparency,
                OutlineTransparency = targetOutlineTransparency
            }
        )
        
        -- Store the tween reference
        data.currentTween = tween
        
        -- Clean up tween reference when complete
        tween.Completed:Connect(function()
            if data.currentTween == tween then
                data.currentTween = nil
            end
            tween:Destroy()
        end)
        
        tween:Play()
    end
end

-- Public methods
function MushroomHoverService:GetHoveredMushroom()
    return self._currentHovered
end

function MushroomHoverService:IsMushroomHovered(mushroom)
    local data = self._mushrooms[mushroom]
    return data and data.isHovered or false
end

function MushroomHoverService:GetTrackedMushrooms()
    local mushrooms = {}
    for mushroom, _ in pairs(self._mushrooms) do
        table.insert(mushrooms, mushroom)
    end
    return mushrooms
end

function MushroomHoverService:_getMushroomCount()
    local count = 0
    for _ in pairs(self._mushrooms) do
        count = count + 1
    end
    return count
end

function MushroomHoverService:GetStatus()
    return {
        isInitialized = self._isInitialized,
        trackedMushrooms = self:_getMushroomCount(),
        currentHovered = self._currentHovered and self._currentHovered.Name or "none",
        isMobile = self._isMobile
    }
end

-- Force rescan method for debugging
function MushroomHoverService:ForceRescan()
    Logger:Info("[MushroomHover] === FORCE RESCAN INITIATED ===")
    
    local beforeCount = self:_getMushroomCount()
    self:_scanForMushrooms()
    local afterCount = self:_getMushroomCount()
    
    Logger:Info(string.format("[MushroomHover] Rescan complete: %d -> %d mushrooms", beforeCount, afterCount))
    
    return {
        before = beforeCount,
        after = afterCount,
        found = afterCount - beforeCount
    }
end

function MushroomHoverService:Cleanup()
    Logger:Info("[MushroomHover] Cleaning up...")
    
    -- Disconnect all connections
    for name, connection in pairs(self._connections) do
        if connection then
            if name == "PeriodicScan" or name == "MouseMove" then
                HeartbeatManager.getInstance():unregister(connection)
            else
                connection:Disconnect()
            end
        end
    end
    self._connections = {}
    
    -- Clean up all mushrooms
    for mushroom, data in pairs(self._mushrooms) do
        if data.highlight then
            data.highlight:Destroy()
        end
    end
    self._mushrooms = {}
    
    self._currentHovered = nil
    self._isInitialized = false
    
    Logger:Info("[MushroomHover] ✓ Cleanup complete")
end

return MushroomHoverService