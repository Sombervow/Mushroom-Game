local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local UIManager = {}
UIManager.__index = UIManager

-- UI Configuration
local UI_CONFIGS = {
    ["OpenWishGUI"] = {
        screenGui = "WishFountain",
        uiType = "wish_fountain",
        autoClose = true, -- Close when stepping off
        activationDistance = 5
    },
    ["OpenGemShop"] = {
        screenGui = "GemShop", 
        uiType = "gem_shop",
        autoClose = false, -- Manual close only
        activationDistance = 8
    },
    ["UpgradeShop"] = {
        screenGui = "MushroomShop",
        uiType = "mushroom_shop", 
        autoClose = false, -- Manual close only
        activationDistance = 8
    },
    ["MushroomShop1"] = {
        screenGui = "MushroomShop",
        uiType = "mushroom_shop", 
        autoClose = false, -- Manual close only
        activationDistance = 8
    },
    ["Area2Shop"] = {
        screenGui = "MushroomShop",
        uiType = "mushroom_shop", 
        autoClose = false, -- Manual close only
        activationDistance = 8
    },
    ["MushroomShop2"] = {
        screenGui = "MushroomShop2",
        uiType = "mushroom_shop2", 
        autoClose = false, -- Manual close only
        activationDistance = 8
    },
    ["MushroomShop3"] = {
        screenGui = "MushroomShop3",
        uiType = "mushroom_shop3", 
        autoClose = false, -- Manual close only
        activationDistance = 8
    },
    ["Inventory"] = {
        screenGui = "Inventory",
        uiType = "inventory",
        autoClose = false, -- Manual close only
        activationDistance = 0 -- Button-only activation
    },
    ["DailyRewards"] = {
        screenGui = "DailyRewards", 
        uiType = "daily_rewards",
        autoClose = false, -- Manual close only
        activationDistance = 0 -- Button-only activation
    },
    ["GroupRewards"] = {
        screenGui = "GroupRewards",
        uiType = "group_rewards", 
        autoClose = false, -- Manual close only
        activationDistance = 0 -- Button-only activation
    },
    ["Activate"] = {
        screenGui = "GamepassShop",
        uiType = "gamepass_shop",
        autoClose = false, -- Manual close only
        activationDistance = 8
    },
    ["StarterPack"] = {
        screenGui = "StarterPack",
        uiType = "starter_pack",
        autoClose = false, -- Manual close only
        activationDistance = 0 -- Button-only activation
    }
}

function UIManager.new()
    local self = setmetatable({}, UIManager)
    
    self.player = Players.LocalPlayer
    self.playerGui = self.player:WaitForChild("PlayerGui")
    self.character = self.player.Character or self.player.CharacterAdded:Wait()
    self.humanoidRootPart = nil
    
    -- UI state tracking
    self.activeParts = {} -- Parts player is currently touching
    self.openUIs = {} -- Currently open UIs
    self.uiAnimations = {} -- Active animations
    self.activePressurePlates = {} -- Track pressure plate states
    self.partResetFunctions = {} -- Functions to reset part states
    self.screenGuiToPlateKey = {} -- Map screenGui names to their plateKeys
    self.openUIToPlateKey = {} -- Track which plateKey was used to open each specific UI
    
    -- Connection tracking
    self.connections = {}
    self.heartbeatConnection = nil
    self.scrollingAnimations = {} -- Track active scrolling animations
    
    -- Camera FOV tracking
    self.camera = Workspace.CurrentCamera
    self.originalFOV = self.camera.FieldOfView
    self.fovTween = nil
    
    -- Service references
    self.gamepassClient = nil
    
    self:_initialize()
    return self
end

function UIManager:_initialize()
    Logger:Info("UIManager initializing...")
    
    self:_setupCharacterConnections()
    self:_findAndSetupParts()
    self:_setupExitButtons()
    self:_setupFooterButtons()
    self:_setupGUITracking()
    
    Logger:Info("✓ UIManager initialized")
end

function UIManager:_setupCharacterConnections()
    -- Handle character respawning
    local characterConnection = self.player.CharacterAdded:Connect(function(character)
        self.character = character
        self.humanoidRootPart = character:WaitForChild("HumanoidRootPart")
        
        -- Close all UIs on respawn
        self:_closeAllUIs()
        
        Logger:Info("Character respawned - UI states reset")
    end)
    
    table.insert(self.connections, characterConnection)
    
    -- Set initial humanoidRootPart
    if self.character then
        self.humanoidRootPart = self.character:FindFirstChild("HumanoidRootPart")
    end
end

function UIManager:_findAndSetupParts()
    -- Find parts in workspace
    local foundParts = {}
    local function findPartsRecursively(parent)
        for _, child in pairs(parent:GetChildren()) do
            if child:IsA("BasePart") and UI_CONFIGS[child.Name] then
                self:_setupPart(child)
                table.insert(foundParts, child.Name .. " at " .. tostring(child:GetFullName()))
            end
            findPartsRecursively(child)
        end
    end
    
    findPartsRecursively(workspace)
    
    -- Debug: Log what parts were found
    if #foundParts > 0 then
        Logger:Info("Found UI trigger parts: " .. table.concat(foundParts, ", "))
    else
        Logger:Warn("No UI trigger parts found in workspace")
    end
    
    -- Listen for new parts being added
    local descendantConnection = workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") and UI_CONFIGS[descendant.Name] then
            self:_setupPart(descendant)
            Logger:Info("New UI trigger part added: " .. descendant.Name .. " at " .. tostring(descendant:GetFullName()))
        end
    end)
    
    table.insert(self.connections, descendantConnection)
    
    Logger:Info("✓ Found and setup UI trigger parts")
end

function UIManager:_setupPart(part)
    local config = UI_CONFIGS[part.Name]
    if not config then return end
    
    Logger:Debug(string.format("Setting up UI trigger part: %s -> %s", part.Name, config.screenGui))
    
    local plateKey = part.Name .. "_" .. tostring(math.floor(part.Position.X)) .. "_" .. tostring(math.floor(part.Position.Z))
    
    -- Map screenGui to plateKey for manual close handling
    self.screenGuiToPlateKey[config.screenGui] = plateKey
    Logger:Info(string.format("Mapped screenGui '%s' to plateKey '%s'", config.screenGui, plateKey))
    
    -- Simple state tracking
    local lastActivation = 0
    local manualCloseTime = 0
    local ACTIVATION_COOLDOWN = 0.3 -- Cooldown between activations
    local MANUAL_CLOSE_COOLDOWN = 0.5 -- Cooldown after manual close
    
    -- Store reference to reset function for manual close
    self.partResetFunctions = self.partResetFunctions or {}
    self.partResetFunctions[plateKey] = function()
        manualCloseTime = tick() -- Record when manually closed
    end
    
    -- Function to check if player is still near the part
    local function isPlayerNearPart()
        if not self.humanoidRootPart then return false end
        
        local distance = (self.humanoidRootPart.Position - part.Position).Magnitude
        local maxDistance = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2 + 8 -- Part radius + buffer
        return distance <= maxDistance
    end
    
    -- Simple activation function
    local function tryActivateUI()
        local currentTime = tick()
        
        -- Debug logging for gem shop pressure plates
        if part.Name == "OpenGemShop" then
            Logger:Info(string.format("GemShop pressure plate activation attempt - plateKey: %s, state: %s, plateMap: %s", 
                plateKey, tostring(self.activePressurePlates[plateKey]), tostring(self.activePressurePlates)))
        end
        
        -- Check cooldowns
        if currentTime - lastActivation < ACTIVATION_COOLDOWN then
            if part.Name == "OpenGemShop" then
                Logger:Info("GemShop blocked by activation cooldown")
            end
            return false
        end
        
        if currentTime - manualCloseTime < MANUAL_CLOSE_COOLDOWN then
            if part.Name == "OpenGemShop" then
                Logger:Info("GemShop blocked by manual close cooldown")
            end
            return false
        end
        
        -- Check if UI is already open
        if self.activePressurePlates[plateKey] then
            if part.Name == "OpenGemShop" then
                Logger:Info("GemShop blocked - pressure plate state says it's already open")
            end
            return false
        end
        
        -- Open the UI
        self.activePressurePlates[plateKey] = true
        lastActivation = currentTime
        Logger:Info(string.format("PRESSURE PLATE: Opening %s from %s", config.screenGui, part.Name))
        self:_openUI(config.screenGui, config.uiType, plateKey)
        return true
    end
    
    -- Touch detection - only activates UI, doesn't track continuous state
    local touchConnection = part.Touched:Connect(function(hit)
        local humanoid = hit.Parent:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        
        local character = humanoid.Parent
        if character ~= self.character then return end
        
        -- Try to activate UI (respects cooldowns)
        tryActivateUI()
    end)
    
    -- Auto-close functionality if enabled
    if config.autoClose then
        local checkConnection = task.spawn(function()
            while true do
                task.wait(1.0) -- Check every second
                
                -- Only check if UI is open and should auto-close
                if self.activePressurePlates[plateKey] and not isPlayerNearPart() then
                    Logger:Info(string.format("PRESSURE PLATE: Auto-closing %s - player left %s", config.screenGui, part.Name))
                    self.activePressurePlates[plateKey] = false
                    self:_closeUI(config.screenGui, config.uiType)
                end
            end
        end)
        table.insert(self.connections, checkConnection)
    end
    
    table.insert(self.connections, touchConnection)
end

function UIManager:_setupExitButtons()
    -- Store the setup function for use in _openUI
    self._setupExitBTN = function(screenGuiName)
        local screenGui = self.playerGui:FindFirstChild(screenGuiName)
        if screenGui and screenGui.Enabled then
            local exitBTN = screenGui:FindFirstChild("Container")
            if exitBTN then exitBTN = exitBTN:FindFirstChild("ShopContainer") end
            if exitBTN then exitBTN = exitBTN:FindFirstChild("Header") end
            if exitBTN then exitBTN = exitBTN:FindFirstChild("ExitBTN") end
            
            if exitBTN and exitBTN:IsA("GuiButton") then
                Logger:Info("Setting up " .. screenGuiName .. " ExitBTN")
                local exitConnection = exitBTN.MouseButton1Click:Connect(function()
                    Logger:Info(screenGuiName .. " ExitBTN clicked!")
                    self:CloseUI(screenGuiName)
                end)
                table.insert(self.connections, exitConnection)
            else
                Logger:Warn("Could not find ExitBTN in " .. screenGuiName)
            end
        end
    end
    
    Logger:Info("✓ ExitBTN buttons setup complete")
end

function UIManager:_setupFooterButtons()
    task.spawn(function()
        task.wait(1)
        
        local footer = self.playerGui:FindFirstChild("Footer")
        if not footer then
            Logger:Warn("Footer GUI not found for footer buttons")
            return
        end
        
        local container = footer:FindFirstChild("Container")
        if not container then
            Logger:Warn("Container not found in Footer")
            return
        end
        
        local buttonContainer = container:FindFirstChild("ButtonContainer")
        if not buttonContainer then
            Logger:Warn("ButtonContainer not found in Container")
            return
        end
        
        -- Setup InventoryButton
        local inventoryButton = buttonContainer:FindFirstChild("InventoryButton")
        if inventoryButton and inventoryButton:IsA("GuiButton") then
            Logger:Info("Setting up InventoryButton")
            local inventoryConnection = inventoryButton.MouseButton1Click:Connect(function()
                Logger:Info("InventoryButton clicked!")
                self:_openUI("Inventory", "inventory")
            end)
            table.insert(self.connections, inventoryConnection)
            Logger:Info("✓ InventoryButton connected")
        else
            Logger:Warn("InventoryButton not found or not a GuiButton")
        end
        
        -- Setup EnchantButton (opens GemShop)
        local enchantButton = buttonContainer:FindFirstChild("EnchantButton")
        if enchantButton and enchantButton:IsA("GuiButton") then
            Logger:Info("Setting up EnchantButton")
            local enchantConnection = enchantButton.MouseButton1Click:Connect(function()
                Logger:Info("EnchantButton clicked - opening GemShop!")
                self:_openUI("GemShop", "gem_shop")
            end)
            table.insert(self.connections, enchantConnection)
            Logger:Info("✓ EnchantButton connected")
        else
            Logger:Warn("EnchantButton not found or not a GuiButton")
        end
        
        -- Setup DailyRewardsButton (opens DailyRewards) - now in separate MenuButtons GUI
        local menuButtonsGui = self.playerGui:FindFirstChild("MenuButtons")
        if menuButtonsGui then
            local menuContainer = menuButtonsGui:FindFirstChild("Container")
            if menuContainer then
                local dailyRewardsButton = menuContainer:FindFirstChild("DailyRewardsButton")
                if dailyRewardsButton and dailyRewardsButton:IsA("GuiButton") then
                    Logger:Info("Setting up DailyRewardsButton")
                    local dailyRewardsConnection = dailyRewardsButton.MouseButton1Click:Connect(function()
                        Logger:Info("DailyRewardsButton clicked - opening DailyRewards!")
                        self:_openUI("DailyRewards", "daily_rewards")
                    end)
                    table.insert(self.connections, dailyRewardsConnection)
                    Logger:Info("✓ DailyRewardsButton connected")
                else
                    Logger:Warn("DailyRewardsButton not found in MenuButtons.Container or not a GuiButton")
                end
                
                -- Setup GroupRewardButton (opens GroupRewards)
                local groupRewardButton = menuContainer:FindFirstChild("GroupRewardButton")
                if groupRewardButton and groupRewardButton:IsA("GuiButton") then
                    Logger:Info("Setting up GroupRewardButton")
                    local groupRewardConnection = groupRewardButton.MouseButton1Click:Connect(function()
                        Logger:Info("GroupRewardButton clicked - opening GroupRewards!")
                        self:_openUI("GroupRewards", "group_rewards")
                    end)
                    table.insert(self.connections, groupRewardConnection)
                    Logger:Info("✓ GroupRewardButton connected")
                else
                    Logger:Warn("GroupRewardButton not found in MenuButtons.Container or not a GuiButton")
                end
            else
                Logger:Warn("Container not found in MenuButtons GUI")
            end
        else
            Logger:Warn("MenuButtons GUI not found in PlayerGui - DailyRewardsButton not setup")
        end
        
        -- Setup ShopButton (opens GamepassShop) - look specifically in MenuButtons → Container → ShopButton
        task.spawn(function()
            task.wait(2) -- Give time for UI to load
            
            local menuButtonsGui = self.playerGui:FindFirstChild("MenuButtons")
            if menuButtonsGui then
                local container = menuButtonsGui:FindFirstChild("Container") 
                if container then
                    local shopButton = container:FindFirstChild("ShopButton")
                    if shopButton and shopButton:IsA("GuiButton") then
                        Logger:Info("Setting up ShopButton at: MenuButtons→Container→ShopButton")
                        local shopConnection = shopButton.MouseButton1Click:Connect(function()
                            Logger:Info("ShopButton clicked - opening GamepassShop!")
                            self:_openUI("GamepassShop", "gamepass_shop")
                        end)
                        table.insert(self.connections, shopConnection)
                        Logger:Info("✓ ShopButton connected")
                    else
                        Logger:Warn("ShopButton not found in MenuButtons→Container")
                    end
                else
                    Logger:Warn("Container not found in MenuButtons")
                end
            else
                Logger:Warn("MenuButtons GUI not found - ShopButton not setup")
            end
        end)
    end)
end

function UIManager:_setupGUITracking()
    -- Track specific GUIs for automatic scrolling when they become enabled
    local trackedGUIs = {
        ["DailyRewards"] = "daily_rewards",
        ["GroupRewards"] = "group_rewards",
        ["GemShop"] = "gem_shop"
    }
    
    local function setupGUITracking(guiName, uiType)
        local screenGui = self.playerGui:FindFirstChild(guiName)
        if screenGui then
            -- Set up tracking for this GUI
            local function onEnabledChanged()
                if screenGui.Enabled then
                    -- GUI was enabled - check if we need to start scrolling
                    if not self.scrollingAnimations[guiName] then
                        local container = screenGui:FindFirstChild("Container")
                        if container then
                            Logger:Info(guiName .. " GUI auto-enabled, starting scrolling background and synced fade-in")
                            
                            -- IMMEDIATELY hide scroller to prevent flash
                            local scroller = container:FindFirstChild("Scroller")
                            if scroller then
                                scroller.ImageTransparency = 1
                                scroller.BackgroundTransparency = 1
                            end
                            
                            -- Apply delayed container fade-in effect for auto-opened UIs (synced with scroller)
                            container.BackgroundTransparency = 1
                            task.spawn(function()
                                task.wait(0.75)
                                local fadeIn = TweenService:Create(
                                    container,
                                    TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                                    {BackgroundTransparency = 0.55}
                                )
                                fadeIn:Play()
                            end)
                            
                            -- Small delay to ensure container is ready, then start scrolling
                            task.spawn(function()
                                task.wait(0.1)
                                self:_startScrollingBackgroundForUI(container, guiName)
                            end)
                        end
                    end
                else
                    -- GUI was disabled - stop scrolling
                    if self.scrollingAnimations[guiName] then
                        Logger:Info(guiName .. " GUI disabled, stopping scrolling background")
                        self:_stopScrollingBackground(guiName)
                    end
                end
            end
            
            -- Connect to Enabled property changes
            local enabledConnection = screenGui:GetPropertyChangedSignal("Enabled"):Connect(onEnabledChanged)
            table.insert(self.connections, enabledConnection)
            
            -- Check initial state
            if screenGui.Enabled then
                onEnabledChanged()
            end
            
            Logger:Info("✓ Set up GUI tracking for " .. guiName)
            return true
        end
        return false
    end
    
    -- Try to set up tracking for existing GUIs
    for guiName, uiType in pairs(trackedGUIs) do
        if not setupGUITracking(guiName, uiType) then
            Logger:Debug("GUI " .. guiName .. " not found yet, will monitor for it")
        end
    end
    
    -- Monitor for new GUIs being added to PlayerGui
    local childAddedConnection = self.playerGui.ChildAdded:Connect(function(child)
        if child:IsA("ScreenGui") and trackedGUIs[child.Name] then
            Logger:Info("New tracked GUI added: " .. child.Name)
            setupGUITracking(child.Name, trackedGUIs[child.Name])
        end
    end)
    table.insert(self.connections, childAddedConnection)
end

function UIManager:_openUI(screenGuiName, uiType, plateKey)
    -- Debug logging for gem shop
    if screenGuiName == "GemShop" then
        local screenGui = self.playerGui:FindFirstChild(screenGuiName)
        Logger:Info(string.format("GemShop open attempt - openUIs state: %s, screenGui.Enabled: %s", 
            tostring(self.openUIs[screenGuiName]), 
            screenGui and tostring(screenGui.Enabled) or "nil"))
    end
    
    -- Prevent multiple opens of same UI
    if self.openUIs[screenGuiName] then 
        Logger:Debug(string.format("UI '%s' already open, skipping", screenGuiName))
        return 
    end
    
    local screenGui = self.playerGui:FindFirstChild(screenGuiName)
    if not screenGui then
        Logger:Warn(string.format("ScreenGui '%s' not found in PlayerGui", screenGuiName))
        
        -- Special handling for GemShop - try to find it more aggressively
        if screenGuiName == "GemShop" then
            Logger:Info("Searching more thoroughly for GemShop...")
            for _, child in pairs(self.playerGui:GetChildren()) do
                if child.Name == "GemShop" then
                    Logger:Info(string.format("Found GemShop: %s, Enabled: %s, Parent: %s", 
                        child.Name, tostring(child.Enabled), child.Parent and child.Parent.Name or "nil"))
                    screenGui = child
                    break
                end
            end
        end
        
        if not screenGui then
            -- Debug: List what ScreenGuis are available
            local availableGuis = {}
            for _, child in pairs(self.playerGui:GetChildren()) do
                if child:IsA("ScreenGui") then
                    table.insert(availableGuis, child.Name)
                end
            end
            Logger:Debug("Available ScreenGuis: " .. table.concat(availableGuis, ", "))
            return
        end
    end
    
    self.openUIs[screenGuiName] = true
    
    -- Apply 70% zoom effect for all UI menus
    self:_applyMenuZoomEffect()
    
    -- Handle specific UI types
    if uiType == "wish_fountain" then
        self:_openWishFountain(screenGui)
    elseif uiType == "gem_shop" then
        self:_openShop(screenGui, "gem")
    elseif uiType == "mushroom_shop" then
        self:_openShop(screenGui, "mushroom")
    elseif uiType == "mushroom_shop2" then
        self:_openShop(screenGui, "mushroom2")
    elseif uiType == "mushroom_shop3" then
        self:_openShop(screenGui, "mushroom3")
    elseif uiType == "inventory" then
        self:_openInventory(screenGui)
    elseif uiType == "daily_rewards" then
        self:_openDailyRewards(screenGui)
    elseif uiType == "group_rewards" then
        self:_openGroupRewards(screenGui)
    elseif uiType == "gamepass_shop" then
        self:_openGamepassShop(screenGui)
    end
    
    -- Track which plateKey was used to open this UI (if opened via pressure plate)
    if plateKey then
        self.openUIToPlateKey[screenGuiName] = plateKey
        Logger:Info(string.format("Tracked plateKey '%s' for opened UI: %s", plateKey, screenGuiName))
    end
    
    Logger:Info(string.format("Opened UI: %s (%s)", screenGuiName, uiType))
end

function UIManager:_closeUI(screenGuiName, uiType)
    -- Debug logging for gem shop
    if screenGuiName == "GemShop" then
        Logger:Info(string.format("GemShop close attempt - Current state: %s", tostring(self.openUIs[screenGuiName])))
    end
    
    if not self.openUIs[screenGuiName] then return end
    
    local screenGui = self.playerGui:FindFirstChild(screenGuiName)
    if not screenGui then return end
    
    self.openUIs[screenGuiName] = nil
    
    -- Debug logging for gem shop
    if screenGuiName == "GemShop" then
        Logger:Info("GemShop state cleared from openUIs")
    end
    
    -- Handle specific UI types
    if uiType == "wish_fountain" then
        self:_closeWishFountain(screenGui)
    elseif uiType == "gem_shop" then
        self:_closeShop(screenGui, "gem")
    elseif uiType == "mushroom_shop" then
        self:_closeShop(screenGui, "mushroom")
    elseif uiType == "mushroom_shop2" then
        self:_closeShop(screenGui, "mushroom2")
    elseif uiType == "mushroom_shop3" then
        self:_closeShop(screenGui, "mushroom3")
    elseif uiType == "inventory" then
        self:_closeInventory(screenGui)
    elseif uiType == "daily_rewards" then
        self:_closeDailyRewards(screenGui)
    elseif uiType == "group_rewards" then
        self:_closeGroupRewards(screenGui)
    elseif uiType == "gamepass_shop" then
        self:_closeGamepassShop(screenGui)
    end
    
    -- Remove zoom effect when no UIs are open
    local hasOpenUIs = false
    for _, _ in pairs(self.openUIs) do
        hasOpenUIs = true
        break
    end
    
    if not hasOpenUIs then
        self:_removeMenuZoomEffect()
    end
    
    Logger:Info(string.format("Closed UI: %s (%s)", screenGuiName, uiType))
end

function UIManager:_openWishFountain(screenGui)
    -- Phase 1: Slide Footer Container down and out of view
    local footerGui = self.playerGui:FindFirstChild("Footer")
    if footerGui then
        local footerContainer = footerGui:FindFirstChild("Container")
        if footerContainer then
            -- Store original position if not already stored
            if not footerContainer:GetAttribute("OriginalPosition") then
                footerContainer:SetAttribute("OriginalPosition", tostring(footerContainer.Position))
            end
            
            -- Slide Footer Container down off screen
            local footerSlideOut = TweenService:Create(
                footerContainer,
                TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                {Position = UDim2.new(footerContainer.Position.X.Scale, footerContainer.Position.X.Offset, 1.2, 0)}
            )
            
            footerSlideOut:Play()
            footerSlideOut.Completed:Connect(function()
                footerGui.Enabled = false
                self:_animateWishContainers(screenGui)
            end)
        else
            self:_animateWishContainers(screenGui)
        end
    else
        self:_animateWishContainers(screenGui)
    end
end

function UIManager:_animateWishContainers(screenGui)
    screenGui.Enabled = true
    
    local frame = screenGui:FindFirstChild("Frame")
    if not frame then return end
    
    local buttonContainer = frame:FindFirstChild("ButtonContainer")
    local itemContainer = frame:FindFirstChild("ItemContainer")
    
    if not buttonContainer or not itemContainer then return end
    
    -- Store original positions
    if not buttonContainer:GetAttribute("OriginalPosition") then
        buttonContainer:SetAttribute("OriginalPosition", tostring(buttonContainer.Position))
    end
    if not itemContainer:GetAttribute("OriginalPosition") then
        itemContainer:SetAttribute("OriginalPosition", tostring(itemContainer.Position))
    end
    
    -- Parse original positions
    local function parseUDim2FromString(str)
        local values = {}
        for value in str:gmatch("[-0-9.]+") do
            table.insert(values, tonumber(value))
        end
        if #values >= 4 then
            return UDim2.new(values[1], values[2], values[3], values[4])
        end
        return UDim2.new(0.5, 0, 0.5, 0)
    end
    
    local buttonOriginalPos = parseUDim2FromString(buttonContainer:GetAttribute("OriginalPosition"))
    local itemOriginalPos = parseUDim2FromString(itemContainer:GetAttribute("OriginalPosition"))
    
    -- Set initial positions (off-screen)
    buttonContainer.Position = UDim2.new(buttonOriginalPos.X.Scale, buttonOriginalPos.X.Offset, 1.2, 0) -- Below screen
    itemContainer.Position = UDim2.new(1.2, 0, itemOriginalPos.Y.Scale, itemOriginalPos.Y.Offset) -- Right of screen
    
    -- Phase 2: Slide ButtonContainer up from bottom
    local buttonSlideIn = TweenService:Create(
        buttonContainer,
        TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Position = buttonOriginalPos}
    )
    
    -- Phase 3: Slide ItemContainer in from right (with delay)
    local itemSlideIn = TweenService:Create(
        itemContainer,
        TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Position = itemOriginalPos}
    )
    
    -- Start animations
    buttonSlideIn:Play()
    
    task.wait(0.1) -- Small delay for stagger effect
    itemSlideIn:Play()
end

function UIManager:_closeFooter(footerGui, callback)
    local container = footerGui:FindFirstChild("Container")
    if not container then
        if callback then callback() end
        return
    end
    
    -- Slide container down off screen
    local slideOut = TweenService:Create(
        container,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {Position = UDim2.new(0, 0, 1.2, 0)}
    )
    
    slideOut:Play()
    slideOut.Completed:Connect(function()
        footerGui.Enabled = false
        if callback then callback() end
    end)
end

function UIManager:_animateWishFountainOpen(screenGui)
    screenGui.Enabled = true
    
    local frame = screenGui:FindFirstChild("Frame")
    if not frame then return end
    
    -- Animate the main Frame growing in (similar to shops)
    local originalSize = frame.Size
    frame.Size = UDim2.new(0, 0, 0, 0)
    
    local growIn = TweenService:Create(
        frame,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = originalSize}
    )
    growIn:Play()
end

function UIManager:_closeWishFountain(screenGui)
    local frame = screenGui:FindFirstChild("Frame")
    if not frame then
        screenGui.Enabled = false
        self:_restoreFooter()
        return
    end
    
    local buttonContainer = frame:FindFirstChild("ButtonContainer")
    local itemContainer = frame:FindFirstChild("ItemContainer")
    
    if not buttonContainer or not itemContainer then
        screenGui.Enabled = false
        self:_restoreFooter()
        return
    end
    
    -- Phase 1: Slide containers out
    local buttonSlideOut = TweenService:Create(
        buttonContainer,
        TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
        {Position = UDim2.new(buttonContainer.Position.X.Scale, buttonContainer.Position.X.Offset, 1.2, 0)}
    )
    
    local itemSlideOut = TweenService:Create(
        itemContainer,
        TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
        {Position = UDim2.new(1.2, 0, itemContainer.Position.Y.Scale, itemContainer.Position.Y.Offset)}
    )
    
    -- Start animations
    buttonSlideOut:Play()
    itemSlideOut:Play()
    
    -- When both complete, disable WishFountain and restore Footer
    local animationsCompleted = 0
    local function onAnimationComplete()
        animationsCompleted = animationsCompleted + 1
        if animationsCompleted >= 2 then
            screenGui.Enabled = false
            self:_restoreFooter()
        end
    end
    
    buttonSlideOut.Completed:Connect(onAnimationComplete)
    itemSlideOut.Completed:Connect(onAnimationComplete)
end

function UIManager:_restoreFooter()
    local footerGui = self.playerGui:FindFirstChild("Footer")
    if not footerGui then return end
    
    local footerContainer = footerGui:FindFirstChild("Container")
    if not footerContainer then return end
    
    -- Parse Footer's original position
    local function parseUDim2FromString(str)
        local values = {}
        for value in str:gmatch("[-0-9.]+") do
            table.insert(values, tonumber(value))
        end
        if #values >= 4 then
            return UDim2.new(values[1], values[2], values[3], values[4])
        end
        return UDim2.new(0, 0, 0.9, 0) -- Fallback
    end
    
    local footerOriginalPos = parseUDim2FromString(footerContainer:GetAttribute("OriginalPosition") or "0,0,0.9,0")
    
    -- Enable Footer and animate it back up
    footerGui.Enabled = true
    
    local footerSlideUp = TweenService:Create(
        footerContainer,
        TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Position = footerOriginalPos}
    )
    footerSlideUp:Play()
end

function UIManager:_openShop(screenGui, shopType)
    screenGui.Enabled = true
    
    -- Set up ExitBTN for this shop
    if self._setupExitBTN then
        task.spawn(function()
            task.wait(0.1) -- Small delay to ensure UI is fully loaded
            Logger:Info(string.format("Setting up exit button for %s", screenGui.Name))
            self._setupExitBTN(screenGui.Name)
        end)
    end
    
    -- Update shop UI - fire bindable event for all shop types
    if shopType == "mushroom" then
        task.spawn(function()
            task.wait(0.2) -- Allow UI to fully load
            -- Fire bindable event to notify ShopClient
            local shopOpenedEvent = ReplicatedStorage:FindFirstChild("ShopOpened")
            if shopOpenedEvent and shopOpenedEvent:IsA("BindableEvent") then
                shopOpenedEvent:Fire("mushroom")
            end
        end)
    elseif shopType == "mushroom2" then
        task.spawn(function()
            task.wait(0.2) -- Allow UI to fully load
            -- Fire bindable event to notify ShopClient
            local shopOpenedEvent = ReplicatedStorage:FindFirstChild("ShopOpened")
            if shopOpenedEvent and shopOpenedEvent:IsA("BindableEvent") then
                shopOpenedEvent:Fire("mushroom2")
            end
        end)
    elseif shopType == "mushroom3" then
        task.spawn(function()
            task.wait(0.2) -- Allow UI to fully load
            -- Fire bindable event to notify ShopClient
            local shopOpenedEvent = ReplicatedStorage:FindFirstChild("ShopOpened")
            if shopOpenedEvent and shopOpenedEvent:IsA("BindableEvent") then
                shopOpenedEvent:Fire("mushroom3")
            end
        end)
    elseif shopType == "gem" then
        task.spawn(function()
            task.wait(0.2) -- Allow UI to fully load
            -- Fire bindable event to notify ShopClient
            local shopOpenedEvent = ReplicatedStorage:FindFirstChild("ShopOpened")
            if shopOpenedEvent and shopOpenedEvent:IsA("BindableEvent") then
                shopOpenedEvent:Fire("gem_shop")
            end
        end)
    end
    
    if shopType == "gem" then
        -- Handle GemShop structure with Container (identical to mushroom shop)
        local container = screenGui:FindFirstChild("Container")
        
        if container then
            -- IMMEDIATELY hide scroller to prevent flash
            local scroller = container:FindFirstChild("Scroller")
            if scroller then
                scroller.ImageTransparency = 1
                scroller.BackgroundTransparency = 1
            end
            
            -- Store original size if not already stored
            if not container:GetAttribute("OriginalSize") then
                container:SetAttribute("OriginalSize", tostring(container.Size))
            end
            
            -- Parse original size
            local originalSizeStr = container:GetAttribute("OriginalSize")
            local function parseUDim2FromString(str)
                local values = {}
                for value in str:gmatch("[-0-9.]+") do
                    table.insert(values, tonumber(value))
                end
                if #values >= 4 then
                    return UDim2.new(values[1], values[2], values[3], values[4])
                end
                return UDim2.new(0.5, 0, 0.5, 0) -- Fallback
            end
            
            local originalSize = parseUDim2FromString(originalSizeStr)
            container.Size = UDim2.new(0, 0, 0, 0)
            
            local growIn = TweenService:Create(
                container,
                TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                {Size = originalSize}
            )
            growIn:Play()
            
            -- Start diagonal scrolling animation after container animation completes
            growIn.Completed:Connect(function()
                self:_startScrollingBackgroundForUI(container, "MushroomShop")
            end)
        end
    else
        -- Handle MushroomShop with Container structure (same as gem shop)
        local container = screenGui:FindFirstChild("Container")
        
        if container then
            -- IMMEDIATELY hide scroller to prevent flash
            local scroller = container:FindFirstChild("Scroller")
            if scroller then
                scroller.ImageTransparency = 1
                scroller.BackgroundTransparency = 1
            end
            
            -- Store original size if not already stored
            if not container:GetAttribute("OriginalSize") then
                container:SetAttribute("OriginalSize", tostring(container.Size))
            end
            
            -- Parse original size
            local originalSizeStr = container:GetAttribute("OriginalSize")
            local function parseUDim2FromString(str)
                local values = {}
                for value in str:gmatch("[-0-9.]+") do
                    table.insert(values, tonumber(value))
                end
                if #values >= 4 then
                    return UDim2.new(values[1], values[2], values[3], values[4])
                end
                return UDim2.new(0.5, 0, 0.5, 0) -- Fallback
            end
            
            local originalSize = parseUDim2FromString(originalSizeStr)
            container.Size = UDim2.new(0, 0, 0, 0)
            
            local growIn = TweenService:Create(
                container,
                TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                {Size = originalSize}
            )
            growIn:Play()
            
            -- Start diagonal scrolling animation after container animation completes
            growIn.Completed:Connect(function()
                self:_startScrollingBackgroundForUI(container, "MushroomShop")
            end)
        end
    end
end

function UIManager:_closeShop(screenGui, shopType)
    -- Stop scrolling animation for shops (all use MushroomShop now)
    if shopType == "gem" or shopType == "mushroom" or shopType == "mushroom2" or shopType == "mushroom3" then
        self:_stopScrollingBackground("MushroomShop")
    end
    
    -- Handle all shops with identical Container structure
    local container = screenGui:FindFirstChild("Container")
    
    if container then
        local shrinkOut = TweenService:Create(
            container,
            TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
            {Size = UDim2.new(0, 0, 0, 0)}
        )
        shrinkOut:Play()
        shrinkOut.Completed:Connect(function()
            if screenGui.Name == "GemShop" then
                Logger:Info(string.format("GemShop closing - Setting Enabled = false. Current Parent: %s", 
                    screenGui.Parent and screenGui.Parent.Name or "nil"))
            end
            screenGui.Enabled = false
            -- Check if we should remove zoom effect after closing
            self:_checkAndRemoveZoom()
        end)
    else
        if screenGui.Name == "GemShop" then
            Logger:Info(string.format("GemShop closing (no container) - Setting Enabled = false. Current Parent: %s", 
                screenGui.Parent and screenGui.Parent.Name or "nil"))
        end
        screenGui.Enabled = false
        -- Check if we should remove zoom effect after closing
        self:_checkAndRemoveZoom()
    end
end

-- Helper function to check if zoom should be removed
function UIManager:_checkAndRemoveZoom()
    local hasOpenUIs = false
    for _, _ in pairs(self.openUIs) do
        hasOpenUIs = true
        break
    end
    
    if not hasOpenUIs then
        self:_removeMenuZoomEffect()
    end
end

function UIManager:_closeAllUIs()
    for screenGuiName, _ in pairs(self.openUIs) do
        for _, config in pairs(UI_CONFIGS) do
            if config.screenGui == screenGuiName then
                self:_closeUI(screenGuiName, config.uiType)
                break
            end
        end
    end
    
    -- Reset pressure plate states
    self.activePressurePlates = {}
end

-- Manual UI control methods (for close buttons)
function UIManager:CloseUI(screenGuiName)
    Logger:Info(string.format("CloseUI called for: %s", screenGuiName))
    
    for _, config in pairs(UI_CONFIGS) do
        if config.screenGui == screenGuiName then
            self:_closeUI(screenGuiName, config.uiType)
            
            -- Use the tracked plateKey that was actually used to open this UI
            local plateKey = self.openUIToPlateKey[screenGuiName]
            Logger:Info(string.format("CloseUI - screenGui: %s, tracked plateKey: %s", screenGuiName, tostring(plateKey)))
            
            if plateKey then
                Logger:Info(string.format("Resetting pressure plate state for plateKey: %s (was: %s)", plateKey, tostring(self.activePressurePlates[plateKey])))
                self.activePressurePlates[plateKey] = nil
                Logger:Info(string.format("Pressure plate state after reset: %s", tostring(self.activePressurePlates[plateKey])))
                
                -- Clear the tracking for this UI
                self.openUIToPlateKey[screenGuiName] = nil
                Logger:Info(string.format("Cleared plateKey tracking for UI: %s", screenGuiName))
                
                -- Reset the part's touch detection and start manual close cooldown
                if self.partResetFunctions and self.partResetFunctions[plateKey] then
                    Logger:Info(string.format("Calling partResetFunction for plateKey: %s", plateKey))
                    self.partResetFunctions[plateKey]()
                else
                    Logger:Warn(string.format("No partResetFunction found for plateKey: %s", plateKey))
                end
            else
                Logger:Warn(string.format("No tracked plateKey found for screenGui: %s (UI may have been opened via button)", screenGuiName))
            end
            break
        end
    end
end

function UIManager:IsUIOpen(screenGuiName)
    return self.openUIs[screenGuiName] == true
end

function UIManager:GetOpenUIs()
    local openList = {}
    for screenGuiName, _ in pairs(self.openUIs) do
        table.insert(openList, screenGuiName)
    end
    return openList
end

-- Service linking method
function UIManager:SetGamepassClient(gamepassClient)
    self.gamepassClient = gamepassClient
    Logger:Info("UIManager: GamepassClient linked for dynamic pricing")
end

function UIManager:_zoomCameraIn()
    if not self.camera then
        self.camera = Workspace.CurrentCamera
        self.originalFOV = self.camera.FieldOfView
    end
    
    -- Cancel any existing FOV tween
    if self.fovTween then
        self.fovTween:Cancel()
    end
    
    -- Zoom camera in by reducing FOV from default (~70) to ~45
    local targetFOV = self.originalFOV * 0.65 -- 65% of original FOV for zoom effect
    
    self.fovTween = TweenService:Create(
        self.camera,
        TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {FieldOfView = targetFOV}
    )
    
    self.fovTween:Play()
    Logger:Debug(string.format("Zooming camera FOV from %.1f to %.1f", self.originalFOV, targetFOV))
end

function UIManager:_zoomCameraOut()
    if not self.camera then
        return
    end
    
    -- Cancel any existing FOV tween
    if self.fovTween then
        self.fovTween:Cancel()
    end
    
    -- Restore original FOV
    self.fovTween = TweenService:Create(
        self.camera,
        TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {FieldOfView = self.originalFOV}
    )
    
    self.fovTween:Play()
    Logger:Debug(string.format("Restoring camera FOV to %.1f", self.originalFOV))
end

function UIManager:_applyMenuZoomEffect()
    if not self.camera then
        self.camera = Workspace.CurrentCamera
        self.originalFOV = self.camera.FieldOfView
    end
    
    -- Cancel any existing FOV tween
    if self.fovTween then
        self.fovTween:Cancel()
    end
    
    -- Apply 70% zoom effect (30% reduction in FOV)
    local targetFOV = self.originalFOV * 0.7
    
    self.fovTween = TweenService:Create(
        self.camera,
        TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {FieldOfView = targetFOV}
    )
    
    self.fovTween:Play()
    Logger:Debug(string.format("Applying 70%% zoom effect - FOV from %.1f to %.1f", self.originalFOV, targetFOV))
end

function UIManager:_removeMenuZoomEffect()
    if not self.camera then
        return
    end
    
    -- Cancel any existing FOV tween
    if self.fovTween then
        self.fovTween:Cancel()
    end
    
    -- Restore original FOV
    self.fovTween = TweenService:Create(
        self.camera,
        TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {FieldOfView = self.originalFOV}
    )
    
    self.fovTween:Play()
    Logger:Debug(string.format("Removing zoom effect - restoring FOV to %.1f", self.originalFOV))
end

function UIManager:_openInventory(screenGui)
    screenGui.Enabled = true
    
    local frame = screenGui:FindFirstChild("Frame")
    if not frame then
        Logger:Warn("Frame not found in Inventory GUI")
        return
    end
    
    if not frame:GetAttribute("OriginalSize") then
        frame:SetAttribute("OriginalSize", tostring(frame.Size))
    end
    
    local function parseUDim2FromString(str)
        local values = {}
        for value in str:gmatch("[-0-9.]+") do
            table.insert(values, tonumber(value))
        end
        if #values >= 4 then
            return UDim2.new(values[1], values[2], values[3], values[4])
        end
        return UDim2.new(0.5, 0, 0.5, 0)
    end
    
    local originalSize = parseUDim2FromString(frame:GetAttribute("OriginalSize"))
    frame.Size = UDim2.new(0, 0, 0, 0)
    
    local growIn = TweenService:Create(
        frame,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = originalSize}
    )
    growIn:Play()
    
    self:_setupInventoryExitButton(screenGui)
    
    Logger:Info("Opened Inventory with grow animation")
end

function UIManager:_closeInventory(screenGui)
    local frame = screenGui:FindFirstChild("Frame")
    if not frame then
        screenGui.Enabled = false
        return
    end
    
    local shrinkOut = TweenService:Create(
        frame,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {Size = UDim2.new(0, 0, 0, 0)}
    )
    shrinkOut:Play()
    shrinkOut.Completed:Connect(function()
        screenGui.Enabled = false
    end)
    
    Logger:Info("Closed Inventory with shrink animation")
end

function UIManager:_setupInventoryExitButton(screenGui)
    task.spawn(function()
        task.wait(0.1)
        
        -- Navigate path: Inventory → Frame → InventoryBackground → ExitBTN
        local frame = screenGui:FindFirstChild("Frame")
        if not frame then 
            Logger:Warn("Frame not found in Inventory")
            return 
        end
        
        local inventoryBackground = frame:FindFirstChild("InventoryBackground")
        if not inventoryBackground then 
            Logger:Warn("InventoryBackground not found in Inventory Frame")
            return 
        end
        
        local exitBTN = inventoryBackground:FindFirstChild("ExitBTN")
        if exitBTN and exitBTN:IsA("GuiButton") then
            Logger:Info("Setting up Inventory ExitBTN at path: Frame→InventoryBackground→ExitBTN")
            local exitConnection = exitBTN.MouseButton1Click:Connect(function()
                Logger:Info("Inventory ExitBTN clicked!")
                self:CloseUI("Inventory")
            end)
            table.insert(self.connections, exitConnection)
        else
            Logger:Warn("ExitBTN not found in Inventory InventoryBackground")
        end
    end)
end

function UIManager:_openDailyRewards(screenGui)
    screenGui.Enabled = true
    
    local container = screenGui:FindFirstChild("Container")
    if not container then
        Logger:Warn("Container not found in DailyRewards GUI")
        return
    end
    
    -- IMMEDIATELY hide scroller to prevent flash
    local scroller = container:FindFirstChild("Scroller")
    if scroller then
        scroller.ImageTransparency = 1
        scroller.BackgroundTransparency = 1
    end
    
    if not container:GetAttribute("OriginalSize") then
        container:SetAttribute("OriginalSize", tostring(container.Size))
    end
    
    -- Start container invisible for fade-in effect
    container.BackgroundTransparency = 1
    
    local function parseUDim2FromString(str)
        local values = {}
        for value in str:gmatch("[-0-9.]+") do
            table.insert(values, tonumber(value))
        end
        if #values >= 4 then
            return UDim2.new(values[1], values[2], values[3], values[4])
        end
        return UDim2.new(0.5, 0, 0.5, 0)
    end
    
    local originalSize = parseUDim2FromString(container:GetAttribute("OriginalSize"))
    container.Size = UDim2.new(0, 0, 0, 0)
    
    -- Create grow animation (immediate)
    local growIn = TweenService:Create(
        container,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = originalSize}
    )
    
    growIn:Play()
    
    -- Create delayed fade-in animation (0.75 second delay to sync with scroller)
    task.spawn(function()
        task.wait(0.75)
        local fadeIn = TweenService:Create(
            container,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.55}
        )
        fadeIn:Play()
    end)
    
    -- Start diagonal scrolling animation after container animation completes
    growIn.Completed:Connect(function()
        self:_startScrollingBackgroundForUI(container, "DailyRewards")
    end)
    
    -- Setup exit button for DailyRewards
    self:_setupDailyRewardsExitButton(screenGui)
    
    Logger:Info("Opened DailyRewards with grow and synced fade-in animation")
end

function UIManager:_closeDailyRewards(screenGui)
    -- Stop scrolling animation
    self:_stopScrollingBackground("DailyRewards")
    
    local container = screenGui:FindFirstChild("Container")
    if not container then
        screenGui.Enabled = false
        return
    end
    
    local shrinkOut = TweenService:Create(
        container,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {Size = UDim2.new(0, 0, 0, 0)}
    )
    shrinkOut:Play()
    shrinkOut.Completed:Connect(function()
        screenGui.Enabled = false
    end)
    
    Logger:Info("Closed DailyRewards with shrink animation")
end

function UIManager:_setupDailyRewardsExitButton(screenGui)
    task.spawn(function()
        task.wait(0.1)
        
        -- Try multiple possible paths for DailyRewards ExitBTN
        local container = screenGui:FindFirstChild("Container")
        if not container then 
            Logger:Warn("Container not found in DailyRewards")
            return 
        end
        
        -- First try direct path: Container → ExitBTN
        local exitBTN = container:FindFirstChild("ExitBTN")
        
        -- If not found, try shop-style path: Container → ShopContainer → Header → ExitBTN
        if not exitBTN then
            local shopContainer = container:FindFirstChild("ShopContainer")
            if shopContainer then
                local header = shopContainer:FindFirstChild("Header")
                if header then
                    exitBTN = header:FindFirstChild("ExitBTN")
                end
            end
        end
        
        -- If still not found, try other common locations
        if not exitBTN then
            -- Try Container → Header → ExitBTN
            local header = container:FindFirstChild("Header")
            if header then
                exitBTN = header:FindFirstChild("ExitBTN")
            end
        end
        
        if exitBTN and exitBTN:IsA("GuiButton") then
            Logger:Info("Setting up DailyRewards ExitBTN found at: " .. exitBTN:GetFullName())
            local exitConnection = exitBTN.MouseButton1Click:Connect(function()
                Logger:Info("DailyRewards ExitBTN clicked!")
                self:CloseUI("DailyRewards")
            end)
            table.insert(self.connections, exitConnection)
        else
            Logger:Warn("ExitBTN not found in DailyRewards Container - checked multiple paths")
            -- Debug: List all children of container
            local children = {}
            for _, child in pairs(container:GetChildren()) do
                table.insert(children, child.Name .. "(" .. child.ClassName .. ")")
            end
            Logger:Debug("DailyRewards Container children: " .. table.concat(children, ", "))
        end
    end)
end

function UIManager:_openGroupRewards(screenGui)
    screenGui.Enabled = true
    
    local container = screenGui:FindFirstChild("Container")
    if not container then
        Logger:Warn("Container not found in GroupRewards GUI")
        return
    end
    
    -- IMMEDIATELY hide scroller to prevent flash
    local scroller = container:FindFirstChild("Scroller")
    if scroller then
        scroller.ImageTransparency = 1
        scroller.BackgroundTransparency = 1
    end
    
    if not container:GetAttribute("OriginalSize") then
        container:SetAttribute("OriginalSize", tostring(container.Size))
    end
    
    -- Start container invisible for fade-in effect
    container.BackgroundTransparency = 1
    
    local function parseUDim2FromString(str)
        local values = {}
        for value in str:gmatch("[-0-9.]+") do
            table.insert(values, tonumber(value))
        end
        if #values >= 4 then
            return UDim2.new(values[1], values[2], values[3], values[4])
        end
        return UDim2.new(0.5, 0, 0.5, 0)
    end
    
    local originalSize = parseUDim2FromString(container:GetAttribute("OriginalSize"))
    container.Size = UDim2.new(0, 0, 0, 0)
    
    -- Create grow animation (immediate)
    local growIn = TweenService:Create(
        container,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = originalSize}
    )
    
    growIn:Play()
    
    -- Create delayed fade-in animation (0.75 second delay to sync with scroller)
    task.spawn(function()
        task.wait(0.75)
        local fadeIn = TweenService:Create(
            container,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.55}
        )
        fadeIn:Play()
    end)
    
    -- Start diagonal scrolling animation after container animation completes
    growIn.Completed:Connect(function()
        self:_startScrollingBackground(container)
    end)
    
    -- Setup exit button for GroupRewards
    self:_setupGroupRewardsExitButton(screenGui)
    
    -- Setup verify button for GroupRewards
    self:_setupGroupRewardsVerifyButton(screenGui)
    
    Logger:Info("Opened GroupRewards with grow and synced fade-in animation")
end

function UIManager:_closeGroupRewards(screenGui)
    -- Stop scrolling animation
    self:_stopScrollingBackground("GroupRewards")
    
    local container = screenGui:FindFirstChild("Container")
    if not container then
        screenGui.Enabled = false
        return
    end
    
    local shrinkOut = TweenService:Create(
        container,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {Size = UDim2.new(0, 0, 0, 0)}
    )
    shrinkOut:Play()
    shrinkOut.Completed:Connect(function()
        screenGui.Enabled = false
    end)
    
    Logger:Info("Closed GroupRewards with shrink animation")
end

function UIManager:_setupGroupRewardsExitButton(screenGui)
    task.spawn(function()
        task.wait(0.1)
        
        -- Navigate path: GroupRewards → Container → Background → ExitBTN
        local container = screenGui:FindFirstChild("Container")
        if not container then 
            Logger:Warn("Container not found in GroupRewards")
            return 
        end
        
        local background = container:FindFirstChild("Background")
        if not background then 
            Logger:Warn("Background not found in GroupRewards Container")
            return 
        end
        
        local exitBTN = background:FindFirstChild("ExitBTN")
        if exitBTN and exitBTN:IsA("GuiButton") then
            Logger:Info("Setting up GroupRewards ExitBTN at path: Container→Background→ExitBTN")
            local exitConnection = exitBTN.MouseButton1Click:Connect(function()
                Logger:Info("GroupRewards ExitBTN clicked!")
                self:CloseUI("GroupRewards")
            end)
            table.insert(self.connections, exitConnection)
        else
            Logger:Warn("ExitBTN not found in GroupRewards Container→Background")
            -- Debug: List all children of background
            if background then
                local children = {}
                for _, child in pairs(background:GetChildren()) do
                    table.insert(children, child.Name .. "(" .. child.ClassName .. ")")
                end
                Logger:Debug("GroupRewards Background children: " .. table.concat(children, ", "))
            end
        end
    end)
end

function UIManager:_setupGroupRewardsVerifyButton(screenGui)
    task.spawn(function()
        task.wait(0.1)
        
        -- Navigate path: GroupRewards → Container → Background → VerifyBTN
        local container = screenGui:FindFirstChild("Container")
        if not container then 
            Logger:Warn("Container not found in GroupRewards for VerifyBTN")
            return 
        end
        
        local background = container:FindFirstChild("Background")
        if not background then 
            Logger:Warn("Background not found in GroupRewards Container for VerifyBTN")
            return 
        end
        
        local verifyBTN = background:FindFirstChild("VerifyBTN")
        if verifyBTN and verifyBTN:IsA("GuiButton") then
            Logger:Info("Setting up GroupRewards VerifyBTN at path: Container→Background→VerifyBTN")
            
            -- Check claim status from server first
            self:_checkGroupRewardStatus(verifyBTN)
            
            local verifyConnection = verifyBTN.MouseButton1Click:Connect(function()
                Logger:Info("GroupRewards VerifyBTN clicked!")
                self:_handleGroupVerification(verifyBTN)
            end)
            table.insert(self.connections, verifyConnection)
        else
            Logger:Warn("VerifyBTN not found in GroupRewards Container→Background")
        end
    end)
end

function UIManager:_checkGroupRewardStatus(verifyButton)
    task.spawn(function()
        -- Get the server status for this player's group reward
        local remoteEvents = ReplicatedStorage:FindFirstChild("Shared")
        if not remoteEvents then
            Logger:Warn("Shared folder not found in ReplicatedStorage")
            return
        end
        
        remoteEvents = remoteEvents:FindFirstChild("RemoteEvents")
        if not remoteEvents then
            Logger:Warn("RemoteEvents folder not found")
            return
        end
        
        local groupRewardEvents = remoteEvents:FindFirstChild("GroupRewardEvents")
        if not groupRewardEvents then
            Logger:Warn("GroupRewardEvents folder not found")
            return
        end
        
        local getStatusFunction = groupRewardEvents:FindFirstChild("GetGroupRewardStatus")
        if not getStatusFunction then
            Logger:Warn("GetGroupRewardStatus RemoteFunction not found")
            return
        end
        
        local success, result = pcall(function()
            return getStatusFunction:InvokeServer()
        end)
        
        if success and result then
            if result.claimed then
                -- Player has already claimed - disable button
                verifyButton.Active = false
                verifyButton.AutoButtonColor = false
                verifyButton.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
                
                -- Update the TextLabel inside the ImageButton
                local textLabel = verifyButton:FindFirstChild("TextLabel")
                if textLabel then
                    textLabel.Text = "Already Claimed"
                end
                
                Logger:Info("Group reward already claimed - button disabled")
            else
                -- Player hasn't claimed - enable button
                verifyButton.Active = true
                verifyButton.AutoButtonColor = true
                Logger:Info("Group reward not yet claimed - button enabled")
            end
        else
            Logger:Warn("Failed to check group reward status from server: " .. tostring(result))
        end
    end)
end

function UIManager:_handleGroupVerification(verifyButton)
    Logger:Info("Player " .. self.player.Name .. " clicked group verification button")
    
    -- Let the server handle all group checking and validation
    -- This prevents client-side bypassing and ensures consistent logic
    local remoteEvents = ReplicatedStorage:FindFirstChild("Shared")
    if remoteEvents then
        remoteEvents = remoteEvents:FindFirstChild("RemoteEvents")
        if remoteEvents then
            local groupRewardEvents = remoteEvents:FindFirstChild("GroupRewardEvents")
            if groupRewardEvents then
                local groupRewardEvent = groupRewardEvents:FindFirstChild("ClaimGroupReward")
                if groupRewardEvent then
                    -- Disable the button immediately to prevent double-clicking
                    verifyButton.Active = false
                    verifyButton.AutoButtonColor = false
                    verifyButton.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
                    
                    -- Update the TextLabel inside the ImageButton
                    local textLabel = verifyButton:FindFirstChild("TextLabel")
                    if textLabel then
                        textLabel.Text = "Processing..."
                    end
                    
                    -- Send to server for processing
                    groupRewardEvent:FireServer()
                    Logger:Info("Group reward claim sent to server")
                    
                    -- Wait a moment then re-check status to ensure server has processed
                    task.spawn(function()
                        task.wait(2)  -- Give server time to process
                        self:_checkGroupRewardStatus(verifyButton)
                    end)
                else
                    Logger:Warn("ClaimGroupReward RemoteEvent not found in GroupRewardEvents")
                end
            else
                Logger:Warn("GroupRewardEvents folder not found")
            end
        else
            Logger:Warn("RemoteEvents folder not found")
        end
    else
        Logger:Warn("Shared folder not found in ReplicatedStorage")
    end
end

function UIManager:_showNotification(title, message, color)
    -- Simple notification system - you may want to integrate with existing notification UI
    Logger:Info("NOTIFICATION: " .. title .. " - " .. message)
    
    -- You can expand this to show actual UI notifications
    -- For now, this logs the notification and could be expanded to show GUI notifications
end

function UIManager:_startScrollingBackground(container)
    -- This is the old method, now redirects to the new generalized one
    self:_startScrollingBackgroundForUI(container, "GroupRewards")
end

function UIManager:_startScrollingBackgroundForUI(container, uiName)
    local scroller = container:FindFirstChild("Scroller")
    if not scroller then
        Logger:Warn("Scroller not found in " .. uiName .. " Container")
        return
    end
    
    -- Stop any existing scrolling animation for this UI
    self:_stopScrollingBackground(uiName)
    
    -- Handle scrolling background with tiled approach for smooth animation
    local tileSize = 45 -- Your tile size is 0,45,0,45
    
    -- IMMEDIATELY set scroller to invisible to prevent flash
    scroller.ImageTransparency = 1
    scroller.BackgroundTransparency = 1
    
    -- Set up size to be larger than container for seamless scrolling effect
    -- Use scale 1.2 (120%) to cover the area while staying mostly visible
    scroller.Size = UDim2.new(1.2, tileSize, 1.2, tileSize)
    
    -- Start position: offset by negative tile size for smooth entry
    scroller.Position = UDim2.new(-0.1, -tileSize, -0.1, -tileSize)
    
    -- End position: move by exactly one tile size for seamless loop
    local endPosition = UDim2.new(-0.1, 0, -0.1, 0)
    
    -- Create infinite diagonal scrolling animation (down and right)
    local tweenInfo = TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false)
    local scrollTween = TweenService:Create(
        scroller,
        tweenInfo,
        {Position = endPosition}
    )
    
    -- Start scrolling animation immediately but invisible
    scrollTween:Play()
    
    -- Fade in the scroller after 0.75 seconds to match Container
    task.spawn(function()
        task.wait(0.75)
        
        -- Only fade in if the animation is still active
        if self.scrollingAnimations[uiName] then
            -- Determine background transparency based on UI type
            local backgroundTransparency = 0 -- Default for most UIs
            if uiName == "GemShop" then
                backgroundTransparency = 1 -- Keep gem shop scroller background transparent
                Logger:Info(string.format("GemShop detected - setting scroller backgroundTransparency to 1 (transparent)"))
            else
                Logger:Info(string.format("Non-GemShop UI (%s) - setting scroller backgroundTransparency to 0 (visible)", uiName))
            end
            
            local fadeInTween = TweenService:Create(
                scroller,
                TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {ImageTransparency = 0, BackgroundTransparency = backgroundTransparency}
            )
            fadeInTween:Play()
            
            Logger:Info(string.format("Scroller faded in after 0.75 second delay for %s (backgroundTransparency: %d)", uiName, backgroundTransparency))
        end
    end)
    
    -- Store the animation for cleanup
    self.scrollingAnimations[uiName] = scrollTween
    
    Logger:Info("Started smooth diagonal scrolling background for " .. uiName .. " with tile size: " .. tileSize)
end

function UIManager:_stopScrollingBackground(uiName)
    local animation = self.scrollingAnimations[uiName]
    if animation then
        animation:Cancel()
        self.scrollingAnimations[uiName] = nil
        Logger:Info("Stopped scrolling background for " .. uiName)
    end
end

function UIManager:_openGamepassShop(screenGui)
    screenGui.Enabled = true
    
    -- Set up ExitBTN for GamepassShop with custom logic
    task.spawn(function()
        task.wait(0.1) -- Small delay to ensure UI is fully loaded
        Logger:Info("Setting up exit button for GamepassShop")
        self:_setupGamepassShopExitButton(screenGui)
    end)
    
    -- Trigger dynamic pricing update
    if self.gamepassClient then
        self.gamepassClient:TriggerPricingUpdate("GamepassShop")
    end
    
    -- Handle GamepassShop structure (similar to other shops)
    local container = screenGui:FindFirstChild("Container")
    
    if container then
        -- Store original size if not already stored
        if not container:GetAttribute("OriginalSize") then
            container:SetAttribute("OriginalSize", tostring(container.Size))
        end
        
        -- Parse original size
        local originalSizeStr = container:GetAttribute("OriginalSize")
        local function parseUDim2FromString(str)
            local values = {}
            for value in str:gmatch("[-0-9.]+") do
                table.insert(values, tonumber(value))
            end
            if #values >= 4 then
                return UDim2.new(values[1], values[2], values[3], values[4])
            end
            return UDim2.new(0.5, 0, 0.5, 0) -- Fallback
        end
        
        local originalSize = parseUDim2FromString(originalSizeStr)
        container.Size = UDim2.new(0, 0, 0, 0)
        
        local growIn = TweenService:Create(
            container,
            TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = originalSize}
        )
        growIn:Play()
    else
        -- Handle if GamepassShop doesn't use Container structure
        local frame = screenGui:FindFirstChild("Frame")
        if frame then
            if not frame:GetAttribute("OriginalSize") then
                frame:SetAttribute("OriginalSize", tostring(frame.Size))
            end
            
            local function parseUDim2FromString(str)
                local values = {}
                for value in str:gmatch("[-0-9.]+") do
                    table.insert(values, tonumber(value))
                end
                if #values >= 4 then
                    return UDim2.new(values[1], values[2], values[3], values[4])
                end
                return UDim2.new(0.5, 0, 0.5, 0)
            end
            
            local originalSize = parseUDim2FromString(frame:GetAttribute("OriginalSize"))
            frame.Size = UDim2.new(0, 0, 0, 0)
            
            local growIn = TweenService:Create(
                frame,
                TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                {Size = originalSize}
            )
            growIn:Play()
        end
    end
    
    Logger:Info("Opened GamepassShop with grow animation")
end

function UIManager:_closeGamepassShop(screenGui)
    -- Handle GamepassShop structure (similar to other shops)
    local container = screenGui:FindFirstChild("Container")
    
    if container then
        local shrinkOut = TweenService:Create(
            container,
            TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
            {Size = UDim2.new(0, 0, 0, 0)}
        )
        shrinkOut:Play()
        shrinkOut.Completed:Connect(function()
            screenGui.Enabled = false
        end)
    else
        -- Handle if GamepassShop doesn't use Container structure
        local frame = screenGui:FindFirstChild("Frame")
        if frame then
            local shrinkOut = TweenService:Create(
                frame,
                TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
                {Size = UDim2.new(0, 0, 0, 0)}
            )
            shrinkOut:Play()
            shrinkOut.Completed:Connect(function()
                screenGui.Enabled = false
            end)
        else
            screenGui.Enabled = false
        end
    end
    
    Logger:Info("Closed GamepassShop with shrink animation")
end

function UIManager:_setupGamepassShopExitButton(screenGui)
    -- Search for ExitBTN in GamepassShop using multiple possible paths
    local function findExitButton(parent, depth)
        if depth > 4 then return nil end -- Prevent infinite recursion
        
        for _, child in pairs(parent:GetChildren()) do
            if child.Name == "ExitBTN" and child:IsA("GuiButton") then
                return child
            elseif child:IsA("GuiObject") then
                local found = findExitButton(child, depth + 1)
                if found then return found end
            end
        end
        return nil
    end
    
    local exitBTN = findExitButton(screenGui, 0)
    
    if exitBTN then
        Logger:Info("Found GamepassShop ExitBTN at: " .. exitBTN:GetFullName())
        local exitConnection = exitBTN.MouseButton1Click:Connect(function()
            Logger:Info("GamepassShop ExitBTN clicked!")
            self:CloseUI("GamepassShop")
        end)
        table.insert(self.connections, exitConnection)
        Logger:Info("✓ GamepassShop ExitBTN connected successfully")
    else
        Logger:Warn("ExitBTN not found in GamepassShop")
        -- Debug: List all children of GamepassShop
        local function listChildren(parent, prefix)
            for _, child in pairs(parent:GetChildren()) do
                Logger:Debug(prefix .. child.Name .. " (" .. child.ClassName .. ")")
                if child:IsA("GuiObject") and #child:GetChildren() > 0 then
                    listChildren(child, prefix .. "  ")
                end
            end
        end
        Logger:Debug("GamepassShop structure:")
        listChildren(screenGui, "  ")
    end
end

function UIManager:Cleanup()
    Logger:Info("UIManager shutting down...")
    
    -- Disconnect all connections
    for _, connection in pairs(self.connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    -- Close all UIs
    self:_closeAllUIs()
    
    -- Stop all scrolling animations
    for uiName, animation in pairs(self.scrollingAnimations) do
        if animation then
            animation:Cancel()
        end
    end
    
    -- Clear tables
    self.connections = {}
    self.openUIs = {}
    self.activePressurePlates = {}
    self.openUIToPlateKey = {}
    self.scrollingAnimations = {}
    
    Logger:Info("✓ UIManager shutdown complete")
end

return UIManager