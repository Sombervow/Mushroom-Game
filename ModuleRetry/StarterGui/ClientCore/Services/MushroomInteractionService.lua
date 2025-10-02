local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Logger = require(game.ReplicatedStorage.Shared.Modules.ClientLogger)

local MushroomInteractionService = {}
MushroomInteractionService.__index = MushroomInteractionService

local player = Players.LocalPlayer

-- Configuration
local INTERACTION_CONFIG = {
	MAX_INTERACTION_DISTANCE = 50,
	CLICK_COOLDOWN = 0.3,
	CLICK_SCALE = 1.15,
	ANIMATION_SPEED = 0.12,
	CLICK_SOUND_ID = "rbxassetid://88156854062341",
	PITCH_VARIATIONS = {0.85, 0.95, 1.0, 1.05, 1.15},
	RAYCAST_DISTANCE = 1000,
	FALLBACK_TOUCH_RADIUS = 8,
	VFX_LIFETIME = 2,
	SOUND_CLEANUP_TIME = 3
}

-- Mobile detection helper
local function detectMobile()
	if not UserInputService.TouchEnabled then
		return false
	end
	
	if not UserInputService.MouseEnabled then
		return true
	end
	
	if UserInputService.GamepadEnabled then
		return false
	end
	
	return false
end

function MushroomInteractionService.new()
	local self = setmetatable({}, MushroomInteractionService)
	self._connections = {}
	self._remoteEvent = nil
	self._hoverService = nil
	self._isMobile = detectMobile()
	self._lastClickTime = 0
	self._isInitialized = false

	Logger:Info("[MushroomInteraction] Initializing MushroomInteractionService...")
	Logger:Info(string.format("[MushroomInteraction] Platform - Mobile: %s, Touch: %s, Mouse: %s, Keyboard: %s", 
		tostring(self._isMobile),
		tostring(UserInputService.TouchEnabled),
		tostring(UserInputService.MouseEnabled),
		tostring(UserInputService.KeyboardEnabled)
	))

	self:_initialize()
	return self
end

function MushroomInteractionService:_initialize()
	self:_setupRemoteEvents()
	self:_setupInputHandling()
	self._isInitialized = true
	Logger:Info("[MushroomInteraction] ✓ MushroomInteractionService initialized")
end

function MushroomInteractionService:_setupRemoteEvents()
	spawn(function()
		local success, result = pcall(function()
			local shared = ReplicatedStorage:WaitForChild("Shared", 10)
			if not shared then
				Logger:Warn("[MushroomInteraction] Shared folder not found")
				return
			end
			
			local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
			if not remoteEvents then
				Logger:Warn("[MushroomInteraction] RemoteEvents folder not found")
				return
			end
			
			local mushroomEvents = remoteEvents:WaitForChild("MushroomEvents", 10)
			if not mushroomEvents then
				Logger:Warn("[MushroomInteraction] MushroomEvents folder not found")
				return
			end
			
			local mushroomClicked = mushroomEvents:WaitForChild("MushroomClicked", 10)
			if mushroomClicked then
				self._remoteEvent = mushroomClicked
				Logger:Info("[MushroomInteraction] ✓ Remote events connected")
			else
				Logger:Warn("[MushroomInteraction] MushroomClicked event not found")
			end
		end)
		
		if not success then
			Logger:Error("[MushroomInteraction] Error setting up remote events: " .. tostring(result))
		end
	end)
end

function MushroomInteractionService:_setupInputHandling()
	if self._isMobile then
		self:_setupMobileInput()
	else
		self:_setupDesktopInput()
	end
end

function MushroomInteractionService:_setupMobileInput()
	Logger:Info("[MushroomInteraction] Setting up mobile touch input...")
	
	self._connections.TouchTap = UserInputService.TouchTap:Connect(function(touchPositions, gameProcessed)
		if gameProcessed then 
			Logger:Debug("[MushroomInteraction] Touch ignored - UI processed")
			return 
		end
		
		if #touchPositions > 0 then
			Logger:Info(string.format("[MushroomInteraction] Touch detected at: (%d, %d)", 
				touchPositions[1].X, touchPositions[1].Y))
			self:_handleMobileTouch(touchPositions[1])
		end
	end)
	
	Logger:Info("[MushroomInteraction] ✓ Mobile touch input configured")
end

function MushroomInteractionService:_setupDesktopInput()
	Logger:Info("[MushroomInteraction] Setting up desktop mouse input...")
	
	-- Set up mouse click detection for desktop
	self._connections.MouseClick = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then 
			Logger:Debug("[MushroomInteraction] Mouse click ignored - UI processed")
			return 
		end
		
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Logger:Info("[MushroomInteraction] Mouse click detected")
			self:_handleDesktopClick(input.Position)
		end
	end)
	
	Logger:Info("[MushroomInteraction] ✓ Desktop mouse input configured")
end

function MushroomInteractionService:SetHoverService(hoverService)
	self._hoverService = hoverService
	Logger:Info("[MushroomInteraction] ✓ Hover service linked")
end

function MushroomInteractionService:_handleDesktopClick(mousePosition)
	local camera = workspace.CurrentCamera
	if not camera then
		Logger:Warn("[MushroomInteraction] No camera found")
		return
	end

	local unitRay = camera:ScreenPointToRay(mousePosition.X, mousePosition.Y)

	-- Use raycast to find what the mouse clicked on
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {player.Character}
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = false

	local raycastResult = workspace:Raycast(
		unitRay.Origin, 
		unitRay.Direction * INTERACTION_CONFIG.RAYCAST_DISTANCE, 
		raycastParams
	)

	if raycastResult then
		local hitPart = raycastResult.Instance
		Logger:Info(string.format("[MushroomInteraction] Mouse click hit: %s (Parent: %s)", 
			hitPart.Name, 
			hitPart.Parent and hitPart.Parent.Name or "nil"
		))

		local mushroom = self:_findMushroomFromPart(hitPart)
		if mushroom then
			Logger:Info(string.format("[MushroomInteraction] Found mushroom via mouse click: %s", mushroom.Name))
			self:_onMushroomClicked(mushroom)
			return
		end
	end

	Logger:Debug("[MushroomInteraction] Mouse click missed - no mushroom found")
end

function MushroomInteractionService:_handleMobileTouch(touchPosition)
	local camera = workspace.CurrentCamera
	if not camera then
		Logger:Warn("[MushroomInteraction] No camera found")
		return
	end

	local unitRay = camera:ScreenPointToRay(touchPosition.X, touchPosition.Y)

	-- Primary method: Raycast with permissive settings
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {player.Character}
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = false

	local raycastResult = workspace:Raycast(
		unitRay.Origin, 
		unitRay.Direction * INTERACTION_CONFIG.RAYCAST_DISTANCE, 
		raycastParams
	)

	if raycastResult then
		local hitPart = raycastResult.Instance
		Logger:Info(string.format("[MushroomInteraction] Raycast hit: %s (Parent: %s)", 
			hitPart.Name, 
			hitPart.Parent and hitPart.Parent.Name or "nil"
		))

		local mushroom = self:_findMushroomFromPart(hitPart)
		if mushroom then
			Logger:Info(string.format("[MushroomInteraction] Found mushroom via raycast: %s", mushroom.Name))
			self:_onMushroomClicked(mushroom)
			return
		end
	end

	-- Fallback method: Find closest mushroom near touch ray
	Logger:Info("[MushroomInteraction] Raycast miss - trying proximity search")
	self:_findClosestMushroomToTouch(touchPosition)
end

function MushroomInteractionService:_findClosestMushroomToTouch(touchPosition)
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local ray = camera:ScreenPointToRay(touchPosition.X, touchPosition.Y)
	local playerPlot = self:_getPlayerPlot()
	
	if not playerPlot then
		Logger:Debug("[MushroomInteraction] Player plot not found")
		return
	end

	local closestMushroom = nil
	local closestDistance = math.huge

	-- Search both main area and Area2
	local searchLocations = {
		playerPlot:FindFirstChild("Mushrooms"),
		playerPlot:FindFirstChild("Area2") and playerPlot.Area2:FindFirstChild("Mushrooms")
	}

	for _, mushroomsFolder in ipairs(searchLocations) do
		if mushroomsFolder then
			for _, child in ipairs(mushroomsFolder:GetChildren()) do
				if child:IsA("Model") and child.Name:match("MushroomModel_") then
					local distance = self:_getMushroomDistanceFromRay(child, ray)
					if distance and distance < closestDistance and distance < INTERACTION_CONFIG.FALLBACK_TOUCH_RADIUS then
						closestDistance = distance
						closestMushroom = child
					end
				end
			end
		end
	end

	if closestMushroom then
		Logger:Info(string.format("[MushroomInteraction] Found closest mushroom: %s (distance: %.2f studs)", 
			closestMushroom.Name, closestDistance))
		self:_onMushroomClicked(closestMushroom)
	else
		Logger:Debug("[MushroomInteraction] No mushroom found within touch radius")
	end
end

function MushroomInteractionService:_getMushroomDistanceFromRay(mushroom, ray)
	local mushroomPosition = self:_getMushroomPosition(mushroom)
	if not mushroomPosition then
		return nil
	end

	local rayDirection = ray.Direction.Unit
	local rayToPoint = mushroomPosition - ray.Origin
	local projectedLength = rayToPoint:Dot(rayDirection)

	if projectedLength < 0 then
		return (mushroomPosition - ray.Origin).Magnitude
	end

	local closestPointOnRay = ray.Origin + rayDirection * projectedLength
	return (mushroomPosition - closestPointOnRay).Magnitude
end

function MushroomInteractionService:_getMushroomPosition(mushroom)
	if mushroom.PrimaryPart then
		return mushroom.PrimaryPart.Position
	end
	
	for _, child in ipairs(mushroom:GetChildren()) do
		if child:IsA("BasePart") then
			return child.Position
		end
	end
	
	return nil
end

function MushroomInteractionService:_findMushroomFromPart(part)
	local current = part
	local maxDepth = 10
	local depth = 0
	
	while current and depth < maxDepth do
		if current:IsA("Model") and current.Name:match("MushroomModel_") then
			return current
		end
		current = current.Parent
		depth = depth + 1
	end
	
	return nil
end

function MushroomInteractionService:_getPlayerPlot()
	local playerPlots = workspace:FindFirstChild("PlayerPlots")
	if playerPlots then
		return playerPlots:FindFirstChild("Plot_" .. player.Name)
	end
	
	return workspace:FindFirstChild("Plot_" .. player.Name)
end

function MushroomInteractionService:_onMushroomClicked(mushroom)
	if not self:_canInteractWithMushroom(mushroom) then
		Logger:Debug("[MushroomInteraction] Cannot interact - out of range or wrong plot")
		return
	end

	local currentTime = tick()
	if currentTime - self._lastClickTime < INTERACTION_CONFIG.CLICK_COOLDOWN then
		Logger:Debug("[MushroomInteraction] Click blocked - cooldown active")
		return
	end

	self._lastClickTime = currentTime
	Logger:Info(string.format("[MushroomInteraction] Mushroom clicked: %s", mushroom.Name))

	self:_playClickAnimation(mushroom)
	self:_playClickSound()
	self:_playClickVFX(mushroom)

	if _G.TutorialSystem and _G.TutorialSystem.incrementMushroomClicks then
		_G.TutorialSystem.incrementMushroomClicks()
	end

	if self._remoteEvent then
		self._remoteEvent:FireServer(mushroom)
	else
		Logger:Warn("[MushroomInteraction] Remote event not available")
	end
end

function MushroomInteractionService:_canInteractWithMushroom(mushroom)
	if not player.Character then
		return false
	end
	
	local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	local mushroomPosition = self:_getMushroomPosition(mushroom)
	if not mushroomPosition then
		return false
	end

	local distance = (rootPart.Position - mushroomPosition).Magnitude
	if distance > INTERACTION_CONFIG.MAX_INTERACTION_DISTANCE then
		Logger:Debug(string.format("[MushroomInteraction] Too far: %.1f studs", distance))
		return false
	end

	local playerPlot = self:_getPlayerPlot()
	if not playerPlot then
		return false
	end

	return mushroom:IsDescendantOf(playerPlot)
end

function MushroomInteractionService:_playClickAnimation(mushroom)
	local mainPart = mushroom.PrimaryPart or mushroom:FindFirstChildOfClass("BasePart")
	if not mainPart then return end

	local originalSize = mainPart.Size
	local originalCFrame = mainPart.CFrame
	local scaledSize = originalSize * INTERACTION_CONFIG.CLICK_SCALE

	local tweenInfo = TweenInfo.new(
		INTERACTION_CONFIG.ANIMATION_SPEED,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out,
		0,
		true
	)

	local tween = TweenService:Create(mainPart, tweenInfo, {Size = scaledSize})
	
	tween.Completed:Connect(function()
		mainPart.CFrame = originalCFrame
	end)
	
	tween:Play()
end

function MushroomInteractionService:_playClickSound()
	local sound = Instance.new("Sound")
	sound.SoundId = INTERACTION_CONFIG.CLICK_SOUND_ID
	sound.Volume = 0.8
	sound.PlaybackSpeed = INTERACTION_CONFIG.PITCH_VARIATIONS[math.random(1, #INTERACTION_CONFIG.PITCH_VARIATIONS)]
	sound.Parent = SoundService

	local success, err = pcall(function()
		sound:Play()
	end)

	if not success then
		Logger:Warn("[MushroomInteraction] Sound play failed: " .. tostring(err))
	end

	sound.Ended:Connect(function()
		sound:Destroy()
	end)

	Debris:AddItem(sound, INTERACTION_CONFIG.SOUND_CLEANUP_TIME)
end

function MushroomInteractionService:_playClickVFX(mushroom)
	local vfxTemplate = ReplicatedStorage:FindFirstChild("VFX")
	if not vfxTemplate then
		Logger:Debug("[MushroomInteraction] VFX folder not found")
		return
	end

	local clickVFX = vfxTemplate:FindFirstChild("ClickVFX")
	if not clickVFX then
		Logger:Debug("[MushroomInteraction] ClickVFX template not found")
		return
	end

	local mushroomPosition = self:_getMushroomPosition(mushroom)
	if not mushroomPosition then return end

	local vfxClone = clickVFX:Clone()
	vfxClone.Name = "ActiveClickVFX"
	vfxClone.Parent = workspace

	if vfxClone:IsA("BasePart") then
		vfxClone.Position = mushroomPosition
		vfxClone.Anchored = true
		vfxClone.CanCollide = false
	elseif vfxClone:IsA("Model") and vfxClone.PrimaryPart then
		vfxClone:SetPrimaryPartCFrame(CFrame.new(mushroomPosition))
	end

	for _, descendant in ipairs(vfxClone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local emitCount = descendant:GetAttribute("EmitCount") or 50
			descendant:Emit(emitCount)
		elseif descendant:IsA("Sound") then
			descendant:Play()
		elseif descendant:IsA("PointLight") or descendant:IsA("SpotLight") then
			descendant.Enabled = true
		end
	end

	Debris:AddItem(vfxClone, INTERACTION_CONFIG.VFX_LIFETIME)
end

function MushroomInteractionService:GetStatus()
	return {
		initialized = self._isInitialized,
		hasRemoteEvent = self._remoteEvent ~= nil,
		hasHoverService = self._hoverService ~= nil,
		isMobile = self._isMobile,
		lastClickTime = self._lastClickTime,
		connectionCount = #self._connections
	}
end

function MushroomInteractionService:ForceRescanMushrooms()
	Logger:Info("[MushroomInteraction] ForceRescanMushrooms - delegating to hover service")
	if self._hoverService and self._hoverService.ForceRescan then
		return self._hoverService:ForceRescan()
	end
	Logger:Warn("[MushroomInteraction] No hover service available")
	return {before = 0, after = 0, found = 0}
end

function MushroomInteractionService:_debugHighlightStatus()
	Logger:Info("[MushroomInteraction] Debug status requested")
	if self._hoverService and self._hoverService.GetStatus then
		local status = self._hoverService:GetStatus()
		Logger:Info(string.format("[MushroomInteraction] Hover service: %d tracked, current: %s", 
			status.trackedMushrooms or 0, 
			tostring(status.currentHovered)
		))
		return status
	end
	Logger:Warn("[MushroomInteraction] No hover service available")
	return nil
end

function MushroomInteractionService:Cleanup()
	Logger:Info("[MushroomInteraction] Cleaning up...")

	for _, connection in pairs(self._connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	
	self._connections = {}
	self._remoteEvent = nil
	self._hoverService = nil
	self._isInitialized = false

	Logger:Info("[MushroomInteraction] ✓ Cleanup complete")
end

return MushroomInteractionService