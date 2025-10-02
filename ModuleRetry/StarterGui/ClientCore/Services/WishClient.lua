local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)
local GamepassConfig = require(ReplicatedStorage.Shared.Modules.GamepassConfig)

local WishClient = {}
WishClient.__index = WishClient

local player = Players.LocalPlayer

local SOUNDS = {
    entrance = "rbxassetid://131961136",
    spinning = "rbxassetid://131961136",
    reveal = "rbxassetid://131961136",
    legendary = "rbxassetid://131961136",
    epic = "rbxassetid://131961136",
    rare = "rbxassetid://131961136",
    common = "rbxassetid://131961136",
    celebration = "rbxassetid://131961136",
    sparkles = "rbxassetid://131961136"
}

local RARITY_COLORS = {
    legendary = Color3.fromRGB(255, 215, 0),
    epic = Color3.fromRGB(128, 0, 128),
    rare = Color3.fromRGB(0, 162, 255),
    common = Color3.fromRGB(0, 255, 0)
}

function WishClient.new()
    local self = setmetatable({}, WishClient)
    
    self._connections = {}
    self._uiElements = {}
    self._inventory = {}
    self._itemConfig = {}
    
    self:_initialize()
    return self
end

function WishClient:_initialize()
    Logger:Info("WishClient initializing...")
    
    task.spawn(function()
        self:_setupRemoteEvents()
        self:_setupUI()
    end)
    
    Logger:Info("✓ WishClient initialized")
end

function WishClient:_setupRemoteEvents()
    local shared = ReplicatedStorage:WaitForChild("Shared", 10)
    if not shared then
        Logger:Error("Shared folder not found")
        return
    end
    
    local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
    if not remoteEvents then
        Logger:Error("RemoteEvents folder not found")
        return
    end
    
    local wishEvents = remoteEvents:WaitForChild("WishEvents", 10)
    if not wishEvents then
        Logger:Error("WishEvents folder not found")
        return
    end
    
    local updateWishGUI = wishEvents:WaitForChild("UpdateWishGUI", 10)
    local wishSpin = wishEvents:WaitForChild("WishSpin", 10)
    local playWishAnimation = wishEvents:WaitForChild("PlayWishAnimation", 10)
    local updateInventory = wishEvents:WaitForChild("UpdateInventory", 10)
    
    if updateWishGUI then
        self._connections.UpdateWishGUI = updateWishGUI.OnClientEvent:Connect(function(wishCount, timeUntilNext)
            self:_updateWishGUI(wishCount, timeUntilNext)
        end)
    end
    
    if playWishAnimation then
        self._connections.PlayWishAnimation = playWishAnimation.OnClientEvent:Connect(function(rarity, item)
            self:_playWishAnimation(rarity, item)
        end)
    end
    
    if updateInventory then
        self._connections.UpdateInventory = updateInventory.OnClientEvent:Connect(function(inventory, itemConfig)
            self._inventory = inventory
            self._itemConfig = itemConfig
            self:_updateInventoryDisplay()
        end)
    end
    
    self._wishSpinEvent = wishSpin
    
    Logger:Info("✓ Wish remote events connected")
end

function WishClient:_setupUI()
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then
        Logger:Error("PlayerGui not found")
        return
    end
    
    local wishFountainGui = playerGui:WaitForChild("WishFountain", 10)
    if wishFountainGui then
        local frame = wishFountainGui:WaitForChild("Frame", 10)
        if frame then
            local buttonContainer = frame:WaitForChild("ButtonContainer", 10)
            if buttonContainer then
                Logger:Info("ButtonContainer found, looking for children...")
                
                -- List all children for debugging
                for _, child in pairs(buttonContainer:GetChildren()) do
                    Logger:Info(string.format("Found child: %s (%s)", child.Name, child.ClassName))
                end
                
                local wishCountLabel = buttonContainer:FindFirstChild("WishCount")
                local wishButton = buttonContainer:FindFirstChild("Wish")
                local buy5Button = buttonContainer:FindFirstChild("Buy5")
                local buy50Button = buttonContainer:FindFirstChild("Buy50")
                
                if wishCountLabel then
                    self._uiElements.wishCountLabel = wishCountLabel
                    Logger:Info("✓ Found WishCount label")
                else
                    Logger:Warn("❌ WishCount label not found")
                end
                
                if wishButton and wishButton:IsA("GuiButton") then
                    self._uiElements.wishButton = wishButton
                    self._connections.WishButton = wishButton.MouseButton1Click:Connect(function()
                        self:_onWishButtonClicked()
                    end)
                    Logger:Info("✓ Connected wish button")
                else
                    Logger:Warn("❌ Wish button not found or not a GuiButton")
                end
                
                if buy5Button then
                    if buy5Button:IsA("GuiButton") then
                        self._uiElements.buy5Button = buy5Button
                        self._connections.Buy5Button = buy5Button.MouseButton1Click:Connect(function()
                            self:_onBuy5ButtonClicked()
                        end)
                        Logger:Info("✓ Connected Buy5 button")
                    else
                        Logger:Warn(string.format("❌ Buy5 found but is %s, not GuiButton", buy5Button.ClassName))
                    end
                else
                    Logger:Warn("❌ Buy5 button not found")
                end
                
                if buy50Button then
                    if buy50Button:IsA("GuiButton") then
                        self._uiElements.buy50Button = buy50Button
                        self._connections.Buy50Button = buy50Button.MouseButton1Click:Connect(function()
                            self:_onBuy50ButtonClicked()
                        end)
                        Logger:Info("✓ Connected Buy50 button")
                    else
                        Logger:Warn(string.format("❌ Buy50 found but is %s, not GuiButton", buy50Button.ClassName))
                    end
                else
                    Logger:Warn("❌ Buy50 button not found")
                end
            else
                Logger:Error("❌ ButtonContainer not found")
            end
        end
    end
    
    local wishFountainPart = workspace:FindFirstChild("Wish Fountain")
    if wishFountainPart then
        local billboardGui = wishFountainPart:FindFirstChild("Wish Fountain")
        if billboardGui then
            local wishFountainLabel = billboardGui:FindFirstChild("Wish Fountain")
            if wishFountainLabel then
                self._uiElements.wishFountainLabel = wishFountainLabel
                Logger:Info("✓ Found wish fountain billboard")
            end
        end
    end
end

function WishClient:_updateWishGUI(wishCount, timeUntilNext)
    Logger:Debug(string.format("WishClient received GUI update: wishes=%d, timeUntil=%d", wishCount, timeUntilNext))
    
    if self._uiElements.wishFountainLabel then
        if wishCount > 0 then
            if wishCount == 1 then
                self._uiElements.wishFountainLabel.Text = "1 Wish Available!"
            else
                self._uiElements.wishFountainLabel.Text = wishCount .. " Wishes Available!"
            end
        else
            self._uiElements.wishFountainLabel.Text = "No Wishes Available!"
        end
        Logger:Debug(string.format("Updated wish fountain label to: %s", self._uiElements.wishFountainLabel.Text))
    end
    
    if self._uiElements.wishCountLabel then
        local timeText = ""
        if wishCount < 5 then
            local minutes = math.floor(timeUntilNext / 60)
            local seconds = timeUntilNext % 60
            timeText = string.format(" (Free in %d:%02d)", minutes, seconds)
        else
            timeText = " (MAX)"
        end
        
        self._uiElements.wishCountLabel.Text = "Owned : " .. wishCount .. "/5" .. timeText
        Logger:Debug(string.format("Updated wish count label to: %s", self._uiElements.wishCountLabel.Text))
    end
end

function WishClient:_onWishButtonClicked()
    if self._wishSpinEvent then
        self._wishSpinEvent:FireServer()
        Logger:Info("Wish spin requested")
    end
end

function WishClient:_onBuy5ButtonClicked()
    Logger:Info("🔥 BUY5 BUTTON CLICKED! 🔥")
    
    local MarketplaceService = game:GetService("MarketplaceService")
    local productId = GamepassConfig.DEV_PRODUCT_IDS.WISHES_5
    
    local success, error = pcall(function()
        MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
    end)
    
    if success then
        Logger:Info("✓ Successfully prompted purchase for 5 wishes")
    else
        Logger:Error(string.format("❌ Failed to prompt purchase: %s", tostring(error)))
    end
end

function WishClient:_onBuy50ButtonClicked()
    Logger:Info("🔥 BUY50 BUTTON CLICKED! 🔥")
    
    local MarketplaceService = game:GetService("MarketplaceService")
    local productId = GamepassConfig.DEV_PRODUCT_IDS.WISHES_50
    
    local success, error = pcall(function()
        MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
    end)
    
    if success then
        Logger:Info("✓ Successfully prompted purchase for 50 wishes")
    else
        Logger:Error(string.format("❌ Failed to prompt purchase: %s", tostring(error)))
    end
end

function WishClient:_playSound(soundId, volume, pitch)
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = volume or 0.5
    sound.Pitch = pitch or 1
    sound.Parent = SoundService
    sound:Play()
    
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
    
    return sound
end

function WishClient:_createSparkle(parent, color, size)
    local sparkle = Instance.new("Frame")
    sparkle.Size = UDim2.new(0, size, 0, size)
    sparkle.Position = UDim2.new(math.random(), 0, math.random(), 0)
    sparkle.BackgroundColor3 = color
    sparkle.BorderSizePixel = 0
    sparkle.ZIndex = 107
    sparkle.Parent = parent
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = sparkle
    
    local tween = TweenService:Create(sparkle,
        TweenInfo.new(math.random(10, 20) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0)}
    )
    tween:Play()
    
    tween.Completed:Connect(function()
        sparkle:Destroy()
    end)
end

function WishClient:_createAnimationGUI()
    local playerGui = player:WaitForChild("PlayerGui")
    
    local animGui = Instance.new("ScreenGui")
    animGui.Name = "WishAnimation"
    animGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    animGui.IgnoreGuiInset = true
    animGui.Parent = playerGui
    
    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.Position = UDim2.new(0, 0, 0, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.2
    overlay.ZIndex = 100
    overlay.Parent = animGui
    
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 40)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 10, 20)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 15))
    }
    gradient.Rotation = 45
    gradient.Parent = overlay
    
    local particleFrame = Instance.new("Frame")
    particleFrame.Name = "ParticleFrame"
    particleFrame.Size = UDim2.new(1, 0, 1, 0)
    particleFrame.Position = UDim2.new(0, 0, 0, 0)
    particleFrame.BackgroundTransparency = 1
    particleFrame.ZIndex = 105
    particleFrame.Parent = animGui
    
    local animContainer = Instance.new("Frame")
    animContainer.Name = "AnimationContainer"
    animContainer.Size = UDim2.new(1, 0, 1, 0)
    animContainer.Position = UDim2.new(0, 0, 0, 0)
    animContainer.BackgroundTransparency = 1
    animContainer.ZIndex = 101
    animContainer.Parent = animGui
    
    local magicCircle = Instance.new("Frame")
    magicCircle.Name = "MagicCircle"
    magicCircle.Size = UDim2.new(0, 400, 0, 400)
    magicCircle.Position = UDim2.new(0.5, -200, 0.5, -200)
    magicCircle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    magicCircle.BackgroundTransparency = 0.8
    magicCircle.BorderSizePixel = 0
    magicCircle.ZIndex = 102
    magicCircle.Parent = animContainer
    
    local circleCorner = Instance.new("UICorner")
    circleCorner.CornerRadius = UDim.new(0.5, 0)
    circleCorner.Parent = magicCircle
    
    local glowFrame = Instance.new("Frame")
    glowFrame.Name = "GlowFrame"
    glowFrame.Size = UDim2.new(0, 300, 0, 300)
    glowFrame.Position = UDim2.new(0.5, -150, 0.5, -150)
    glowFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    glowFrame.BackgroundTransparency = 0.9
    glowFrame.BorderSizePixel = 0
    glowFrame.ZIndex = 103
    glowFrame.Parent = animContainer
    
    local glowCorner = Instance.new("UICorner")
    glowCorner.CornerRadius = UDim.new(0.5, 0)
    glowCorner.Parent = glowFrame
    
    local cubeContainer = Instance.new("Frame")
    cubeContainer.Name = "CubeContainer"
    cubeContainer.Size = UDim2.new(0, 120, 0, 120)
    cubeContainer.Position = UDim2.new(0.5, -60, 0.5, -60)
    cubeContainer.BackgroundTransparency = 1
    cubeContainer.ZIndex = 104
    cubeContainer.Parent = animContainer
    
    local cubeShadow = Instance.new("Frame")
    cubeShadow.Name = "CubeShadow"
    cubeShadow.Size = UDim2.new(1, 0, 1, 0)
    cubeShadow.Position = UDim2.new(0, 3, 0, 3)
    cubeShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    cubeShadow.BackgroundTransparency = 0.7
    cubeShadow.BorderSizePixel = 0
    cubeShadow.ZIndex = 103
    cubeShadow.Parent = cubeContainer
    
    local shadowCorner = Instance.new("UICorner")
    shadowCorner.CornerRadius = UDim.new(0, 15)
    shadowCorner.Parent = cubeShadow
    
    local cube = Instance.new("Frame")
    cube.Name = "Cube"
    cube.Size = UDim2.new(1, 0, 1, 0)
    cube.Position = UDim2.new(0, 0, 0, 0)
    cube.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
    cube.BorderSizePixel = 0
    cube.ZIndex = 104
    cube.Parent = cubeContainer
    
    local cubeCorner = Instance.new("UICorner")
    cubeCorner.CornerRadius = UDim.new(0, 15)
    cubeCorner.Parent = cube
    
    local cubeGlow = Instance.new("UIStroke")
    cubeGlow.Color = Color3.fromRGB(255, 255, 255)
    cubeGlow.Thickness = 0
    cubeGlow.Transparency = 0.5
    cubeGlow.Parent = cube
    
    local sparkleContainer = Instance.new("Frame")
    sparkleContainer.Name = "SparkleContainer"
    sparkleContainer.Size = UDim2.new(0, 600, 0, 600)
    sparkleContainer.Position = UDim2.new(0.5, -300, 0.5, -300)
    sparkleContainer.BackgroundTransparency = 1
    sparkleContainer.ZIndex = 106
    sparkleContainer.Parent = animGui
    
    local resultFrame = Instance.new("Frame")
    resultFrame.Name = "ResultFrame"
    resultFrame.Size = UDim2.new(0, 500, 0, 300)
    resultFrame.Position = UDim2.new(0.5, -250, 0.5, -150)
    resultFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    resultFrame.BackgroundTransparency = 1
    resultFrame.BorderSizePixel = 0
    resultFrame.ZIndex = 107
    resultFrame.Parent = animGui
    
    local resultCorner = Instance.new("UICorner")
    resultCorner.CornerRadius = UDim.new(0, 20)
    resultCorner.Parent = resultFrame
    
    local rarityBanner = Instance.new("Frame")
    rarityBanner.Name = "RarityBanner"
    rarityBanner.Size = UDim2.new(1, 0, 0, 80)
    rarityBanner.Position = UDim2.new(0, 0, 0, 0)
    rarityBanner.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    rarityBanner.BackgroundTransparency = 1
    rarityBanner.BorderSizePixel = 0
    rarityBanner.ZIndex = 108
    rarityBanner.Parent = resultFrame
    
    local bannerCorner = Instance.new("UICorner")
    bannerCorner.CornerRadius = UDim.new(0, 20)
    bannerCorner.Parent = rarityBanner
    
    local rarityText = Instance.new("TextLabel")
    rarityText.Name = "RarityText"
    rarityText.Size = UDim2.new(1, 0, 0.4, 0)
    rarityText.Position = UDim2.new(0, 0, 0.1, 0)
    rarityText.BackgroundTransparency = 1
    rarityText.Text = ""
    rarityText.TextColor3 = Color3.fromRGB(255, 255, 255)
    rarityText.TextScaled = true
    rarityText.Font = Enum.Font.FredokaOne
    rarityText.ZIndex = 109
    rarityText.TextStrokeTransparency = 0.5
    rarityText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    rarityText.Parent = resultFrame
    
    local resultText = Instance.new("TextLabel")
    resultText.Name = "ResultText"
    resultText.Size = UDim2.new(1, 0, 0.4, 0)
    resultText.Position = UDim2.new(0, 0, 0.5, 0)
    resultText.BackgroundTransparency = 1
    resultText.Text = ""
    resultText.TextColor3 = Color3.fromRGB(255, 255, 255)
    resultText.TextScaled = true
    resultText.Font = Enum.Font.FredokaOne
    resultText.ZIndex = 108
    resultText.TextStrokeTransparency = 0.8
    resultText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    resultText.Parent = resultFrame
    
    return animGui, animContainer, cube, cubeContainer, magicCircle, glowFrame, sparkleContainer, resultFrame, rarityBanner, rarityText, resultText, cubeGlow
end

function WishClient:_playWishAnimation(rarity, item)
    local playerGui = player:WaitForChild("PlayerGui")
    local rarityColor = RARITY_COLORS[rarity] or Color3.fromRGB(255, 255, 255)
    
    local animGui, animContainer, cube, cubeContainer, magicCircle, glowFrame, sparkleContainer, resultFrame, rarityBanner, rarityText, resultText, cubeGlow = self:_createAnimationGUI()
    
    animContainer.BackgroundTransparency = 1
    magicCircle.BackgroundTransparency = 1
    glowFrame.BackgroundTransparency = 1
    cubeContainer.Size = UDim2.new(0, 0, 0, 0)
    cubeContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
    resultFrame.Size = UDim2.new(0, 0, 0, 0)
    resultFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    cube.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    rarityText.Text = ""
    resultText.Text = ""
    
    task.spawn(function()
        task.wait(0.1)
        
        self:_playSound(SOUNDS.entrance, 0.6, 1.2)
        
        local circleAppear = TweenService:Create(magicCircle,
            TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.7, Size = UDim2.new(0, 500, 0, 500), Position = UDim2.new(0.5, -250, 0.5, -250)}
        )
        circleAppear:Play()
        
        task.wait(0.2)
        
        local glowAppear = TweenService:Create(glowFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.85}
        )
        glowAppear:Play()
        
        local cubeAppear = TweenService:Create(cubeContainer,
            TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 120, 0, 120), Position = UDim2.new(0.5, -60, 0.5, -60)}
        )
        cubeAppear:Play()
        
        task.wait(0.4)
        
        local spinningSound = self:_playSound(SOUNDS.spinning, 0.4, 1)
        spinningSound.Looped = true
        
        local spinTween = TweenService:Create(cubeContainer,
            TweenInfo.new(2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
            {Rotation = 360}
        )
        spinTween:Play()
        
        local circleRotate = TweenService:Create(magicCircle,
            TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
            {Rotation = -360}
        )
        circleRotate:Play()
        
        task.spawn(function()
            for i = 1, 8 do
                TweenService:Create(glowFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0.6}):Play()
                task.wait(0.3)
                TweenService:Create(glowFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0.9}):Play()
                task.wait(0.3)
            end
        end)
        
        local coloringActive = true
        task.spawn(function()
            local rarityOrder = {"common", "rare", "epic", "legendary"}
            local colorCycles = 15
            
            for cycle = 1, colorCycles do
                if not coloringActive then break end
                for _, currentRarity in pairs(rarityOrder) do
                    if not coloringActive then break end
                    local currentColor = RARITY_COLORS[currentRarity]
                    cube.BackgroundColor3 = currentColor
                    cubeGlow.Color = currentColor
                    TweenService:Create(cubeGlow, TweenInfo.new(0.1), {Thickness = math.random(2, 6)}):Play()
                    
                    local cycleSpeed = 0.05 + (cycle / colorCycles) * 0.1
                    task.wait(cycleSpeed)
                end
            end
            
            for i = 1, 3 do
                if not coloringActive then break end
                for _, currentRarity in pairs(rarityOrder) do
                    if not coloringActive then break end
                    local currentColor = RARITY_COLORS[currentRarity]
                    cube.BackgroundColor3 = currentColor
                    cubeGlow.Color = currentColor
                    TweenService:Create(cubeGlow, TweenInfo.new(0.2), {Thickness = math.random(4, 8)}):Play()
                    task.wait(0.2)
                end
            end
            
            coloringActive = false
        end)
        
        task.spawn(function()
            for i = 1, 50 do
                self:_createSparkle(sparkleContainer, rarityColor, math.random(3, 8))
                if i % 10 == 0 then
                    self:_playSound(SOUNDS.sparkles, 0.2, math.random(80, 120) / 100)
                end
                task.wait(0.05)
            end
        end)
        
        task.wait(2.5)
        
        spinTween:Cancel()
        circleRotate:Cancel()
        spinningSound:Stop()
        coloringActive = false
        
        self:_playSound(SOUNDS.reveal, 0.8, 0.9)
        
        local finalGlow = TweenService:Create(cubeGlow,
            TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {Thickness = 15, Transparency = 0.2}
        )
        finalGlow:Play()
        
        local flashFrame = Instance.new("Frame")
        flashFrame.Size = UDim2.new(1, 0, 1, 0)
        flashFrame.Position = UDim2.new(0, 0, 0, 0)
        flashFrame.BackgroundColor3 = rarityColor
        flashFrame.BackgroundTransparency = 1
        flashFrame.ZIndex = 110
        flashFrame.Parent = animGui
        
        local flash = TweenService:Create(flashFrame,
            TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.7}
        )
        flash:Play()
        
        task.wait(0.1)
        
        local raritySound = SOUNDS[rarity] or SOUNDS.common
        self:_playSound(raritySound, 0.7, 1)
        
        local flashOut = TweenService:Create(flashFrame,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 1}
        )
        flashOut:Play()
        
        cube.BackgroundColor3 = rarityColor
        cubeGlow.Color = rarityColor
        
        local impactPulse = TweenService:Create(cubeContainer,
            TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 140, 0, 140), Position = UDim2.new(0.5, -70, 0.5, -70)}
        )
        impactPulse:Play()
        
        task.wait(0.15)
        
        local cubeReturn = TweenService:Create(cubeContainer,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 120, 0, 120), Position = UDim2.new(0.5, -60, 0.5, -60)}
        )
        cubeReturn:Play()
        
        task.wait(0.1)
        
        local circleColorTween = TweenService:Create(magicCircle,
            TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {BackgroundColor3 = rarityColor}
        )
        circleColorTween:Play()
        
        task.wait(0.2)
        
        local glowColorTween = TweenService:Create(glowFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundColor3 = rarityColor}
        )
        glowColorTween:Play()
        
        task.wait(0.3)
        
        local cubeTransform = TweenService:Create(cubeContainer,
            TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.3, 0)}
        )
        cubeTransform:Play()
        
        task.wait(0.3)
        
        rarityBanner.BackgroundColor3 = rarityColor
        local resultAppear = TweenService:Create(resultFrame,
            TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 500, 0, 300), Position = UDim2.new(0.5, -250, 0.5, -150)}
        )
        resultAppear:Play()
        
        task.wait(0.3)
        rarityText.Text = string.upper(rarity)
        rarityText.TextColor3 = Color3.fromRGB(255, 255, 255)
        
        resultText.Text = item
        resultText.TextColor3 = rarityColor
        
        self:_playSound(SOUNDS.celebration, 0.6, 1)
        
        task.spawn(function()
            for i = 1, 100 do
                self:_createSparkle(sparkleContainer, rarityColor, math.random(5, 15))
                self:_createSparkle(sparkleContainer, Color3.fromRGB(255, 255, 255), math.random(2, 8))
                if i % 5 == 0 then
                    self:_playSound(SOUNDS.sparkles, 0.15, math.random(80, 120) / 100)
                end
                task.wait(0.02)
            end
        end)
        
        for i = 1, 5 do
            local pulseScale = 1 + (i * 0.05)
            local pulseIn = TweenService:Create(resultFrame,
                TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Size = UDim2.new(0, 500 * pulseScale, 0, 300 * pulseScale), Position = UDim2.new(0.5, -250 * pulseScale, 0.5, -150 * pulseScale)}
            )
            pulseIn:Play()
            pulseIn.Completed:Wait()
            
            local pulseOut = TweenService:Create(resultFrame,
                TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Size = UDim2.new(0, 500, 0, 300), Position = UDim2.new(0.5, -250, 0.5, -150)}
            )
            pulseOut:Play()
            pulseOut.Completed:Wait()
            task.wait(0.1)
        end
        
        local circleExpand = TweenService:Create(magicCircle,
            TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 800, 0, 800), Position = UDim2.new(0.5, -400, 0.5, -400), BackgroundTransparency = 1}
        )
        circleExpand:Play()
        
        task.wait(1.5)
        
        local sparklesFade = TweenService:Create(sparkleContainer,
            TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}
        )
        sparklesFade:Play()
        
        task.wait(0.3)
        
        local resultShrink = TweenService:Create(resultFrame,
            TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.In),
            {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}
        )
        resultShrink:Play()
        
        local glowFade = TweenService:Create(glowFrame,
            TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 1}
        )
        glowFade:Play()
        
        task.wait(0.5)
        
        for _, child in pairs(animGui:GetDescendants()) do
            if child:IsA("GuiObject") then
                local tweenProperties = {}
                
                if child.BackgroundTransparency then
                    tweenProperties.BackgroundTransparency = 1
                end
                if child:IsA("TextLabel") or child:IsA("TextButton") then
                    tweenProperties.TextTransparency = 1
                end
                if child:IsA("ImageLabel") or child:IsA("ImageButton") then
                    tweenProperties.ImageTransparency = 1
                end
                
                if next(tweenProperties) then
                    TweenService:Create(child, TweenInfo.new(0.5), tweenProperties):Play()
                end
            end
        end
        
        task.wait(0.5)
        animGui:Destroy()
    end)
end

function WishClient:_updateInventoryDisplay()
    Logger:Debug(string.format("Updating inventory display with %d items", self._inventory and #self._inventory or 0))
end

function WishClient:Cleanup()
    Logger:Info("WishClient shutting down...")
    
    for _, connection in pairs(self._connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    self._uiElements = {}
    
    Logger:Info("✓ WishClient shutdown complete")
end

return WishClient