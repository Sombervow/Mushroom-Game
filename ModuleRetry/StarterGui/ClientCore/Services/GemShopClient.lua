local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local GemShopClient = {}
GemShopClient.__index = GemShopClient

local player = Players.LocalPlayer

local UPGRADE_CONFIGS = {
    FastRunner = {
        startingCost = 10,
        costIncrease = 2,
        speedBoostPercent = 0.04,
        containerName = "FastRunner",
        buttonName = "PurchaseFastRunner",
        remoteName = "PurchaseFastRunner",
        syncRemoteName = "SyncFastRunner",
        confirmRemoteName = "FastRunnerConfirm"
    }
}

function GemShopClient.new()
    local self = setmetatable({}, GemShopClient)
    
    self._connections = {}
    self._remoteEvents = {}
    self._upgrades = {}
    
    -- Initialize each upgrade
    for upgradeName, config in pairs(UPGRADE_CONFIGS) do
        self._upgrades[upgradeName] = {
            level = 1,  -- Start at level 1 to match server
            cost = config.startingCost,
            ui = {}
        }
    end
    
    self:_initialize()
    return self
end

function GemShopClient:_initialize()
    Logger:Info("GemShopClient initializing... (DISABLED - ShopClient handles everything)")
    -- All functionality disabled to prevent conflicts with ShopClient
end

function GemShopClient:_waitForUI()
    local gemShop = player.PlayerGui:WaitForChild("GemShop", 30)
    if not gemShop then
        Logger:Error("GemShop GUI not found")
        return
    end
    
    local container = gemShop:WaitForChild("Container", 10)
    local shopContainer = container:WaitForChild("ShopContainer", 10) 
    local gemShopInner = shopContainer:WaitForChild("GemShop", 10)
    local shroomBackground = gemShopInner:WaitForChild("ShroomBackground", 10)
    local scrollingFrame = shroomBackground:WaitForChild("ScrollingFrame", 10)
    
    -- Find UI elements for each upgrade
    for upgradeName, config in pairs(UPGRADE_CONFIGS) do
        local upgradeContainer = scrollingFrame:WaitForChild(config.containerName, 10)
        if upgradeContainer then
            local upgradeData = self._upgrades[upgradeName]
            upgradeData.ui.container = upgradeContainer
            upgradeData.ui.button = upgradeContainer:WaitForChild(config.buttonName, 10)
            upgradeData.ui.gemCost = upgradeData.ui.button:FindFirstChild("GemCost")
            upgradeData.ui.upgradeLevel = upgradeContainer:FindFirstChild("UpgradeLevel")
            upgradeData.ui.nextUpgrade = upgradeContainer:FindFirstChild("NextUpgrade")
            
            Logger:Info(string.format("%s UI references found", upgradeName))
        else
            Logger:Error(string.format("%s container not found", upgradeName))
        end
    end
end

function GemShopClient:_setupRemotes()
    local gemShopRemotes = ReplicatedStorage:WaitForChild("GemShopRemotes", 10)
    if not gemShopRemotes then
        Logger:Error("GemShopRemotes folder not found")
        return
    end
    
    -- Setup remotes for each upgrade
    for upgradeName, config in pairs(UPGRADE_CONFIGS) do
        self._remoteEvents[upgradeName] = {
            Purchase = gemShopRemotes:WaitForChild(config.remoteName, 10),
            Sync = gemShopRemotes:WaitForChild(config.syncRemoteName, 10),
            Confirm = gemShopRemotes:WaitForChild(config.confirmRemoteName, 10)
        }
        
        local remotes = self._remoteEvents[upgradeName]
        if remotes.Purchase and remotes.Sync and remotes.Confirm then
            -- Connect sync and confirm events
            self._connections[upgradeName .. "Sync"] = remotes.Sync.OnClientEvent:Connect(function(level, ...)
                self:_onSync(upgradeName, level, ...)
            end)
            
            self._connections[upgradeName .. "Confirm"] = remotes.Confirm.OnClientEvent:Connect(function(level, ...)
                self:_onPurchaseConfirm(upgradeName, level, ...)
            end)
            
            Logger:Info(string.format("%s remotes connected", upgradeName))
        else
            Logger:Error(string.format("Failed to find %s remote events", upgradeName))
        end
    end
end

function GemShopClient:_connectButtons()
    -- DISABLED: ShopClient handles button connections now to prevent conflicts
    Logger:Info("GemShopClient button connections disabled - ShopClient handles them")
end

function GemShopClient:_connectGemUpdates()
    local leaderstats = player:FindFirstChild("leaderstats") or player:WaitForChild("leaderstats", 10)
    if leaderstats then
        local gems = leaderstats:FindFirstChild("Gems")
        if gems then
            self._connections.GemChanged = gems.Changed:Connect(function()
                self:_updateAllButtonStates()
            end)
        end
    end
end

function GemShopClient:_calculateCost(upgradeName, level)
    local config = UPGRADE_CONFIGS[upgradeName]
    -- Level 1 is the starting level, so cost is based on upgrades beyond level 1
    return config.startingCost + ((level - 1) * config.costIncrease)
end

function GemShopClient:_calculateBonus(upgradeName, level)
    local config = UPGRADE_CONFIGS[upgradeName]
    if upgradeName == "FastRunner" then
        return level * config.speedBoostPercent * 100
    end
    return 0
end

function GemShopClient:_formatCost(cost)
    if cost >= 1000 then
        return string.format("%.1fK", cost / 1000)
    else
        return tostring(cost)
    end
end

function GemShopClient:_formatBonus(upgradeName, bonus)
    if upgradeName == "FastRunner" then
        if bonus == math.floor(bonus) then
            return tostring(math.floor(bonus)) .. "%+"
        else
            return string.format("%.1f", bonus) .. "%+"
        end
    end
    return tostring(bonus)
end

function GemShopClient:_getCurrentGems()
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return 0 end
    
    local gems = leaderstats:FindFirstChild("Gems")
    if not gems then return 0 end
    
    return gems.Value
end

function GemShopClient:_canAffordPurchase(upgradeName)
    return self:_getCurrentGems() >= self._upgrades[upgradeName].cost
end

function GemShopClient:_updateGUI(upgradeName)
    local upgradeData = self._upgrades[upgradeName]
    local ui = upgradeData.ui
    
    -- Update cost in button
    if ui.gemCost then
        ui.gemCost.Text = self:_formatCost(upgradeData.cost)
    end
    
    -- Update level display (show next level to purchase)
    if ui.upgradeLevel then
        local displayLevel = math.max(1, upgradeData.level + 1)
        ui.upgradeLevel.Text = "Lv. " .. tostring(displayLevel)
    end
    
    -- Update next upgrade display (current -> next)
    if ui.nextUpgrade then
        local currentBonus = self:_calculateBonus(upgradeName, upgradeData.level)
        local nextBonus = self:_calculateBonus(upgradeName, upgradeData.level + 1)
        ui.nextUpgrade.Text = self:_formatBonus(upgradeName, currentBonus) .. " -> " .. self:_formatBonus(upgradeName, nextBonus)
    end
    
    Logger:Debug(string.format("%s GUI updated - Level: %d, Cost: %s", 
        upgradeName, upgradeData.level, self:_formatCost(upgradeData.cost)))
end

function GemShopClient:_updateButtonState(upgradeName)
    local upgradeData = self._upgrades[upgradeName]
    local button = upgradeData.ui.button
    if not button then return end
    
    if self:_canAffordPurchase(upgradeName) then
        -- Can afford - green appearance
        button.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
        button.Active = true
        if upgradeData.ui.gemCost then
            upgradeData.ui.gemCost.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    else
        -- Can't afford - grayed out
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
        button.Active = true -- Keep active for shake animation
        if upgradeData.ui.gemCost then
            upgradeData.ui.gemCost.TextColor3 = Color3.fromRGB(255, 100, 100)
        end
    end
end

function GemShopClient:_updateAllButtonStates()
    for upgradeName in pairs(self._upgrades) do
        self:_updateButtonState(upgradeName)
    end
end

function GemShopClient:_animateButtonClick(upgradeName)
    local button = self._upgrades[upgradeName].ui.button
    if not button then return end
    
    if not self:_canAffordPurchase(upgradeName) then
        -- Shake animation for insufficient funds
        local originalPosition = button.Position
        
        local shakeInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
        local shakeTween = TweenService:Create(button, shakeInfo, {
            Position = originalPosition + UDim2.new(0, 5, 0, 0)
        })
        
        shakeTween:Play()
        shakeTween.Completed:Connect(function()
            button.Position = originalPosition
        end)
        
        Logger:Info(string.format("Insufficient gems for %s! Need: %d, Have: %d", 
            upgradeName, self._upgrades[upgradeName].cost, self:_getCurrentGems()))
        return
    end
    
    -- Success animation - button press effect
    local originalSize = button.Size
    local pressedSize = UDim2.new(originalSize.X.Scale * 0.95, originalSize.X.Offset, 
        originalSize.Y.Scale * 0.95, originalSize.Y.Offset)
    
    local pressInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local pressTween = TweenService:Create(button, pressInfo, {Size = pressedSize})
    pressTween:Play()
    
    pressTween.Completed:Connect(function()
        local releaseInfo = TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        local releaseTween = TweenService:Create(button, releaseInfo, {Size = originalSize})
        releaseTween:Play()
    end)
end

function GemShopClient:_onButtonClick(upgradeName)
    Logger:Info(string.format("%s button clicked!", upgradeName))
    
    self:_animateButtonClick(upgradeName)
    
    if not self:_canAffordPurchase(upgradeName) then
        return
    end
    
    local remotes = self._remoteEvents[upgradeName]
    if not remotes or not remotes.Purchase then
        Logger:Error(string.format("%s purchase remote not available", upgradeName))
        return
    end
    
    local upgradeData = self._upgrades[upgradeName]
    -- Send purchase request with validation data
    remotes.Purchase:FireServer(upgradeData.cost, upgradeData.level)
    Logger:Info(string.format("Sent %s purchase request - Cost: %d, Level: %d, Gems: %d",
        upgradeName, upgradeData.cost, upgradeData.level, self:_getCurrentGems()))
end

function GemShopClient:_onSync(upgradeName, level, ...)
    Logger:Info(string.format("%s sync received - Level: %d", upgradeName, level))
    
    local upgradeData = self._upgrades[upgradeName]
    -- Update local data
    upgradeData.level = level
    upgradeData.cost = self:_calculateCost(upgradeName, level)
    
    -- Update GUI
    self:_updateGUI(upgradeName)
    self:_updateButtonState(upgradeName)
end

function GemShopClient:_onPurchaseConfirm(upgradeName, level, ...)
    Logger:Info(string.format("%s purchase confirmed! Level: %d", upgradeName, level))
    
    -- Track for tutorial
    if _G.TutorialSystem and _G.TutorialSystem.incrementGemBoostUpgrades then
        _G.TutorialSystem.incrementGemBoostUpgrades()
    end
    
    local upgradeData = self._upgrades[upgradeName]
    -- Update local data
    upgradeData.level = level
    upgradeData.cost = self:_calculateCost(upgradeName, level)
    
    -- Update GUI
    self:_updateGUI(upgradeName)
    self:_updateButtonState(upgradeName)
end

function GemShopClient:_requestSyncs()
    -- DISABLED: ShopClient handles sync requests now
    Logger:Info("GemShopClient sync requests disabled - ShopClient handles them")
end

function GemShopClient:Cleanup()
    Logger:Info("GemShopClient shutting down...")
    
    for _, connection in pairs(self._connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    self._remoteEvents = {}
    self._upgrades = {}
    
    Logger:Info("GemShopClient cleanup complete")
end

return GemShopClient