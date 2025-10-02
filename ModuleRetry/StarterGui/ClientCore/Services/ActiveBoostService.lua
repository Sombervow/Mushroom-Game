local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)
local HeartbeatManager = require(ReplicatedStorage.Shared.Modules.HeartbeatManager)

local ActiveBoostService = {}
ActiveBoostService.__index = ActiveBoostService

local player = Players.LocalPlayer

-- Configuration for active boosts UI
local BOOST_CONFIG = {
    MAX_VISIBLE_BOOSTS = 5,
    FADE_DURATION = 0.3,
    SLIDE_DURATION = 0.4,
    UPDATE_INTERVAL = 1, -- Update timers every second
}

-- Night time configuration
local NIGHT_CONFIG = {
    START_HOUR = 18, -- 6 PM
    END_HOUR = 6,    -- 6 AM
    NIGHT_ICON = "rbxassetid://90453550429467"
}

-- Item configurations for boosts
local ITEM_BOOST_CONFIG = {
    ["Shroom Food"] = {
        image = "rbxassetid://127204542535592",
        name = "Shroom Food",
        description = "Increased mushroom production"
    },
    ["Energy Bar"] = {
        image = "rbxassetid://110491282217664",
        name = "Energy Bar", 
        description = "Boosted energy regeneration"
    },
    ["Golden Apple"] = {
        image = "rbxassetid://120295649276578",
        name = "Golden Apple",
        description = "Enhanced collection rates"
    },
    ["Gem Potion"] = {
        image = "rbxassetid://126345409470651",
        name = "Gem Potion",
        description = "Increased gem spawn chance"
    },
    ["Bux Potion"] = {
        image = "rbxassetid://130449969956988",
        name = "Bux Potion",
        description = "Currency multiplier active"
    },
    ["Apple"] = {
        image = "rbxassetid://96389092320560",
        name = "Apple",
        description = "Health regeneration boost"
    },
    ["Bone"] = {
        image = "rbxassetid://73911550220270",
        name = "Bone",
        description = "Double gem production boost"
    }
}

function ActiveBoostService.new()
    local self = setmetatable({}, ActiveBoostService)
    
    self._connections = {}
    self._activeBoosts = {}
    self._boostElements = {}
    self._footerGui = nil
    self._eventsContainer = nil
    self._eventTemplate = nil
    self._updateLoop = nil
    self._nightCheckLoop = nil
    self._isNightTime = false
    
    self:_initialize()
    return self
end

function ActiveBoostService:_initialize()
    Logger:Info("ActiveBoostService initializing...")
    
    self:_setupGUI()
    self:_setupEventTemplate()
    self:_connectEvents()
    self:_startUpdateLoop()
    self:_startNightTimeCheck()
    
    Logger:Info("✓ ActiveBoostService initialized")
end

function ActiveBoostService:_setupGUI()
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- Find Footer GUI
    self._footerGui = playerGui:WaitForChild("Footer", 10)
    if not self._footerGui then
        Logger:Error("Footer GUI not found!")
        return
    end
    
    local container = self._footerGui:WaitForChild("Container")
    if not container then
        Logger:Error("Container not found in Footer!")
        return
    end
    
    -- Find or create EventsContainer
    self._eventsContainer = container:FindFirstChild("EventsContainer")
    if not self._eventsContainer then
        Logger:Warn("EventsContainer not found in Footer Container - creating it")
        
        -- Create EventsContainer
        self._eventsContainer = Instance.new("Frame")
        self._eventsContainer.Name = "EventsContainer"
        self._eventsContainer.Size = UDim2.new(0, 300, 0, 100)
        self._eventsContainer.Position = UDim2.new(0, 10, 0, 10)
        self._eventsContainer.BackgroundTransparency = 1
        self._eventsContainer.Parent = container
        
        -- Create UIListLayout for vertical stacking
        local listLayout = Instance.new("UIListLayout")
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.FillDirection = Enum.FillDirection.Vertical
        listLayout.Padding = UDim.new(0, 5)
        listLayout.Parent = self._eventsContainer
        
        Logger:Info("Created EventsContainer in Footer")
    end
    
    Logger:Info("✓ Active boost GUI setup complete")
end

function ActiveBoostService:_setupEventTemplate()
    -- Check multiple possible locations for EventItem template
    local possiblePaths = {
        ReplicatedStorage:FindFirstChild("EventItem"),
        ReplicatedStorage:FindFirstChild("GUI") and ReplicatedStorage.GUI:FindFirstChild("EventItem"),
        ReplicatedStorage:FindFirstChild("Templates") and ReplicatedStorage.Templates:FindFirstChild("EventItem")
    }
    
    for _, template in pairs(possiblePaths) do
        if template then
            self._eventTemplate = template
            Logger:Info("✓ EventItem template found at: " .. template:GetFullName())
            return
        end
    end
    
    -- Wait for EventItem to be created
    Logger:Warn("EventItem template not found, waiting for it to be created...")
    task.spawn(function()
        for i = 1, 30 do -- Wait up to 30 seconds
            local eventItem = ReplicatedStorage:FindFirstChild("EventItem")
            if not eventItem and ReplicatedStorage:FindFirstChild("GUI") then
                eventItem = ReplicatedStorage.GUI:FindFirstChild("EventItem")
            end
            
            if eventItem then
                self._eventTemplate = eventItem
                Logger:Info("✓ EventItem template found at: " .. eventItem:GetFullName())
                return
            end
            
            task.wait(1)
        end
        
        Logger:Error("EventItem template still not found after 30 seconds!")
        -- List what's available in ReplicatedStorage
        Logger:Debug("Available in ReplicatedStorage:")
        for _, child in pairs(ReplicatedStorage:GetChildren()) do
            Logger:Debug("  - " .. child.Name .. " (" .. child.ClassName .. ")")
            if child:IsA("Folder") then
                for _, grandchild in pairs(child:GetChildren()) do
                    Logger:Debug("    - " .. grandchild.Name .. " (" .. grandchild.ClassName .. ")")
                end
            end
        end
    end)
end

function ActiveBoostService:_connectEvents()
    -- Connect to inventory events for food boosts
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local remoteEvents = shared:WaitForChild("RemoteEvents")
    local inventoryEvents = remoteEvents:WaitForChild("InventoryEvents")
    
    -- Listen for boost activations
    local syncBoosts = inventoryEvents:WaitForChild("SyncBoosts")
    self._connections.SyncBoosts = syncBoosts.OnClientEvent:Connect(function(boostData)
        self:_handleBoostSync(boostData)
    end)
    
    -- Listen for item usage confirmations that create boosts
    local itemUsedEvent = inventoryEvents:FindFirstChild("ItemUsed")
    if itemUsedEvent then
        self._connections.ItemUsed = itemUsedEvent.OnClientEvent:Connect(function(itemName, boostDuration, serverItemConfig)
            self:_handleItemUsed(itemName, boostDuration, serverItemConfig)
        end)
    end
    
    Logger:Info("✓ Active boost events connected")
end

function ActiveBoostService:_startUpdateLoop()
    -- Update boost timers using centralized heartbeat manager
    self._updateLoop = HeartbeatManager.getInstance():register(function()
        self:_updateBoostTimers()
    end, BOOST_CONFIG.UPDATE_INTERVAL)
end

function ActiveBoostService:_startNightTimeCheck()
    -- Check for night time using centralized heartbeat manager with 30 second interval
    self._nightCheckLoop = HeartbeatManager.getInstance():register(function()
        self:_checkNightTime()
    end, 30)
    
    -- Initial check
    self:_checkNightTime()
end

function ActiveBoostService:_checkNightTime()
    -- Get current time from Lighting service (game time, not real time)
    local Lighting = game:GetService("Lighting")
    local clockTime = Lighting.ClockTime
    
    -- ClockTime is 0-24, where 0 = midnight, 12 = noon
    -- Night is from 18:00 (6 PM) to 06:00 (6 AM)
    -- This spans across midnight, so we need special logic
    local isNight
    if NIGHT_CONFIG.START_HOUR > NIGHT_CONFIG.END_HOUR then
        -- Night spans across midnight (like 18-6)
        isNight = (clockTime >= NIGHT_CONFIG.START_HOUR or clockTime < NIGHT_CONFIG.END_HOUR)
    else
        -- Night doesn't span midnight (like 20-4, but this case doesn't apply here)
        isNight = (clockTime >= NIGHT_CONFIG.START_HOUR and clockTime < NIGHT_CONFIG.END_HOUR)
    end
    
    -- Debug logging to see what's happening
    Logger:Debug(string.format("Night check: ClockTime=%.2f, StartHour=%d, EndHour=%d, IsNight=%s, WasNight=%s", 
        clockTime, NIGHT_CONFIG.START_HOUR, NIGHT_CONFIG.END_HOUR, tostring(isNight), tostring(self._isNightTime)))
    
    if isNight ~= self._isNightTime then
        self._isNightTime = isNight
        
        if isNight then
            -- Add night time boost
            self:_addNightTimeBoost()
            Logger:Info("Night time detected - gem production boost active (ClockTime: " .. string.format("%.2f", clockTime) .. ")")
        else
            -- Remove night time boost
            self:_removeNightTimeBoost()
            Logger:Info("Day time detected - gem production boost ended (ClockTime: " .. string.format("%.2f", clockTime) .. ")")
        end
    end
end

function ActiveBoostService:_addNightTimeBoost()
    local nightBoost = {
        id = "night_gem_boost",
        name = "Night Time",
        description = "Increased gem production during night",
        image = NIGHT_CONFIG.NIGHT_ICON,
        endTime = nil, -- Indefinite until day
        isNightTime = true
    }
    
    self:_addBoostToUI(nightBoost)
end

function ActiveBoostService:_removeNightTimeBoost()
    self:_removeBoostFromUI("night_gem_boost")
end

function ActiveBoostService:_handleBoostSync(boostData)
    local boostCount = 0
    for _ in pairs(boostData) do boostCount = boostCount + 1 end
    Logger:Debug("Received boost sync data: " .. tostring(boostCount) .. " active boosts - DISABLED to prevent duplicates")
    
    -- DISABLED: Don't use sync system to prevent duplicate boosts
    -- ItemUsed events provide better information (item names, proper descriptions)
    -- This sync system would only be used for boosts that didn't come from item usage
    
    Logger:Debug("Boost sync disabled - using ItemUsed events only")
end

function ActiveBoostService:_handleItemUsed(itemName, boostDuration, serverItemConfig)
    -- Use server config if available, fallback to client config
    local itemConfig = serverItemConfig or ITEM_BOOST_CONFIG[itemName]
    if not itemConfig then
        Logger:Warn("No boost configuration found for item: " .. tostring(itemName))
        return
    end
    
    -- Create unique boost ID based on item name and current time
    local boostId = itemName .. "_used_" .. math.floor(tick())
    
    -- Use server description, or fallback to client config
    local displayName = itemConfig.name or itemName
    local description = itemConfig.description or "Active boost"
    
    -- Get image from client config (server doesn't have image IDs)
    local clientConfig = ITEM_BOOST_CONFIG[itemName]
    local image = (clientConfig and clientConfig.image) or "rbxassetid://0"
    
    local boost = {
        id = boostId,
        name = displayName,
        description = description, -- This now comes from server
        image = image,
        endTime = tick() + boostDuration,
        duration = boostDuration,
        source = "ItemUsed" -- Mark source for debugging
    }
    
    self:_addBoostToUI(boost)
    Logger:Info("Added ItemUsed boost for: " .. itemName .. " (duration: " .. boostDuration .. "s) with server description: " .. description)
end

function ActiveBoostService:_addBoostToUI(boostData)
    if not self._eventTemplate or not self._eventsContainer then
        Logger:Warn("Cannot add boost - template or container missing")
        if not self._eventTemplate then
            Logger:Warn("EventItem template is nil")
        end
        if not self._eventsContainer then
            Logger:Warn("EventsContainer is nil") 
        end
        return
    end
    
    -- Don't add duplicate boosts
    if self._activeBoosts[boostData.id] then
        Logger:Debug("Boost already active: " .. boostData.id)
        return
    end
    
    -- Debug structure only if needed
    Logger:Debug("Using EventItem template: " .. self._eventTemplate.Name)
    
    -- Clone the EventItem template
    local eventItem = self._eventTemplate:Clone()
    eventItem.Name = "EventItem_" .. boostData.id
    eventItem.LayoutOrder = #self._eventsContainer:GetChildren()
    
    -- Get UI elements based on the actual structure
    local eventIcon = eventItem:FindFirstChild("EventIcon")
    local eventInfoBackground = nil
    local eventTimer = nil
    local eventName = nil
    local eventInfo = nil
    
    -- Get elements from EventIcon
    if eventIcon then
        eventTimer = eventIcon:FindFirstChild("EventTimer")
        eventInfoBackground = eventIcon:FindFirstChild("EventInfoBackground")  -- It's INSIDE EventIcon!
    end
    
    -- Get text elements from EventInfoBackground
    if eventInfoBackground then
        eventName = eventInfoBackground:FindFirstChild("EventName")
        eventInfo = eventInfoBackground:FindFirstChild("EventInfo")
    end
    
    -- If we still don't have everything, try alternative structures
    if not eventIcon then
        -- Maybe the icon is named differently
        for _, child in pairs(eventItem:GetChildren()) do
            if child:IsA("ImageButton") or child:IsA("ImageLabel") then
                eventIcon = child
                Logger:Info("Found alternative icon: " .. child.Name)
                break
            end
        end
    end
    
    if not eventInfoBackground then
        -- Maybe the background is named differently
        for _, child in pairs(eventItem:GetChildren()) do
            if child.Name:find("Info") or child.Name:find("Background") then
                eventInfoBackground = child
                Logger:Info("Found alternative info background: " .. child.Name)
                break
            end
        end
    end
    
    Logger:Debug("Elements found - Icon: " .. tostring(eventIcon ~= nil) .. ", Info: " .. tostring(eventInfoBackground ~= nil) .. ", Timer: " .. tostring(eventTimer ~= nil))
    
    if not eventIcon then
        Logger:Error("Could not find EventIcon or suitable alternative")
        eventItem:Destroy()
        return
    end
    
    -- Proceed with available elements
    Logger:Debug("Creating boost UI for: " .. boostData.name)
    
    -- Configure the boost UI
    if eventIcon and eventIcon:IsA("ImageButton") or eventIcon:IsA("ImageLabel") then
        eventIcon.Image = boostData.image
    end
    
    if eventName then
        eventName.Text = boostData.name
    end
    
    if eventInfo then
        eventInfo.Text = boostData.description
    end
    
    -- Initially hide info background (if it exists)
    if eventInfoBackground then
        eventInfoBackground.Visible = false
    end
    
    -- Setup hover functionality (only if we have the required elements)
    local hoverConnection1, hoverConnection2
    if eventIcon and eventInfoBackground and (eventIcon:IsA("ImageButton") or eventIcon:IsA("ImageLabel")) then
        hoverConnection1 = eventIcon.MouseEnter:Connect(function()
            eventInfoBackground.Visible = true
        end)
        
        hoverConnection2 = eventIcon.MouseLeave:Connect(function()
            eventInfoBackground.Visible = false
        end)
    else
        Logger:Warn("Hover functionality disabled - missing required elements")
    end
    
    -- Store boost data
    self._activeBoosts[boostData.id] = {
        element = eventItem,
        data = boostData,
        timer = eventTimer,
        hoverConnections = {hoverConnection1, hoverConnection2}
    }
    
    -- Add to UI with slide animation
    eventItem.Position = UDim2.new(0, -300, 0, 0) -- Start off-screen left
    eventItem.Parent = self._eventsContainer
    
    -- Slide in animation
    local slideIn = TweenService:Create(
        eventItem,
        TweenInfo.new(BOOST_CONFIG.SLIDE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0, 0, 0, 0)}
    )
    slideIn:Play()
    
    Logger:Info("Added boost to UI: " .. boostData.name)
end

function ActiveBoostService:_removeBoostFromUI(boostId)
    local boost = self._activeBoosts[boostId]
    if not boost then
        return
    end
    
    -- Disconnect hover connections
    if boost.hoverConnections then
        for _, connection in pairs(boost.hoverConnections) do
            if connection then
                connection:Disconnect()
            end
        end
    end
    
    -- Slide out animation
    local slideOut = TweenService:Create(
        boost.element,
        TweenInfo.new(BOOST_CONFIG.SLIDE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        {Position = UDim2.new(0, -300, 0, 0)}
    )
    slideOut:Play()
    
    slideOut.Completed:Connect(function()
        boost.element:Destroy()
    end)
    
    self._activeBoosts[boostId] = nil
    Logger:Info("Removed boost from UI: " .. boostId)
end

function ActiveBoostService:_updateBoostTimers()
    local currentTime = tick()
    local boostsToRemove = {}
    
    for boostId, boost in pairs(self._activeBoosts) do
        -- Skip night time boost (no timer)
        if boost.data.isNightTime then
            if boost.timer then
                boost.timer.Text = "∞"
            end
        else
            if boost.data.endTime and boost.data.endTime > currentTime then
                local timeLeft = boost.data.endTime - currentTime
                if boost.timer then
                    boost.timer.Text = self:_formatTime(timeLeft)
                end
            else
                -- Boost expired
                table.insert(boostsToRemove, boostId)
            end
        end
    end
    
    -- Remove expired boosts
    for _, boostId in pairs(boostsToRemove) do
        self:_removeBoostFromUI(boostId)
    end
end

function ActiveBoostService:_formatTime(seconds)
    if seconds <= 0 then
        return "0s"
    elseif seconds < 60 then
        return string.format("%.0fs", seconds)
    elseif seconds < 3600 then
        local minutes = math.floor(seconds / 60)
        local remainingSeconds = math.floor(seconds % 60)
        return string.format("%dm %ds", minutes, remainingSeconds)
    else
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, minutes)
    end
end

-- Public methods for other services to use
function ActiveBoostService:AddBoost(itemName, duration, customData)
    local itemConfig = ITEM_BOOST_CONFIG[itemName] or customData
    if not itemConfig then
        Logger:Warn("Cannot add boost - no configuration for: " .. tostring(itemName))
        return
    end
    
    local boost = {
        id = itemName .. "_" .. tick(),
        name = itemConfig.name or itemName,
        description = itemConfig.description or "Active boost",
        image = itemConfig.image or "",
        endTime = tick() + duration,
        duration = duration
    }
    
    self:_addBoostToUI(boost)
end

function ActiveBoostService:RemoveBoost(boostId)
    self:_removeBoostFromUI(boostId)
end

function ActiveBoostService:GetActiveBoosts()
    local activeList = {}
    for boostId, boost in pairs(self._activeBoosts) do
        table.insert(activeList, {
            id = boostId,
            name = boost.data.name,
            timeLeft = boost.data.endTime and (boost.data.endTime - tick()) or math.huge
        })
    end
    return activeList
end

function ActiveBoostService:ClearAllBoosts()
    for boostId, _ in pairs(self._activeBoosts) do
        self:_removeBoostFromUI(boostId)
    end
end

function ActiveBoostService:Cleanup()
    Logger:Info("ActiveBoostService shutting down...")
    
    -- Disconnect all connections
    for _, connection in pairs(self._connections) do
        if connection then
            connection:Disconnect()
        end
    end
    
    -- Stop update loops
    if self._updateLoop then
        HeartbeatManager.getInstance():unregister(self._updateLoop)
    end
    
    if self._nightCheckLoop then
        HeartbeatManager.getInstance():unregister(self._nightCheckLoop)
    end
    
    -- Clear all boosts
    self:ClearAllBoosts()
    
    -- Clear references
    self._connections = {}
    self._activeBoosts = {}
    self._boostElements = {}
    
    Logger:Info("✓ ActiveBoostService cleanup complete")
end

return ActiveBoostService