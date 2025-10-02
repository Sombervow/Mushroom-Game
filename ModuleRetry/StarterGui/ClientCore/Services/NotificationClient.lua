local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local NotificationClient = {}
NotificationClient.__index = NotificationClient

local player = Players.LocalPlayer

-- Animation configuration
local ANIMATION_TIME = 0.5
local DISPLAY_TIME = 3.0

function NotificationClient.new()
    local self = setmetatable({}, NotificationClient)
    self._connections = {}
    self._remoteEvents = {}
    self._guiElements = {}
    self._notificationQueue = {}
    self._isShowingNotification = false
    self._notificationSound = nil
    self:_initialize()
    return self
end

function NotificationClient:_initialize()
    Logger:Info("NotificationClient initializing...")
    
    self:_waitForRemoteEvents()
    self:_setupGUI()
    self:_setupSound()
    self:_connectEvents()
    
    Logger:Info("✓ NotificationClient initialized")
end

function NotificationClient:_waitForRemoteEvents()
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local remoteEvents = shared:WaitForChild("RemoteEvents")
    local notificationEvents = remoteEvents:WaitForChild("NotificationEvents")
    
    self._remoteEvents.ShowNotification = notificationEvents:WaitForChild("ShowNotification")
    
    Logger:Info("✓ Notification remote events connected")
end

function NotificationClient:_setupGUI()
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- Wait for notification GUI
    local notificationGui = playerGui:WaitForChild("Notification", 10)
    if not notificationGui then
        Logger:Error("Notification GUI not found!")
        return
    end
    
    self._guiElements.notificationGui = notificationGui
    self._guiElements.notificationFrame = notificationGui:WaitForChild("Frame")
    
    -- Navigate to the notification text element
    local notiBorder = self._guiElements.notificationFrame:WaitForChild("NotiBorder")
    self._guiElements.notificationText = notiBorder:WaitForChild("Notification")
    
    -- Store original position for animations
    self._guiElements.originalPosition = self._guiElements.notificationFrame.Position
    self._guiElements.hiddenPosition = UDim2.new(
        self._guiElements.originalPosition.X.Scale, 
        self._guiElements.originalPosition.X.Offset, 
        -1, 0
    ) -- Hidden above screen
    
    -- Initialize notification as hidden
    self._guiElements.notificationGui.Enabled = false
    self._guiElements.notificationFrame.Position = self._guiElements.hiddenPosition
    
    Logger:Info("✓ Notification GUI elements setup complete")
end

function NotificationClient:_setupSound()
    self._notificationSound = Instance.new("Sound")
    self._notificationSound.SoundId = "rbxassetid://106782787340501"
    self._notificationSound.Volume = 0.5
    self._notificationSound.Parent = SoundService
    
    Logger:Info("✓ Notification sound setup complete")
end

function NotificationClient:_connectEvents()
    -- Connect remote event
    self._connections.ShowNotification = self._remoteEvents.ShowNotification.OnClientEvent:Connect(function(message, soundId)
        self:_showNotification(message, soundId)
    end)
    
    Logger:Info("✓ Notification events connected")
end

function NotificationClient:_showNotification(message, soundId)
    -- Add to queue
    table.insert(self._notificationQueue, {message = message, soundId = soundId})
    
    -- Process queue if not currently showing
    if not self._isShowingNotification then
        self:_processNotificationQueue()
    end
end

function NotificationClient:_processNotificationQueue()
    if #self._notificationQueue == 0 then
        self._isShowingNotification = false
        return
    end
    
    self._isShowingNotification = true
    local notification = table.remove(self._notificationQueue, 1)
    
    -- Enable the GUI and set the notification text
    self._guiElements.notificationGui.Enabled = true
    self._guiElements.notificationText.Text = notification.message
    
    -- Ensure frame starts hidden
    self._guiElements.notificationFrame.Position = self._guiElements.hiddenPosition
    
    -- Play sound
    if notification.soundId and notification.soundId ~= "" then
        self._notificationSound.SoundId = notification.soundId
    end
    self._notificationSound:Play()
    
    Logger:Debug("Showing notification: " .. notification.message)
    
    -- Pop in animation
    local popInTween = TweenService:Create(
        self._guiElements.notificationFrame,
        TweenInfo.new(
            ANIMATION_TIME,
            Enum.EasingStyle.Back,
            Enum.EasingDirection.Out
        ),
        {Position = self._guiElements.originalPosition}
    )
    
    popInTween:Play()
    
    -- Wait for display time, then pop out
    popInTween.Completed:Connect(function()
        task.wait(DISPLAY_TIME)
        
        -- Pop out animation
        local popOutTween = TweenService:Create(
            self._guiElements.notificationFrame,
            TweenInfo.new(
                ANIMATION_TIME,
                Enum.EasingStyle.Back,
                Enum.EasingDirection.In
            ),
            {Position = self._guiElements.hiddenPosition}
        )
        
        popOutTween:Play()
        
        -- Hide GUI and process next notification when animation completes
        popOutTween.Completed:Connect(function()
            self._guiElements.notificationGui.Enabled = false
            self:_processNotificationQueue()
        end)
    end)
end

function NotificationClient:ShowLocalNotification(message, soundId)
    self:_showNotification(message, soundId or "rbxassetid://106782787340501")
end

function NotificationClient:Cleanup()
    Logger:Info("NotificationClient shutting down...")
    
    for _, connection in pairs(self._connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    self._notificationQueue = {}
    
    if self._notificationSound then
        self._notificationSound:Destroy()
    end
    
    Logger:Info("✓ NotificationClient shutdown complete")
end

return NotificationClient