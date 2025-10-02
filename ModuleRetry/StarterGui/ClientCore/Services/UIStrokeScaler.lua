local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local UIStrokeScaler = {}
UIStrokeScaler.__index = UIStrokeScaler

-- Base thickness values for different screen types
local BASE_THICKNESS_VALUES = {
    -- Common stroke thicknesses used in the game
    [1] = 1,
    [2] = 2,
    [3] = 3,
    [4] = 4,
    [5] = 5,
    [6] = 6,
    [8] = 8,
    [10] = 10,
}

-- Reference resolution for scaling calculations
local REFERENCE_RESOLUTION = Vector2.new(1920, 1080)

function UIStrokeScaler.new()
    local self = setmetatable({}, UIStrokeScaler)
    
    self.player = Players.LocalPlayer
    self.playerGui = self.player:WaitForChild("PlayerGui")
    
    -- Track all UIStrokes and their original thickness values
    self.trackedStrokes = {}
    self.connections = {}
    
    -- Current scale factor
    self.currentScaleFactor = 1
    
    self:_initialize()
    return self
end

function UIStrokeScaler:_initialize()
    Logger:Info("UIStrokeScaler initializing...")
    
    -- Calculate initial scale factor
    self:_updateScaleFactor()
    
    -- Find and scale all existing UIStrokes
    self:_findAndScaleAllStrokes()
    
    -- Set up listeners for new UIStrokes
    self:_setupStrokeListeners()
    
    -- Listen for screen size changes
    self:_setupScreenSizeListener()
    
    Logger:Info("✓ UIStrokeScaler initialized with scale factor: " .. tostring(self.currentScaleFactor))
end

function UIStrokeScaler:_updateScaleFactor()
    -- Get current screen resolution
    local viewport = workspace.CurrentCamera.ViewportSize
    
    -- Calculate scale factor based on the smallest dimension to maintain aspect ratio
    local widthScale = viewport.X / REFERENCE_RESOLUTION.X
    local heightScale = viewport.Y / REFERENCE_RESOLUTION.Y
    
    -- Use the smaller scale to prevent oversized strokes on wide screens
    self.currentScaleFactor = math.min(widthScale, heightScale)
    
    -- Clamp the scale factor to reasonable bounds
    self.currentScaleFactor = math.max(0.5, math.min(self.currentScaleFactor, 2.0))
    
    Logger:Debug(string.format("Updated scale factor to %.3f (viewport: %.0fx%.0f)", 
        self.currentScaleFactor, viewport.X, viewport.Y))
end

function UIStrokeScaler:_findAndScaleAllStrokes()
    -- Recursively find all UIStrokes in PlayerGui
    local function findStrokesRecursive(parent)
        for _, child in pairs(parent:GetChildren()) do
            if child:IsA("UIStroke") then
                self:_trackAndScaleStroke(child)
            end
            
            -- Continue searching in children
            if child:IsA("GuiObject") or child:IsA("ScreenGui") then
                findStrokesRecursive(child)
            end
        end
    end
    
    findStrokesRecursive(self.playerGui)
    
    Logger:Info(string.format("Found and scaled %d UIStrokes", #self.trackedStrokes))
end

function UIStrokeScaler:_trackAndScaleStroke(stroke)
    -- Don't track the same stroke twice
    for _, trackedStroke in pairs(self.trackedStrokes) do
        if trackedStroke.stroke == stroke then
            return
        end
    end
    
    -- Store original thickness if not already stored
    local originalThickness = stroke:GetAttribute("OriginalThickness")
    if not originalThickness then
        originalThickness = stroke.Thickness
        stroke:SetAttribute("OriginalThickness", originalThickness)
    end
    
    -- Track this stroke
    local strokeData = {
        stroke = stroke,
        originalThickness = originalThickness
    }
    table.insert(self.trackedStrokes, strokeData)
    
    -- Apply scaling
    self:_scaleStroke(strokeData)
    
    Logger:Debug(string.format("Tracking UIStroke with original thickness %.1f -> scaled %.1f", 
        originalThickness, stroke.Thickness))
end

function UIStrokeScaler:_scaleStroke(strokeData)
    local scaledThickness = strokeData.originalThickness * self.currentScaleFactor
    
    -- Round to prevent fractional pixels
    scaledThickness = math.max(1, math.round(scaledThickness))
    
    strokeData.stroke.Thickness = scaledThickness
end

function UIStrokeScaler:_setupStrokeListeners()
    -- Listen for new ScreenGuis being added
    local screenGuiConnection = self.playerGui.ChildAdded:Connect(function(child)
        if child:IsA("ScreenGui") then
            self:_setupGuiListener(child)
        end
    end)
    table.insert(self.connections, screenGuiConnection)
    
    -- Set up listeners for existing ScreenGuis
    for _, child in pairs(self.playerGui:GetChildren()) do
        if child:IsA("ScreenGui") then
            self:_setupGuiListener(child)
        end
    end
end

function UIStrokeScaler:_setupGuiListener(gui)
    -- Listen for descendants being added to this GUI
    local descendantConnection = gui.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("UIStroke") then
            self:_trackAndScaleStroke(descendant)
        end
    end)
    table.insert(self.connections, descendantConnection)
    
    -- Listen for descendants being removed (cleanup)
    local descendantRemovedConnection = gui.DescendantRemoving:Connect(function(descendant)
        if descendant:IsA("UIStroke") then
            self:_untrackStroke(descendant)
        end
    end)
    table.insert(self.connections, descendantRemovedConnection)
end

function UIStrokeScaler:_untrackStroke(stroke)
    for i, strokeData in ipairs(self.trackedStrokes) do
        if strokeData.stroke == stroke then
            table.remove(self.trackedStrokes, i)
            Logger:Debug("Untracked removed UIStroke")
            break
        end
    end
end

function UIStrokeScaler:_setupScreenSizeListener()
    -- Listen for viewport changes
    local camera = workspace.CurrentCamera
    local viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        self:_onScreenSizeChanged()
    end)
    table.insert(self.connections, viewportConnection)
end

function UIStrokeScaler:_onScreenSizeChanged()
    local oldScaleFactor = self.currentScaleFactor
    self:_updateScaleFactor()
    
    -- Only rescale if the scale factor actually changed significantly
    if math.abs(self.currentScaleFactor - oldScaleFactor) > 0.01 then
        self:_rescaleAllStrokes()
        Logger:Info(string.format("Screen size changed - rescaled %d UIStrokes (factor: %.3f -> %.3f)", 
            #self.trackedStrokes, oldScaleFactor, self.currentScaleFactor))
    end
end

function UIStrokeScaler:_rescaleAllStrokes()
    -- Clean up any destroyed strokes first
    local activeStrokes = {}
    for _, strokeData in pairs(self.trackedStrokes) do
        if strokeData.stroke and strokeData.stroke.Parent then
            table.insert(activeStrokes, strokeData)
            self:_scaleStroke(strokeData)
        end
    end
    self.trackedStrokes = activeStrokes
end

-- Public method to manually scale a specific stroke
function UIStrokeScaler:ScaleStroke(stroke)
    if not stroke or not stroke:IsA("UIStroke") then
        Logger:Warn("Invalid UIStroke provided to ScaleStroke")
        return
    end
    
    self:_trackAndScaleStroke(stroke)
end

-- Public method to get current scale factor
function UIStrokeScaler:GetScaleFactor()
    return self.currentScaleFactor
end

-- Public method to force rescale all strokes
function UIStrokeScaler:ForceRescale()
    self:_updateScaleFactor()
    self:_rescaleAllStrokes()
    Logger:Info("Force rescaled all UIStrokes")
end

function UIStrokeScaler:Cleanup()
    Logger:Info("UIStrokeScaler shutting down...")
    
    -- Disconnect all connections
    for _, connection in pairs(self.connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    -- Clear tracked strokes
    self.trackedStrokes = {}
    self.connections = {}
    
    Logger:Info("✓ UIStrokeScaler cleanup complete")
end

return UIStrokeScaler