local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local HeartbeatManager = require(script.Parent.Parent.Utilities.HeartbeatManager)

local SystemChatService = {}
SystemChatService.__index = SystemChatService

-- Tip system configuration
local TIP_INTERVAL = 60 -- 1 minute in seconds
local TIP_COLOR = Color3.fromRGB(255, 255, 0) -- Yellow color

-- Database of helpful tips about game mechanics
local GAME_TIPS = {
    "TIP: Mushrooms earn spores while you're offline! Check back later for rewards.",
    "TIP: Click on mushrooms to force them to drop extra spores instantly!",
    "TIP: Collect 100 regular spores and they'll automatically combine into a BigSpore worth 100x!",
    "TIP: Night time doubles your gem production! Look out for the moon.",
    "TIP: Use the Wish Fountain to spin for rare items and gems every 20 minutes.",
    "TIP: Upgrade your PickUpRange to collect items from further away.",
    "TIP: FastRunner upgrades make you move faster around your plot.",
    "TIP: FasterShrooms upgrades make your mushrooms drop spores more frequently.",
    "TIP: ShinySpore upgrades increase the value of all spores you collect.",
    "TIP: Buy more mushrooms from the shop to increase your spore production.",
    "TIP: Your spore multiplier increases with each upgrade level you purchase.",
    "TIP: Stay close to spores and gems to automatically collect them.",
    "TIP: Each plot can hold multiple mushrooms - buy more to boost earnings!",
    "TIP: GemHunter upgrades increase your chances of finding gems.",
    "TIP: Items from the Wish Fountain can be used as temporary boosts.",
    "TIP: Check your inventory to use boost items for enhanced gameplay.",
    "TIP: The day/night cycle affects gem production - night time is more profitable!",
    "TIP: Spore upgrades apply a percentage multiplier to all spores collected.",
    "TIP: Your mushrooms will keep working even when you're not playing!",
    "TIP: Gems are the premium currency - use them wisely for powerful upgrades."
}

function SystemChatService.new()
    local self = setmetatable({}, SystemChatService)
    self._connections = {}
    self._lastTipTime = 0
    self._currentTipIndex = 1
    self._textChannel = nil
    self:_initialize()
    return self
end

function SystemChatService:_initialize()
    Logger:Info("SystemChatService initializing...")
    
    -- Setup RemoteEvent first, then start tip system when ready
    self:_setupTextChannel()
    
    Logger:Info("✓ SystemChatService initialized")
end

function SystemChatService:_setupTextChannel()
    -- Create RemoteEvent for sending tips to clients
    task.spawn(function()
        task.wait(1) -- Brief wait
        
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        if shared then
            local remoteEvents = shared:FindFirstChild("RemoteEvents")
            if remoteEvents then
                -- Create or find SystemTip RemoteEvent
                local systemTipEvent = remoteEvents:FindFirstChild("SystemTip")
                if not systemTipEvent then
                    systemTipEvent = Instance.new("RemoteEvent")
                    systemTipEvent.Name = "SystemTip"
                    systemTipEvent.Parent = remoteEvents
                end
                
                self._systemTipEvent = systemTipEvent
                Logger:Info("✓ SystemTip RemoteEvent ready")
                
                -- Now start the tip system since RemoteEvent is ready
                self:_startTipSystem()
            end
        end
    end)
end

function SystemChatService:_startTipSystem()
    task.spawn(function()
        -- Send first tip immediately after a short delay
        task.wait(3)
        self:_sendSystemTip()
        self._lastTipTime = tick()
    end)
    
    -- Use HeartbeatManager with 60 second interval for tip system
    self._connections.TipSystem = HeartbeatManager.getInstance():register(function()
        local currentTime = tick()
        
        -- Check if it's time for a new tip
        if currentTime - self._lastTipTime >= TIP_INTERVAL then
            self:_sendSystemTip()
            self._lastTipTime = currentTime
        end
    end)
    
    Logger:Info("✓ System tip timer started (interval: " .. TIP_INTERVAL .. " seconds)")
end

function SystemChatService:_sendSystemTip()
    if not self._systemTipEvent then
        Logger:Warn("SystemTip RemoteEvent not ready")
        return
    end
    
    -- Get the current tip
    local tip = GAME_TIPS[self._currentTipIndex]
    if not tip then
        Logger:Warn("Invalid tip index: " .. self._currentTipIndex)
        return
    end
    
    -- Advance to next tip (cycle through all tips)
    self._currentTipIndex = self._currentTipIndex + 1
    if self._currentTipIndex > #GAME_TIPS then
        self._currentTipIndex = 1 -- Reset to first tip
    end
    
    -- Send tip to all players via RemoteEvent
    local success, result = pcall(function()
        self._systemTipEvent:FireAllClients(tip)
    end)
    
    if success then
        Logger:Debug("Sent system tip: " .. tip)
    else
        Logger:Warn("Failed to send system tip: " .. tostring(result))
    end
end

function SystemChatService:SendCustomTip(message)
    if not self._textChannel then
        Logger:Warn("No text channel available for custom tip")
        return false
    end
    
    local customTip = "TIP: " .. message
    
    local success, result = pcall(function()
        self._textChannel:DisplaySystemMessage(customTip)
    end)
    
    if success then
        Logger:Info("Sent custom system tip: " .. customTip)
        return true
    else
        Logger:Warn("Failed to send custom tip: " .. tostring(result))
        return false
    end
end

function SystemChatService:SendSystemMessage(message)
    if not self._textChannel then
        Logger:Warn("No text channel available for system message")
        return false
    end
    
    local success, result = pcall(function()
        self._textChannel:DisplaySystemMessage(message)
    end)
    
    if success then
        Logger:Info("Sent system message: " .. message)
        return true
    else
        Logger:Warn("Failed to send system message: " .. tostring(result))
        return false
    end
end

function SystemChatService:GetTipCount()
    return #GAME_TIPS
end

function SystemChatService:GetCurrentTipIndex()
    return self._currentTipIndex
end

function SystemChatService:GetNextTipIn()
    local currentTime = tick()
    local timeElapsed = currentTime - self._lastTipTime
    return math.max(0, TIP_INTERVAL - timeElapsed)
end

function SystemChatService:ForceNextTip()
    self:_sendSystemTip()
    self._lastTipTime = tick()
    Logger:Info("Forced next system tip")
end

function SystemChatService:Cleanup()
    Logger:Info("SystemChatService shutting down...")
    
    for name, connection in pairs(self._connections) do
        if connection then
            if name == "TipSystem" then
                HeartbeatManager.getInstance():unregister(connection)
            elseif connection.Connected then
                connection:Disconnect()
            end
        end
    end
    
    self._connections = {}
    
    Logger:Info("✓ SystemChatService shutdown complete")
end

return SystemChatService