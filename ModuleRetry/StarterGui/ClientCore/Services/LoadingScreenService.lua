local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local LoadingScreenService = {}
LoadingScreenService.__index = LoadingScreenService

function LoadingScreenService.new()
    local self = setmetatable({}, LoadingScreenService)
    
    self.player = Players.LocalPlayer
    self.playerGui = self.player:WaitForChild("PlayerGui")
    self.loadingScreenGui = nil
    self.isLoading = true
    self.loadingComplete = false
    self.completionCallbacks = {}
    
    -- Loading phases
    self.currentPhase = 0
    self.totalPhases = 5
    self.phaseNames = {
        "Initializing...",
        "Loading game assets...",
        "Setting up services...",
        "Connecting to server...",
        "Finalizing..."
    }
    
    -- Dynamic content system
    self.tipMessages = {
        "💡 TIP: Click mushrooms to make them spawn spores instantly!",
        "🍄 TIP: Mushrooms spawn spores automatically every few seconds.",
        "💎 TIP: Upgrade your gem boosts to collect spores faster!",
        "🛒 TIP: Buy more mushrooms to increase your spore production.",
        "⭐ TIP: Upgrade your spore level for bigger collection multipliers!",
        "🌙 TIP: Your mushrooms earn spores even while you're offline!",
        "🎯 TIP: 100 spores automatically combine into a valuable BigSpore!",
        "💰 TIP: BigSpores are worth 100x more than regular spores!",
        "🏪 TIP: Use gems to buy powerful permanent upgrades!",
        "🎮 TIP: Complete the tutorial to earn your first wish!",
        "⚡ TIP: FasterShrooms upgrade increases spore spawn rate!",
        "📏 TIP: PickUpRange upgrade increases your collection radius!",
        "🏃 TIP: FastRunner upgrade makes you move faster around your plot!",
        "✨ TIP: ShinySpore upgrade increases the value of all spores!"
    }
    
    self.thankYouMessages = {
        "Thank you for playing Fungi to Fortune! 🍄",
        "Made with ❤️ for the Roblox community!",
        "Special thanks to all our beta testers! 🙏",
        "Join our community for updates and tips! 📢",
        "Rate the game if you're enjoying it! ⭐",
        "Share with friends to grow the fungal empire! 🌱",
        "Every click helps build your mushroom kingdom! 👑",
        "From small spores to great fortunes! 💰"
    }
    
    self.funFacts = {
        "🔬 Fun Fact: Real mushrooms can grow incredibly fast!",
        "🌍 Fun Fact: Fungi help forests communicate through networks!",
        "🍄 Fun Fact: Some mushrooms glow in the dark!",
        "⚗️ Fun Fact: Mushrooms can break down almost anything!",
        "🎨 Fun Fact: There are over 10,000 mushroom species!",
        "🔬 Fun Fact: Mushrooms are more related to animals than plants!",
        "🌟 Fun Fact: The largest organism on Earth is a fungus!",
        "💊 Fun Fact: Many medicines come from fungi!"
    }
    
    -- Animation state  
    self.messageLabel = nil
    
    self:_initialize()
    return self
end

function LoadingScreenService:_initialize()
    Logger:Info("[LoadingScreen] Initializing loading screen...")
    
    -- Create the loading screen UI directly
    self:_createLoadingScreenUI()
    
    -- Get UI elements
    self.backgroundFrame = self.loadingScreenGui:FindFirstChild("Background")
    self.loadingContainer = self.backgroundFrame:FindFirstChild("LoadingContainer")
    self.loadingText = self.loadingContainer:FindFirstChild("LoadingText")
    self.loadingBarFill = self.loadingContainer:FindFirstChild("LoadingBarBackground"):FindFirstChild("LoadingBarFill")
    self.gameTitle = self.backgroundFrame:FindFirstChild("GameTitle")
    self.titleShadow = self.backgroundFrame:FindFirstChild("TitleShadow")
    
    -- Start the loading sequence
    self:_startLoadingSequence()
    
    Logger:Info("[LoadingScreen] ✓ Loading screen initialized")
end

function LoadingScreenService:_createLoadingScreenUI()
    -- Create the loading screen ScreenGui
    self.loadingScreenGui = Instance.new("ScreenGui")
    self.loadingScreenGui.Name = "LoadingScreen"
    self.loadingScreenGui.IgnoreGuiInset = true
    self.loadingScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    self.loadingScreenGui.ResetOnSpawn = false
    self.loadingScreenGui.DisplayOrder = 10000 -- Ensure it's on top of all other UIs
    self.loadingScreenGui.Parent = self.playerGui

    -- Main background frame
    local backgroundFrame = Instance.new("Frame")
    backgroundFrame.Name = "Background"
    backgroundFrame.Size = UDim2.new(1, 0, 1, 0)
    backgroundFrame.Position = UDim2.new(0, 0, 0, 0)
    backgroundFrame.BackgroundColor3 = Color3.new(0.05, 0.05, 0.08) -- Dark blue-gray
    backgroundFrame.BorderSizePixel = 0
    backgroundFrame.ZIndex = 10000
    backgroundFrame.Parent = self.loadingScreenGui

    -- Enhanced gradient overlay for visual depth
    local backgroundGradient = Instance.new("UIGradient")
    backgroundGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0.0, Color3.new(0.1, 0.12, 0.18)),   -- Deeper blue-gray at top
        ColorSequenceKeypoint.new(0.3, Color3.new(0.06, 0.08, 0.12)),  -- Mid-tone
        ColorSequenceKeypoint.new(0.7, Color3.new(0.04, 0.05, 0.08)),  -- Darker middle
        ColorSequenceKeypoint.new(1.0, Color3.new(0.02, 0.03, 0.06))   -- Very dark at bottom
    }
    backgroundGradient.Rotation = 35  -- Slightly more dynamic angle
    backgroundGradient.Parent = backgroundFrame
    
    -- Add subtle texture overlay
    local textureOverlay = Instance.new("Frame")
    textureOverlay.Name = "TextureOverlay"
    textureOverlay.Size = UDim2.new(1, 0, 1, 0)
    textureOverlay.Position = UDim2.new(0, 0, 0, 0)
    textureOverlay.BackgroundColor3 = Color3.new(0.1, 0.15, 0.25)
    textureOverlay.BackgroundTransparency = 0.95
    textureOverlay.ZIndex = 10001
    textureOverlay.Parent = backgroundFrame
    
    -- Add noise-like texture pattern
    local textureGradient = Instance.new("UIGradient")
    textureGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0.0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(0.2, Color3.new(0.8, 0.9, 1)),
        ColorSequenceKeypoint.new(0.4, Color3.new(0.6, 0.7, 0.9)),
        ColorSequenceKeypoint.new(0.6, Color3.new(0.8, 0.9, 1)),
        ColorSequenceKeypoint.new(0.8, Color3.new(0.5, 0.6, 0.8)),
        ColorSequenceKeypoint.new(1.0, Color3.new(0.9, 0.95, 1))
    }
    textureGradient.Rotation = 125
    textureGradient.Parent = textureOverlay

    -- Game title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "GameTitle"
    titleLabel.Size = UDim2.new(0, 600, 0, 120)
    titleLabel.Position = UDim2.new(0.5, -300, 0.35, -60)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "FUNGI TO FORTUNE"
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 72
    titleLabel.TextColor3 = Color3.new(0.9, 0.9, 0.95)
    titleLabel.TextStrokeTransparency = 0.5
    titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    titleLabel.ZIndex = 10005
    titleLabel.Parent = backgroundFrame

    -- Title shadow effect
    local titleShadow = Instance.new("TextLabel")
    titleShadow.Name = "TitleShadow"
    titleShadow.Size = titleLabel.Size
    titleShadow.Position = UDim2.new(0.5, -298, 0.35, -58)
    titleShadow.BackgroundTransparency = 1
    titleShadow.Text = titleLabel.Text
    titleShadow.Font = titleLabel.Font
    titleShadow.TextSize = titleLabel.TextSize
    titleShadow.TextColor3 = Color3.new(0.2, 0.4, 0.6)
    titleShadow.TextTransparency = 0.7
    titleShadow.ZIndex = 10004
    titleShadow.Parent = backgroundFrame

    -- Loading container
    local loadingContainer = Instance.new("Frame")
    loadingContainer.Name = "LoadingContainer"
    loadingContainer.Size = UDim2.new(0, 400, 0, 100)
    loadingContainer.Position = UDim2.new(0.5, -200, 0.65, -50)
    loadingContainer.BackgroundTransparency = 1
    loadingContainer.ZIndex = 10006
    loadingContainer.Parent = backgroundFrame

    -- Loading text
    local loadingText = Instance.new("TextLabel")
    loadingText.Name = "LoadingText"
    loadingText.Size = UDim2.new(1, 0, 0, 40)
    loadingText.Position = UDim2.new(0, 0, 0, 0)
    loadingText.BackgroundTransparency = 1
    loadingText.Text = "Loading..."
    loadingText.Font = Enum.Font.Gotham
    loadingText.TextSize = 24
    loadingText.TextColor3 = Color3.new(0.8, 0.8, 0.85)
    loadingText.ZIndex = 10007
    loadingText.Parent = loadingContainer

    -- Loading bar background
    local loadingBarBg = Instance.new("Frame")
    loadingBarBg.Name = "LoadingBarBackground"
    loadingBarBg.Size = UDim2.new(1, 0, 0, 8)
    loadingBarBg.Position = UDim2.new(0, 0, 0, 60)
    loadingBarBg.BackgroundColor3 = Color3.new(0.15, 0.15, 0.2)
    loadingBarBg.BorderSizePixel = 0
    loadingBarBg.ZIndex = 10007
    loadingBarBg.Parent = loadingContainer

    -- Loading bar background corner
    local loadingBarBgCorner = Instance.new("UICorner")
    loadingBarBgCorner.CornerRadius = UDim.new(0, 4)
    loadingBarBgCorner.Parent = loadingBarBg

    -- Loading bar fill with gradient
    local loadingBarFill = Instance.new("Frame")
    loadingBarFill.Name = "LoadingBarFill"
    loadingBarFill.Size = UDim2.new(0, 0, 1, 0)
    loadingBarFill.Position = UDim2.new(0, 0, 0, 0)
    loadingBarFill.BackgroundColor3 = Color3.new(0.3, 0.6, 0.9)
    loadingBarFill.BorderSizePixel = 0
    loadingBarFill.ZIndex = 10008
    loadingBarFill.Parent = loadingBarBg
    
    -- Enhanced loading bar gradient
    local loadingBarGradient = Instance.new("UIGradient")
    loadingBarGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0.0, Color3.new(0.4, 0.7, 1.0)),    -- Bright blue
        ColorSequenceKeypoint.new(0.5, Color3.new(0.3, 0.6, 0.9)),    -- Mid blue
        ColorSequenceKeypoint.new(1.0, Color3.new(0.2, 0.5, 0.8))     -- Deeper blue
    }
    loadingBarGradient.Rotation = 0
    loadingBarGradient.Parent = loadingBarFill
    
    -- Add glow effect to loading bar
    local loadingBarGlow = Instance.new("UIStroke")
    loadingBarGlow.Thickness = 2
    loadingBarGlow.Color = Color3.new(0.5, 0.8, 1.0)
    loadingBarGlow.Transparency = 0.4
    loadingBarGlow.Parent = loadingBarFill

    -- Loading bar fill corner
    local loadingBarFillCorner = Instance.new("UICorner")
    loadingBarFillCorner.CornerRadius = UDim.new(0, 4)
    loadingBarFillCorner.Parent = loadingBarFill

    -- Loading bar gradient
    local loadingBarGradient = Instance.new("UIGradient")
    loadingBarGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0.0, Color3.new(0.4, 0.7, 1.0)),
        ColorSequenceKeypoint.new(0.5, Color3.new(0.3, 0.6, 0.9)),
        ColorSequenceKeypoint.new(1.0, Color3.new(0.2, 0.5, 0.8))
    }
    loadingBarGradient.Parent = loadingBarFill

    -- Animated dots for loading text
    spawn(function()
        local dots = {"", ".", "..", "..."}
        local dotIndex = 1
        
        while self.loadingScreenGui and self.loadingScreenGui.Parent do
            if loadingText and loadingText.Parent then
                loadingText.Text = "Loading" .. dots[dotIndex]
                dotIndex = (dotIndex % #dots) + 1
            end
            wait(0.5)
        end
    end)

    -- Create sophisticated background pattern
    self:_createBackgroundPattern(backgroundFrame)
    
    -- Create simple rotating message below loading bar
    self:_createRotatingMessage(backgroundFrame)
end

function LoadingScreenService:_createBackgroundPattern(backgroundFrame)
    -- Create geometric pattern layer
    local patternFrame = Instance.new("Frame")
    patternFrame.Name = "PatternLayer"
    patternFrame.Size = UDim2.new(1, 0, 1, 0)
    patternFrame.Position = UDim2.new(0, 0, 0, 0)
    patternFrame.BackgroundTransparency = 1
    patternFrame.ZIndex = 10002
    patternFrame.Parent = backgroundFrame
    
    -- Create hexagonal pattern grid
    local function createHexagon(x, y, size, delay)
        local hexagon = Instance.new("Frame")
        hexagon.Size = UDim2.new(0, size, 0, size)
        hexagon.Position = UDim2.new(0, x, 0, y)
        hexagon.BackgroundColor3 = Color3.new(0.15, 0.25, 0.4)
        hexagon.BackgroundTransparency = 0.85
        hexagon.BorderSizePixel = 0
        hexagon.ZIndex = 10002
        hexagon.Parent = patternFrame
        
        -- Create hexagonal corner (approximated with high corner radius)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, size * 0.15)
        corner.Parent = hexagon
        
        -- Create border stroke for more definition
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Color = Color3.new(0.2, 0.4, 0.6)
        stroke.Transparency = 0.7
        stroke.Parent = hexagon
        
        -- Animate the hexagon with a subtle pulse and rotation
        spawn(function()
            wait(delay)
            
            -- Initial fade in
            local fadeIn = TweenService:Create(
                hexagon,
                TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {BackgroundTransparency = 0.9}
            )
            fadeIn:Play()
            
            -- Continuous gentle animation
            while hexagon and hexagon.Parent do
                -- Pulse animation
                local pulseOut = TweenService:Create(
                    hexagon,
                    TweenInfo.new(3 + math.random() * 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {
                        BackgroundTransparency = 0.95,
                        Size = UDim2.new(0, size * 1.1, 0, size * 1.1)
                    }
                )
                
                local pulseIn = TweenService:Create(
                    hexagon,
                    TweenInfo.new(3 + math.random() * 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {
                        BackgroundTransparency = 0.85,
                        Size = UDim2.new(0, size, 0, size)
                    }
                )
                
                pulseOut:Play()
                pulseOut.Completed:Wait()
                pulseIn:Play()
                pulseIn.Completed:Wait()
            end
        end)
        
        return hexagon
    end
    
    -- Create grid of hexagons
    local hexSize = 40
    local spacing = hexSize * 1.5
    local rows = math.ceil(backgroundFrame.AbsoluteSize.Y / spacing) + 2
    local cols = math.ceil(backgroundFrame.AbsoluteSize.X / spacing) + 2
    
    for row = 0, rows do
        for col = 0, cols do
            local x = col * spacing
            local y = row * spacing
            
            -- Offset every other row for hexagonal pattern
            if row % 2 == 1 then
                x = x + spacing * 0.5
            end
            
            -- Random delay for staggered animation
            local delay = math.random() * 3
            
            createHexagon(x - spacing, y - spacing, hexSize, delay)
        end
    end
    
    -- Create floating accent elements
    self:_createFloatingAccents(patternFrame)
    
    -- Create animated border elements
    self:_createAnimatedBorders(patternFrame)
    
    -- Create floating icons for extra visual interest
    self:_createFloatingIcons(patternFrame)
end

function LoadingScreenService:_createFloatingAccents(patternFrame)
    -- Create larger decorative elements that slowly drift
    for i = 1, 8 do
        local accent = Instance.new("Frame")
        accent.Size = UDim2.new(0, math.random(60, 120), 0, math.random(60, 120))
        accent.Position = UDim2.new(math.random() * 0.8 + 0.1, 0, math.random() * 0.8 + 0.1, 0)
        accent.BackgroundColor3 = Color3.new(0.2, 0.5, 0.8)
        accent.BackgroundTransparency = 0.95
        accent.BorderSizePixel = 0
        accent.ZIndex = 10001
        accent.Parent = patternFrame
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.3, 0)
        corner.Parent = accent
        
        -- Slow drift animation
        spawn(function()
            while accent and accent.Parent do
                local newX = math.random() * 0.8 + 0.1
                local newY = math.random() * 0.8 + 0.1
                
                local driftTween = TweenService:Create(
                    accent,
                    TweenInfo.new(15 + math.random() * 10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {
                        Position = UDim2.new(newX, 0, newY, 0),
                        Rotation = math.random(-30, 30),
                        BackgroundTransparency = 0.92 + math.random() * 0.06
                    }
                )
                
                driftTween:Play()
                driftTween.Completed:Wait()
            end
        end)
    end
end

function LoadingScreenService:_createAnimatedBorders(patternFrame)
    -- Create animated corner accents
    local corners = {
        {0, 0, 0, 45},           -- Top-left
        {1, 0, -200, 45},        -- Top-right  
        {0, 1, 0, -45},          -- Bottom-left
        {1, 1, -200, -45}        -- Bottom-right
    }
    
    for _, corner in ipairs(corners) do
        local borderAccent = Instance.new("Frame")
        borderAccent.Size = UDim2.new(0, 200, 0, 4)
        borderAccent.Position = UDim2.new(corner[1], corner[3], corner[2], corner[4])
        borderAccent.BackgroundColor3 = Color3.new(0.3, 0.6, 0.9)
        borderAccent.BackgroundTransparency = 0.3
        borderAccent.BorderSizePixel = 0
        borderAccent.ZIndex = 10003
        borderAccent.Parent = patternFrame
        
        -- Add glow effect
        local glow = Instance.new("UIStroke")
        glow.Thickness = 2
        glow.Color = Color3.new(0.4, 0.7, 1.0)
        glow.Transparency = 0.5
        glow.Parent = borderAccent
        
        -- Animate the border
        spawn(function()
            while borderAccent and borderAccent.Parent do
                local glowTween = TweenService:Create(
                    glow,
                    TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {Transparency = 0.8}
                )
                
                local glowBack = TweenService:Create(
                    glow,
                    TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {Transparency = 0.3}
                )
                
                glowTween:Play()
                glowTween.Completed:Wait()
                glowBack:Play()
                glowBack.Completed:Wait()
            end
        end)
    end
end

function LoadingScreenService:_createFloatingIcons(patternFrame)
    -- Create floating mushroom and spore icons for thematic elements
    local icons = {"🍄", "💎", "⭐", "💰", "✨", "🌟", "💫", "🔮"}
    
    for i = 1, 12 do
        local iconLabel = Instance.new("TextLabel")
        iconLabel.Size = UDim2.new(0, 30, 0, 30)
        iconLabel.Position = UDim2.new(math.random() * 0.9 + 0.05, 0, math.random() * 0.9 + 0.05, 0)
        iconLabel.BackgroundTransparency = 1
        iconLabel.Text = icons[math.random(#icons)]
        iconLabel.Font = Enum.Font.Gotham
        iconLabel.TextSize = 20
        iconLabel.TextColor3 = Color3.new(0.6, 0.8, 1.0)
        iconLabel.TextTransparency = 0.7
        iconLabel.ZIndex = 10001
        iconLabel.Parent = patternFrame
        
        -- Floating animation with random paths
        spawn(function()
            local startDelay = math.random() * 5
            task.wait(startDelay)
            
            while iconLabel and iconLabel.Parent do
                -- Random floating movement
                local newX = math.random() * 0.9 + 0.05
                local newY = math.random() * 0.9 + 0.05
                local duration = 8 + math.random() * 6
                
                local floatTween = TweenService:Create(
                    iconLabel,
                    TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {
                        Position = UDim2.new(newX, 0, newY, 0),
                        TextTransparency = 0.5 + math.random() * 0.4,
                        Rotation = math.random(-180, 180)
                    }
                )
                
                floatTween:Play()
                floatTween.Completed:Wait()
            end
        end)
    end
end

function LoadingScreenService:_createRotatingMessage(backgroundFrame)
    -- Create a single rotating message below the loading bar
    local messageLabel = Instance.new("TextLabel")
    messageLabel.Name = "RotatingMessage"
    messageLabel.Size = UDim2.new(0, 600, 0, 30)
    messageLabel.Position = UDim2.new(0.5, -300, 0.7, 0)
    messageLabel.BackgroundTransparency = 1
    messageLabel.Text = self.tipMessages[1]
    messageLabel.Font = Enum.Font.Gotham
    messageLabel.TextSize = 16
    messageLabel.TextColor3 = Color3.new(0.8, 0.9, 1.0)
    messageLabel.TextXAlignment = Enum.TextXAlignment.Center
    messageLabel.TextWrapped = true
    messageLabel.ZIndex = 10007
    messageLabel.Parent = backgroundFrame
    
    -- Store reference for rotation
    self.messageLabel = messageLabel
    
    -- Start message rotation
    self:_startMessageRotation()
end

function LoadingScreenService:_startMessageRotation()
    spawn(function()
        while self.loadingScreenGui and self.loadingScreenGui.Parent do
            task.wait(2.5) -- Rotate every 2.5 seconds
            self:_rotateMessage()
        end
    end)
end

function LoadingScreenService:_rotateMessage()
    if not self.messageLabel then return end
    
    -- Fade out
    local fadeOut = TweenService:Create(
        self.messageLabel,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {TextTransparency = 1}
    )
    
    fadeOut:Play()
    fadeOut.Completed:Connect(function()
        -- Combine all messages into one array
        local allMessages = {}
        
        -- Add tips
        for _, tip in ipairs(self.tipMessages) do
            table.insert(allMessages, tip)
        end
        
        -- Add thank you messages  
        for _, thanks in ipairs(self.thankYouMessages) do
            table.insert(allMessages, thanks)
        end
        
        -- Add fun facts
        for _, fact in ipairs(self.funFacts) do
            table.insert(allMessages, fact)
        end
        
        -- Pick random message
        local randomIndex = math.random(1, #allMessages)
        self.messageLabel.Text = allMessages[randomIndex]
        
        -- Fade in
        local fadeIn = TweenService:Create(
            self.messageLabel,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {TextTransparency = 0.2}
        )
        fadeIn:Play()
    end)
end

function LoadingScreenService:_startLoadingSequence()
    -- Animate title entrance
    self.gameTitle.Position = UDim2.new(0.5, -300, 0.15, -60)
    self.titleShadow.Position = UDim2.new(0.5, -298, 0.15, -58)
    self.gameTitle.TextTransparency = 1
    self.titleShadow.TextTransparency = 1
    
    -- Loading container starts invisible
    self.loadingContainer.Position = UDim2.new(0.5, -200, 0.85, -50)
    for _, child in pairs(self.loadingContainer:GetDescendants()) do
        if child:IsA("GuiObject") then
            child.BackgroundTransparency = 1
            if child:IsA("TextLabel") then
                child.TextTransparency = 1
            end
        end
    end
    
    -- Phase 1: Title animation
    self:_nextPhase(function()
        local titleTween = TweenService:Create(
            self.gameTitle,
            TweenInfo.new(1.0, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {
                Position = UDim2.new(0.5, -300, 0.35, -60),
                TextTransparency = 0
            }
        )
        
        local shadowTween = TweenService:Create(
            self.titleShadow,
            TweenInfo.new(1.0, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {
                Position = UDim2.new(0.5, -298, 0.35, -58),
                TextTransparency = 0.7
            }
        )
        
        titleTween:Play()
        shadowTween:Play()
        
        titleTween.Completed:Connect(function()
            task.wait(0.5)
            self:_nextPhase()
        end)
    end)
end

function LoadingScreenService:_nextPhase(customCallback)
    if customCallback then
        customCallback()
        return
    end
    
    self.currentPhase = self.currentPhase + 1
    
    if self.currentPhase > self.totalPhases then
        self:_completeLoading()
        return
    end
    
    -- Update loading text
    if self.currentPhase <= #self.phaseNames then
        self.loadingText.Text = self.phaseNames[self.currentPhase]
    end
    
    -- Show loading container on phase 2
    if self.currentPhase == 2 then
        self:_showLoadingContainer()
    end
    
    -- Update progress bar
    local progress = (self.currentPhase - 1) / self.totalPhases
    local targetSize = UDim2.new(progress, 0, 1, 0)
    
    local progressTween = TweenService:Create(
        self.loadingBarFill,
        TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = targetSize}
    )
    
    progressTween:Play()
    
    -- Simulate loading time for each phase
    local phaseTime = math.random(800, 1500) / 1000 -- 0.8 to 1.5 seconds
    
    task.wait(phaseTime)
    
    -- Continue to next phase
    spawn(function()
        self:_nextPhase()
    end)
end

function LoadingScreenService:_showLoadingContainer()
    -- Animate loading container entrance
    local containerTween = TweenService:Create(
        self.loadingContainer,
        TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, -200, 0.65, -50)}
    )
    
    containerTween:Play()
    
    -- Fade in all container elements
    for _, child in pairs(self.loadingContainer:GetDescendants()) do
        if child:IsA("Frame") and child.Name ~= "LoadingBarFill" then
            local bgTween = TweenService:Create(child, TweenInfo.new(0.6), {BackgroundTransparency = 0})
            bgTween:Play()
        elseif child:IsA("TextLabel") then
            local textTween = TweenService:Create(child, TweenInfo.new(0.6), {TextTransparency = 0})
            textTween:Play()
        end
    end
    
    -- Special handling for loading bar background
    local loadingBarBg = self.loadingContainer:FindFirstChild("LoadingBarBackground")
    if loadingBarBg then
        local bgTween = TweenService:Create(loadingBarBg, TweenInfo.new(0.6), {BackgroundTransparency = 0})
        bgTween:Play()
        
        local fillTween = TweenService:Create(self.loadingBarFill, TweenInfo.new(0.6), {BackgroundTransparency = 0})
        fillTween:Play()
    end
end

function LoadingScreenService:_completeLoading()
    Logger:Info("[LoadingScreen] Loading complete, starting exit animation...")
    
    self.loadingComplete = true
    self.isLoading = false
    
    -- Final progress bar fill
    local finalProgressTween = TweenService:Create(
        self.loadingBarFill,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.new(1, 0, 1, 0)}
    )
    
    finalProgressTween:Play()
    
    -- Update loading text
    self.loadingText.Text = "Complete!"
    
    task.wait(0.8)
    
    -- Start exit animation
    self:_exitAnimation()
end

function LoadingScreenService:_exitAnimation()
    Logger:Info("[LoadingScreen] Starting exit animation...")
    
    -- Slide title up and fade out
    local titleExitTween = TweenService:Create(
        self.gameTitle,
        TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {
            Position = UDim2.new(0.5, -300, 0.15, -60),
            TextTransparency = 1
        }
    )
    
    local shadowExitTween = TweenService:Create(
        self.titleShadow,
        TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {
            Position = UDim2.new(0.5, -298, 0.15, -58),
            TextTransparency = 1
        }
    )
    
    -- Slide loading container down and fade out
    local containerExitTween = TweenService:Create(
        self.loadingContainer,
        TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {Position = UDim2.new(0.5, -200, 0.85, -50)}
    )
    
    -- Fade out all container elements
    for _, child in pairs(self.loadingContainer:GetDescendants()) do
        if child:IsA("GuiObject") then
            local fadeTween = TweenService:Create(child, TweenInfo.new(0.6), {BackgroundTransparency = 1})
            fadeTween:Play()
            if child:IsA("TextLabel") then
                local textFadeTween = TweenService:Create(child, TweenInfo.new(0.6), {TextTransparency = 1})
                textFadeTween:Play()
            end
        end
    end
    
    titleExitTween:Play()
    shadowExitTween:Play()
    containerExitTween:Play()
    
    titleExitTween.Completed:Connect(function()
        -- Final background fade out
        local backgroundExitTween = TweenService:Create(
            self.backgroundFrame,
            TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 1}
        )
        
        backgroundExitTween:Play()
        
        backgroundExitTween.Completed:Connect(function()
            -- Destroy loading screen
            self.loadingScreenGui:Destroy()
            self.loadingScreenGui = nil
            
            Logger:Info("[LoadingScreen] ✓ Loading screen removed")
            
            -- Call all completion callbacks
            self:_callCompletionCallbacks()
        end)
    end)
end

function LoadingScreenService:_callCompletionCallbacks()
    Logger:Info("[LoadingScreen] Calling completion callbacks...")
    
    for _, callback in pairs(self.completionCallbacks) do
        spawn(function()
            local success, error = pcall(callback)
            if not success then
                Logger:Error("[LoadingScreen] Completion callback failed: " .. tostring(error))
            end
        end)
    end
    
    self.completionCallbacks = {}
end

-- Public methods
function LoadingScreenService:IsLoading()
    return self.isLoading
end

function LoadingScreenService:IsComplete()
    return self.loadingComplete
end

function LoadingScreenService:OnLoadingComplete(callback)
    if self.loadingComplete then
        -- If loading is already complete, call immediately
        spawn(callback)
    else
        -- Add to callbacks list
        table.insert(self.completionCallbacks, callback)
    end
end

function LoadingScreenService:WaitForLoadingComplete()
    while self.isLoading do
        task.wait(0.1)
    end
end

function LoadingScreenService:Cleanup()
    if self.loadingScreenGui then
        self.loadingScreenGui:Destroy()
    end
    self.completionCallbacks = {}
    Logger:Info("[LoadingScreen] ✓ Cleanup complete")
end

return LoadingScreenService