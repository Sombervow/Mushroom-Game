local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local OfflineEarningsClient = {}
OfflineEarningsClient.__index = OfflineEarningsClient

-- Sound Configuration
local SOUND_CONFIG = {
    SLIDE_DOWN_ID = "rbxassetid://115499965016769",
    MONEY_COUNT_ID = "rbxassetid://71535048133820",
    BUTTON_CLICK_ID = "rbxassetid://130887017380626"
}

function OfflineEarningsClient.new()
    local self = setmetatable({}, OfflineEarningsClient)
    
    self.player = Players.LocalPlayer
    self.playerGui = self.player:WaitForChild("PlayerGui")
    
    -- Reference to existing UI elements
    self.offlineEarningsGui = nil
    self.container = nil
    self.amountBackground = nil
    self.claimSpores = nil
    self.doubleSpores = nil
    self.youEarned = nil
    self.whileAway = nil
    self.amountEarned = nil
    self.claimAmount = nil
    
    self.currentOfflineEarnings = 0
    self.isAnimating = false
    self.gamepassService = nil -- Will be set externally
    self.dailyRewardClient = nil -- Will be set externally
    self.soundsLoaded = false
    self.loadingScreenService = nil -- Will be set externally
    
    self:_initialize()
    return self
end

function OfflineEarningsClient:_initialize()
    Logger:Info("OfflineEarningsClient initializing...")
    
    self:_findExistingUI()
    self:_setupDoubleSporesButton()
    self:_setupRemoteEvents()
    self:_preloadSounds()
    
    Logger:Info("✓ OfflineEarningsClient initialized")
end

function OfflineEarningsClient:_findExistingUI()
    -- Find the existing OfflineEarnings ScreenGui
    self.offlineEarningsGui = self.playerGui:FindFirstChild("OfflineEarnings")
    
    if not self.offlineEarningsGui then
        Logger:Error("OfflineEarnings ScreenGui not found in StarterGui!")
        return
    end
    
    -- Find existing UI elements
    self.container = self.offlineEarningsGui:FindFirstChild("Container")
    
    if self.container then
        self.amountBackground = self.container:FindFirstChild("AmountBackground")
        self.claimSpores = self.container:FindFirstChild("ClaimSpores")
        self.youEarned = self.container:FindFirstChild("YouEarned")
        self.whileAway = self.container:FindFirstChild("WhileAway")
        
        if self.amountBackground then
            self.amountEarned = self.amountBackground:FindFirstChild("AmountEarned")
        end
        
        if self.claimSpores then
            self.claimAmount = self.claimSpores:FindFirstChild("ClaimAmount")
        end
    end
    
    -- Initially hide the GUI
    if self.offlineEarningsGui then
        self.offlineEarningsGui.Enabled = false
    end
    
    Logger:Info("✓ Found existing OfflineEarnings UI structure")
end

function OfflineEarningsClient:_setupDoubleSporesButton()
    if not self.container then return end
    
    -- Create DoubleSpores button if it doesn't exist
    self.doubleSpores = self.container:FindFirstChild("DoubleSpores")
    if not self.doubleSpores then
        -- Create DoubleSpores button next to ClaimSpores
        self.doubleSpores = Instance.new("TextButton")
        self.doubleSpores.Name = "DoubleSpores"
        self.doubleSpores.Size = self.claimSpores and self.claimSpores.Size or UDim2.new(0, 150, 0, 40)
        
        if self.claimSpores then
            -- Position it next to ClaimSpores
            local claimPos = self.claimSpores.Position
            self.doubleSpores.Position = UDim2.new(claimPos.X.Scale + 0.3, claimPos.X.Offset, claimPos.Y.Scale, claimPos.Y.Offset)
        else
            self.doubleSpores.Position = UDim2.new(0.7, -75, 1, -60)
        end
        
        self.doubleSpores.BackgroundColor3 = Color3.new(0.8, 0.6, 0)
        self.doubleSpores.BorderSizePixel = 0
        self.doubleSpores.Visible = false -- Start invisible
        self.doubleSpores.Parent = self.container
        
        -- Add corner rounding if ClaimSpores has it
        if self.claimSpores and self.claimSpores:FindFirstChild("UICorner") then
            local corner = Instance.new("UICorner")
            corner.CornerRadius = self.claimSpores.UICorner.CornerRadius
            corner.Parent = self.doubleSpores
        end
        
        -- Add text label
        local doubleText = Instance.new("TextLabel")
        doubleText.Name = "ClaimAmount"
        doubleText.Size = UDim2.new(1, 0, 1, 0)
        doubleText.Position = UDim2.new(0, 0, 0, 0)
        doubleText.BackgroundTransparency = 1
        doubleText.Text = "Claim Double (2x)"
        doubleText.TextColor3 = Color3.new(1, 1, 1)
        doubleText.TextScaled = true
        doubleText.Font = Enum.Font.GothamBold
        doubleText.Parent = self.doubleSpores
        
        Logger:Info("✓ Created DoubleSpores button")
    end
    
    self:_setupButtonConnections()
end

function OfflineEarningsClient:_setupRemoteEvents()
    -- Wait for remote events to be created
    local remoteEvents = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteEvents", 10)
    if remoteEvents then
        local showOfflineEarnings = remoteEvents:WaitForChild("ShowOfflineEarnings", 5)
        if showOfflineEarnings then
            showOfflineEarnings.OnClientEvent:Connect(function(offlineTime, earningsPerSecond)
                self:ShowOfflineEarnings(offlineTime, earningsPerSecond)
            end)
        end
    end
end

function OfflineEarningsClient:_preloadSounds()
    Logger:Info("Preloading offline earnings sounds...")
    
    local soundAssets = {
        SOUND_CONFIG.SLIDE_DOWN_ID,
        SOUND_CONFIG.MONEY_COUNT_ID,
        SOUND_CONFIG.BUTTON_CLICK_ID
    }
    
    -- Remove duplicates (MONEY_COUNT_ID and BUTTON_CLICK_ID are the same)
    local uniqueAssets = {}
    local seen = {}
    for _, asset in ipairs(soundAssets) do
        if not seen[asset] then
            seen[asset] = true
            table.insert(uniqueAssets, asset)
        end
    end
    
    spawn(function()
        local success, error = pcall(function()
            ContentProvider:PreloadAsync(uniqueAssets)
        end)
        
        if success then
            Logger:Info("✓ Offline earnings sounds preloaded successfully")
        else
            Logger:Warn("⚠ Failed to preload some sounds: " .. tostring(error))
        end
        
        self.soundsLoaded = true
    end)
end

function OfflineEarningsClient:_setupButtonConnections()
    -- Claim button connection
    if self.claimSpores then
        self.claimSpores.Activated:Connect(function()
            if not self.isAnimating then
                -- If offline earnings GUI is not active or no earnings, open daily rewards instead
                if not self.offlineEarningsGui.Enabled or self.currentOfflineEarnings <= 0 then
                    self:_openDailyRewardsInstead()
                else
                    self:ClaimEarnings(false)
                end
            end
        end)
    end
    
    -- Double button connection  
    if self.doubleSpores then
        self.doubleSpores.Activated:Connect(function()
            if not self.isAnimating then
                self:HandleDoublePurchase()
            end
        end)
    end
end

function OfflineEarningsClient:ShowOfflineEarnings(offlineTime, earningsPerSecond)
    if self.isAnimating or not self.offlineEarningsGui then return end
    
    -- Wait for loading screen to complete before showing
    if self.loadingScreenService and not self.loadingScreenService:IsComplete() then
        Logger:Info("Delaying offline earnings until loading screen completes...")
        self.loadingScreenService:OnLoadingComplete(function()
            task.wait(1) -- Additional delay after loading completes
            self:ShowOfflineEarnings(offlineTime, earningsPerSecond)
        end)
        return
    end
    
    self.isAnimating = true
    self.currentOfflineEarnings = math.floor(offlineTime * earningsPerSecond)
    
    Logger:Info(string.format("Showing offline earnings: %d spores for %d seconds offline", self.currentOfflineEarnings, offlineTime))
    
    -- IMMEDIATELY cancel daily rewards auto-open since offline earnings are being shown
    if self.dailyRewardClient and self.dailyRewardClient.CancelAutoOpen then
        self.dailyRewardClient:CancelAutoOpen()
        Logger:Info("✓ Daily rewards auto-open cancelled due to offline earnings")
    end
    
    -- Enable the GUI and wait for sounds to load before starting animation
    self.offlineEarningsGui.Enabled = true
    self:_resetUIPositions()
    
    -- Wait for sounds to load before starting animations
    self:_waitForSoundsAndAnimate()
end

function OfflineEarningsClient:_waitForSoundsAndAnimate()
    -- Wait for sounds to load with a timeout
    local maxWaitTime = 3.0 -- Maximum 3 seconds to wait for sounds
    local startTime = tick()
    
    local function checkAndStart()
        if self.soundsLoaded or (tick() - startTime) >= maxWaitTime then
            if not self.soundsLoaded then
                Logger:Warn("⚠ Starting offline earnings animation without all sounds loaded (timeout)")
            else
                Logger:Info("✓ Sounds loaded, starting offline earnings animation")
            end
            self:_animateSequence()
        else
            -- Check again in 0.1 seconds
            task.wait(0.1)
            checkAndStart()
        end
    end
    
    spawn(checkAndStart)
end

function OfflineEarningsClient:_resetUIPositions()
    -- Reset Container to invisible
    if self.container then
        self.container.BackgroundTransparency = 1
    end
    
    -- Reset AmountBackground to top of screen (changed from bottom)
    if self.amountBackground then
        self.amountBackground.Position = UDim2.new(0.5, -self.amountBackground.Size.X.Offset/2, -0.5, 0)
    end
    
    -- Hide buttons
    if self.claimSpores then
        self.claimSpores.Visible = false
    end
    if self.doubleSpores then
        self.doubleSpores.Visible = false
    end
    
    -- Reset amount text
    if self.amountEarned then
        self.amountEarned.Text = "$0"
    end
end

function OfflineEarningsClient:_animateSequence()
    -- Play slide down sound early before any animations
    self:_playSlideDownSound()
    
    -- Wait 0.5 seconds before starting animations
    task.wait(0.5)
    
    -- 1. Fade in Container (darkened background)
    if self.container then
        local containerFadeIn = TweenService:Create(
            self.container,
            TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.5}
        )
        
        containerFadeIn:Play()
        
        containerFadeIn.Completed:Connect(function()
            self:_slideInAmountBackground()
        end)
    else
        self:_slideInAmountBackground()
    end
end

function OfflineEarningsClient:_slideInAmountBackground()
    -- 2. Bouncy slide AmountBackground from top to center
    if self.amountBackground then
        local targetPos = UDim2.new(0.5, -self.amountBackground.Size.X.Offset/2, 0.5, -self.amountBackground.Size.Y.Offset/2)
        
        local slideIn = TweenService:Create(
            self.amountBackground,
            TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Position = targetPos}
        )
        
        slideIn:Play()
        
        slideIn.Completed:Connect(function()
            self:_animateCountUp()
        end)
    else
        self:_animateCountUp()
    end
end

function OfflineEarningsClient:_animateCountUp()
    -- 3. Count up AmountEarned from 0 to earned amount
    if not self.amountEarned then
        self:_animateClaimButton()
        return
    end
    
    -- Start playing counting sound immediately before animation starts
    spawn(function()
        local soundStartTime = tick()
        local soundInterval = 0.08
        local lastSoundTime = -1
        local activeSounds = {}
        
        -- Play sounds for the entire duration + a bit extra
        while tick() - soundStartTime < 3.0 do
            local elapsed = tick() - soundStartTime
            local progress = math.min(elapsed / 2.0, 1) -- Match the 2 second duration
            
            if elapsed - lastSoundTime >= soundInterval and progress < 0.95 then
                local sound = self:_playCountingSound(progress)
                if sound then
                    table.insert(activeSounds, sound)
                end
                lastSoundTime = elapsed
            end
            
            task.wait()
        end
        
        -- Clean up any remaining sounds
        for _, sound in ipairs(activeSounds) do
            if sound and sound.Parent then
                sound:Stop()
                sound:Destroy()
            end
        end
    end)
    
    local duration = 2.0
    local startTime = tick()
    local startValue = 0
    local targetValue = self.currentOfflineEarnings
    
    local connection
    connection = RunService.Heartbeat:Connect(function()
        local elapsed = tick() - startTime
        local progress = math.min(elapsed / duration, 1)
        
        -- Ease out the counting
        local easedProgress = 1 - math.pow(1 - progress, 3)
        local currentValue = math.floor(startValue + (targetValue - startValue) * easedProgress)
        
        self.amountEarned.Text = self:_formatCurrency(currentValue)
        
        if progress >= 1 then
            connection:Disconnect()
            self.amountEarned.Text = self:_formatCurrency(targetValue)
            self:_animateClaimButton()
        end
    end)
end

function OfflineEarningsClient:_animateClaimButton()
    -- 4. Animate ClaimSpores button (slide up from bottom) - NOT grow animation
    if self.claimSpores and self.claimAmount then
        self.claimAmount.Text = "Claim (" .. self:_formatCurrency(self.currentOfflineEarnings) .. ")"
        
        -- Store the original position and setup slide animation
        local originalPos = self.claimSpores.Position
        local centeredPos = UDim2.new(0.5, -75, originalPos.Y.Scale, originalPos.Y.Offset) -- Center horizontally
        
        -- Ensure button is fully visible and normal size (no grow effect)
        self.claimSpores.Size = self.claimSpores.Size -- Keep original size
        self.claimSpores.BackgroundTransparency = 0 -- Fully visible
        
        -- Make sure all text is visible
        for _, child in pairs(self.claimSpores:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                child.TextTransparency = 0
            elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
                child.ImageTransparency = 0
            end
        end
        
        -- Start the button off-screen at the bottom
        local startPos = UDim2.new(0.5, -75, 1.2, 0) -- Well below the screen
        self.claimSpores.Position = startPos
        self.claimSpores.Visible = true
        
        -- Play button sound and wait before animation
        self:_playButtonSound()
        task.wait(0.5)
        
        -- Slide up from bottom to center with bouncy animation
        local slideUpTween = TweenService:Create(
            self.claimSpores,
            TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Position = centeredPos}
        )
        
        slideUpTween:Play()
        slideUpTween.Completed:Connect(function()
            self:_animateDoubleButtonWithPush(originalPos)
        end)
    else
        self:_animateDoubleButton()
    end
end

function OfflineEarningsClient:_animateDoubleButtonWithPush(claimOriginalPos)
    -- 5. Animate DoubleSpores button while pushing ClaimSpores to its final position
    if self.doubleSpores and self.claimSpores then
        local doubleText = self.doubleSpores:FindFirstChild("ClaimAmount")
        if doubleText then
            doubleText.Text = "Claim " .. self:_formatCurrency(self.currentOfflineEarnings * 2) .. " (2x)"
        end
        
        -- Start DoubleSpores animation and ClaimSpores push simultaneously
        local doubleGrowTween = self:_createButtonGrowTween(self.doubleSpores)
        local claimPushTween = TweenService:Create(
            self.claimSpores,
            TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Position = claimOriginalPos}
        )
        
        -- Play button sound and wait before animation
        self:_playButtonSound()
        task.wait(0.5)
        
        -- Start both animations at the same time
        doubleGrowTween:Play()
        claimPushTween:Play()
        
        doubleGrowTween.Completed:Connect(function()
            self.isAnimating = false
        end)
    else
        self:_animateDoubleButton()
    end
end

function OfflineEarningsClient:_animateDoubleButton()
    -- Fallback if ClaimSpores doesn't exist
    if self.doubleSpores then
        local doubleText = self.doubleSpores:FindFirstChild("ClaimAmount")
        if doubleText then
            doubleText.Text = "Claim " .. self:_formatCurrency(self.currentOfflineEarnings * 2) .. " (2x)"
        end
        
        self:_animateButtonGrow(self.doubleSpores, function()
            self.isAnimating = false
        end)
    else
        self.isAnimating = false
    end
end

function OfflineEarningsClient:_createButtonGrowTween(button)
    -- Make button and all children completely invisible initially
    button.Visible = true
    button.BackgroundTransparency = 1
    
    -- Make all child elements invisible (only text and images, not backgrounds)
    for _, child in pairs(button:GetDescendants()) do
        if child:IsA("TextLabel") or child:IsA("TextButton") then
            child.TextTransparency = 1
        elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
            child.ImageTransparency = 1
        end
    end
    
    local originalSize = button.Size
    button.Size = UDim2.new(0, 0, 0, 0) -- Start at 0 size
    
    -- Create size tween
    local sizeTween = TweenService:Create(
        button,
        TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = originalSize}
    )
    
    -- Create transparency tween for the button itself
    local buttonTransparencyTween = TweenService:Create(
        button,
        TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0}
    )
    
    -- Create transparency tweens for text and images only
    local childTweens = {}
    for _, child in pairs(button:GetDescendants()) do
        local targetProps = {}
        if (child:IsA("TextLabel") or child:IsA("TextButton")) and child.TextTransparency == 1 then
            targetProps.TextTransparency = 0
        elseif (child:IsA("ImageLabel") or child:IsA("ImageButton")) and child.ImageTransparency == 1 then
            targetProps.ImageTransparency = 0
        end
        
        if next(targetProps) then
            local childTween = TweenService:Create(
                child,
                TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                targetProps
            )
            table.insert(childTweens, childTween)
        end
    end
    
    -- Play all tweens together
    sizeTween:Play()
    buttonTransparencyTween:Play()
    for _, tween in pairs(childTweens) do
        tween:Play()
    end
    
    return sizeTween -- Return the main size tween for completion tracking
end

function OfflineEarningsClient:_animateButtonGrow(button, callback)
    local growTween = self:_createButtonGrowTween(button)
    growTween:Play()
    
    if callback then
        growTween.Completed:Connect(callback)
    end
end

function OfflineEarningsClient:_formatCurrency(amount)
    if amount >= 1000000 then
        return string.format("$%.1fM", amount / 1000000)
    elseif amount >= 1000 then
        return string.format("$%.1fK", amount / 1000)
    else
        return string.format("$%d", amount)
    end
end

function OfflineEarningsClient:ClaimEarnings(doubled)
    self.isAnimating = true
    
    local amount = doubled and (self.currentOfflineEarnings * 2) or self.currentOfflineEarnings
    
    -- Send claim request to server
    local remoteEvents = ReplicatedStorage.Shared.RemoteEvents
    local claimOfflineEarnings = remoteEvents:FindFirstChild("ClaimOfflineEarnings")
    if claimOfflineEarnings then
        claimOfflineEarnings:FireServer(amount)
    end
    
    Logger:Info(string.format("Claiming offline earnings: %d spores", amount))
    
    -- Animate UI closing
    self:_animateClose()
end

function OfflineEarningsClient:HandleDoublePurchase()
    if not self.gamepassService then
        Logger:Error("GamepassService not available for offline earnings double purchase")
        return
    end
    
    -- Use GamepassService to handle the dev product purchase
    self.gamepassService:PurchaseProduct("DOUBLE_OFFLINE_EARNINGS", 
        function()
            -- On success - claim doubled earnings
            self:ClaimEarnings(true)
        end,
        function(error)
            -- On failure
            Logger:Warn("Double offline earnings purchase failed: " .. tostring(error))
        end
    )
end

function OfflineEarningsClient:SetGamepassService(gamepassService)
    self.gamepassService = gamepassService
end

function OfflineEarningsClient:SetDailyRewardClient(dailyRewardClient)
    self.dailyRewardClient = dailyRewardClient
end

function OfflineEarningsClient:SetLoadingScreenService(loadingScreenService)
    self.loadingScreenService = loadingScreenService
end

function OfflineEarningsClient:_openDailyRewardsInstead()
    Logger:Info("Offline earnings button clicked but no earnings - opening daily rewards instead")
    
    if self.dailyRewardClient then
        self.dailyRewardClient:OpenDailyRewards()
    else
        Logger:Warn("DailyRewardClient not available - cannot open daily rewards")
    end
end

function OfflineEarningsClient:_animateClose()
    -- Slide AmountBackground up off screen and fade out container
    if self.amountBackground then
        local slideOut = TweenService:Create(
            self.amountBackground,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {Position = UDim2.new(0.5, -self.amountBackground.Size.X.Offset/2, -0.5, 0)}
        )
        
        slideOut:Play()
        
        slideOut.Completed:Connect(function()
            -- Fade out Container after AmountBackground slides out
            if self.container then
                local fadeOut = TweenService:Create(
                    self.container,
                    TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                    {BackgroundTransparency = 1}
                )
                fadeOut:Play()
                fadeOut.Completed:Connect(function()
                    self.offlineEarningsGui.Enabled = false
                    self.isAnimating = false
                    
                    -- Reset daily rewards cancellation and open after offline earnings are claimed
                    if self.dailyRewardClient then
                        -- Reset the cancellation flag
                        if self.dailyRewardClient.ResetAutoOpenCancellation then
                            self.dailyRewardClient:ResetAutoOpenCancellation()
                        end
                        
                        task.spawn(function()
                            task.wait(0.5) -- Small delay for smooth transition
                            self.dailyRewardClient:OpenDailyRewards()
                        end)
                    end
                end)
            else
                self.offlineEarningsGui.Enabled = false
                self.isAnimating = false
                
                -- Reset daily rewards cancellation for fallback case too
                if self.dailyRewardClient and self.dailyRewardClient.ResetAutoOpenCancellation then
                    self.dailyRewardClient:ResetAutoOpenCancellation()
                    
                    task.spawn(function()
                        task.wait(0.5)
                        self.dailyRewardClient:OpenDailyRewards()
                    end)
                end
            end
        end)
    else
        -- Fallback if no AmountBackground
        if self.container then
            local fadeOut = TweenService:Create(
                self.container,
                TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                {BackgroundTransparency = 1}
            )
            fadeOut:Play()
            fadeOut.Completed:Connect(function()
                self.offlineEarningsGui.Enabled = false
                self.isAnimating = false
                
                -- Reset daily rewards cancellation for final fallback case
                if self.dailyRewardClient and self.dailyRewardClient.ResetAutoOpenCancellation then
                    self.dailyRewardClient:ResetAutoOpenCancellation()
                    
                    task.spawn(function()
                        task.wait(0.5)
                        self.dailyRewardClient:OpenDailyRewards()
                    end)
                end
            end)
        else
            self.offlineEarningsGui.Enabled = false
            self.isAnimating = false
            
            -- Reset daily rewards cancellation for ultimate fallback case
            if self.dailyRewardClient and self.dailyRewardClient.ResetAutoOpenCancellation then
                self.dailyRewardClient:ResetAutoOpenCancellation()
                
                task.spawn(function()
                    task.wait(0.5)
                    self.dailyRewardClient:OpenDailyRewards()
                end)
            end
        end
    end
end

function OfflineEarningsClient:_playSlideDownSound()
    local sound = Instance.new("Sound")
    sound.SoundId = SOUND_CONFIG.SLIDE_DOWN_ID
    sound.Volume = 0.6
    sound.PlaybackSpeed = 1.0
    sound.Parent = SoundService
    sound:Play()
    
    -- Cleanup after playback
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
    game:GetService("Debris"):AddItem(sound, 3)
end

function OfflineEarningsClient:_playCountingSound(progress)
    local sound = Instance.new("Sound")
    sound.SoundId = SOUND_CONFIG.MONEY_COUNT_ID
    sound.Volume = 0.6 -- Increased volume for counting sound
    
    -- Increase pitch as counting progresses (0.8 to 1.4)
    local minPitch = 0.8
    local maxPitch = 1.4
    sound.PlaybackSpeed = minPitch + (maxPitch - minPitch) * progress
    
    sound.Parent = SoundService
    sound:Play()
    
    -- Cleanup after playback
    sound.Ended:Connect(function()
        if sound.Parent then
            sound:Destroy()
        end
    end)
    game:GetService("Debris"):AddItem(sound, 2)
    
    return sound -- Return the sound object so it can be tracked and stopped
end

function OfflineEarningsClient:_playButtonSound(delaySeconds)
    local delay = delaySeconds or 0
    
    local function playSound()
        local sound = Instance.new("Sound")
        sound.SoundId = SOUND_CONFIG.BUTTON_CLICK_ID
        sound.Volume = 0.8 -- Increased volume
        sound.PlaybackSpeed = 1.0
        sound.Parent = SoundService
        sound:Play()
        
        -- Cleanup after playback
        sound.Ended:Connect(function()
            sound:Destroy()
        end)
        game:GetService("Debris"):AddItem(sound, 3)
    end
    
    if delay > 0 then
        task.wait(delay)
        playSound()
    else
        playSound()
    end
end

function OfflineEarningsClient:Cleanup()
    if self.offlineEarningsGui then
        Logger:Info("OfflineEarningsClient cleaned up")
    end
end

return OfflineEarningsClient