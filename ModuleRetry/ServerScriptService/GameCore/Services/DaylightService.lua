local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local HeartbeatManager = require(script.Parent.Parent.Utilities.HeartbeatManager)

local DaylightService = {}
DaylightService.__index = DaylightService

-- Day/Night cycle configuration
local DAY_LENGTH = 300 -- 5 minutes in seconds
local NIGHT_LENGTH = 300 -- 5 minutes in seconds
local TOTAL_CYCLE_TIME = DAY_LENGTH + NIGHT_LENGTH -- 10 minutes total

-- Time configuration - only change ClockTime
local DAY_TIME = 12 -- Noon
local NIGHT_TIME = 0 -- Midnight

-- Transition time (how long it takes to fade between day/night)
local TRANSITION_TIME = 10 -- 10 seconds

function DaylightService.new()
    local self = setmetatable({}, DaylightService)
    self._connections = {}
    self._notificationService = nil
    self._currentCycleStartTime = 0
    self._isDay = true
    self._isTransitioning = false
    self._currentTween = nil
    self._gemProductionBoost = 1.0 -- Normal production during day
    self:_initialize()
    return self
end

function DaylightService:_initialize()
    Logger:Info("DaylightService initializing...")
    
    self:_setupInitialLighting()
    self:_startDayNightCycle()
    
    Logger:Info("✓ DaylightService initialized")
end

function DaylightService:_setupInitialLighting()
    -- Set initial day time
    Lighting.ClockTime = DAY_TIME
    
    self._currentCycleStartTime = tick()
    self._isDay = true
    
    Logger:Info("✓ Initial time set to day (ClockTime: " .. DAY_TIME .. ")")
end

function DaylightService:_startDayNightCycle()
    -- Use HeartbeatManager with 1 second interval for day/night cycle checks
    self._connections.DayNightCycle = HeartbeatManager.getInstance():register(function()
        local currentTime = tick()
        local elapsedTime = currentTime - self._currentCycleStartTime
        
        -- Check if we need to transition
        if self._isDay and elapsedTime >= DAY_LENGTH and not self._isTransitioning then
            self:_transitionToNight()
        elseif not self._isDay and elapsedTime >= NIGHT_LENGTH and not self._isTransitioning then
            self:_transitionToDay()
        end
    end, 1)
    
    Logger:Info("✓ Day/Night cycle started")
end

function DaylightService:_transitionToNight()
    if self._isTransitioning then return end
    
    self._isTransitioning = true
    self._gemProductionBoost = 2.0 -- Double gem production at night
    
    Logger:Info("Transitioning to night time - Gem production boosted to 2x")
    
    -- Animate time transition
    self:_animateTimeTransition(NIGHT_TIME, function()
        self._isDay = false
        self._currentCycleStartTime = tick()
        self._isTransitioning = false
        
        -- Send notification after the transition is complete (now it's actually night)
        if self._notificationService then
            self._notificationService:ShowNightTimeBegin()
        end
        
        Logger:Info("Night time transition completed (ClockTime: " .. NIGHT_TIME .. ")")
    end)
end

function DaylightService:_transitionToDay()
    if self._isTransitioning then return end
    
    self._isTransitioning = true
    self._gemProductionBoost = 1.0 -- Normal gem production during day
    
    Logger:Info("Transitioning to day time - Gem production back to normal")
    
    -- Animate time transition
    self:_animateTimeTransition(DAY_TIME, function()
        self._isDay = true
        self._currentCycleStartTime = tick()
        self._isTransitioning = false
        
        -- Send notification after the transition is complete (now it's actually day)
        if self._notificationService then
            self._notificationService:ShowDayTimeBegin()
        end
        
        Logger:Info("Day time transition completed (ClockTime: " .. DAY_TIME .. ")")
    end)
end

function DaylightService:_animateTimeTransition(targetTime, callback)
    -- Cancel any existing tween
    if self._currentTween then
        self._currentTween:Cancel()
    end
    
    -- Create tween for time transition (only ClockTime)
    self._currentTween = TweenService:Create(
        Lighting,
        TweenInfo.new(
            TRANSITION_TIME,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut
        ),
        {ClockTime = targetTime}
    )
    
    self._currentTween:Play()
    
    if callback then
        self._currentTween.Completed:Connect(function()
            callback()
            self._currentTween = nil
        end)
    end
end

function DaylightService:GetCurrentTimeOfDay()
    return self._isDay and "Day" or "Night"
end

function DaylightService:IsDay()
    return self._isDay
end

function DaylightService:IsNight()
    return not self._isDay
end

function DaylightService:GetGemProductionBoost()
    return self._gemProductionBoost
end

function DaylightService:GetTimeUntilNextCycle()
    local currentTime = tick()
    local elapsedTime = currentTime - self._currentCycleStartTime
    local cycleLength = self._isDay and DAY_LENGTH or NIGHT_LENGTH
    
    return math.max(0, cycleLength - elapsedTime)
end

function DaylightService:GetCycleProgress()
    local currentTime = tick()
    local elapsedTime = currentTime - self._currentCycleStartTime
    local cycleLength = self._isDay and DAY_LENGTH or NIGHT_LENGTH
    
    return math.min(1, elapsedTime / cycleLength)
end

function DaylightService:ForceTransitionToDay()
    if self._isDay then return end
    
    Logger:Info("Forcing transition to day time")
    self._isTransitioning = false -- Reset transition state
    self:_transitionToDay()
end

function DaylightService:ForceTransitionToNight()
    if not self._isDay then return end
    
    Logger:Info("Forcing transition to night time")
    self._isTransitioning = false -- Reset transition state
    self:_transitionToNight()
end

function DaylightService:SetNotificationService(notificationService)
    self._notificationService = notificationService
    Logger:Info("DaylightService linked with NotificationService")
end

function DaylightService:Cleanup()
    Logger:Info("DaylightService shutting down...")
    
    -- Cancel any active tweens
    if self._currentTween then
        self._currentTween:Cancel()
        self._currentTween = nil
    end
    
    for name, connection in pairs(self._connections) do
        if connection then
            if name == "DayNightCycle" then
                HeartbeatManager.getInstance():unregister(connection)
            elseif connection.Connected then
                connection:Disconnect()
            end
        end
    end
    
    self._connections = {}
    
    Logger:Info("✓ DaylightService shutdown complete")
end

return DaylightService