local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

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
    PITCH_VARIATIONS = {0.85, 0.95, 1.0, 1.05, 1.15}
}

function MushroomInteractionService.new()
    local self = setmetatable({}, MushroomInteractionService)
    self._connections = {}
    self._mushroomRenderService = nil
    self._collectionService = nil
    self._lastClickTime = 0
    
    self:_initialize()
    return self
end

function MushroomInteractionService:_initialize()
    Logger:Info("MushroomInteractionService initializing...")
    
    self:_connectInputEvents()
    self:_startCollectionDetection()
    
    Logger:Info("✓ MushroomInteractionService initialized")
end

function MushroomInteractionService:_connectInputEvents()
    -- Connect mouse/touch input for mushroom clicking
    self._connections.InputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            self:_handleClick(input)
        end
    end)
end

function MushroomInteractionService:_handleClick(input)
    local currentTime = tick()
    if currentTime - self._lastClickTime < INTERACTION_CONFIG.CLICK_COOLDOWN then
        return
    end
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    -- Get click position
    local clickPosition
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        clickPosition = input.Position
    elseif input.UserInputType == Enum.UserInputType.Touch then
        clickPosition = input.Position
    else
        return
    end
    
    -- Cast ray from camera through click position
    local unitRay = camera:ScreenPointToRay(clickPosition.X, clickPosition.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {}
    
    local raycastResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)
    
    if raycastResult then
        local hitPart = raycastResult.Instance
        local mushroom = self:_findMushroomFromPart(hitPart)
        
        if mushroom then
            self:_clickMushroom(mushroom, raycastResult.Position)
        end
    end
end

function MushroomInteractionService:_findMushroomFromPart(part)
    -- Walk up the hierarchy to find a mushroom model
    local current = part
    while current and current ~= workspace do
        if current:IsA("Model") and current.Name:match("MushroomModel_") then
            -- Check if it's tagged as a client mushroom
            if CollectionService:HasTag(current, "ClientMushroom") then
                return current
            end
        end
        current = current.Parent
    end
    return nil
end

function MushroomInteractionService:_clickMushroom(mushroom, clickPosition)
    -- Validate distance
    if not self:_isMushroomInRange(mushroom) then
        return
    end
    
    self._lastClickTime = tick()
    
    -- Play click animation and sound
    self:_playClickEffects(mushroom)
    
    -- Send click to mushroom render service
    if self._mushroomRenderService and self._mushroomRenderService.HandleMushroomClick then
        self._mushroomRenderService:HandleMushroomClick(mushroom, clickPosition)
    end
    
    Logger:Debug("Clicked mushroom: " .. mushroom.Name)
end

function MushroomInteractionService:_isMushroomInRange(mushroom)
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    if not mushroom.PrimaryPart then
        return false
    end
    
    local distance = (player.Character.HumanoidRootPart.Position - mushroom.PrimaryPart.Position).Magnitude
    return distance <= INTERACTION_CONFIG.MAX_INTERACTION_DISTANCE
end

function MushroomInteractionService:_playClickEffects(mushroom)
    -- Scale animation
    if mushroom.PrimaryPart then
        local originalSize = mushroom.PrimaryPart.Size
        local scaledSize = originalSize * INTERACTION_CONFIG.CLICK_SCALE
        
        local scaleUp = TweenService:Create(
            mushroom.PrimaryPart,
            TweenInfo.new(INTERACTION_CONFIG.ANIMATION_SPEED, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Size = scaledSize}
        )
        
        local scaleDown = TweenService:Create(
            mushroom.PrimaryPart,
            TweenInfo.new(INTERACTION_CONFIG.ANIMATION_SPEED, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {Size = originalSize}
        )
        
        scaleUp:Play()
        scaleUp.Completed:Connect(function()
            scaleDown:Play()
        end)
    end
    
    -- Play sound
    self:_playClickSound(mushroom)
end

function MushroomInteractionService:_playClickSound(mushroom)
    local sound = Instance.new("Sound")
    sound.SoundId = INTERACTION_CONFIG.CLICK_SOUND_ID
    sound.Volume = 0.5
    sound.Pitch = INTERACTION_CONFIG.PITCH_VARIATIONS[math.random(#INTERACTION_CONFIG.PITCH_VARIATIONS)]
    sound.Parent = mushroom.PrimaryPart or mushroom
    
    sound:Play()
    
    -- Clean up sound after playing
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

function MushroomInteractionService:_startCollectionDetection()
    -- Monitor for spore collection
    self._connections.SporeCollection = CollectionService:GetInstanceAddedSignal("Spore"):Connect(function(spore)
        self:_setupSporeCollection(spore)
    end)
    
    self._connections.GemSporeCollection = CollectionService:GetInstanceAddedSignal("GemSpore"):Connect(function(spore)
        self:_setupSporeCollection(spore)
    end)
    
    self._connections.BigSporeCollection = CollectionService:GetInstanceAddedSignal("BigSpore"):Connect(function(spore)
        self:_setupSporeCollection(spore, 100) -- BigSpores are worth 100 regular spores
    end)
    
    -- Handle existing spores
    for _, spore in ipairs(CollectionService:GetTagged("Spore")) do
        self:_setupSporeCollection(spore)
    end
    
    for _, spore in ipairs(CollectionService:GetTagged("GemSpore")) do
        self:_setupSporeCollection(spore)
    end
    
    for _, spore in ipairs(CollectionService:GetTagged("BigSpore")) do
        self:_setupSporeCollection(spore, 100)
    end
end

function MushroomInteractionService:_setupSporeCollection(spore, value)
    if not spore or not spore.Parent then
        return
    end
    
    value = value or 1
    
    -- Check if spore is in collection range periodically
    local checkConnection
    checkConnection = task.spawn(function()
        while spore and spore.Parent do
            if self:_isSporeInCollectionRange(spore) then
                self:_collectSpore(spore, value)
                break
            end
            task.wait(0.1) -- Check every 0.1 seconds
        end
    end)
end

function MushroomInteractionService:_isSporeInCollectionRange(spore)
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    if not spore.PrimaryPart then
        return false
    end
    
    -- Get collection range from collection service
    local collectionRange = 10 -- Default range
    if self._collectionService and self._collectionService.GetCollectionRange then
        collectionRange = self._collectionService:GetCollectionRange()
    end
    
    local distance = (player.Character.HumanoidRootPart.Position - spore.PrimaryPart.Position).Magnitude
    return distance <= collectionRange
end

function MushroomInteractionService:_collectSpore(spore, value)
    -- Send collection event to mushroom render service
    if self._mushroomRenderService and self._mushroomRenderService.HandleSporeCollection then
        self._mushroomRenderService:HandleSporeCollection(spore, value)
    end
    
    -- Also send to collection service for visual effects
    if self._collectionService and self._collectionService.CollectSpore then
        self._collectionService:CollectSpore(spore, value)
    end
    
    Logger:Debug(string.format("Collected spore: %s (value: %d)", spore.Name, value))
end

function MushroomInteractionService:SetMushroomRenderService(mushroomRenderService)
    self._mushroomRenderService = mushroomRenderService
    Logger:Info("MushroomInteractionService linked with MushroomRenderService")
end

function MushroomInteractionService:SetCollectionService(collectionService)
    self._collectionService = collectionService
    Logger:Info("MushroomInteractionService linked with CollectionService")
end

function MushroomInteractionService:Cleanup()
    Logger:Info("MushroomInteractionService shutting down...")
    
    for name, connection in pairs(self._connections) do
        if connection then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    
    Logger:Info("✓ MushroomInteractionService shutdown complete")
end

return MushroomInteractionService