local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)

local NotificationService = {}
NotificationService.__index = NotificationService

-- Sound IDs for different notification types
local NOTIFICATION_SOUNDS = {
    wishEarned = "rbxassetid://106782787340501",
    itemReceived = "rbxassetid://106782787340501", 
    dayTime = "rbxassetid://106782787340501",
    nightTime = "rbxassetid://106782787340501",
    rare = "rbxassetid://106782787340501",
    epic = "rbxassetid://106782787340501",
    legendary = "rbxassetid://106782787340501"
}

function NotificationService.new()
    local self = setmetatable({}, NotificationService)
    self._connections = {}
    self._remoteEvents = {}
    self:_initialize()
    return self
end

function NotificationService:_initialize()
    Logger:Info("NotificationService initializing...")
    
    self:_setupRemoteEvents()
    
    Logger:Info("✓ NotificationService initialized")
end

function NotificationService:_setupRemoteEvents()
    local shared = ReplicatedStorage:WaitForChild("Shared", 5)
    if not shared then
        shared = Instance.new("Folder")
        shared.Name = "Shared"
        shared.Parent = ReplicatedStorage
    end
    
    local remoteEvents = shared:FindFirstChild("RemoteEvents")
    if not remoteEvents then
        remoteEvents = Instance.new("Folder")
        remoteEvents.Name = "RemoteEvents"
        remoteEvents.Parent = shared
    end
    
    local notificationEvents = remoteEvents:FindFirstChild("NotificationEvents")
    if not notificationEvents then
        notificationEvents = Instance.new("Folder")
        notificationEvents.Name = "NotificationEvents"
        notificationEvents.Parent = remoteEvents
    end
    
    local showNotificationEvent = notificationEvents:FindFirstChild("ShowNotification")
    if not showNotificationEvent then
        showNotificationEvent = Instance.new("RemoteEvent")
        showNotificationEvent.Name = "ShowNotification"
        showNotificationEvent.Parent = notificationEvents
    end
    
    self._remoteEvents.ShowNotification = showNotificationEvent
    
    Logger:Info("✓ Notification remote events setup complete")
end

function NotificationService:ShowNotificationToPlayer(player, message, notificationType, soundId)
    if not player or not player.Parent then
        Logger:Warn("Invalid player for notification: " .. tostring(message))
        return
    end
    
    local finalSoundId = soundId or NOTIFICATION_SOUNDS[notificationType] or NOTIFICATION_SOUNDS.wishEarned
    
    self._remoteEvents.ShowNotification:FireClient(player, message, finalSoundId)
    Logger:Debug(string.format("Sent notification to %s: %s", player.Name, message))
end

function NotificationService:ShowNotificationToAll(message, notificationType, soundId)
    local finalSoundId = soundId or NOTIFICATION_SOUNDS[notificationType] or NOTIFICATION_SOUNDS.wishEarned
    
    self._remoteEvents.ShowNotification:FireAllClients(message, finalSoundId)
    Logger:Info(string.format("Sent notification to all players: %s", message))
end

function NotificationService:ShowWishEarned(player)
    local message = "✨ You earned a wish! Go to the Wish Fountain!"
    self:ShowNotificationToPlayer(player, message, "wishEarned")
    Logger:Info(string.format("Sent wish earned notification to %s", player.Name))
end

function NotificationService:ShowItemReceived(player, itemName, rarity)
    local rarityEmojis = {
        legendary = "🌟",
        epic = "💜", 
        rare = "💎",
        common = "⭐"
    }
    
    local emoji = rarityEmojis[rarity] or "🎁"
    local message = emoji .. " You received: " .. itemName .. "!"
    
    self:ShowNotificationToPlayer(player, message, rarity)
    Logger:Info(string.format("Sent item notification to %s: %s (%s)", player.Name, itemName, rarity))
end

function NotificationService:ShowDayTimeBegin()
    local message = "🌅 Rise and shine! A new day begins!"
    self:ShowNotificationToAll(message, "dayTime")
    Logger:Info("Sent day time notification to all players")
end

function NotificationService:ShowNightTimeBegin()
    local message = "🌙 Night has fallen! Gem production is boosted!"
    self:ShowNotificationToAll(message, "nightTime")
    Logger:Info("Sent night time notification to all players")
end

function NotificationService:ShowCustomNotification(player, message, notificationType, soundId)
    if player then
        self:ShowNotificationToPlayer(player, message, notificationType, soundId)
    else
        self:ShowNotificationToAll(message, notificationType, soundId)
    end
end

function NotificationService:Cleanup()
    Logger:Info("NotificationService shutting down...")
    
    for _, connection in pairs(self._connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    
    Logger:Info("✓ NotificationService shutdown complete")
end

return NotificationService