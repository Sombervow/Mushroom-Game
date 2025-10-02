local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local ButtonManager = {}
ButtonManager.__index = ButtonManager

-- Sound IDs
local HOVER_SOUND_ID = "rbxassetid://105835466453392"
local CLICK_SOUND_ID = "rbxassetid://137022660612321"

-- Animation settings
local HOVER_SCALE = 1.05
local CLICK_SCALE = 0.95
local HOVER_DURATION = 0.15
local CLICK_DURATION = 0.1

function ButtonManager.new()
    local self = setmetatable({}, ButtonManager)
    
    self.player = Players.LocalPlayer
    self.registeredButtons = {}
    self.buttonStates = {}
    self.activeTweens = {}
    self.hoverSound = nil
    self.clickSound = nil
    self.buttonCounter = 0 -- For generating unique IDs
    
    self:_initialize()
    return self
end

function ButtonManager:_initialize()
    Logger:Info("ButtonManager initializing...")
    
    self:_createSounds()
    self:_autoRegisterAllButtons()
    
    Logger:Info("✓ ButtonManager initialized")
end

function ButtonManager:_createSounds()
    -- Create hover sound
    self.hoverSound = Instance.new("Sound")
    self.hoverSound.SoundId = HOVER_SOUND_ID
    self.hoverSound.Volume = 0.3
    self.hoverSound.RollOffMode = Enum.RollOffMode.Inverse
    self.hoverSound.Parent = SoundService
    
    -- Create click sound
    self.clickSound = Instance.new("Sound")
    self.clickSound.SoundId = CLICK_SOUND_ID
    self.clickSound.Volume = 0.5
    self.clickSound.RollOffMode = Enum.RollOffMode.Inverse
    self.clickSound.Parent = SoundService
    
    Logger:Info("✓ Button sounds created")
end

function ButtonManager:RegisterButton(button, options)
    if not button or not button:IsA("GuiButton") then
        Logger:Warn("Invalid button passed to RegisterButton")
        return
    end
    
    self.buttonCounter = self.buttonCounter + 1
    local buttonId = button.Name .. "_" .. tostring(self.buttonCounter) .. "_" .. tostring(tick()):sub(-6)
    
    -- Default options
    options = options or {}
    local config = {
        hoverScale = options.hoverScale or HOVER_SCALE,
        clickScale = options.clickScale or CLICK_SCALE,
        hoverDuration = options.hoverDuration or HOVER_DURATION,
        clickDuration = options.clickDuration or CLICK_DURATION,
        enableHover = options.enableHover ~= false,
        enableClick = options.enableClick ~= false,
        enableSounds = options.enableSounds ~= false,
    }
    
    -- Store button data
    self.registeredButtons[buttonId] = {
        button = button,
        config = config,
        originalSize = button.Size,
        connections = {}
    }
    
    -- Initialize button state
    self.buttonStates[buttonId] = {
        isHovered = false,
        isPressed = false,
        isAnimating = false,
        currentScale = 1.0
    }
    
    self:_setupButtonConnections(buttonId)
    
    Logger:Debug(string.format("Registered button: %s", button.Name))
    return buttonId
end

function ButtonManager:_setupButtonConnections(buttonId)
    local buttonData = self.registeredButtons[buttonId]
    local button = buttonData.button
    local config = buttonData.config
    
    -- Mouse Enter (Hover start)
    if config.enableHover then
        local mouseEnterConnection = button.MouseEnter:Connect(function()
            self:_onButtonHover(buttonId, true)
        end)
        
        local mouseLeaveConnection = button.MouseLeave:Connect(function()
            self:_onButtonHover(buttonId, false)
        end)
        
        table.insert(buttonData.connections, mouseEnterConnection)
        table.insert(buttonData.connections, mouseLeaveConnection)
    end
    
    -- Button Down/Up (Click animation)
    if config.enableClick then
        local buttonDownConnection = button.MouseButton1Down:Connect(function()
            self:_onButtonPress(buttonId, true)
        end)
        
        local buttonUpConnection = button.MouseButton1Up:Connect(function()
            self:_onButtonPress(buttonId, false)
        end)
        
        table.insert(buttonData.connections, buttonDownConnection)
        table.insert(buttonData.connections, buttonUpConnection)
    end
end

function ButtonManager:_onButtonHover(buttonId, isHovering)
    local buttonData = self.registeredButtons[buttonId]
    local buttonState = self.buttonStates[buttonId]
    
    if not buttonData or not buttonState then return end
    
    buttonState.isHovered = isHovering
    
    -- Play hover sound
    if isHovering and buttonData.config.enableSounds then
        self:_playHoverSound()
    end
    
    -- Update button scale based on current state
    self:_updateButtonScale(buttonId)
end

function ButtonManager:_onButtonPress(buttonId, isPressed)
    local buttonData = self.registeredButtons[buttonId]
    local buttonState = self.buttonStates[buttonId]
    
    if not buttonData or not buttonState then return end
    
    buttonState.isPressed = isPressed
    
    -- Play click sound on press down
    if isPressed and buttonData.config.enableSounds then
        self:_playClickSound()
    end
    
    -- Update button scale based on current state
    self:_updateButtonScale(buttonId)
end

function ButtonManager:_updateButtonScale(buttonId)
    local buttonData = self.registeredButtons[buttonId]
    local buttonState = self.buttonStates[buttonId]
    local config = buttonData.config
    
    if not buttonData or not buttonState then return end
    
    -- Determine target scale based on state priority
    local targetScale = 1.0
    local duration = HOVER_DURATION
    
    if buttonState.isPressed then
        -- Click takes priority over hover
        targetScale = config.clickScale
        duration = config.clickDuration
    elseif buttonState.isHovered then
        targetScale = config.hoverScale
        duration = config.hoverDuration
    end
    
    -- Only animate if scale actually changed
    if math.abs(buttonState.currentScale - targetScale) < 0.001 then
        return
    end
    
    buttonState.currentScale = targetScale
    self:_animateButtonScale(buttonId, targetScale, duration)
end

function ButtonManager:_animateButtonScale(buttonId, targetScale, duration)
    local buttonData = self.registeredButtons[buttonId]
    local buttonState = self.buttonStates[buttonId]
    
    if not buttonData or not buttonState then return end
    
    local button = buttonData.button
    local originalSize = buttonData.originalSize
    
    -- Cancel any existing tween for this button
    if self.activeTweens[buttonId] then
        self.activeTweens[buttonId]:Cancel()
        self.activeTweens[buttonId]:Destroy()
        self.activeTweens[buttonId] = nil
    end
    
    -- Calculate target size
    local targetSize = UDim2.new(
        originalSize.X.Scale * targetScale,
        originalSize.X.Offset * targetScale,
        originalSize.Y.Scale * targetScale,
        originalSize.Y.Offset * targetScale
    )
    
    -- Choose easing style based on animation type
    local easingStyle = Enum.EasingStyle.Quad
    local easingDirection = Enum.EasingDirection.Out
    
    if targetScale < 1.0 then
        -- Click animation - bouncy
        easingStyle = Enum.EasingStyle.Back
        easingDirection = Enum.EasingDirection.Out
    end
    
    -- Create and play tween
    local tween = TweenService:Create(
        button,
        TweenInfo.new(duration, easingStyle, easingDirection),
        {Size = targetSize}
    )
    
    buttonState.isAnimating = true
    self.activeTweens[buttonId] = tween
    
    tween.Completed:Connect(function()
        buttonState.isAnimating = false
        self.activeTweens[buttonId] = nil
        tween:Destroy()
    end)
    
    tween:Play()
end

function ButtonManager:_playHoverSound()
    if self.hoverSound and self.hoverSound.IsLoaded then
        -- Stop any currently playing hover sound
        if self.hoverSound.IsPlaying then
            self.hoverSound:Stop()
        end
        self.hoverSound:Play()
    end
end

function ButtonManager:_playClickSound()
    if self.clickSound and self.clickSound.IsLoaded then
        -- Create a clone for overlapping clicks
        local soundClone = self.clickSound:Clone()
        soundClone.Parent = SoundService
        soundClone:Play()
        
        -- Clean up after playing
        soundClone.Ended:Connect(function()
            soundClone:Destroy()
        end)
    end
end

function ButtonManager:UnregisterButton(buttonId)
    local buttonData = self.registeredButtons[buttonId]
    
    if not buttonData then
        Logger:Warn("Attempted to unregister non-existent button: " .. tostring(buttonId))
        return
    end
    
    -- Cancel any active tweens and clean up properly
    if self.activeTweens[buttonId] then
        self.activeTweens[buttonId]:Cancel()
        self.activeTweens[buttonId]:Destroy()
        self.activeTweens[buttonId] = nil
    end
    
    -- Disconnect all connections
    for _, connection in pairs(buttonData.connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    -- Reset button to original size
    buttonData.button.Size = buttonData.originalSize
    
    -- Clean up
    self.registeredButtons[buttonId] = nil
    self.buttonStates[buttonId] = nil
    
    Logger:Debug("Unregistered button: " .. buttonData.button.Name)
end

function ButtonManager:UnregisterAllButtons()
    local buttonIds = {}
    for buttonId in pairs(self.registeredButtons) do
        table.insert(buttonIds, buttonId)
    end
    
    for _, buttonId in pairs(buttonIds) do
        self:UnregisterButton(buttonId)
    end
    
    Logger:Info("Unregistered all buttons")
end

-- Auto-register all buttons in PlayerGui
function ButtonManager:_autoRegisterAllButtons()
    local playerGui = self.player:WaitForChild("PlayerGui")
    
    -- Function to register a button if it's valid
    local function registerIfButton(instance)
        if instance:IsA("GuiButton") and not instance.Parent:IsA("CoreGui") then
            self:RegisterButton(instance)
        end
    end
    
    -- Register existing buttons
    local function scanForButtons(parent)
        for _, child in pairs(parent:GetChildren()) do
            registerIfButton(child)
            scanForButtons(child) -- Recursively scan children
        end
    end
    
    -- Initial scan
    scanForButtons(playerGui)
    
    -- Listen for new buttons being added
    local connection = playerGui.DescendantAdded:Connect(function(descendant)
        registerIfButton(descendant)
    end)
    
    -- Store connection for cleanup
    table.insert(self.registeredButtons, {connection = connection})
    
    Logger:Info("✓ Auto-registered all existing buttons and listening for new ones")
end

-- Auto-register buttons with a specific tag
function ButtonManager:RegisterButtonsWithTag(tagName, options)
    local CollectionService = game:GetService("CollectionService")
    local taggedButtons = CollectionService:GetTagged(tagName)
    
    local registeredIds = {}
    
    for _, button in pairs(taggedButtons) do
        if button:IsA("GuiButton") then
            local buttonId = self:RegisterButton(button, options)
            table.insert(registeredIds, buttonId)
        end
    end
    
    -- Also listen for new buttons with this tag
    local addedConnection = CollectionService:GetInstanceAddedSignal(tagName):Connect(function(instance)
        if instance:IsA("GuiButton") then
            local buttonId = self:RegisterButton(instance, options)
            table.insert(registeredIds, buttonId)
        end
    end)
    
    Logger:Info(string.format("Auto-registered %d buttons with tag '%s'", #registeredIds, tagName))
    return registeredIds, addedConnection
end

-- Get button stats for debugging
function ButtonManager:GetButtonStats()
    local stats = {
        registeredCount = 0,
        activeAnimations = 0,
        hoveredButtons = 0,
        pressedButtons = 0
    }
    
    for buttonId, buttonState in pairs(self.buttonStates) do
        stats.registeredCount = stats.registeredCount + 1
        
        if buttonState.isAnimating then
            stats.activeAnimations = stats.activeAnimations + 1
        end
        
        if buttonState.isHovered then
            stats.hoveredButtons = stats.hoveredButtons + 1
        end
        
        if buttonState.isPressed then
            stats.pressedButtons = stats.pressedButtons + 1
        end
    end
    
    return stats
end

function ButtonManager:Cleanup()
    Logger:Info("ButtonManager shutting down...")
    
    -- Clean up all active tweens
    for buttonId, tween in pairs(self.activeTweens) do
        if tween then
            tween:Cancel()
            tween:Destroy()
        end
    end
    self.activeTweens = {}
    
    -- Unregister all buttons
    self:UnregisterAllButtons()
    
    -- Clean up sounds
    if self.hoverSound then
        self.hoverSound:Destroy()
    end
    
    if self.clickSound then
        self.clickSound:Destroy()
    end
    
    Logger:Info("✓ ButtonManager shutdown complete")
end

return ButtonManager