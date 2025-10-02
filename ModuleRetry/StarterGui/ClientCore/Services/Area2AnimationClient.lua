local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)
local HeartbeatManager = require(ReplicatedStorage.Shared.Modules.HeartbeatManager)

local Area2AnimationClient = {}
Area2AnimationClient.__index = Area2AnimationClient

local player = Players.LocalPlayer

function Area2AnimationClient.new()
    local self = setmetatable({}, Area2AnimationClient)
    self._connections = {}
    self:_initialize()
    return self
end

function Area2AnimationClient:_initialize()
    Logger:Info("Area2AnimationClient initializing...")
    
    self:_setupRemoteEvents()
    
    Logger:Info("✓ Area2AnimationClient initialized")
end

function Area2AnimationClient:_setupRemoteEvents()
    task.spawn(function()
        local shared = ReplicatedStorage:WaitForChild("Shared", 10)
        if shared then
            local remoteEvents = shared:WaitForChild("RemoteEvents", 10)
            if remoteEvents then
                local shopEvents = remoteEvents:WaitForChild("ShopEvents", 10)
                if shopEvents then
                    local area2UnlockAnimation = shopEvents:WaitForChild("Area2UnlockAnimation", 10)
                    if area2UnlockAnimation then
                        self._connections.Area2UnlockAnimation = area2UnlockAnimation.OnClientEvent:Connect(function()
                            self:_playArea2UnlockAnimation()
                        end)
                        Logger:Info("✓ Area2 unlock animation event connected")
                    else
                        Logger:Warn("Area2UnlockAnimation remote event not found within timeout")
                    end

                    -- Also setup Area3 unlock animation
                    local area3UnlockAnimation = shopEvents:WaitForChild("Area3UnlockAnimation", 10)
                    if area3UnlockAnimation then
                        self._connections.Area3UnlockAnimation = area3UnlockAnimation.OnClientEvent:Connect(function()
                            self:_playArea3UnlockAnimation()
                        end)
                        Logger:Info("✓ Area3 unlock animation event connected")
                    else
                        Logger:Warn("Area3UnlockAnimation remote event not found within timeout")
                    end
                end
            end
        end
    end)
end

function Area2AnimationClient:_playArea2UnlockAnimation()
    Logger:Info("Playing Area2 unlock animation")
    
    -- Get player's camera
    local camera = Workspace.CurrentCamera
    if not camera then
        Logger:Error("Camera not found for Area2 animation")
        return
    end
    
    -- Store original camera properties
    local originalCFrame = camera.CFrame
    local originalFieldOfView = camera.FieldOfView
    
    -- Create white flash effect
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "Area2UnlockEffect"
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = player:WaitForChild("PlayerGui")
    
    local whiteFrame = Instance.new("Frame")
    whiteFrame.Size = UDim2.new(1, 0, 1, 0)
    whiteFrame.Position = UDim2.new(0, 0, 0, 0)
    whiteFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    whiteFrame.BackgroundTransparency = 1
    whiteFrame.BorderSizePixel = 0
    whiteFrame.Parent = screenGui
    
    -- Screen shake effect
    self:_startScreenShake(camera, originalCFrame, 3.0) -- 3 second shake
    
    -- Zoom and flash sequence
    local sequence = {}
    
    -- Phase 1: Zoom in slightly (0.5 seconds)
    table.insert(sequence, function()
        local zoomTween = TweenService:Create(
            camera,
            TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {FieldOfView = originalFieldOfView * 0.8}
        )
        zoomTween:Play()
        return zoomTween
    end)
    
    -- Phase 2: White flash (0.3 seconds)
    table.insert(sequence, function()
        local flashTween = TweenService:Create(
            whiteFrame,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0}
        )
        flashTween:Play()
        
        -- Fade out after flash
        flashTween.Completed:Connect(function()
            local fadeOutTween = TweenService:Create(
                whiteFrame,
                TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                {BackgroundTransparency = 1}
            )
            fadeOutTween:Play()
        end)
        
        return flashTween
    end)
    
    -- Phase 3: Zoom back out (0.8 seconds)
    table.insert(sequence, function()
        local zoomBackTween = TweenService:Create(
            camera,
            TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
            {FieldOfView = originalFieldOfView}
        )
        zoomBackTween:Play()
        return zoomBackTween
    end)
    
    -- Execute sequence
    self:_executeAnimationSequence(sequence, function()
        -- Animation complete - cleanup
        task.wait(1) -- Wait a bit before cleanup
        if screenGui then
            screenGui:Destroy()
        end
        Logger:Info("Area2 unlock animation completed")
    end)
end

function Area2AnimationClient:_startScreenShake(camera, originalCFrame, duration)
    local startTime = tick()
    local heartbeatManager = HeartbeatManager.getInstance()
    
    -- Declare shakeConnection first
    local shakeConnection
    
    -- Use HeartbeatManager instead of RenderStepped for better performance
    shakeConnection = heartbeatManager:register(function()
        local elapsed = tick() - startTime
        if elapsed >= duration then
            -- Stop shaking and restore original position
            camera.CFrame = originalCFrame
            heartbeatManager:unregister(shakeConnection)
            return
        end
        
        -- Calculate shake intensity (starts strong, fades out)
        local intensity = math.max(0, 1 - (elapsed / duration))
        local shakeAmount = intensity * 2 -- Max shake amount
        
        -- Generate random shake offset
        local shakeX = (math.random() - 0.5) * shakeAmount
        local shakeY = (math.random() - 0.5) * shakeAmount
        local shakeZ = (math.random() - 0.5) * shakeAmount
        
        -- Apply shake to camera
        local shakeOffset = Vector3.new(shakeX, shakeY, shakeZ)
        camera.CFrame = originalCFrame + shakeOffset
    end, 0.016) -- ~60fps update rate
end

function Area2AnimationClient:_executeAnimationSequence(sequence, onComplete)
    local currentIndex = 1
    
    local function executeNext()
        if currentIndex > #sequence then
            if onComplete then
                onComplete()
            end
            return
        end
        
        local animationFunction = sequence[currentIndex]
        local tween = animationFunction()
        
        if tween and tween.Completed then
            tween.Completed:Connect(function()
                currentIndex = currentIndex + 1
                executeNext()
            end)
        else
            -- If no tween returned, continue immediately
            currentIndex = currentIndex + 1
            executeNext()
        end
    end
    
    executeNext()
end

function Area2AnimationClient:_playArea3UnlockAnimation()
    Logger:Info("Playing Area3 unlock animation")
    
    -- Get player's camera
    local camera = Workspace.CurrentCamera
    if not camera then
        Logger:Error("Camera not found for Area3 animation")
        return
    end
    
    -- Store original camera properties
    local originalCFrame = camera.CFrame
    local originalFieldOfView = camera.FieldOfView
    
    -- Create golden flash effect (different from Area2's white)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "Area3UnlockEffect"
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = player:WaitForChild("PlayerGui")
    
    local goldenFrame = Instance.new("Frame")
    goldenFrame.Size = UDim2.new(1, 0, 1, 0)
    goldenFrame.Position = UDim2.new(0, 0, 0, 0)
    goldenFrame.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Golden color
    goldenFrame.BackgroundTransparency = 1
    goldenFrame.BorderSizePixel = 0
    goldenFrame.Parent = screenGui
    
    -- Screen shake effect (stronger for Area3)
    self:_startScreenShake(camera, originalCFrame, 3.5) -- 3.5 second shake
    
    -- Zoom and flash sequence
    local sequence = {}
    
    -- Phase 1: Zoom in more dramatically (0.6 seconds)
    table.insert(sequence, function()
        local zoomTween = TweenService:Create(
            camera,
            TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {FieldOfView = originalFieldOfView * 0.7} -- More dramatic zoom
        )
        zoomTween:Play()
        return zoomTween
    end)
    
    -- Phase 2: Golden flash (0.4 seconds)
    table.insert(sequence, function()
        local flashTween = TweenService:Create(
            goldenFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0}
        )
        flashTween:Play()
        
        -- Fade out after flash
        flashTween.Completed:Connect(function()
            local fadeOutTween = TweenService:Create(
                goldenFrame,
                TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                {BackgroundTransparency = 1}
            )
            fadeOutTween:Play()
        end)
        
        return flashTween
    end)
    
    -- Phase 3: Zoom back out (1.0 seconds, slower)
    table.insert(sequence, function()
        local zoomBackTween = TweenService:Create(
            camera,
            TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
            {FieldOfView = originalFieldOfView}
        )
        zoomBackTween:Play()
        return zoomBackTween
    end)
    
    -- Execute sequence
    self:_executeAnimationSequence(sequence, function()
        -- Animation complete - cleanup
        task.wait(1.2) -- Wait a bit longer for Area3
        if screenGui then
            screenGui:Destroy()
        end
        Logger:Info("Area3 unlock animation completed")
    end)
end

function Area2AnimationClient:Cleanup()
    Logger:Info("Area2AnimationClient shutting down...")
    
    for _, connection in pairs(self._connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    
    Logger:Info("✓ Area2AnimationClient shutdown complete")
end

return Area2AnimationClient