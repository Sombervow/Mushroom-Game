local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local DailyRewardClient = {}
DailyRewardClient.__index = DailyRewardClient

function DailyRewardClient.new()
    local success, result = pcall(function()
        local self = setmetatable({}, DailyRewardClient)
        
        self.player = Players.LocalPlayer
        self.playerGui = self.player:WaitForChild("PlayerGui")
        self.connections = {}
        self.hoverTweens = {}
        self.timerConnection = nil
        self.currentTimer = nil
        self.dailyRewardsGui = nil
        self.uiManager = nil
        self.notificationClient = nil
        self.autoOpenCancelled = false -- Flag to prevent auto-open if offline earnings shown
        self.loadingScreenService = nil -- Will be set externally
        
        self:_initialize()
        return self
    end)
    
    if success then
        return result
    else
        Logger:Error("Failed to create DailyRewardClient: " .. tostring(result))
        -- Return a minimal object that won't break the system
        return setmetatable({
            SetUIManager = function() end,
            SetNotificationClient = function() end,
            OpenDailyRewards = function() end,
            Cleanup = function() end
        }, DailyRewardClient)
    end
end

function DailyRewardClient:_initialize()
    Logger:Info("DailyRewardClient starting initialization...")
    self:_setupRemoteEvents()
    self:_setupGUI()
    self:_startAutoOpenTimer()
    Logger:Info("DailyRewardClient initialized successfully")
end

function DailyRewardClient:_setupRemoteEvents()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared then
        local remoteEvents = shared:FindFirstChild("RemoteEvents")
        if remoteEvents then
            local dailyRewardEvents = remoteEvents:FindFirstChild("DailyRewardEvents")
            if dailyRewardEvents then
                local rewardClaimedEvent = dailyRewardEvents:FindFirstChild("RewardClaimed")
                if rewardClaimedEvent then
                    rewardClaimedEvent.OnClientEvent:Connect(function(day, rewards)
                        Logger:Info(string.format("Received RewardClaimed event for day %d", day))
                        self:_onRewardClaimed(day, rewards)
                    end)
                    Logger:Info("Connected to RewardClaimed RemoteEvent")
                else
                    Logger:Warn("RewardClaimed RemoteEvent not found during setup")
                end
            else
                Logger:Warn("DailyRewardEvents folder not found during setup")
            end
        end
    end
end

function DailyRewardClient:_setupGUI()
    task.spawn(function()
        task.wait(3) -- Increased wait time for GUI and server to load properly
        
        self.dailyRewardsGui = self.playerGui:FindFirstChild("DailyRewards")
        if not self.dailyRewardsGui then
            Logger:Warn("DailyRewards GUI not found")
            return
        end
        
        local container = self.dailyRewardsGui:FindFirstChild("Container")
        if not container then
            Logger:Warn("Container not found in DailyRewards")
            return
        end
        
        -- Setup exit button
        local exitBTN = container:FindFirstChild("ExitBTN")
        if exitBTN and exitBTN:IsA("GuiButton") then
            local exitConnection = exitBTN.MouseButton1Click:Connect(function()
                self:_closeDailyRewards()
            end)
            table.insert(self.connections, exitConnection)
        end
        
        -- Setup day buttons - iterate through all children to find DAY buttons
        local background = container:FindFirstChild("Background")
        if background then
            local scrollingFrame = background:FindFirstChild("ScrollingFrame")
            if scrollingFrame then
                -- Get all children and find DAY buttons
                for _, child in pairs(scrollingFrame:GetChildren()) do
                    if child:IsA("GuiButton") and string.match(child.Name, "^DAY%d+$") then
                        local dayNumber = tonumber(string.match(child.Name, "%d+"))
                        if dayNumber and dayNumber >= 1 and dayNumber <= 15 then
                            self:_setupDayButton(child, dayNumber)
                        end
                    end
                end
                Logger:Info("Day button setup complete")
            else
                Logger:Warn("ScrollingFrame not found in Background during setup")
            end
        else
            Logger:Warn("Background not found in Container during setup")
        end
        
        Logger:Info("DailyRewards GUI setup complete")
    end)
end

function DailyRewardClient:_startAutoOpenTimer()
    -- Auto-open daily rewards after 5 seconds if no offline earnings shown and tutorial not active
    task.spawn(function()
        task.wait(5)
        
        -- Check if auto-open was cancelled (by offline earnings showing)
        if self.autoOpenCancelled then
            Logger:Info("Auto-open daily rewards cancelled - offline earnings were shown")
            return
        end
        
        -- Check if tutorial is active
        if _G.TutorialSystem and _G.TutorialSystem.isActive and _G.TutorialSystem.isActive() then
            Logger:Info("Tutorial is active, skipping auto-open daily rewards")
            return
        end
        
        -- Check if offline earnings GUI is currently active
        local offlineEarningsGui = self.playerGui:FindFirstChild("OfflineEarnings")
        local isOfflineEarningsActive = offlineEarningsGui and offlineEarningsGui.Enabled
        
        if not isOfflineEarningsActive then
            Logger:Info("Auto-opening daily rewards after 5 seconds (no offline earnings, tutorial not active)")
            self:OpenDailyRewards()
        else
            Logger:Info("Offline earnings active, skipping auto-open daily rewards")
        end
    end)
end

function DailyRewardClient:CancelAutoOpen()
    -- Called by OfflineEarningsClient when offline earnings are shown
    self.autoOpenCancelled = true
    Logger:Info("Daily rewards auto-open cancelled - offline earnings are being shown")
end

function DailyRewardClient:ResetAutoOpenCancellation()
    -- Called to reset the cancellation flag so daily rewards can show later
    self.autoOpenCancelled = false
    Logger:Info("Daily rewards auto-open cancellation reset")
end

function DailyRewardClient:_setupDayButton(dayButton, dayNumber)
    -- Setup hover effects
    local originalSize = dayButton.Size
    
    local hoverInTween = TweenService:Create(
        dayButton,
        TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.new(originalSize.X.Scale * 1.05, originalSize.X.Offset, originalSize.Y.Scale * 1.05, originalSize.Y.Offset)}
    )
    
    local hoverOutTween = TweenService:Create(
        dayButton,
        TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = originalSize}
    )
    
    -- Mouse hover connections
    local mouseEnterConnection = dayButton.MouseEnter:Connect(function()
        if self.hoverTweens[dayButton] then
            self.hoverTweens[dayButton]:Cancel()
            self.hoverTweens[dayButton]:Destroy()
        end
        self.hoverTweens[dayButton] = hoverInTween
        hoverInTween:Play()
        hoverInTween.Completed:Connect(function()
            if self.hoverTweens[dayButton] == hoverInTween then
                self.hoverTweens[dayButton] = nil
            end
        end)
    end)
    
    local mouseLeaveConnection = dayButton.MouseLeave:Connect(function()
        if self.hoverTweens[dayButton] then
            self.hoverTweens[dayButton]:Cancel()
            self.hoverTweens[dayButton]:Destroy()
        end
        self.hoverTweens[dayButton] = hoverOutTween
        hoverOutTween:Play()
        hoverOutTween.Completed:Connect(function()
            if self.hoverTweens[dayButton] == hoverOutTween then
                self.hoverTweens[dayButton] = nil
            end
        end)
    end)
    
    -- Click connection
    local clickConnection = dayButton.MouseButton1Click:Connect(function()
        self:_onDayButtonClicked(dayNumber)
    end)
    
    table.insert(self.connections, mouseEnterConnection)
    table.insert(self.connections, mouseLeaveConnection)
    table.insert(self.connections, clickConnection)
end

function DailyRewardClient:_onDayButtonClicked(dayNumber)
    Logger:Info(string.format("Day %d button clicked by user", dayNumber))
    
    -- Only allow claiming if this is the current available day
    -- We should check this on the client side too for better UX
    
    -- Send claim request to server (server will validate)
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared then
        local remoteEvents = shared:FindFirstChild("RemoteEvents")
        if remoteEvents then
            local dailyRewardEvents = remoteEvents:FindFirstChild("DailyRewardEvents")
            if dailyRewardEvents then
                local claimRewardEvent = dailyRewardEvents:FindFirstChild("ClaimReward")
                if claimRewardEvent then
                    Logger:Info("Sending claim request to server...")
                    claimRewardEvent:FireServer()
                else
                    Logger:Warn("ClaimReward RemoteEvent not found")
                end
            else
                Logger:Warn("DailyRewardEvents folder not found")
            end
        else
            Logger:Warn("RemoteEvents folder not found")
        end
    else
        Logger:Warn("Shared folder not found")
    end
end

function DailyRewardClient:_onRewardClaimed(day, rewards)
    -- Create summary of rewards for logging
    local rewardSummary = {}
    for _, reward in ipairs(rewards) do
        table.insert(rewardSummary, string.format("%d %s", reward.amount, reward.type:gsub("_", " ")))
    end
    local summaryText = table.concat(rewardSummary, " + ")
    
    Logger:Info(string.format("Rewards claimed for day %d: %s - updating UI states", day, summaryText))
    
    -- First, immediately update the claimed day to "claimed" state
    Logger:Info(string.format("Setting day %d to claimed state", day))
    self:_updateDayButtonState(day, "claimed")
    
    -- Then refresh the entire UI to get the latest server state for next day
    task.spawn(function()
        task.wait(0.2) -- Small delay to see the claimed state first
        Logger:Info("Refreshing daily rewards UI to show next day state")
        self:RefreshDailyRewards()
    end)
end

function DailyRewardClient:_updateDayButtonState(dayNumber, state)
    if not self.dailyRewardsGui then 
        Logger:Warn("DailyRewards GUI not found in _updateDayButtonState")
        return 
    end
    
    local container = self.dailyRewardsGui:FindFirstChild("Container")
    if not container then 
        Logger:Warn("Container not found in DailyRewards GUI")
        return 
    end
    
    local background = container:FindFirstChild("Background")
    if not background then 
        Logger:Warn("Background not found in Container")
        return 
    end
    
    local scrollingFrame = background:FindFirstChild("ScrollingFrame")
    if not scrollingFrame then 
        Logger:Warn("ScrollingFrame not found in Background")
        return 
    end
    
    local dayButton = scrollingFrame:FindFirstChild("DAY" .. dayNumber)
    if not dayButton then 
        Logger:Warn(string.format("DAY%d button not found in ScrollingFrame", dayNumber))
        return 
    end
    
    local inactive = dayButton:FindFirstChild("Inactive")
    local claimText = dayButton:FindFirstChild("Claim")
    local claimed = inactive and inactive:FindFirstChild("Claimed")
    
    Logger:Info(string.format("Updating DAY%d to state '%s' - inactive: %s, claimText: %s, claimed: %s", 
        dayNumber, state, tostring(inactive ~= nil), tostring(claimText ~= nil), tostring(claimed ~= nil)))
    
    if state == "claimed" then
        -- Set button to claimed state
        Logger:Info(string.format("DAY%d: Setting claimed state", dayNumber))
        if inactive then 
            inactive.Visible = true
            Logger:Info(string.format("DAY%d: Set inactive to TRUE (claimed state)", dayNumber))
        end
        if claimText then 
            claimText.Text = "Claimed"
            claimText.TextColor3 = Color3.new(0, 1, 0) -- Green
            claimText.Visible = true
            Logger:Info(string.format("DAY%d: Set Claim text to 'Claimed' GREEN and visible", dayNumber))
        end
        if claimed then 
            claimed.Visible = true
            Logger:Info(string.format("DAY%d: Set Claimed image to TRUE", dayNumber))
        else
            Logger:Warn(string.format("DAY%d: Claimed image not found!", dayNumber))
        end
        
    elseif state == "available" then
        -- Set button to available state (current day, ready to claim)
        if inactive then 
            inactive.Visible = false
            Logger:Info(string.format("DAY%d: Set inactive to FALSE (available state)", dayNumber))
        end
        if claimText then 
            claimText.Text = "Claim"
            claimText.TextColor3 = Color3.new(1, 1, 1) -- White
            claimText.Visible = true
            Logger:Info(string.format("DAY%d: Set Claim text to visible WHITE", dayNumber))
        end
        if claimed then 
            claimed.Visible = false 
            Logger:Info(string.format("DAY%d: Set Claimed image to FALSE", dayNumber))
        end
        
    elseif state == "locked" then
        -- Set button to locked state
        if inactive then inactive.Visible = true end
        if claimText then claimText.Visible = false end
        if claimed then claimed.Visible = false end
        
    elseif state == "timer" then
        -- Set button to timer state (next day with countdown) - should be ACTIVE not inactive
        Logger:Info(string.format("DAY%d: Setting timer state", dayNumber))
        if inactive then 
            inactive.Visible = false  -- FALSE so button is active and shows countdown
            Logger:Info(string.format("DAY%d: Set inactive to FALSE (timer state - button should be active)", dayNumber))
        end
        if claimText then 
            claimText.TextColor3 = Color3.new(1, 1, 1) -- WHITE for timer countdown
            claimText.Visible = true
            claimText.Text = "Loading..."
            Logger:Info(string.format("DAY%d: Set Claim text to WHITE and visible for timer", dayNumber))
        end
        if claimed then 
            claimed.Visible = false
            Logger:Info(string.format("DAY%d: Set Claimed image to FALSE (timer state)", dayNumber))
        end
    end
end

function DailyRewardClient:RefreshDailyRewards()
    Logger:Info("RefreshDailyRewards called")
    
    -- Get daily reward data from server with retry logic
    self:_getDailyDataWithRetry(3) -- Retry up to 3 times
end

function DailyRewardClient:_getDailyDataWithRetry(maxRetries)
    maxRetries = maxRetries or 3
    
    local function attemptGetData(retryCount)
        -- Get daily reward data from server
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        if not shared then
            Logger:Warn("Shared folder not found in ReplicatedStorage")
            if retryCount < maxRetries then
                Logger:Info(string.format("Retrying in 1 second... (attempt %d/%d)", retryCount + 1, maxRetries))
                task.wait(1)
                attemptGetData(retryCount + 1)
            else
                Logger:Error("Failed to find Shared folder after all retries")
            end
            return
        end
        
        local remoteEvents = shared:FindFirstChild("RemoteEvents")
        if not remoteEvents then
            Logger:Warn("RemoteEvents not found in Shared")
            if retryCount < maxRetries then
                Logger:Info(string.format("Retrying in 1 second... (attempt %d/%d)", retryCount + 1, maxRetries))
                task.wait(1)
                attemptGetData(retryCount + 1)
            else
                Logger:Error("Failed to find RemoteEvents after all retries")
            end
            return
        end
        
        local dailyRewardEvents = remoteEvents:FindFirstChild("DailyRewardEvents")
        if not dailyRewardEvents then
            Logger:Warn("DailyRewardEvents not found in RemoteEvents")
            if retryCount < maxRetries then
                Logger:Info(string.format("Retrying in 1 second... (attempt %d/%d)", retryCount + 1, maxRetries))
                task.wait(1)
                attemptGetData(retryCount + 1)
            else
                Logger:Error("Failed to find DailyRewardEvents after all retries")
            end
            return
        end
        
        local getDailyDataEvent = dailyRewardEvents:FindFirstChild("GetDailyData")
        if not getDailyDataEvent then
            Logger:Warn("GetDailyData RemoteFunction not found")
            if retryCount < maxRetries then
                Logger:Info(string.format("Retrying in 1 second... (attempt %d/%d)", retryCount + 1, maxRetries))
                task.wait(1)
                attemptGetData(retryCount + 1)
            else
                Logger:Error("Failed to find GetDailyData RemoteFunction after all retries")
            end
            return
        end
        
        Logger:Info(string.format("Attempting to get daily reward data from server... (attempt %d/%d)", retryCount + 1, maxRetries))
        local success, dailyData = pcall(function()
            return getDailyDataEvent:InvokeServer()
        end)
        
        if success and dailyData then
            Logger:Info(string.format("✓ Received daily data - Current day: %d, Can claim: %s", 
                dailyData.currentDay, tostring(dailyData.canClaim)))
            self:_updateAllDayButtons(dailyData)
        else
            Logger:Warn(string.format("Failed to get daily reward data from server: %s", tostring(dailyData)))
            if retryCount < maxRetries then
                Logger:Info(string.format("Retrying in 2 seconds... (attempt %d/%d)", retryCount + 1, maxRetries))
                task.wait(2)
                attemptGetData(retryCount + 1)
            else
                Logger:Error("Failed to get daily reward data after all retries - setting all buttons to locked state")
                -- Fallback: Set all buttons to locked state rather than leaving them greyed out
                local fallbackData = {
                    currentDay = 1,
                    canClaim = false,
                    nextClaimTime = os.time() + (24 * 60 * 60),
                    claimedDays = {}
                }
                self:_updateAllDayButtons(fallbackData)
            end
        end
    end
    
    -- Start the retry process
    task.spawn(function()
        attemptGetData(0)
    end)
end

function DailyRewardClient:_updateAllDayButtons(dailyData)
    local currentDay = dailyData.currentDay
    local canClaim = dailyData.canClaim
    local nextClaimTime = dailyData.nextClaimTime
    local claimedDays = dailyData.claimedDays or {}
    
    Logger:Info(string.format("Updating day buttons - Current day: %d, Can claim: %s", currentDay, tostring(canClaim)))
    
    -- Stop existing timer if any
    if self.timerConnection then
        self.timerConnection:Disconnect()
        self.timerConnection = nil
    end
    
    for i = 1, 15 do
        if i == currentDay then
            if canClaim then
                Logger:Info(string.format("Day %d: AVAILABLE (current day, can claim)", i))
                self:_updateDayButtonState(i, "available")
            else
                -- Current day already claimed today - show as claimed
                Logger:Info(string.format("Day %d: CLAIMED (current day, already claimed today)", i))
                self:_updateDayButtonState(i, "claimed")
                
                -- Start timer on NEXT day if it exists
                local nextDay = (currentDay % 15) + 1
                Logger:Info(string.format("Day %d: TIMER (next day after claimed current day)", nextDay))
                self:_updateDayButtonState(nextDay, "timer")
                self:_startTimer(nextDay, nextClaimTime)
            end
        elseif claimedDays[i] then
            Logger:Info(string.format("Day %d: CLAIMED (completed in previous cycles)", i))
            self:_updateDayButtonState(i, "claimed")
        else
            -- Check if this is the next day after a claimed current day
            local nextDay = (currentDay % 15) + 1
            if i == nextDay and not canClaim then
                -- This will be handled in the currentDay logic above
                -- Skip to avoid double-processing
            else
                Logger:Info(string.format("Day %d: LOCKED (future day)", i))
                self:_updateDayButtonState(i, "locked")
            end
        end
    end
end

function DailyRewardClient:_startTimer(dayNumber, nextClaimTime)
    Logger:Info(string.format("Starting timer for day %d with nextClaimTime: %d", dayNumber, nextClaimTime))
    
    if self.timerConnection then
        self.timerConnection:Disconnect()
    end
    
    -- Calculate next claim time (tomorrow at same time)
    if nextClaimTime == 0 then
        nextClaimTime = os.time() + (24 * 60 * 60) -- 24 hours from now
        Logger:Info(string.format("Calculated nextClaimTime as %d (24 hours from now)", nextClaimTime))
    end
    
    self.timerConnection = RunService.Heartbeat:Connect(function()
        local currentTime = os.time()
        local timeLeft = nextClaimTime - currentTime
        
        if timeLeft <= 0 then
            -- Timer finished, refresh UI
            Logger:Info(string.format("Timer finished for day %d, refreshing UI", dayNumber))
            self.timerConnection:Disconnect()
            self.timerConnection = nil
            self:RefreshDailyRewards()
            return
        end
        
        -- Update timer display
        local hours = math.floor(timeLeft / 3600)
        local minutes = math.floor((timeLeft % 3600) / 60)
        local seconds = timeLeft % 60
        
        local timerText = string.format("%02d:%02d:%02d", hours, minutes, seconds)
        
        if self.dailyRewardsGui then
            local container = self.dailyRewardsGui:FindFirstChild("Container")
            if container then
                local background = container:FindFirstChild("Background")
                if background then
                    local scrollingFrame = background:FindFirstChild("ScrollingFrame")
                    if scrollingFrame then
                        local dayButton = scrollingFrame:FindFirstChild("DAY" .. dayNumber)
                        if dayButton then
                            local claimText = dayButton:FindFirstChild("Claim")
                            if claimText then
                                claimText.Text = timerText
                            end
                        end
                    end
                end
            end
        end
    end)
    
    -- Immediately verify UI path exists
    if self.dailyRewardsGui then
        local container = self.dailyRewardsGui:FindFirstChild("Container")
        if container then
            local background = container:FindFirstChild("Background")
            if background then
                local scrollingFrame = background:FindFirstChild("ScrollingFrame")
                if scrollingFrame then
                    local dayButton = scrollingFrame:FindFirstChild("DAY" .. dayNumber)
                    if dayButton then
                        local claimText = dayButton:FindFirstChild("Claim")
                        if claimText then
                            Logger:Info(string.format("DAY%d: Timer path verification SUCCESS - claimText found and current text is '%s'", dayNumber, claimText.Text))
                        else
                            Logger:Error(string.format("DAY%d: Timer path verification FAILED - claimText not found in dayButton", dayNumber))
                        end
                    else
                        Logger:Error(string.format("DAY%d: Timer path verification FAILED - dayButton not found in scrollingFrame", dayNumber))
                    end
                else
                    Logger:Error(string.format("DAY%d: Timer path verification FAILED - scrollingFrame not found in background", dayNumber))
                end
            else
                Logger:Error(string.format("DAY%d: Timer path verification FAILED - background not found in container", dayNumber))
            end
        else
            Logger:Error(string.format("DAY%d: Timer path verification FAILED - container not found in dailyRewardsGui", dayNumber))
        end
    else
        Logger:Error(string.format("DAY%d: Timer path verification FAILED - dailyRewardsGui is nil", dayNumber))
    end
    
    Logger:Info(string.format("Timer started for day %d", dayNumber))
end

function DailyRewardClient:OpenDailyRewards()
    if not self.dailyRewardsGui then
        Logger:Warn("DailyRewards GUI not found")
        return
    end
    
    -- Check if auto-open was cancelled (by offline earnings)
    if self.autoOpenCancelled then
        Logger:Info("Daily rewards auto-open was cancelled - not showing")
        return
    end
    
    -- Check if tutorial is active
    if _G.TutorialSystem and _G.TutorialSystem.isActive and _G.TutorialSystem.isActive() then
        Logger:Info("Tutorial is active, not showing daily rewards")
        return
    end
    
    -- Wait for loading screen to complete before showing
    if self.loadingScreenService and not self.loadingScreenService:IsComplete() then
        Logger:Info("Delaying daily rewards until loading screen completes...")
        self.loadingScreenService:OnLoadingComplete(function()
            task.wait(3) -- Longer delay to allow offline earnings to show first
            self:OpenDailyRewards()
        end)
        return
    end
    
    -- Get the Container for animation
    local container = self.dailyRewardsGui:FindFirstChild("Container")
    if not container then
        Logger:Warn("Container not found for animation")
        self.dailyRewardsGui.Enabled = true
        return
    end
    
    -- Enable GUI but start container scaled down
    self.dailyRewardsGui.Enabled = true
    container.Size = UDim2.new(0, 0, 0, 0) -- Start at 0 size
    container.AnchorPoint = Vector2.new(0.5, 0.5) -- Center anchor for scaling
    
    -- Animate container scaling up
    local openTween = TweenService:Create(
        container,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = UDim2.new(1, 0, 1, 0)} -- Scale to full size
    )
    
    openTween:Play()
    Logger:Info("Started opening animation for DailyRewards")
    
    -- Refresh data when opening with delay to ensure UI and server are ready
    task.spawn(function()
        task.wait(0.5) -- Longer delay to ensure server connection is established
        self:RefreshDailyRewards()
    end)
    
    -- Notify UIManager if available
    if self.uiManager then
        -- Add to UIManager's open UIs tracking
        self.uiManager.openUIs = self.uiManager.openUIs or {}
        self.uiManager.openUIs["DailyRewards"] = true
    end
    
    Logger:Info("Opened DailyRewards UI")
end

function DailyRewardClient:_closeDailyRewards()
    if not self.dailyRewardsGui then return end
    
    self.dailyRewardsGui.Enabled = false
    
    -- Stop timer if running
    if self.timerConnection then
        self.timerConnection:Disconnect()
        self.timerConnection = nil
    end
    
    -- Notify UIManager if available
    if self.uiManager and self.uiManager.openUIs then
        self.uiManager.openUIs["DailyRewards"] = nil
    end
    
    Logger:Info("Closed DailyRewards UI")
end

function DailyRewardClient:SetUIManager(uiManager)
    self.uiManager = uiManager
    
    -- Add DailyRewards to UI configs  
    if uiManager and uiManager._openUI then
        -- Create a method for UIManager to open daily rewards through this client
        uiManager.OpenDailyRewards = function()
            self:OpenDailyRewards()
        end
    end
    
    Logger:Debug("DailyRewardClient linked with UIManager")
end

function DailyRewardClient:SetNotificationClient(notificationClient)
    self.notificationClient = notificationClient
    Logger:Debug("DailyRewardClient linked with NotificationClient")
end

function DailyRewardClient:Cleanup()
    -- Stop timer
    if self.timerConnection then
        self.timerConnection:Disconnect()
        self.timerConnection = nil
    end
    
    -- Disconnect all connections
    for _, connection in pairs(self.connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    -- Cancel all hover tweens and destroy them
    for _, tween in pairs(self.hoverTweens) do
        if tween then
            tween:Cancel()
            tween:Destroy()
        end
    end
    
    self.connections = {}
    self.hoverTweens = {}
    
    Logger:Info("DailyRewardClient cleaned up")
end

function DailyRewardClient:SetLoadingScreenService(loadingScreenService)
    self.loadingScreenService = loadingScreenService
end

return DailyRewardClient