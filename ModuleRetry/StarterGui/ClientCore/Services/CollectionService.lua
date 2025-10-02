local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(game.ReplicatedStorage.Shared.Modules.ClientLogger)
local Constants = require(game.ReplicatedStorage.Shared.Modules.Constants)
local HeartbeatManager = require(game.ReplicatedStorage.Shared.Modules.HeartbeatManager)

local CollectionService = {}
CollectionService.__index = CollectionService

local player = Players.LocalPlayer

-- Counter Configuration
local COUNTER_CONFIG = {
    LIFETIME = 1.5,           -- How long counter stays visible
    TWEEN_DISTANCE = 3,       -- How far up the counter moves
    SCALE_SIZE = 1.2,         -- Scale multiplier during animation
    COLOR_CHANGE_INTERVAL = 100 -- Change color every 100 spores
}

-- Confetti configuration
local CONFETTI_CONFIG = {
    TRIGGER_INTERVAL = 100, -- Trigger every 100 spores
    PARTICLE_COUNT = 120, -- Much more confetti for a thick explosion
    COLORS = {
        Color3.fromRGB(255, 223, 0),   -- Gold
        Color3.fromRGB(255, 140, 0),   -- Orange
        Color3.fromRGB(255, 20, 147),  -- Deep Pink
        Color3.fromRGB(50, 205, 50),   -- Lime Green
        Color3.fromRGB(30, 144, 255),  -- Dodger Blue
        Color3.fromRGB(138, 43, 226),  -- Blue Violet
        Color3.fromRGB(255, 69, 0),    -- Red Orange
        Color3.fromRGB(0, 255, 255)    -- Cyan
    }
}

-- Counter state
local currentCounters = {} -- Active counter UIs
local sporeCounterValue = 0
local gemCounterValue = 0
local counterResetTask = nil
local hasCollectedGem = false -- Track if gems have ever been collected
local counterUITemplate = nil
local lastConfettiMilestone = 0 -- Track last confetti milestone

-- Collection radius configuration
local COLLECTION_CONFIG = {
	RADIUS = 6,
	HEIGHT = 0.3,
	COLOR = Color3.fromRGB(255, 255, 255),
	TRANSPARENCY = 0.75,
	MATERIAL = Enum.Material.SmoothPlastic,
	CAN_COLLIDE = false,
	ANCHORED = true,
	Y_OFFSET = 1.8
}

-- Dynamic radius based on upgrades
local DYNAMIC_RADIUS = 6.0 -- Will be updated by upgrades

-- Collection animation configuration
local COLLECTION_ANIMATION_CONFIG = {
	SPEED = 20, -- studs per second for spore movement to player
	VFX_DURATION = 1 -- seconds to play VFX
}

-- Security colors and sizes
local SECURITY_COLORS = {
	OWN_PLOT = Color3.fromRGB(255, 255, 255), -- White - own plot
	OTHER_PLOT = Color3.fromRGB(255, 0, 0), -- Red - other player's plot
	NEUTRAL = Color3.fromRGB(255, 255, 255), -- White - neutral areas
}

local SECURITY_SIZES = {
	OWN_PLOT = 6, -- Full radius on own plot
	OFF_PLOT = 3, -- Reduced radius when not on own plot
}

-- Tween settings for smooth color and size transitions
local TWEEN_INFO = TweenInfo.new(
	0.3, -- Duration
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out,
	0, -- Repeat count
	false, -- Reverses
	0 -- Delay
)

-- Vibrant color palette for counter
local VIBRANT_COLORS = {
    Color3.fromRGB(255, 64, 64),   -- Bright Red
    Color3.fromRGB(255, 128, 0),   -- Orange  
    Color3.fromRGB(255, 255, 0),   -- Yellow
    Color3.fromRGB(0, 255, 0),     -- Lime Green
    Color3.fromRGB(0, 255, 255),   -- Cyan
    Color3.fromRGB(64, 64, 255),   -- Bright Blue
    Color3.fromRGB(255, 0, 255),   -- Magenta
    Color3.fromRGB(255, 128, 255), -- Pink
}

-- Get vibrant color based on counter value
local function getVibrantColor(value)
    if value < COUNTER_CONFIG.COLOR_CHANGE_INTERVAL then
        return Color3.new(1, 1, 1) -- White for values under 100
    end
    
    local colorIndex = math.floor(value / COUNTER_CONFIG.COLOR_CHANGE_INTERVAL) % #VIBRANT_COLORS + 1
    return VIBRANT_COLORS[colorIndex]
end

-- Format decimal numbers to show appropriate precision
local function formatValue(value)
    if value % 1 == 0 then
        return string.format("%.0f", value) -- Show whole numbers without decimals
    else
        return string.format("%.2f", value) -- Show decimals with 2 places
    end
end

-- Create confetti effect when hitting milestones
local function createConfettiEffect()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- Create temporary ScreenGui for confetti
    local confettiGui = Instance.new("ScreenGui")
    confettiGui.Name = "ConfettiEffect"
    confettiGui.Parent = playerGui

    -- Create confetti cannon effect from center
    local confettiCount = 50
    for i = 1, confettiCount do
        local confetti = Instance.new("Frame")
        confetti.Name = "ConfettiPiece" .. i
        confetti.Size = UDim2.new(0, math.random(15, 30), 0, math.random(15, 30))

        -- Start from CENTER of screen
        confetti.Position = UDim2.new(0.5, 0, 0.8, 0)

        confetti.BorderSizePixel = 0
        confetti.BackgroundColor3 = CONFETTI_CONFIG.COLORS[math.random(1, #CONFETTI_CONFIG.COLORS)]
        confetti.Parent = confettiGui

        -- Add rotation and make some pieces different shapes
        confetti.Rotation = math.random(0, 360)

        -- Make some pieces circular for variety
        if math.random() > 0.5 then
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = confetti
        end

        -- Create CANNON effect - shoot in all directions from center
        local angle = (i / confettiCount) * math.pi * 2
        local distance = math.random(300, 600)
        local endX = math.cos(angle) * distance
        local endY = math.sin(angle) * distance * 0.7

        local animationTime = math.random(80, 120) / 100

        -- Create cannon explosion motion
        local moveTween = TweenService:Create(confetti,
            TweenInfo.new(animationTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {
                Position = UDim2.new(0.5, endX, 0.8, endY),
                Rotation = confetti.Rotation + math.random(720, 1440)
            }
        )

        -- Create fade out
        local fadeTween = TweenService:Create(confetti,
            TweenInfo.new(animationTime * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, animationTime * 0.4),
            {
                BackgroundTransparency = 1,
                Size = UDim2.new(0, 0, 0, 0)
            }
        )

        -- Start animations with tiny delays for burst effect
        local delay = math.random(0, 10) / 1000
        task.delay(delay, function()
            moveTween:Play()
            fadeTween:Play()
        end)
    end

    -- Clean up
    game:GetService("Debris"):AddItem(confettiGui, 2)

end

-- Check if we hit a milestone and trigger confetti
local function checkConfettiTrigger(newSporeValue)
    local oldValue = lastConfettiMilestone
    local newMilestone = math.floor(newSporeValue / CONFETTI_CONFIG.TRIGGER_INTERVAL)
    local oldMilestone = math.floor(oldValue / CONFETTI_CONFIG.TRIGGER_INTERVAL)

    if newMilestone > oldMilestone and newMilestone > 0 then
        task.spawn(createConfettiEffect)
        lastConfettiMilestone = newSporeValue
        return true
    end

    lastConfettiMilestone = newSporeValue
    return false
end

-- Initialize counter UI template
local function initializeCounterTemplate()
    counterUITemplate = ReplicatedStorage:FindFirstChild("CounterUI")
    if not counterUITemplate then
        Logger:Warn("CounterUI part not found in ReplicatedStorage")
        return false
    end
    
    local counterFrame = counterUITemplate:FindFirstChild("CounterUIFrame")
    if not counterFrame or not counterFrame:IsA("BillboardGui") then
        Logger:Warn("CounterUIFrame (BillboardGui) not found in CounterUI")
        return false
    end
    
    -- Verify the required components exist
    local sporeIcon = counterFrame:FindFirstChild("SporeIcon")
    local gemIcon = counterFrame:FindFirstChild("GemIcon") 
    local sporeCounter = counterFrame:FindFirstChild("SporeCounter")
    local gemCounter = counterFrame:FindFirstChild("GemCounter")
    
    if not sporeIcon then Logger:Warn("SporeIcon not found in CounterUIFrame") end
    if not gemIcon then Logger:Warn("GemIcon not found in CounterUIFrame") end
    if not sporeCounter then Logger:Warn("SporeCounter not found in CounterUIFrame") end
    if not gemCounter then Logger:Warn("GemCounter not found in CounterUIFrame") end
    
    Logger:Info("Counter UI template found and verified")
    return true
end

-- Create or update counter at position
local function createOrUpdateCounter(position, sporeValue, gemValue, itemType)
    
    -- Update values
    if itemType == "spore" or itemType == "bigspore" then
        local oldSporeValue = sporeCounterValue
        sporeCounterValue = sporeCounterValue + sporeValue
        -- Check if we should trigger confetti effect
        checkConfettiTrigger(sporeCounterValue)
    elseif itemType == "gem" then
        gemCounterValue = gemCounterValue + gemValue
        hasCollectedGem = true -- Show gem UI from now on
    end
    
    -- Find or create counter at this position
    local counter = currentCounters[1] -- Use single counter for now
    
    if counter and counter.Parent then
        -- Update existing counter with hop animation
        local billboardGui = counter:FindFirstChild("CounterUIFrame")
        if billboardGui then
            -- Update spore counter
            local sporeCounter = billboardGui:FindFirstChild("SporeCounter")
            if sporeCounter then
                sporeCounter.Text = formatValue(sporeCounterValue)
                sporeCounter.TextColor3 = getVibrantColor(sporeCounterValue)
            end
            
            -- Update gem counter (show if we've collected gems)
            local gemIcon = billboardGui:FindFirstChild("GemIcon")
            local gemCounter = billboardGui:FindFirstChild("GemCounter")
            
            if hasCollectedGem then
                if gemIcon then 
                    gemIcon.Visible = true
                    gemIcon.ImageTransparency = 0 -- Ensure visible
                end
                if gemCounter then
                    gemCounter.Text = formatValue(gemCounterValue)
                    gemCounter.Visible = true
                    gemCounter.TextTransparency = 0 -- Ensure visible
                end
            end
        end
        
        -- Animate counter to new position with hop
        local hopTween = TweenService:Create(
            counter,
            TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {Position = position + Vector3.new(0, 1, 0)} -- Head height
        )
        hopTween:Play()
        
    else
        -- Create new counter
        if not counterUITemplate then
            Logger:Warn("Cannot create counter - no template available")
            return
        end
        
        counter = counterUITemplate:Clone()
        counter.Name = "ActiveCounter_" .. tick()
        counter.Position = position + Vector3.new(0, 1, 0) -- Head height instead of TWEEN_DISTANCE
        counter.Anchored = true
        counter.CanCollide = false
        counter.Transparency = 1 -- Make part invisible
        counter.Parent = workspace
        
        local billboardGui = counter:FindFirstChild("CounterUIFrame")
        if billboardGui then
            billboardGui.Adornee = counter
            billboardGui.StudsOffset = Vector3.new(0, 2, 0)
            
            -- Setup spore counter
            local sporeCounter = billboardGui:FindFirstChild("SporeCounter")
            if sporeCounter then
                sporeCounter.Text = formatValue(sporeCounterValue)
                sporeCounter.TextColor3 = getVibrantColor(sporeCounterValue)
                sporeCounter.Visible = true
            end
            
            -- Setup gem counter - hide gem elements until first gem collected
            local gemIcon = billboardGui:FindFirstChild("GemIcon") 
            local gemCounter = billboardGui:FindFirstChild("GemCounter")
            
            if hasCollectedGem then
                -- Show gem UI
                if gemIcon then 
                    gemIcon.Visible = true
                    gemIcon.ImageTransparency = 0 -- Ensure it's visible
                    -- Animate gem icon appearance
                    local originalSize = gemIcon.Size
                    gemIcon.Size = UDim2.new(0, 0, 0, 0)
                    local showGemTween = TweenService:Create(
                        gemIcon,
                        TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                        {Size = originalSize}
                    )
                    showGemTween:Play()
                end
                if gemCounter then
                    gemCounter.Text = formatValue(gemCounterValue)
                    gemCounter.Visible = true
                end
            else
                -- Hide gem elements until first collection
                if gemIcon then gemIcon.Visible = false end
                if gemCounter then gemCounter.Visible = false end
            end
            
            -- Animate counter appearance
            local originalSize = billboardGui.Size
            billboardGui.Size = UDim2.new(0, 0, 0, 0)
            
            local appearTween = TweenService:Create(
                billboardGui,
                TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                {Size = originalSize}
            )
            appearTween:Play()
        end
        
        currentCounters[1] = counter
    end
    
    -- Reset cleanup timer
    if counterResetTask then
        task.cancel(counterResetTask)
    end
    
    counterResetTask = task.delay(COUNTER_CONFIG.LIFETIME, function()
        -- Hide counter with fade animation
        if counter and counter.Parent then
            local billboardGui = counter:FindFirstChild("CounterUIFrame")
            if billboardGui then
                -- Fade out all text and images
                local fadeOut = TweenService:Create(
                    billboardGui,
                    TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                    {Size = UDim2.new(0, 0, 0, 0)}
                )
                
                -- Also fade out all child elements
                for _, child in pairs(billboardGui:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        local textFade = TweenService:Create(child, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1})
                        textFade:Play()
                    elseif child:IsA("ImageLabel") then
                        local imageFade = TweenService:Create(child, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {ImageTransparency = 1})
                        imageFade:Play()
                    end
                end
                
                fadeOut:Play()
                fadeOut.Completed:Connect(function()
                    counter:Destroy()
                    currentCounters[1] = nil
                    -- Reset counter values when UI vanishes
                    sporeCounterValue = 0
                    gemCounterValue = 0
                    hasCollectedGem = false
                    lastConfettiMilestone = 0
                end)
            else
                counter:Destroy()
                currentCounters[1] = nil
                -- Reset counter values when UI vanishes
                sporeCounterValue = 0
                gemCounterValue = 0
                hasCollectedGem = false
                lastConfettiMilestone = 0
            end
        end
    end)
end

-- Reset counter system
local function resetCounters()
    sporeCounterValue = 0
    gemCounterValue = 0
    hasCollectedGem = false -- Reset gem visibility when counters reset
    lastConfettiMilestone = 0 -- Reset confetti milestone
    
    -- Clean up active counters
    for i, counter in pairs(currentCounters) do
        if counter and counter.Parent then
            counter:Destroy()
        end
        currentCounters[i] = nil
    end
    
    if counterResetTask then
        task.cancel(counterResetTask)
        counterResetTask = nil
    end
    
    Logger:Debug("Counters reset after inactivity")
end


function CollectionService.new()
	local self = setmetatable({}, CollectionService)
	self._connections = {}
	self._collectionRadius = nil
	self._isActive = false
	self._currentTween = nil
	self._isOnOwnPlot = true
	self._isOnOtherPlot = false
	self._collectableItems = {} -- Track items in collection range
	self._collectionRemoteEvent = nil
	self:_initialize()
	return self
end

function CollectionService:_initialize()
	Logger:Info("CollectionService initializing...")

	self:_setupRemoteEvents()
	self:_setupCounterSystem()

	self._connections.CharacterAdded = player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end)

	if player.Character then
		self:_onCharacterAdded(player.Character)
	end

	Logger:Info("CollectionService initialized successfully")
end

function CollectionService:_setupRemoteEvents()
	-- Wait for remote events to be created by server
	local shared = ReplicatedStorage:WaitForChild("Shared", 5)
	if shared then
		local remoteEvents = shared:WaitForChild("RemoteEvents", 5)
		if remoteEvents then
			local dataEvents = remoteEvents:WaitForChild("DataEvents", 5)
			if dataEvents then
				-- Wait for collection remote event
				local collectionEvent = dataEvents:WaitForChild("ItemCollected", 10)
				self._collectionRemoteEvent = collectionEvent
			end
		end
	end

	if not self._collectionRemoteEvent then
		Logger:Warn("ItemCollected RemoteEvent not found - collection will not work")
	end
end

function CollectionService:_setupCounterSystem()
	Logger:Info("Setting up counter system...")
	
	-- Initialize counter template
	initializeCounterTemplate()
	
	-- Listen for CollectionConfirmed events from server
	local shared = ReplicatedStorage:WaitForChild("Shared", 5)
	if shared then
		local remoteEvents = shared:WaitForChild("RemoteEvents", 5)
		if remoteEvents then
			local dataEvents = remoteEvents:WaitForChild("DataEvents", 5)
			if dataEvents then
				local collectionConfirmed = dataEvents:WaitForChild("CollectionConfirmed", 10)
				if collectionConfirmed then
					self._connections.CollectionConfirmed = collectionConfirmed.OnClientEvent:Connect(function(itemType, value, collectionPosition)
						Logger:Debug(string.format("Collection confirmed: %s worth %s at %s", itemType, tostring(value), tostring(collectionPosition)))
						
						-- Create counter popup at collection position
						if itemType == "spore" or itemType == "bigspore" then
							createOrUpdateCounter(collectionPosition, value, 0, itemType)
						elseif itemType == "gem" then
							createOrUpdateCounter(collectionPosition, 0, value, itemType)
						end
					end)
					Logger:Info("Counter system connected to CollectionConfirmed event")
				else
					Logger:Warn("CollectionConfirmed RemoteEvent not found - counter system disabled")
				end
			end
		end
	end
end

function CollectionService:_onCharacterAdded(character)
	Logger:Debug("Character added, setting up collection radius")

	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoidRootPart then
		Logger:Error("Failed to find HumanoidRootPart for collection radius")
		return
	end

	wait(1) -- Wait for character to fully load

	self:_createCollectionRadius()
	self:_startPositionTracking(humanoidRootPart)
end

function CollectionService:_createCollectionRadius()
	if self._collectionRadius then
		self:_destroyCollectionRadius()
	end

	-- Create the cylinder part
	local cylinder = Instance.new("Part")
	cylinder.Name = "CollectionRadius"
	cylinder.Shape = Enum.PartType.Cylinder
	cylinder.Size = Vector3.new(COLLECTION_CONFIG.HEIGHT, COLLECTION_CONFIG.RADIUS * 2, COLLECTION_CONFIG.RADIUS * 2)
	cylinder.Color = COLLECTION_CONFIG.COLOR
	cylinder.Transparency = COLLECTION_CONFIG.TRANSPARENCY
	cylinder.Material = COLLECTION_CONFIG.MATERIAL
	cylinder.CanCollide = COLLECTION_CONFIG.CAN_COLLIDE
	cylinder.Anchored = COLLECTION_CONFIG.ANCHORED
	cylinder.TopSurface = Enum.SurfaceType.Smooth
	cylinder.BottomSurface = Enum.SurfaceType.Smooth

	-- Orient the cylinder to lay flat (rotate 90 degrees on Z axis)
	cylinder.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90))

	cylinder.Parent = Workspace

	self._collectionRadius = cylinder

	Logger:Debug("Collection radius created successfully")
end

function CollectionService:_startPositionTracking(humanoidRootPart)
	if self._connections.PositionTracking then
		HeartbeatManager.getInstance():unregister(self._connections.PositionTracking)
	end

	-- Use centralized heartbeat manager with 0.1 second interval instead of every frame
	self._connections.PositionTracking = HeartbeatManager.getInstance():register(function()
		if self._collectionRadius and humanoidRootPart and humanoidRootPart.Parent then
			local position = humanoidRootPart.Position
			local targetPosition = Vector3.new(position.X, position.Y - (humanoidRootPart.Size.Y / 2) - COLLECTION_CONFIG.Y_OFFSET, position.Z)

			self._collectionRadius.CFrame = CFrame.new(targetPosition) * CFrame.Angles(0, 0, math.rad(90))
			
			-- Check plot ownership and update security status
			self:_checkPlotSecurity(position)
			
			-- Check for collectible items
			self:_checkForCollectibles(position)
		end
	end, 0.1)

	self._isActive = true
	Logger:Debug("Position tracking started for collection radius")
end

function CollectionService:_checkPlotSecurity(playerPosition)
	local plotStatus = self:_getPlayerPlotStatus(playerPosition)
	
	-- Only update if security status changed
	if plotStatus.isOnOwnPlot ~= self._isOnOwnPlot or plotStatus.isOnOtherPlot ~= self._isOnOtherPlot then
		self._isOnOwnPlot = plotStatus.isOnOwnPlot
		self._isOnOtherPlot = plotStatus.isOnOtherPlot
		self:_updateSecurityVisuals(plotStatus)
	end
end

function CollectionService:_getPlayerPlotStatus(playerPosition)
	local playerPlots = Workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		return {isOnOwnPlot = false, isOnOtherPlot = false} -- Neutral area
	end
	
	-- Check if player is on any plot (including Area2)
	for _, plot in pairs(playerPlots:GetChildren()) do
		if plot:IsA("Model") and plot.Name:find("Plot_") then
			local plotOwner = plot.Name:gsub("Plot_", "")
			local isOwnPlot = plotOwner == player.Name
			
			-- Check Area 1 (main plot area)
			local plotCFrame, plotSize = plot:GetBoundingBox()
			local plotPosition = plotCFrame.Position
			
			local xDistance = math.abs(playerPosition.X - plotPosition.X)
			local zDistance = math.abs(playerPosition.Z - plotPosition.Z)
			
			if xDistance <= plotSize.X / 2 and zDistance <= plotSize.Z / 2 then
				return {
					isOnOwnPlot = isOwnPlot,
					isOnOtherPlot = not isOwnPlot
				}
			end
			
			-- Check Area 2 if it exists
			local area2 = plot:FindFirstChild("Area2")
			if area2 then
				local area2CFrame, area2Size = area2:GetBoundingBox()
				local area2Position = area2CFrame.Position
				
				local area2XDistance = math.abs(playerPosition.X - area2Position.X)
				local area2ZDistance = math.abs(playerPosition.Z - area2Position.Z)
				
				if area2XDistance <= area2Size.X / 2 and area2ZDistance <= area2Size.Z / 2 then
					return {
						isOnOwnPlot = isOwnPlot,
						isOnOtherPlot = not isOwnPlot
					}
				end
			end
		end
	end
	
	-- Player is not on any plot (neutral area)
	return {isOnOwnPlot = false, isOnOtherPlot = false}
end

function CollectionService:_updateSecurityVisuals(plotStatus)
	if not self._collectionRadius then
		return
	end
	
	-- Stop any existing tween
	if self._currentTween then
		self._currentTween:Cancel()
	end
	
	-- Determine target color and size based on plot status
	local targetColor, targetRadius, statusText
	
	if plotStatus.isOnOwnPlot then
		-- On own plot - dynamic radius based on upgrades, white
		targetColor = SECURITY_COLORS.OWN_PLOT
		targetRadius = DYNAMIC_RADIUS
		statusText = "OWN_PLOT"
	elseif plotStatus.isOnOtherPlot then
		-- On other player's plot - small radius, red
		targetColor = SECURITY_COLORS.OTHER_PLOT
		targetRadius = SECURITY_SIZES.OFF_PLOT
		statusText = "OTHER_PLOT"
	else
		-- Neutral area - small radius, white
		targetColor = SECURITY_COLORS.NEUTRAL
		targetRadius = SECURITY_SIZES.OFF_PLOT
		statusText = "NEUTRAL"
	end
	
	local targetSize = Vector3.new(COLLECTION_CONFIG.HEIGHT, targetRadius * 2, targetRadius * 2)
	
	-- Create and play tween for both color and size
	self._currentTween = TweenService:Create(
		self._collectionRadius,
		TWEEN_INFO,
		{
			Color = targetColor,
			Size = targetSize
		}
	)
	
	self._currentTween:Play()
	
	Logger:Debug(string.format("Security status: %s (radius: %d)", statusText, targetRadius))
end

function CollectionService:_destroyCollectionRadius()
	if self._currentTween then
		self._currentTween:Cancel()
		self._currentTween = nil
	end
	
	if self._collectionRadius then
		self._collectionRadius:Destroy()
		self._collectionRadius = nil
		Logger:Debug("Collection radius destroyed")
	end
end

function CollectionService:SetActive(active)
	if active == self._isActive then
		return
	end

	self._isActive = active

	if self._collectionRadius then
		self._collectionRadius.Transparency = active and COLLECTION_CONFIG.TRANSPARENCY or 1
	end

	Logger:Info(string.format("Collection radius %s", active and "activated" or "deactivated"))
end

function CollectionService:IsActive()
	return self._isActive
end

function CollectionService:UpdateConfig(newConfig)
	for key, value in pairs(newConfig) do
		if COLLECTION_CONFIG[key] ~= nil then
			COLLECTION_CONFIG[key] = value
		end
	end

	-- Recreate the radius with new config if it exists
	if self._collectionRadius then
		local wasActive = self._isActive
		self:_destroyCollectionRadius()
		self:_createCollectionRadius()

		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			self:_startPositionTracking(player.Character.HumanoidRootPart)
		end

		self:SetActive(wasActive)
	end

	Logger:Info("Collection radius configuration updated")
end

function CollectionService:GetConfig()
	local configCopy = {}
	for key, value in pairs(COLLECTION_CONFIG) do
		configCopy[key] = value
	end
	return configCopy
end

function CollectionService:GetRadius()
	-- Return effective radius based on plot status, using dynamic radius
	return self._isOnOwnPlot and DYNAMIC_RADIUS or SECURITY_SIZES.OFF_PLOT
end

function CollectionService:GetBaseRadius()
	-- Return the configured base radius
	return COLLECTION_CONFIG.RADIUS
end

function CollectionService:SetRadius(newRadius)
	self:UpdateConfig({RADIUS = newRadius})
end

function CollectionService:SetPickUpRange(newRange)
	DYNAMIC_RADIUS = newRange
	Logger:Info(string.format("Updated collection radius to %.2f studs", newRange))
	
	-- Update visual radius if on own plot
	if self._collectionRadius and self._isOnOwnPlot then
		local targetSize = Vector3.new(COLLECTION_CONFIG.HEIGHT, newRange * 2, newRange * 2)
		
		-- Animate radius change
		if self._currentTween then
			self._currentTween:Cancel()
		end
		
		self._currentTween = TweenService:Create(
			self._collectionRadius,
			TWEEN_INFO,
			{Size = targetSize}
		)
		self._currentTween:Play()
	end
end

function CollectionService:SetTransparency(transparency)
	self:UpdateConfig({TRANSPARENCY = transparency})
end

function CollectionService:SetColor(color)
	self:UpdateConfig({COLOR = color})
end

function CollectionService:SetCollectionSpeed(speed)
	COLLECTION_ANIMATION_CONFIG.SPEED = speed
	Logger:Info(string.format("Collection speed set to %d studs/second", speed))
end

function CollectionService:GetCollectionSpeed()
	return COLLECTION_ANIMATION_CONFIG.SPEED
end

function CollectionService:GetCollectionPart()
	return self._collectionRadius
end

function CollectionService:IsOnOwnPlot()
	return self._isOnOwnPlot
end

function CollectionService:IsSecure()
	return self._isOnOwnPlot
end

function CollectionService:_checkForCollectibles(playerPosition)
	-- Only collect when on own plot for security
	if not self._isOnOwnPlot then
		return
	end
	
	local currentRadius = self:GetRadius()
	local playerPlots = Workspace:FindFirstChild("PlayerPlots")
	if not playerPlots then
		return
	end
	
	local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
	if not playerPlot then
		return
	end
	
	-- Check Area 1 spores
	local sporesFolder = playerPlot:FindFirstChild("Spores")
	if sporesFolder then
		for _, item in pairs(sporesFolder:GetChildren()) do
			if item:IsA("BasePart") then
				-- Check if item name matches the patterns created by MushroomService
				local isSporePart = string.find(item.Name, "SporePart_") ~= nil
				local isGemPart = string.find(item.Name, "GemSporePart_") ~= nil
				local isBigSpore = string.find(item.Name, "BigSpore_") ~= nil
				
				if isSporePart or isGemPart or isBigSpore then
					local distance = (item.Position - playerPosition).Magnitude
					
					if distance <= currentRadius then
						-- Item is in collection range
						if not self._collectableItems[item] then
							-- New item detected, collect it
							self:_collectItem(item)
							self._collectableItems[item] = true
						end
					else
						-- Item is out of range
						self._collectableItems[item] = nil
					end
				end
			end
		end
	end
	
	-- Check Area 2 spores if Area2 exists
	local area2 = playerPlot:FindFirstChild("Area2")
	if area2 then
		local area2SporesFolder = area2:FindFirstChild("Spores")
		if area2SporesFolder then
			for _, item in pairs(area2SporesFolder:GetChildren()) do
				if item:IsA("BasePart") then
					-- Check if item name matches the patterns created by MushroomService
					local isSporePart = string.find(item.Name, "SporePart_") ~= nil
					local isGemPart = string.find(item.Name, "GemSporePart_") ~= nil
					local isBigSpore = string.find(item.Name, "BigSpore_") ~= nil
					
					if isSporePart or isGemPart or isBigSpore then
						local distance = (item.Position - playerPosition).Magnitude
						
						if distance <= currentRadius then
							-- Item is in collection range
							if not self._collectableItems[item] then
								-- New item detected, collect it
								self:_collectItem(item)
								self._collectableItems[item] = true
							end
						else
							-- Item is out of range
							self._collectableItems[item] = nil
						end
					end
				end
			end
		end
	end
end

function CollectionService:_collectItem(item)
	if not self._collectionRemoteEvent then
		Logger:Warn("Cannot collect item - no RemoteEvent available")
		return
	end
	
	-- FIXED: Properly detect item type based on name pattern
	local itemType = "spore"
	if string.find(item.Name, "GemSporePart_") then
		itemType = "gem"
	elseif string.find(item.Name, "SporePart_") then
		itemType = "spore"
	elseif string.find(item.Name, "BigSpore_") then
		itemType = "bigspore"
	else
		Logger:Warn(string.format("Unknown item type for %s", item.Name))
		return
	end
	
	
	-- Start collection animation
	self:_animateItemCollection(item, itemType)
	
	-- Remove from tracking immediately
	self._collectableItems[item] = nil
	
	Logger:Debug(string.format("Started collecting %s (%s)", itemType, item.Name))
end

function CollectionService:_animateItemCollection(item, itemType)
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		-- Fallback: immediate collection
		self:_completeCollection(item, itemType, item.Position, item.Name)
		return
	end
	
	local humanoidRootPart = player.Character.HumanoidRootPart
	local startPosition = item.Position
	local sporeClone = item:Clone()
	local itemName = item.Name -- Store name before destroying
	
	-- Store original size for shrinking animation
	local originalSize = sporeClone.Size
	
	-- Remove original item
	item:Destroy()
	
	-- Setup animated spore
	sporeClone.Anchored = true
	sporeClone.CanCollide = false
	sporeClone.Parent = Workspace
	
	-- Calculate animation duration based on distance and speed
	local distance = (startPosition - humanoidRootPart.Position).Magnitude
	local duration = math.max(0.2, distance / COLLECTION_ANIMATION_CONFIG.SPEED) -- Minimum duration
	
	-- Use RunService to continuously track the player's position
	local startTime = tick()
	local connection
	
	connection = HeartbeatManager.getInstance():register(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / duration, 1)
		
		-- Check if player still exists
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") or not sporeClone.Parent then
			HeartbeatManager.getInstance():unregister(connection)
			if sporeClone.Parent then
				sporeClone:Destroy()
			end
			self:_completeCollection(nil, itemType, startPosition, itemName)
			return
		end
		
		-- Calculate current position by interpolating towards the player's current position
		local currentPlayerPos = player.Character.HumanoidRootPart.Position
		local currentPos = startPosition:Lerp(currentPlayerPos, alpha)
		sporeClone.Position = currentPos
		
		-- Shrink the spore as it gets closer to the player (starts normal size, ends at 10% size)
		local shrinkFactor = 1 - (alpha * 0.9) -- Goes from 1.0 to 0.1
		sporeClone.Size = originalSize * shrinkFactor
		
		-- Animation complete
		if alpha >= 1 then
			HeartbeatManager.getInstance():unregister(connection)
			local collectionPosition = sporeClone.Position
			sporeClone:Destroy()
			self:_completeCollection(nil, itemType, collectionPosition, itemName)
		end
	end)
	
	Logger:Debug(string.format("Started simple collection animation for %s", itemType))
end

function CollectionService:_completeCollection(item, itemType, vfxPosition, itemName)
	
	-- Send collection request to server
	if item then
		self._collectionRemoteEvent:FireServer(item, itemType, item.Name)
	else
		-- Item was already destroyed in animation, send itemName
		self._collectionRemoteEvent:FireServer(nil, itemType, itemName)
	end
	
	-- Play VFX at collection point
	self:_playCollectionVFX(vfxPosition)
	
	Logger:Debug(string.format("Completed collection of %s", itemType))
end

function CollectionService:_playCollectionVFX(position)
	-- Get player's torso position instead of using passed position
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		Logger:Warn("Cannot play VFX - player character not found")
		return
	end
	
	local torsoPosition = player.Character.HumanoidRootPart.Position
	
	-- Play collection sound effect
	local SoundService = game:GetService("SoundService")
	local collectionSound = Instance.new("Sound")
	collectionSound.SoundId = "rbxassetid://118825886342313"
	collectionSound.Volume = 0.5
	collectionSound.Parent = player.Character.HumanoidRootPart
	collectionSound:Play()
	
	-- Clean up sound after it finishes
	collectionSound.Ended:Connect(function()
		collectionSound:Destroy()
	end)
	
	local vfxTemplate = ReplicatedStorage:FindFirstChild("VFX")
	if vfxTemplate then
		local collectionVFX = vfxTemplate:FindFirstChild("CollectionVFX")
		if collectionVFX then
			Logger:Debug(string.format("Found CollectionVFX folder with %d children", #collectionVFX:GetChildren()))
			
			-- Clone the entire CollectionVFX folder to player's torso position
			local vfxClone = collectionVFX:Clone()
			vfxClone.Name = "ActiveCollectionVFX"
			vfxClone.Parent = Workspace
			
			-- Position and activate each VFX at torso position
			for _, vfxChild in pairs(vfxClone:GetChildren()) do
				Logger:Debug(string.format("Activating VFX: %s (%s)", vfxChild.Name, vfxChild.ClassName))
				
				-- Position the VFX at player's torso
				if vfxChild:IsA("BasePart") then
					vfxChild.Position = torsoPosition
					vfxChild.Anchored = true
					vfxChild.CanCollide = false
					
					-- Activate any particle emitters, sounds, etc.
					for _, descendant in pairs(vfxChild:GetDescendants()) do
						if descendant:IsA("ParticleEmitter") then
							descendant:Emit(descendant:GetAttribute("EmitCount") or 50)
						elseif descendant:IsA("Sound") then
							descendant:Play()
						elseif descendant:IsA("PointLight") or descendant:IsA("SpotLight") then
							descendant.Enabled = true
						end
					end
					
				elseif vfxChild:IsA("Attachment") then
					-- Create anchor part at torso position for attachments
					local anchorPart = Instance.new("Part")
					anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
					anchorPart.Position = torsoPosition
					anchorPart.Anchored = true
					anchorPart.CanCollide = false
					anchorPart.Transparency = 1
					anchorPart.Parent = Workspace
					vfxChild.Parent = anchorPart
					
					-- Activate particle emitters in attachment
					for _, descendant in pairs(vfxChild:GetDescendants()) do
						if descendant:IsA("ParticleEmitter") then
							descendant:Emit(descendant:GetAttribute("EmitCount") or 50)
						end
					end
					
					-- Cleanup anchor part
					game:GetService("Debris"):AddItem(anchorPart, COLLECTION_ANIMATION_CONFIG.VFX_DURATION)
				end
			end
			
			-- Cleanup the entire VFX clone
			game:GetService("Debris"):AddItem(vfxClone, COLLECTION_ANIMATION_CONFIG.VFX_DURATION)
			
			Logger:Debug("Successfully activated all collection VFX at player torso")
		else
			Logger:Warn("CollectionVFX not found in ReplicatedStorage.VFX")
		end
	else
		Logger:Warn("VFX folder not found in ReplicatedStorage")
	end
end

function CollectionService:GetSecurityStatus()
	local statusText, color
	
	if self._isOnOwnPlot then
		statusText = "OWN_PLOT"
		color = SECURITY_COLORS.OWN_PLOT
	elseif self._isOnOtherPlot then
		statusText = "OTHER_PLOT" 
		color = SECURITY_COLORS.OTHER_PLOT
	else
		statusText = "NEUTRAL"
		color = SECURITY_COLORS.NEUTRAL
	end
	
	return {
		isSecure = self._isOnOwnPlot, -- Only secure on own plot
		isOnOwnPlot = self._isOnOwnPlot,
		isOnOtherPlot = self._isOnOtherPlot,
		statusText = statusText,
		color = color,
		radius = self._isOnOwnPlot and SECURITY_SIZES.OWN_PLOT or SECURITY_SIZES.OFF_PLOT
	}
end

function CollectionService:Cleanup()
	for connectionName, connection in pairs(self._connections) do
		if connection then
			if connectionName == "PositionTracking" then
				HeartbeatManager.getInstance():unregister(connection)
			else
				connection:Disconnect()
			end
		end
	end
	self._connections = {}

	self:_destroyCollectionRadius()

	Logger:Info("CollectionService cleaned up")
end

return CollectionService