local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local MoneyManager = {}
MoneyManager.__index = MoneyManager

local player = Players.LocalPlayer

function MoneyManager.new()
    local self = setmetatable({}, MoneyManager)
    
    self._connections = {}
    self._uiElements = {}
    self._currentSpores = 0
    self._currentGems = 0
    
    self:_initialize()
    return self
end

function MoneyManager:_initialize()
    Logger:Info("MoneyManager initializing...")
    
    task.spawn(function()
        self:_setupUI()
        self:_setupCurrencyListeners()
        self:_updateInitialValues()
    end)
    
    Logger:Info("✓ MoneyManager initialized")
end

function MoneyManager:_setupUI()
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then
        Logger:Error("PlayerGui not found")
        return
    end
    
    local footer = playerGui:WaitForChild("Footer", 10)
    if not footer then
        Logger:Error("Footer GUI not found")
        return
    end
    
    local container = footer:WaitForChild("Container", 10)
    if not container then
        Logger:Error("Container not found in Footer")
        return
    end
    
    local buttonContainer = container:WaitForChild("ButtonContainer", 10)
    if not buttonContainer then
        Logger:Error("ButtonContainer not found in Container")
        return
    end
    
    local gemCount = buttonContainer:FindFirstChild("GemCount")
    if gemCount then
        self._uiElements.gemCount = gemCount
        Logger:Info("✓ Found GemCount element")
    else
        Logger:Warn("GemCount element not found in ButtonContainer")
    end
    
    local moneyCounter = buttonContainer:FindFirstChild("MoneyCounter")
    if moneyCounter then
        local sporeIcon = moneyCounter:FindFirstChild("SporeIcon")
        if sporeIcon then
            self._uiElements.sporeIcon = sporeIcon
            Logger:Info("✓ Found SporeIcon element")
            
            local moneyCounterLabel = sporeIcon:FindFirstChild("MoneyCounterLabel")
            if moneyCounterLabel then
                self._uiElements.moneyCounterLabel = moneyCounterLabel
                Logger:Info("✓ Found MoneyCounterLabel element")
            else
                Logger:Warn("MoneyCounterLabel not found in SporeIcon")
            end
        else
            Logger:Warn("SporeIcon not found in MoneyCounter")
        end
    else
        Logger:Warn("MoneyCounter element not found in ButtonContainer")
    end
    
    Logger:Info("UI setup complete")
end

function MoneyManager:_setupCurrencyListeners()
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
    
    local dataEvents = remoteEvents:WaitForChild("DataEvents", 10)
    if not dataEvents then
        Logger:Error("DataEvents folder not found")
        return
    end
    
    local currencyUpdated = dataEvents:WaitForChild("CurrencyUpdated", 10)
    if currencyUpdated then
        self._connections.CurrencyUpdated = currencyUpdated.OnClientEvent:Connect(function(currencyType, newAmount)
            Logger:Debug(string.format("Currency updated: %s = %s", currencyType, tostring(newAmount)))
            
            if currencyType == "Spores" then
                self._currentSpores = newAmount
                self:_updateSporeDisplay()
            elseif currencyType == "Gems" then
                self._currentGems = newAmount
                self:_updateGemDisplay()
            end
        end)
        Logger:Info("✓ CurrencyUpdated event connected")
    else
        Logger:Error("CurrencyUpdated event not found")
    end
    
    local leaderstats = player:WaitForChild("leaderstats", 10)
    if leaderstats then
        local spores = leaderstats:WaitForChild("Spores", 10)
        local gems = leaderstats:WaitForChild("Gems", 10)
        
        if spores then
            self._connections.SporesChanged = spores.Changed:Connect(function()
                local newValue = spores.Value
                if newValue ~= self._currentSpores then
                    self._currentSpores = newValue
                    self:_updateSporeDisplay()
                end
            end)
            Logger:Info("✓ Spores leaderstats listener connected")
        end
        
        if gems then
            self._connections.GemsChanged = gems.Changed:Connect(function()
                local newValue = gems.Value
                if newValue ~= self._currentGems then
                    self._currentGems = newValue
                    self:_updateGemDisplay()
                end
            end)
            Logger:Info("✓ Gems leaderstats listener connected")
        end
    end
end

function MoneyManager:_updateInitialValues()
    local leaderstats = player:WaitForChild("leaderstats", 5)
    if leaderstats then
        local spores = leaderstats:FindFirstChild("Spores")
        local gems = leaderstats:FindFirstChild("Gems")
        
        if spores then
            self._currentSpores = spores.Value
            self:_updateSporeDisplay()
        end
        
        if gems then
            self._currentGems = gems.Value
            self:_updateGemDisplay()
        end
    end
end

function MoneyManager:_formatValue(value)
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK", value / 1000)
    else
        return tostring(math.floor(value))
    end
end

function MoneyManager:_updateSporeDisplay()
    if self._uiElements.moneyCounterLabel then
        local formattedValue = self:_formatValue(self._currentSpores)
        self._uiElements.moneyCounterLabel.Text = formattedValue
        Logger:Debug(string.format("Updated spore display: %s", formattedValue))
    end
end

function MoneyManager:_updateGemDisplay()
    if self._uiElements.gemCount then
        local formattedValue = self:_formatValue(self._currentGems)
        self._uiElements.gemCount.Text = formattedValue
        Logger:Debug(string.format("Updated gem display: %s", formattedValue))
    end
end

function MoneyManager:GetCurrentSpores()
    return self._currentSpores
end

function MoneyManager:GetCurrentGems()
    return self._currentGems
end

function MoneyManager:Cleanup()
    Logger:Info("MoneyManager shutting down...")
    
    for _, connection in pairs(self._connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    self._uiElements = {}
    
    Logger:Info("✓ MoneyManager shutdown complete")
end

return MoneyManager