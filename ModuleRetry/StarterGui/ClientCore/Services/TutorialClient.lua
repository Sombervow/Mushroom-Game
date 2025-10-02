local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local TutorialClient = {}
TutorialClient.__index = TutorialClient

-- Tutorial Configuration
local TUTORIAL_STEPS = {
    {
        text = "Click Your Shroom 4 Times!",
        target = 4,
        progressText = "0/4",
        trackType = "mushroomClicks",
        hasProgress = true,
        beamTarget = "mushroom"
    },
    {
        text = "Collect 10 Spores!",
        target = 10,
        progressText = "0/10",
        trackType = "sporeCollection",
        hasProgress = true,
        beamTarget = "mushroom"
    },
    {
        text = "Upgrade Any Gem Boost Twice!",
        target = 2,
        progressText = "0/2",
        trackType = "gemBoostUpgrades",
        hasProgress = true,
        beamTarget = "gemShop"
    },
    {
        text = "Buy 4 Shrooms!",
        target = 4,
        progressText = "0/4",
        trackType = "mushroomPurchases",
        hasProgress = true,
        beamTarget = "sporeShop"
    },
    {
        text = "Upgrade Your Spore Level!",
        target = 1,
        progressText = "0/1",
        trackType = "sporeLevelUpgrades",
        hasProgress = true,
        beamTarget = "sporeShop"
    },
    {
        text = "Mushrooms earn while offline!",
        target = 1,
        progressText = "0/1",
        trackType = "autoComplete",
        hasProgress = true,
        autoCompleteTime = 4.0,  -- Increased from 1.5 to give more time to read
        beamTarget = "none"
    },
    {
        text = "Thank you for playing! Have Fun!",
        target = 1,
        progressText = "0/1",
        trackType = "autoComplete",
        hasProgress = true,
        autoCompleteTime = 5.0,  -- Increased from 2.0 to give more time to read
        beamTarget = "none"
    }
}

-- Animation Settings
local DROPDOWN_TIME = 0.6
local POPUP_TIME = 0.4
local PROGRESS_UPDATE_TIME = 0.3
local COMPLETION_DELAY = 1.5

function TutorialClient.new()
    local self = setmetatable({}, TutorialClient)
    
    self.player = Players.LocalPlayer
    self.playerGui = self.player:WaitForChild("PlayerGui")
    
    -- Tutorial State
    self.currentStep = 1
    self.stepProgressValue = 0
    self.tutorialActive = false
    self.isAnimating = false
    self.tutorialCompleted = false
    self.completionPending = false
    self._hasAttemptedStart = false -- Track if we've tried to start this session
    
    -- Progress Tracking
    self.progressTracker = {
        mushroomClicks = 0,
        sporeCollection = 0,
        gemBoostUpgrades = 0,
        mushroomPurchases = 0,
        sporeLevelUpgrades = 0
    }
    
    -- GUI References
    self.tutorialGui = nil
    self.container = nil
    self.stepFrame = nil
    self.gradientFrame = nil
    self.stepText = nil
    self.barContainer = nil
    self.barProgress = nil
    self.stepProgressLabel = nil
    
    -- Remote Events
    self.tutorialRemotes = nil
    self.completeTutorialRemote = nil
    self.startTutorialRemote = nil
    self.syncTutorialStatusRemote = nil
    self.requestWishRewardRemote = nil
    self.tutorialPurchaseSuccessRemote = nil
    
    -- Services
    self.loadingScreenService = nil
    self.mushroomInteractionService = nil
    self.collectionService = nil
    
    -- Spore tracking
    self.lastSporeCount = 0
    
    -- Server response tracking
    self._serverResponseReceived = false
    
    -- Store original positions
    self.originalContainerPosition = nil
    self.originalStepFramePosition = nil
    
    -- Beam system
    self.arrowBeam = nil
    self.slideBeamStart = nil
    self.slideBeamEnd = nil
    self.beamActive = false
    
    self:_initialize()
    return self
end

function TutorialClient:_initialize()
    Logger:Info("[Tutorial] Initializing TutorialService...")
    
    self:_setupRemotes()
    self:_findExistingTutorialUI()
    self:_setupBeamSystem()
    self:_setupProgressTracking()
    self:_requestTutorialStatus()
    
    -- Make globally accessible
    _G.TutorialSystem = {
        incrementMushroomClicks = function() self:IncrementMushroomClicks() end,
        startTutorial = function() 
            Logger:Info("[Tutorial] Manual start requested via _G.TutorialSystem")
            self:StartTutorial() 
        end,
        isActive = function() return self.tutorialActive end,
        isCompleted = function() return self.tutorialCompleted end,
        getCurrentStep = function() return self.currentStep end,
        onShopDataUpdate = function(shopData) self:_onShopDataUpdate(shopData) end,
        onGemShopDataUpdate = function(gemShopData) self:_onGemShopDataUpdate(gemShopData) end,
        debugStatus = function()
            Logger:Info("[Tutorial] DEBUG STATUS:")
            Logger:Info("[Tutorial]   tutorialCompleted: " .. tostring(self.tutorialCompleted))
            Logger:Info("[Tutorial]   tutorialActive: " .. tostring(self.tutorialActive))
            Logger:Info("[Tutorial]   currentStep: " .. tostring(self.currentStep))
            Logger:Info("[Tutorial]   hasRemotes: " .. tostring(self.syncTutorialStatusRemote ~= nil))
            Logger:Info("[Tutorial]   hasGUI: " .. tostring(self.tutorialGui ~= nil))
            return {
                tutorialCompleted = self.tutorialCompleted,
                tutorialActive = self.tutorialActive,
                currentStep = self.currentStep,
                hasRemotes = self.syncTutorialStatusRemote ~= nil,
                hasGUI = self.tutorialGui ~= nil
            }
        end
    }
    
    Logger:Info("[Tutorial] ✓ TutorialService initialized")
end

function TutorialClient:_findExistingTutorialUI()
    Logger:Info("[Tutorial] Finding existing tutorial UI...")
    
    -- Debug: List all GUI elements in PlayerGui
    Logger:Info("[Tutorial] DEBUG: PlayerGui children:")
    for _, child in pairs(self.playerGui:GetChildren()) do
        Logger:Info("[Tutorial]   - " .. child.Name .. " (" .. child.ClassName .. ")")
    end
    
    -- Find the existing Tutorial ScreenGui
    self.tutorialGui = self.playerGui:FindFirstChild("Tutorial")
    if not self.tutorialGui then
        Logger:Warn("[Tutorial] Tutorial ScreenGui not found in PlayerGui - checking with WaitForChild...")
        self.tutorialGui = self.playerGui:WaitForChild("Tutorial", 10)
        if not self.tutorialGui then
            Logger:Error("[Tutorial] Tutorial ScreenGui not found even with WaitForChild")
            return false
        end
    end
    
    Logger:Info("[Tutorial] Found Tutorial ScreenGui: " .. self.tutorialGui.Name)

    -- Debug: List Tutorial GUI children
    Logger:Info("[Tutorial] DEBUG: Tutorial ScreenGui children:")
    for _, child in pairs(self.tutorialGui:GetChildren()) do
        Logger:Info("[Tutorial]   - " .. child.Name .. " (" .. child.ClassName .. ")")
    end

    self.container = self.tutorialGui:WaitForChild("Container", 5)
    if not self.container then
        Logger:Warn("[Tutorial] Container frame not found")
        return false
    end

    self.stepFrame = self.container:WaitForChild("Step1", 5)
    if not self.stepFrame then
        Logger:Warn("[Tutorial] Step1 ImageLabel not found")
        return false
    end

    -- Store original positions from existing GUI design
    self.originalContainerPosition = self.container.Position
    self.originalStepFramePosition = self.stepFrame.Position

    self.gradientFrame = self.stepFrame:WaitForChild("Gradient", 5)
    if not self.gradientFrame then
        Logger:Warn("[Tutorial] Gradient frame not found")
        return false
    end

    self.stepText = self.gradientFrame:WaitForChild("Step", 5)
    if not self.stepText then
        Logger:Warn("[Tutorial] Step TextLabel not found")
        return false
    end

    self.barContainer = self.gradientFrame:WaitForChild("BarContainer", 5)
    if not self.barContainer then
        Logger:Warn("[Tutorial] BarContainer frame not found")
        return false
    end

    self.barProgress = self.barContainer:WaitForChild("BarProgress", 5)
    if not self.barProgress then
        Logger:Warn("[Tutorial] BarProgress ImageLabel not found")
        return false
    end

    self.stepProgressLabel = self.barContainer:WaitForChild("StepProgress", 5)
    if not self.stepProgressLabel then
        Logger:Warn("[Tutorial] StepProgress TextLabel not found")
        return false
    end

    -- Initialize tutorial display
    self:_initializeTutorialDisplay()

    Logger:Info("[Tutorial] ✓ Existing tutorial GUI elements found successfully")
    Logger:Debug("[Tutorial] GUI Debug Info:")
    Logger:Debug("[Tutorial]   Container Position: " .. tostring(self.container.Position))
    Logger:Debug("[Tutorial]   Step1 Position: " .. tostring(self.stepFrame.Position))
    Logger:Debug("[Tutorial]   Step1 Size: " .. tostring(self.stepFrame.Size))

    return true
end

function TutorialClient:_initializeTutorialDisplay()
    -- Hide tutorial initially
    self.tutorialGui.Enabled = false

    -- Keep container in its original position - NEVER MOVE IT
    self.container.Position = self.originalContainerPosition

    -- Only move Step1 off-screen for animation
    self.stepFrame.Position = UDim2.new(0.5, 0, -0.5, 0) -- Off-screen top

    Logger:Info("[Tutorial] ✓ Tutorial display initialized - Container stays put, only Step1 moves")
end

function TutorialClient:_setupBeamSystem()
    -- Find the Arrow Beam model in workspace
    local workspace = game:GetService("Workspace")
    local arrowBeamModel = workspace:FindFirstChild("Arrow Beam")
    
    if not arrowBeamModel then
        Logger:Warn("[Tutorial] Arrow Beam model not found in workspace")
        return
    end
    
    -- Get beam start and end attachments
    self.slideBeamStart = arrowBeamModel:FindFirstChild("Start1")
    self.slideBeamEnd = arrowBeamModel:FindFirstChild("End1")
    
    if not self.slideBeamStart or not self.slideBeamEnd then
        Logger:Warn("[Tutorial] Start1 or End1 attachments not found in Arrow Beam model")
        return
    end
    
    -- Store reference to the model
    self.arrowBeam = arrowBeamModel
    
    -- Initially hide the beam
    self.arrowBeam.Parent = workspace
    self:_hideBeam()
    
    Logger:Info("[Tutorial] ✓ Beam system setup complete")
end

function TutorialClient:_showBeam()
    if not self.arrowBeam then return end
    
    self.arrowBeam.Parent = workspace
    self.beamActive = true
    
    -- Position start beam to player
    self:_positionBeamStart()
    
    Logger:Info("[Tutorial] Beam activated")
end

function TutorialClient:_hideBeam()
    if not self.arrowBeam then return end
    
    -- Move model to nil to hide it
    self.arrowBeam.Parent = nil
    self.beamActive = false
    
    Logger:Info("[Tutorial] Beam hidden")
end

function TutorialClient:_positionBeamStart()
    if not self.slideBeamStart or not self.player.Character then return end
    
    local character = self.player.Character
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    
    if humanoidRootPart then
        -- Position the attachment at the player's position
        self.slideBeamStart.WorldPosition = humanoidRootPart.Position
    end
end

function TutorialClient:_positionBeamEnd(target)
    if not self.slideBeamEnd then return end
    
    local targetPosition = self:_getTargetPosition(target)
    if targetPosition then
        self.slideBeamEnd.WorldPosition = targetPosition
    end
end

function TutorialClient:_getTargetPosition(target)
    if target == "none" then
        return nil
    elseif target == "mushroom" then
        return self:_findNearestMushroom()
    elseif target == "gemShop" then
        return self:_findGemShopPosition()
    elseif target == "sporeShop" then
        return self:_findSporeShopPosition()
    elseif target == "fountain" then
        return self:_findFountainPosition()
    end
    
    return nil
end

function TutorialClient:_findNearestMushroom()
    local playerPlots = workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then 
        return self:_getPlayerRelativePosition(Vector3.new(0, 5, 5)) -- Fallback: in front of player
    end
    
    local playerPlot = playerPlots:FindFirstChild("Plot_" .. self.player.Name)
    if not playerPlot then 
        return self:_getPlayerRelativePosition(Vector3.new(0, 5, 5)) -- Fallback: in front of player
    end
    
    -- Find the nearest mushroom in the player's plot
    local nearestMushroom = nil
    local nearestDistance = math.huge
    local playerPosition = self.player.Character and self.player.Character:FindFirstChild("HumanoidRootPart")
    if not playerPosition then 
        playerPosition = {Position = Vector3.new(0, 0, 0)} -- Fallback position
    else
        playerPosition = playerPosition
    end
    
    for _, child in pairs(playerPlot:GetDescendants()) do
        if child:IsA("Model") and child.Name:match("MushroomModel_") then
            local primaryPart = child.PrimaryPart or child:FindFirstChildOfClass("BasePart")
            if primaryPart then
                local distance = (primaryPart.Position - playerPosition.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestMushroom = primaryPart
                end
            end
        end
    end
    
    if nearestMushroom then
        return nearestMushroom.Position -- Directly at the mushroom
    end
    
    -- Final fallback: in front of player
    return self:_getPlayerRelativePosition(Vector3.new(0, 5, 5))
end

function TutorialClient:_getPlayerRelativePosition(offset)
    if self.player.Character and self.player.Character:FindFirstChild("HumanoidRootPart") then
        local hrp = self.player.Character.HumanoidRootPart
        return hrp.Position + offset
    end
    return nil
end

function TutorialClient:_findGemShopPosition()
    -- Find the BuffShop in the player's plot
    local playerPlots = workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then 
        Logger:Debug("[Tutorial] PlayerPlots not found for gem shop position")
        return self:_getPlayerRelativePosition(Vector3.new(8, 4, 0))
    end
    
    local playerPlot = playerPlots:FindFirstChild("Plot_" .. self.player.Name)
    if not playerPlot then 
        Logger:Debug("[Tutorial] Player plot not found for gem shop position")
        return self:_getPlayerRelativePosition(Vector3.new(8, 4, 0))
    end
    
    -- Look for BuffShop in the player's plot
    local buffShop = playerPlot:FindFirstChild("BuffShop")
    if buffShop then
        Logger:Debug("[Tutorial] Found BuffShop model in player plot")
        
        -- Try to find a primary part or any BasePart in the model
        local targetPart = buffShop.PrimaryPart
        if not targetPart then
            targetPart = buffShop:FindFirstChildOfClass("BasePart")
            if targetPart then
                Logger:Debug("[Tutorial] BuffShop has no PrimaryPart, using first BasePart: " .. targetPart.Name)
            end
        else
            Logger:Debug("[Tutorial] Using BuffShop PrimaryPart: " .. targetPart.Name)
        end
        
        if targetPart then
            Logger:Debug("[Tutorial] BuffShop targeting successful")
            return targetPart.Position + Vector3.new(0, 5, 0) -- Slightly above the shop
        else
            Logger:Warn("[Tutorial] BuffShop model found but no BasePart found inside")
        end
    else
        Logger:Debug("[Tutorial] BuffShop not found in player plot")
    end
    
    -- Fallback: Point to player's right side where shop would typically be
    Logger:Debug("[Tutorial] BuffShop not found in plot, using fallback position")
    return self:_getPlayerRelativePosition(Vector3.new(8, 4, 0))
end

function TutorialClient:_findSporeShopPosition()
    -- Find the MushroomShop1 in the player's plot
    local playerPlots = workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then 
        Logger:Debug("[Tutorial] PlayerPlots not found for spore shop position")
        return self:_getPlayerRelativePosition(Vector3.new(-8, 4, 0))
    end
    
    local playerPlot = playerPlots:FindFirstChild("Plot_" .. self.player.Name)
    if not playerPlot then 
        Logger:Debug("[Tutorial] Player plot not found for spore shop position")
        return self:_getPlayerRelativePosition(Vector3.new(-8, 4, 0))
    end
    
    -- Look for MushroomShop1 in the player's plot (it's a Part, not a Model)
    local mushroomShop = playerPlot:FindFirstChild("MushroomShop1")
    if mushroomShop and mushroomShop:IsA("BasePart") then
        Logger:Debug("[Tutorial] Found MushroomShop1 part in player plot")
        return mushroomShop.Position + Vector3.new(0, 5, 0) -- Slightly above the shop
    end
    
    -- Fallback: Point to player's left side where shop would typically be
    Logger:Debug("[Tutorial] MushroomShop1 not found in plot, using fallback position")
    return self:_getPlayerRelativePosition(Vector3.new(-8, 4, 0))
end

function TutorialClient:_findFountainPosition()
    -- Find the Fountain1 in the player's plot
    local playerPlots = workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then 
        Logger:Debug("[Tutorial] PlayerPlots not found for fountain position")
        return self:_getPlayerRelativePosition(Vector3.new(0, 4, 8))
    end
    
    local playerPlot = playerPlots:FindFirstChild("Plot_" .. self.player.Name)
    if not playerPlot then 
        Logger:Debug("[Tutorial] Player plot not found for fountain position")
        return self:_getPlayerRelativePosition(Vector3.new(0, 4, 8))
    end
    
    -- Look for Fountain1 in the player's plot (it's a Part)
    local fountain = playerPlot:FindFirstChild("Fountain1")
    if fountain and fountain:IsA("BasePart") then
        Logger:Debug("[Tutorial] Found Fountain1 part in player plot")
        return fountain.Position + Vector3.new(0, 5, 0) -- Slightly above the fountain
    end
    
    -- Fallback: Point to player's front where fountain would typically be
    Logger:Debug("[Tutorial] Fountain1 not found in plot, using fallback position")
    return self:_getPlayerRelativePosition(Vector3.new(0, 4, 8))
end

function TutorialClient:_getCurrentShopData()
    -- Try to get shop data from remote function
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if not shared then return nil end
    
    local remoteFunctions = shared:FindFirstChild("RemoteFunctions")
    if not remoteFunctions then return nil end
    
    local getShopData = remoteFunctions:FindFirstChild("GetShopData")
    if getShopData then
        local success, shopData = pcall(function()
            return getShopData:InvokeServer()
        end)
        
        if success and shopData then
            return shopData
        end
    end
    
    return nil
end

function TutorialClient:_setupRemotes()
    spawn(function()
        local shared = ReplicatedStorage:WaitForChild("Shared", 30)
        if shared then
            local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
            if remoteEvents then
                self.tutorialRemotes = remoteEvents:FindFirstChild("TutorialRemotes") or remoteEvents:WaitForChild("TutorialRemotes", 10)
                if self.tutorialRemotes then
                    self.completeTutorialRemote = self.tutorialRemotes:WaitForChild("CompleteTutorial", 10)
                    self.startTutorialRemote = self.tutorialRemotes:WaitForChild("StartTutorial", 10)
                    self.syncTutorialStatusRemote = self.tutorialRemotes:WaitForChild("SyncTutorialStatus", 10)
                    self.requestWishRewardRemote = self.tutorialRemotes:WaitForChild("RequestWishReward", 10)

                    if self.completeTutorialRemote and self.startTutorialRemote and self.syncTutorialStatusRemote and self.requestWishRewardRemote then
                        -- Connect remote events
                        self.startTutorialRemote.OnClientEvent:Connect(function()
                            self:_onStartTutorial()
                        end)
                        
                        self.syncTutorialStatusRemote.OnClientEvent:Connect(function(completed)
                            self:_onSyncTutorialStatus(completed)
                        end)
                        
                        Logger:Info("[Tutorial] ✓ Tutorial remotes connected")
                    end
                end

                -- Connect to shop purchase success events
                local shopEvents = remoteEvents:FindFirstChild("ShopEvents")
                if shopEvents then
                    self.tutorialPurchaseSuccessRemote = shopEvents:WaitForChild("TutorialPurchaseSuccess", 10)
                    if self.tutorialPurchaseSuccessRemote then
                        self.tutorialPurchaseSuccessRemote.OnClientEvent:Connect(function(purchaseType, purchaseData)
                            self:_onPurchaseSuccess(purchaseType, purchaseData)
                        end)
                        Logger:Info("[Tutorial] ✓ Purchase success tracking connected")
                    end
                end
                return
            end
        end
        Logger:Warn("[Tutorial] ⚠ Failed to connect tutorial remotes")
    end)
end

function TutorialClient:_setupProgressTracking()
    -- Track spore collection via leaderstats
    spawn(function()
        local leaderstats = self.player:WaitForChild("leaderstats", 10)
        if leaderstats then
            local spores = leaderstats:WaitForChild("Spores", 10) or leaderstats:FindFirstChild("Coins")
            if spores then
                self.lastSporeCount = spores.Value
                spores.Changed:Connect(function()
                    local newCount = spores.Value
                    local gained = newCount - self.lastSporeCount
                    
                    Logger:Debug(string.format("[Tutorial] Spore change detected: oldCount=%d, newCount=%d, gained=%d, tutorialActive=%s, currentStep=%d", 
                        self.lastSporeCount, newCount, gained, tostring(self.tutorialActive), self.currentStep))
                    
                    if gained > 0 and self.tutorialActive and self.currentStep == 2 then
                        local roundedGained = math.floor(gained + 0.5) -- Round to nearest integer
                        local oldProgress = self.progressTracker.sporeCollection
                        self.progressTracker.sporeCollection = self.progressTracker.sporeCollection + roundedGained
                        Logger:Info(string.format("[Tutorial] Spores collected: +%d (progress: %d->%d / %d)", 
                            roundedGained, oldProgress, self.progressTracker.sporeCollection, 10))
                        self:_updateProgress(self.progressTracker.sporeCollection)
                    elseif gained < 0 and self.tutorialActive and self.currentStep == 2 then
                        -- Player spent spores, update baseline but don't affect progress
                        Logger:Info(string.format("[Tutorial] Spores spent: %d (baseline updated, progress unchanged: %d)", -gained, self.progressTracker.sporeCollection))
                    elseif gained > 0 then
                        Logger:Debug(string.format("[Tutorial] Spores gained but not tracked (tutorial not active or wrong step): gained=%d", gained))
                    end
                    
                    self.lastSporeCount = newCount
                end)
                Logger:Info("[Tutorial] ✓ Spore collection tracking ready")
            end
        end
    end)
    
    -- Initialize baseline values for shop tracking
    self.lastMushroomCount = 0
    self.lastSporeLevel = 0
    self.lastGemBoostLevels = {
        FastRunner = 0,
        PickUpRange = 0,
        FasterShrooms = 0,
        ShinySpore = 0,
        GemHunter = 0
    }
    
    spawn(function()
        task.wait(3) -- Wait for data to load
        local currentShopData = self:_getCurrentShopData()
        if currentShopData then
            self.lastMushroomCount = currentShopData.currentMushroomCount or 0
            self.lastSporeLevel = currentShopData.currentSporeUpgradeLevel or 0
            Logger:Info("[Tutorial] Initialized baseline - Mushrooms: " .. self.lastMushroomCount .. ", SporeLevel: " .. self.lastSporeLevel)
        end
    end)
    
    Logger:Info("[Tutorial] ✓ Progress tracking setup complete")
end

function TutorialClient:_onShopDataUpdate(shopData)
    if not shopData then return end
    
    -- Just update baseline tracking values for reference
    if shopData.currentMushroomCount then
        self.lastMushroomCount = shopData.currentMushroomCount
    end
    
    if shopData.currentSporeUpgradeLevel then
        self.lastSporeLevel = shopData.currentSporeUpgradeLevel
    end
    
    if self.tutorialActive then
        Logger:Debug("[Tutorial] Shop data updated - Mushrooms: " .. (self.lastMushroomCount or 0) .. ", SporeLevel: " .. (self.lastSporeLevel or 0))
    end
end

function TutorialClient:_onGemShopDataUpdate(gemShopData)
    if not gemShopData then return end
    
    -- Just update baseline tracking values for reference
    if gemShopData.currentFastRunnerLevel then self.lastGemBoostLevels.FastRunner = gemShopData.currentFastRunnerLevel end
    if gemShopData.currentPickUpRangeLevel then self.lastGemBoostLevels.PickUpRange = gemShopData.currentPickUpRangeLevel end
    if gemShopData.currentFasterShroomsLevel then self.lastGemBoostLevels.FasterShrooms = gemShopData.currentFasterShroomsLevel end
    if gemShopData.currentShinySporeLevel then self.lastGemBoostLevels.ShinySpore = gemShopData.currentShinySporeLevel end
    if gemShopData.currentGemHunterLevel then self.lastGemBoostLevels.GemHunter = gemShopData.currentGemHunterLevel end
    
    if self.tutorialActive then
        Logger:Debug("[Tutorial] Gem shop data updated - FR:" .. self.lastGemBoostLevels.FastRunner .. 
                     " PR:" .. self.lastGemBoostLevels.PickUpRange .. 
                     " FS:" .. self.lastGemBoostLevels.FasterShrooms .. 
                     " SS:" .. self.lastGemBoostLevels.ShinySpore .. 
                     " GH:" .. self.lastGemBoostLevels.GemHunter)
    end
end

function TutorialClient:_onPurchaseSuccess(purchaseType, purchaseData)
    if not self.tutorialActive then return end
    
    Logger:Info(string.format("[Tutorial] Purchase success: %s - %s", purchaseType, tostring(purchaseData)))
    
    if purchaseType == "mushroom" then
        -- Mushroom purchase successful (tutorial step 4)
        if self.currentStep == 4 then
            self.progressTracker.mushroomPurchases = self.progressTracker.mushroomPurchases + 1
            self:_updateProgress(self.progressTracker.mushroomPurchases)
            Logger:Info("[Tutorial] Mushroom purchase confirmed: " .. self.progressTracker.mushroomPurchases)
        end
    elseif purchaseType == "sporeUpgrade" then
        -- Spore upgrade successful (tutorial step 5)
        if self.currentStep == 5 then
            self.progressTracker.sporeLevelUpgrades = self.progressTracker.sporeLevelUpgrades + 1
            self:_updateProgress(self.progressTracker.sporeLevelUpgrades)
            Logger:Info("[Tutorial] Spore upgrade confirmed: " .. self.progressTracker.sporeLevelUpgrades)
        end
    elseif purchaseType == "gemShop" then
        -- Gem shop upgrade successful (tutorial step 3)
        if self.currentStep == 3 then
            self.progressTracker.gemBoostUpgrades = self.progressTracker.gemBoostUpgrades + 1
            self:_updateProgress(self.progressTracker.gemBoostUpgrades)
            Logger:Info("[Tutorial] Gem boost upgrade confirmed: " .. self.progressTracker.gemBoostUpgrades .. " (" .. tostring(purchaseData) .. ")")
        end
    end
end

function TutorialClient:_requestTutorialStatus()
    spawn(function()
        task.wait(3) -- Wait for everything to load
        if self.syncTutorialStatusRemote then
            self.syncTutorialStatusRemote:FireServer()
            Logger:Info("[Tutorial] Requested tutorial status from server")
            
            -- FIXED: Increased timeout and added better logging to prevent false starts
            spawn(function()
                task.wait(15) -- Increased to 15 seconds for slow connections
                if not self.tutorialCompleted and not self.tutorialActive and not self._serverResponseReceived then
                    Logger:Warn("[Tutorial] FALLBACK TRIGGER: No server response after 15 seconds - this should only happen for genuinely new players")
                    Logger:Info("[Tutorial] State check - completed: " .. tostring(self.tutorialCompleted) .. ", active: " .. tostring(self.tutorialActive) .. ", serverResponse: " .. tostring(self._serverResponseReceived))
                    Logger:Info("[Tutorial] CALL PATH: Fallback Timer -> StartTutorial()")
                    self:StartTutorial()
                else
                    Logger:Info("[Tutorial] Server response received or tutorial already handled - no fallback needed")
                end
            end)
        else
            Logger:Warn("[Tutorial] No sync remote available - starting tutorial directly")
            Logger:Info("[Tutorial] CALL PATH: No Sync Remote -> StartTutorial()")
            task.wait(2)
            self:StartTutorial()
        end
    end)
end

function TutorialClient:_updateProgress(newProgress, animate)
    animate = animate ~= false
    
    local currentStepData = TUTORIAL_STEPS[self.currentStep]
    if not currentStepData or not currentStepData.hasProgress then return end
    
    Logger:Info(string.format("[Tutorial] _updateProgress called: step=%d, newProgress=%d, target=%d, trackType=%s", 
        self.currentStep, newProgress, currentStepData.target, currentStepData.trackType or "none"))
    
    newProgress = math.min(newProgress, currentStepData.target)
    self.stepProgressValue = newProgress
    
    local progressPercent = newProgress / currentStepData.target
    local newBarScale = UDim2.new(progressPercent, 0, 1, 0)
    
    if animate then
        local progressTween = TweenService:Create(self.barProgress,
            TweenInfo.new(PROGRESS_UPDATE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {Size = newBarScale}
        )
        progressTween:Play()
    else
        self.barProgress.Size = newBarScale
    end
    
    -- Update progress text
    if newProgress >= currentStepData.target then
        self.stepProgressLabel.Text = "Complete!"
        self.stepProgressLabel.TextColor3 = Color3.new(0, 1, 0)
    else
        self.stepProgressLabel.Text = newProgress .. "/" .. currentStepData.target
        self.stepProgressLabel.TextColor3 = Color3.new(1, 1, 1)
    end
    
    Logger:Info("[Tutorial] Progress updated: " .. newProgress .. "/" .. currentStepData.target)
    
    if newProgress >= currentStepData.target and not self.completionPending then
        self.completionPending = true
        spawn(function()
            task.wait(COMPLETION_DELAY)
            self:_completeCurrentStep()
        end)
    end
end

function TutorialClient:_showTutorialStep(stepNumber)
    if self.isAnimating then return end
    self.isAnimating = true
    
    local stepData = TUTORIAL_STEPS[stepNumber]
    if not stepData then
        Logger:Warn("[Tutorial] Invalid step number: " .. tostring(stepNumber))
        self.isAnimating = false
        return
    end
    
    -- Update text content
    self.stepText.Text = stepData.text
    
    -- Handle progress bar visibility
    if stepData.hasProgress then
        self.barContainer.Visible = true
        self.stepProgressValue = 0
        
        -- Reset progress tracker for this specific step
        if stepNumber == 2 and stepData.trackType == "sporeCollection" then
            self.progressTracker.sporeCollection = 0
            Logger:Info(string.format("[Tutorial] Step 2 - Reset sporeCollection progress to 0"))
        end
        
        self:_updateProgress(0, false)
        Logger:Info(string.format("[Tutorial] Step %d initialized with progress 0/%d", stepNumber, stepData.target))
    else
        self.barContainer.Visible = false
    end
    
    -- Enable GUI
    self.tutorialGui.Enabled = true
    
    -- Position stepFrame off-screen initially
    self.stepFrame.Position = UDim2.new(0.5, 0, -0.5, 0)
    
    -- Animate dropdown
    local dropdownTween = TweenService:Create(self.stepFrame,
        TweenInfo.new(DROPDOWN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = self.originalStepFramePosition}
    )
    
    dropdownTween:Play()
    dropdownTween.Completed:Connect(function()
        self.isAnimating = false
        Logger:Info("[Tutorial] Step " .. stepNumber .. " shown: " .. stepData.text)
        
        -- Show beam for this step
        if stepData.beamTarget and stepData.beamTarget ~= "none" then
            self:_showBeam()
            self:_positionBeamEnd(stepData.beamTarget)
            
            -- Continuously update beam positions to follow player and target
            spawn(function()
                while self.beamActive and self.tutorialActive and self.currentStep == stepNumber do
                    self:_positionBeamStart()
                    self:_positionBeamEnd(stepData.beamTarget) -- Update target position too
                    task.wait(0.1) -- Update every 0.1 seconds
                end
            end)
        end
        
        -- Handle auto-complete steps
        if stepData.trackType == "autoComplete" then
            Logger:Info(string.format("[Tutorial] Starting auto-complete for step %d: '%s' (%.1fs)", stepNumber, stepData.text, stepData.autoCompleteTime or 1.5))
            spawn(function()
                local completeTime = stepData.autoCompleteTime or 1.5
                -- Animate progress bar for auto-complete steps
                if stepData.hasProgress then
                    -- Wait a brief moment, then animate the progress bar filling up
                    task.wait(0.5)
                    Logger:Info(string.format("[Tutorial] Updating progress to 100%% for step %d", stepNumber))
                    self:_updateProgress(1)
                    task.wait(completeTime - 0.5)
                else
                    task.wait(completeTime)
                end
                Logger:Info(string.format("[Tutorial] Auto-complete timer finished for step %d, completing step", stepNumber))
                self:_completeCurrentStep()
            end)
        end
    end)
end

function TutorialClient:_hideTutorialStep()
    if self.isAnimating then return end
    self.isAnimating = true
    
    -- Hide beam when hiding step
    self:_hideBeam()
    
    local popupTween = TweenService:Create(self.stepFrame,
        TweenInfo.new(POPUP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {Position = UDim2.new(0.5, 0, -0.5, 0)}
    )
    
    popupTween:Play()
    popupTween.Completed:Connect(function()
        self.tutorialGui.Enabled = false
        self.isAnimating = false
        Logger:Info("[Tutorial] Tutorial step hidden")
    end)
end

function TutorialClient:_completeCurrentStep()
    if self.isAnimating then return end
    
    local currentStepData = TUTORIAL_STEPS[self.currentStep]
    if not currentStepData then return end
    
    -- Validate step completion based on progress
    if currentStepData.hasProgress then
        if self.stepProgressValue < currentStepData.target then
            Logger:Warn("[Tutorial] Step " .. self.currentStep .. " not completed yet (" .. self.stepProgressValue .. "/" .. currentStepData.target .. ")")
            self.completionPending = false
            return
        end
    end
    
    Logger:Info("[Tutorial] Step " .. self.currentStep .. " completed!")
    
    local previousStep = self.currentStep
    self.currentStep = self.currentStep + 1
    self.completionPending = false
    
    Logger:Info("[Tutorial] Transitioning from step " .. previousStep .. " to step " .. self.currentStep .. " (total steps: " .. #TUTORIAL_STEPS .. ")")
    
    if self.currentStep <= #TUTORIAL_STEPS then
        -- Move to next step
        Logger:Info(string.format("[Tutorial] Moving to step %d/%d: '%s'", self.currentStep, #TUTORIAL_STEPS, TUTORIAL_STEPS[self.currentStep].text))
        self:_hideTutorialStep()
        
        spawn(function()
            task.wait(POPUP_TIME + 0.2)
            if self.currentStep <= #TUTORIAL_STEPS and self.tutorialActive then
                Logger:Info("[Tutorial] Showing step " .. self.currentStep .. ": " .. TUTORIAL_STEPS[self.currentStep].text)
                self:_showTutorialStep(self.currentStep)
            else
                Logger:Warn(string.format("[Tutorial] Skipping step %d display - step out of range (%d > %d) or tutorial inactive (%s)", 
                    self.currentStep, self.currentStep, #TUTORIAL_STEPS, tostring(self.tutorialActive)))
            end
        end)
    else
        -- Tutorial complete!
        Logger:Info("[Tutorial] All steps completed (step " .. self.currentStep .. " > " .. #TUTORIAL_STEPS .. "), finishing tutorial")
        self:_completeTutorial()
    end
end

function TutorialClient:_completeTutorial()
    Logger:Info("[Tutorial] TUTORIAL COMPLETED! (Current step was: " .. self.currentStep .. "/" .. #TUTORIAL_STEPS .. ")")
    
    self.tutorialActive = false
    self.tutorialCompleted = true
    
    -- Hide beam and tutorial
    self:_hideBeam()
    self:_hideTutorialStep()
    
    -- Request wish reward as completion bonus
    self:_requestWishReward()
    
    if self.completeTutorialRemote then
        self.completeTutorialRemote:FireServer()
        Logger:Info("[Tutorial] Notified server of tutorial completion")
    end
    
    spawn(function()
        task.wait(POPUP_TIME + 0.5)
        Logger:Info("[Tutorial] Tutorial system deactivated - player is now experienced!")
    end)
end

function TutorialClient:_onStartTutorial()
    Logger:Info("[Tutorial] Received start tutorial request from server")
    self._serverResponseReceived = true
    Logger:Info("[Tutorial] CALL PATH: _onStartTutorial() -> StartTutorial()")
    self:StartTutorial()
end

function TutorialClient:_onSyncTutorialStatus(completed)
    Logger:Info("[Tutorial] Received tutorial status sync from server: " .. (completed and "COMPLETED" or "INCOMPLETE"))
    self._serverResponseReceived = true
    self.tutorialCompleted = completed
    
    if completed and self.tutorialActive then
        -- Only allow server to complete tutorial if we're past ALL steps (including final thank you steps)
        if self.currentStep > #TUTORIAL_STEPS then
            self.tutorialActive = false
            self:_hideTutorialStep()
            Logger:Info("[Tutorial] Tutorial marked as completed by server, stopping current tutorial")
        else
            Logger:Info("[Tutorial] Server wants to complete tutorial but we're only on step " .. self.currentStep .. "/" .. #TUTORIAL_STEPS .. " - ignoring to allow final steps to show")
        end
    elseif not completed and not self.tutorialActive and not self.tutorialCompleted and not self._hasAttemptedStart then
        -- Server says we should start tutorial (only if we haven't completed it before and haven't tried this session)
        Logger:Info("[Tutorial] Server indicates tutorial not completed and we're not active - will start tutorial")
        Logger:Info("[Tutorial] CALL PATH: _onSyncTutorialStatus() -> StartTutorial()")
        spawn(function()
            task.wait(2)
            self:StartTutorial()
        end)
    elseif not completed and self.tutorialActive then
        -- Tutorial is in progress, server confirms it's not completed yet - this is normal
        Logger:Debug("[Tutorial] Server confirms tutorial in progress (step " .. self.currentStep .. ") - continuing normally")
    end
end

function TutorialClient:_requestWishReward()
    if self.requestWishRewardRemote then
        self.requestWishRewardRemote:FireServer()
        Logger:Info("[Tutorial] Requested wish reward from server")
    else
        Logger:Warn("[Tutorial] RequestWishReward remote not available")
    end
end

-- Public methods
function TutorialClient:StartTutorial()
    -- FIRST CHECK: Prevent multiple simultaneous starts
    if self.tutorialActive then
        Logger:Warn("[Tutorial] Tutorial already active, ignoring start request")
        return false
    end
    
    if self._hasAttemptedStart then
        Logger:Warn("[Tutorial] Tutorial start already attempted this session, ignoring")
        return false
    end
    
    -- Wait for loading screen to complete first
    if self.loadingScreenService and not self.loadingScreenService:IsComplete() then
        Logger:Info("[Tutorial] Waiting for loading screen to complete...")
        self.loadingScreenService:OnLoadingComplete(function()
            task.wait(4) -- Wait longer to let other UI elements show first
            self:StartTutorial()
        end)
        return
    end
    
    if self.tutorialCompleted then
        Logger:Info("[Tutorial] Tutorial already completed, not starting")
        return false
    end
    
    -- Set flag to prevent multiple starts this session
    self._hasAttemptedStart = true
    Logger:Info("[Tutorial] Starting tutorial - setting _hasAttemptedStart = true")
    
    -- Reset all progress
    for key, _ in pairs(self.progressTracker) do
        self.progressTracker[key] = 0
    end
    Logger:Info("[Tutorial] Progress tracker reset - mushroomClicks set to 0")
    
    -- Reset spore baseline to current value to track only NEW spores collected
    spawn(function()
        task.wait(0.1) -- Brief wait to ensure leaderstats are loaded
        local leaderstats = self.player:FindFirstChild("leaderstats")
        if leaderstats then
            local spores = leaderstats:FindFirstChild("Spores") or leaderstats:FindFirstChild("Coins")
            if spores then
                self.lastSporeCount = spores.Value
                Logger:Info(string.format("[Tutorial] Reset spore baseline to %d - will track NEW spores collected", self.lastSporeCount))
            end
        end
    end)
    
    -- Reset baseline values to current player state to prevent immediate completion
    spawn(function()
        task.wait(0.5) -- Brief wait to ensure data is loaded
        local currentShopData = self:_getCurrentShopData()
        if currentShopData then
            self.lastMushroomCount = currentShopData.currentMushroomCount or 0
            self.lastSporeLevel = currentShopData.currentSporeUpgradeLevel or 0
            Logger:Info("[Tutorial] Reset baselines at start - Mushrooms: " .. self.lastMushroomCount .. ", SporeLevel: " .. self.lastSporeLevel)
        end
        
        -- Also initialize gem shop baselines
        if self._lastGemShopData then
            if self._lastGemShopData.currentFastRunnerLevel then self.lastGemBoostLevels.FastRunner = self._lastGemShopData.currentFastRunnerLevel end
            if self._lastGemShopData.currentPickUpRangeLevel then self.lastGemBoostLevels.PickUpRange = self._lastGemShopData.currentPickUpRangeLevel end
            if self._lastGemShopData.currentFasterShroomsLevel then self.lastGemBoostLevels.FasterShrooms = self._lastGemShopData.currentFasterShroomsLevel end
            if self._lastGemShopData.currentShinySporeLevel then self.lastGemBoostLevels.ShinySpore = self._lastGemShopData.currentShinySporeLevel end
            if self._lastGemShopData.currentGemHunterLevel then self.lastGemBoostLevels.GemHunter = self._lastGemShopData.currentGemHunterLevel end
            Logger:Info("[Tutorial] Reset gem boost baselines at start")
        end
    end)
    
    self.currentStep = 1
    self.tutorialActive = true
    self.completionPending = false
    
    spawn(function()
        task.wait(1)
        self:_showTutorialStep(1)
    end)
    
    Logger:Info("[Tutorial] Tutorial system started!")
    return true
end

function TutorialClient:IncrementMushroomClicks()
    if self.tutorialActive and self.currentStep == 1 then
        self.progressTracker.mushroomClicks = self.progressTracker.mushroomClicks + 1
        Logger:Info(string.format("[Tutorial] Mushroom click registered: %d/4 (step %d)", 
            self.progressTracker.mushroomClicks, self.currentStep))
        self:_updateProgress(self.progressTracker.mushroomClicks)
    else
        Logger:Debug(string.format("[Tutorial] Mushroom click ignored - tutorialActive: %s, currentStep: %d", 
            tostring(self.tutorialActive), self.currentStep))
    end
end

-- Note: All purchase tracking is now handled by data update events:
-- - IncrementGemBoostUpgrades: handled by _onGemShopDataUpdate
-- - IncrementMushroomPurchases: handled by _onShopDataUpdate 
-- - IncrementSporeLevelUpgrades: handled by _onShopDataUpdate

function TutorialClient:SetLoadingScreenService(loadingScreenService)
    self.loadingScreenService = loadingScreenService
end

function TutorialClient:SetMushroomInteractionService(mushroomInteractionService)
    self.mushroomInteractionService = mushroomInteractionService
end

function TutorialClient:SetCollectionService(collectionService)
    self.collectionService = collectionService
end

function TutorialClient:IsActive()
    return self.tutorialActive
end

function TutorialClient:IsCompleted()
    return self.tutorialCompleted
end

function TutorialClient:GetCurrentStep()
    return self.currentStep
end

function TutorialClient:Cleanup()
    -- Hide beam
    self:_hideBeam()
    
    if self.tutorialGui then
        self.tutorialGui:Destroy()
    end
    
    -- Clear global reference
    _G.TutorialSystem = nil
    
    Logger:Info("[Tutorial] ✓ Cleanup complete")
end

return TutorialClient