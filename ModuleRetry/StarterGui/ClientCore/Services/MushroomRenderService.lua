local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)
local HeartbeatManager = require(ReplicatedStorage.Shared.Modules.HeartbeatManager)

local MushroomRenderService = {}
MushroomRenderService.__index = MushroomRenderService

local player = Players.LocalPlayer

-- Configuration
local CONFIG = {
    MIN_MOVE_DISTANCE = 15,
    MAX_MOVE_DISTANCE = 40,
    MOVE_SPEED = 4,
    MIN_PAUSE_TIME = 2.0,
    MAX_PAUSE_TIME = 5.0,
    SPORE_LAUNCH_FORCE = 15,
    SPORE_LIFETIME = 600, -- 10 minutes
    COMBINATION_THRESHOLD = 100,
    SPORE_FLY_SPEED = 25,
    BIGSPORE_GROWTH_TIME = 1.0,
    OPTIMIZED_MOVEMENT = true,
    SPORE_PHYSICS_DELAY = 0.5
}

function MushroomRenderService.new()
    local self = setmetatable({}, MushroomRenderService)
    self._mushroomInstances = {} -- Visual mushroom models
    self._sporeInstances = {} -- Visual spore models  
    self._mushroomData = {} -- Server data
    self._connections = {}
    self._remoteEvents = {}
    self._mushroomAI = {} -- AI state for each mushroom
    self._sporeCounter = 0
    self._plot = nil
    
    self:_initialize()
    return self
end

function MushroomRenderService:_initialize()
    Logger:Info("MushroomRenderService initializing...")
    
    self:_setupRemoteEvents()
    self:_startAISystem()
    self:_startSporeCleanup()
    
    -- Wait for player plot to be assigned
    self:_waitForPlot()
    
    Logger:Info("✓ MushroomRenderService initialized")
end

function MushroomRenderService:_setupRemoteEvents()
    local shared = ReplicatedStorage:WaitForChild("Shared", 10)
    if not shared then
        Logger:Error("Shared folder not found in ReplicatedStorage")
        return
    end
    
    local remoteEvents = shared:WaitForChild("RemoteEvents", 5)
    if not remoteEvents then
        Logger:Error("RemoteEvents folder not found")
        return
    end
    
    local mushroomEvents = remoteEvents:WaitForChild("MushroomEvents", 5)
    if not mushroomEvents then
        Logger:Error("MushroomEvents folder not found")
        return
    end
    
    -- Get remote events
    self._remoteEvents = {
        UpdateMushroomData = mushroomEvents:WaitForChild("UpdateMushroomData", 5),
        MushroomClicked = mushroomEvents:WaitForChild("MushroomClicked", 5),
        SporeSpawned = mushroomEvents:WaitForChild("SporeSpawned", 5),
        SporeCollected = mushroomEvents:WaitForChild("SporeCollected", 5)
    }
    
    -- Connect event handlers
    if self._remoteEvents.UpdateMushroomData then
        self._remoteEvents.UpdateMushroomData.OnClientEvent:Connect(function(mushroomData)
            self:_updateMushroomData(mushroomData)
        end)
    end
    
    if self._remoteEvents.SporeSpawned then
        self._remoteEvents.SporeSpawned.OnClientEvent:Connect(function(sporeInfo)
            self:_spawnSporeVisual(sporeInfo)
        end)
    end
    
    Logger:Info("✓ MushroomRenderService remote events connected")
end

function MushroomRenderService:_waitForPlot()
    local function checkForPlot()
        -- Find player's plot in workspace
        for i = 1, 6 do
            local plot = Workspace:FindFirstChild("Plot_" .. i)
            if plot and plot:GetAttribute("OwnerUserId") == player.UserId then
                self._plot = plot
                Logger:Info("Found player plot: " .. plot.Name)
                return true
            end
        end
        return false
    end
    
    if not checkForPlot() then
        -- Wait for plot to be created
        local connection
        connection = Workspace.ChildAdded:Connect(function(child)
            if child.Name:match("Plot_") and child:GetAttribute("OwnerUserId") == player.UserId then
                self._plot = child
                Logger:Info("Plot assigned: " .. child.Name)
                connection:Disconnect()
            end
        end)
        
        -- Also check for attribute changes on existing plots
        for i = 1, 6 do
            local plot = Workspace:FindFirstChild("Plot_" .. i)
            if plot then
                plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
                    if plot:GetAttribute("OwnerUserId") == player.UserId then
                        self._plot = plot
                        Logger:Info("Plot ownership updated: " .. plot.Name)
                    end
                end)
            end
        end
    end
end

function MushroomRenderService:_updateMushroomData(mushroomData)
    Logger:Info("🔥 CLIENT: Received mushroom data from server")
    
    self._mushroomData = mushroomData
    
    -- If plot isn't ready yet, retry later
    if not self._plot then
        Logger:Info("🔥 CLIENT: Plot not ready yet, will retry mushroom creation in 2 seconds")
        task.spawn(function()
            task.wait(2)
            if self._mushroomData then
                Logger:Info("🔥 CLIENT: Retrying mushroom creation after plot delay")
                self:_updateMushroomData(self._mushroomData)
            end
        end)
        return
    end
    
    -- Update visual mushrooms
    for area, mushrooms in pairs(mushroomData) do
        Logger:Info(string.format("🔥 CLIENT: Processing area %s with %d mushrooms", area, #mushrooms))
        for mushroomId, data in pairs(mushrooms) do
            Logger:Info(string.format("🔥 CLIENT: Creating/updating mushroom %s in %s (type: %s)", mushroomId, area, data.type))
            self:_createOrUpdateMushroom(mushroomId, area, data)
        end
    end
    
    Logger:Info("🔥 CLIENT: Finished updating mushroom data from server")
end

function MushroomRenderService:_createOrUpdateMushroom(mushroomId, area, data)
    Logger:Info(string.format("🔥 CLIENT: _createOrUpdateMushroom called for %s in %s", mushroomId, area))
    
    if not self._plot then
        Logger:Warn("🔥 CLIENT: No plot available, cannot create mushroom")
        return
    end
    
    Logger:Info(string.format("🔥 CLIENT: Plot available: %s", self._plot.Name))
    
    local existingMushroom = self._mushroomInstances[mushroomId]
    
    if existingMushroom then
        -- Update existing mushroom if type changed
        if existingMushroom:GetAttribute("ModelType") ~= data.type then
            self:_destroyMushroom(mushroomId)
            existingMushroom = nil
        end
    end
    
    if not existingMushroom then
        -- Create new mushroom
        local mushroomTemplate = self:_getMushroomTemplate(data.type)
        if not mushroomTemplate then
            Logger:Error("Mushroom template not found: " .. data.type)
            return
        end
        
        local mushroom = mushroomTemplate:Clone()
        mushroom.Name = "MushroomModel_" .. mushroomId
        mushroom:SetAttribute("ModelType", data.type)
        mushroom:SetAttribute("MushroomId", mushroomId)
        mushroom:SetAttribute("Area", area)
        
        -- Position the mushroom
        local areaFolder = self._plot:FindFirstChild(area)
        if areaFolder then
            mushroom.Parent = areaFolder
            if mushroom.PrimaryPart then
                mushroom:SetPrimaryPartCFrame(CFrame.new(data.position[1], data.position[2], data.position[3]))
            end
        else
            Logger:Warn("Area folder not found: " .. area)
            mushroom:Destroy()
            return
        end
        
        -- Add to collection service for interaction
        CollectionService:AddTag(mushroom, "ClientMushroom")
        
        self._mushroomInstances[mushroomId] = mushroom
        
        -- Initialize AI for this mushroom
        self:_initializeMushroomAI(mushroomId, mushroom, areaFolder)
        
        Logger:Debug(string.format("Created mushroom %s (%s) in %s", mushroomId, data.type, area))
    end
end

function MushroomRenderService:_getMushroomTemplate(modelType)
    local modelsFolder = ReplicatedStorage:FindFirstChild("MODELS")
    if not modelsFolder then
        Logger:Error("MODELS folder not found in ReplicatedStorage")
        return nil
    end
    
    return modelsFolder:FindFirstChild(modelType)
end

function MushroomRenderService:_initializeMushroomAI(mushroomId, mushroom, areaFolder)
    self._mushroomAI[mushroomId] = {
        mushroom = mushroom,
        area = areaFolder,
        isMoving = false,
        nextMoveTime = os.time() + math.random(CONFIG.MIN_PAUSE_TIME, CONFIG.MAX_PAUSE_TIME),
        currentTween = nil
    }
end

function MushroomRenderService:_startAISystem()
    self._connections.AISystem = HeartbeatManager.getInstance():register(function()
        local currentTime = os.time()
        
        for mushroomId, aiData in pairs(self._mushroomAI) do
            if aiData.mushroom and aiData.mushroom.Parent then
                self:_updateMushroomAI(mushroomId, aiData, currentTime)
            else
                -- Clean up if mushroom was destroyed
                self._mushroomAI[mushroomId] = nil
            end
        end
    end)
end

function MushroomRenderService:_updateMushroomAI(mushroomId, aiData, currentTime)
    if aiData.isMoving then
        return -- Already moving
    end
    
    if currentTime < aiData.nextMoveTime then
        return -- Still waiting
    end
    
    -- Time to move
    local mushroom = aiData.mushroom
    local area = aiData.area
    
    if not mushroom.PrimaryPart then
        return
    end
    
    local currentPosition = mushroom.PrimaryPart.Position
    local targetPosition = self:_getRandomPosition(currentPosition, area)
    
    if not targetPosition then
        -- Try again later
        aiData.nextMoveTime = currentTime + math.random(CONFIG.MIN_PAUSE_TIME, CONFIG.MAX_PAUSE_TIME)
        return
    end
    
    -- Start movement
    aiData.isMoving = true
    
    local distance = (targetPosition - currentPosition).Magnitude
    local duration = distance / CONFIG.MOVE_SPEED
    
    local tweenInfo = TweenInfo.new(
        duration,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.InOut
    )
    
    if CONFIG.OPTIMIZED_MOVEMENT then
        -- Only move PrimaryPart for better performance
        aiData.currentTween = TweenService:Create(
            mushroom.PrimaryPart,
            tweenInfo,
            {Position = targetPosition}
        )
    else
        -- Move entire model
        local targetCFrame = CFrame.new(targetPosition)
        aiData.currentTween = TweenService:Create(
            mushroom.PrimaryPart,
            tweenInfo,
            {CFrame = targetCFrame}
        )
    end
    
    aiData.currentTween:Play()
    
    aiData.currentTween.Completed:Connect(function()
        aiData.isMoving = false
        aiData.nextMoveTime = currentTime + math.random(CONFIG.MIN_PAUSE_TIME, CONFIG.MAX_PAUSE_TIME)
        aiData.currentTween = nil
    end)
end

function MushroomRenderService:_getRandomPosition(currentPosition, area)
    if not area then return nil end
    
    -- Get area boundaries
    local bounds = area:GetBoundingBox()
    local size = bounds.Size
    local center = bounds.Position
    
    -- Generate random position within bounds
    local attempts = 10
    for i = 1, attempts do
        local randomOffset = Vector3.new(
            math.random(-size.X/2, size.X/2),
            0,
            math.random(-size.Z/2, size.Z/2)
        )
        
        local targetPosition = center + randomOffset
        
        -- Check if movement distance is reasonable
        local distance = (targetPosition - currentPosition).Magnitude
        if distance >= CONFIG.MIN_MOVE_DISTANCE and distance <= CONFIG.MAX_MOVE_DISTANCE then
            return Vector3.new(targetPosition.X, currentPosition.Y, targetPosition.Z)
        end
    end
    
    return nil
end

function MushroomRenderService:_spawnSporeVisual(sporeInfo)
    if not self._plot then
        return
    end
    
    local mushroomId = sporeInfo.mushroomId
    local mushroom = self._mushroomInstances[mushroomId]
    
    if not mushroom or not mushroom.PrimaryPart then
        Logger:Warn("Cannot spawn spore - mushroom not found: " .. mushroomId)
        return
    end
    
    -- Create spore visual
    local sporeModel = self:_createSporeModel(sporeInfo.sporeType)
    if not sporeModel then
        return
    end
    
    self._sporeCounter = self._sporeCounter + 1
    local sporeId = string.format("spore_%s_%d", sporeInfo.sporeType, self._sporeCounter)
    sporeModel.Name = sporeId
    
    -- Position at mushroom
    local spawnPosition = mushroom.PrimaryPart.Position + Vector3.new(0, 2, 0)
    sporeModel:SetPrimaryPartCFrame(CFrame.new(spawnPosition))
    
    -- Parent to appropriate area
    local areaFolder = self._plot:FindFirstChild(sporeInfo.area)
    if areaFolder then
        sporeModel.Parent = areaFolder
    else
        sporeModel.Parent = self._plot
    end
    
    -- Launch the spore
    self:_launchSpore(sporeModel, spawnPosition)
    
    -- Tag for collection
    CollectionService:AddTag(sporeModel, sporeInfo.sporeType == "gem" and "GemSpore" or "Spore")
    
    -- Store reference
    self._sporeInstances[sporeId] = {
        model = sporeModel,
        spawnTime = os.time(),
        sporeType = sporeInfo.sporeType,
        area = sporeInfo.area
    }
    
    Logger:Debug(string.format("Spawned %s visual: %s", sporeInfo.sporeType, sporeId))
end

function MushroomRenderService:_createSporeModel(sporeType)
    -- Create a simple spore model
    local spore = Instance.new("Model")
    
    local part = Instance.new("Part")
    part.Name = "SporePart"
    part.Size = Vector3.new(1, 1, 1)
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.CanCollide = false
    part.Anchored = false
    
    if sporeType == "gem" then
        part.Color = Color3.fromRGB(0, 255, 255) -- Cyan for gems
        part.Name = "GemSporePart"
    else
        part.Color = Color3.fromRGB(255, 255, 0) -- Yellow for spores
    end
    
    part.Parent = spore
    spore.PrimaryPart = part
    
    -- Add body velocity for physics
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
    bodyVelocity.Velocity = Vector3.new(0, 0, 0)
    bodyVelocity.Parent = part
    
    return spore
end

function MushroomRenderService:_launchSpore(sporeModel, spawnPosition)
    if not sporeModel.PrimaryPart then
        return
    end
    
    -- Random launch direction
    local launchDirection = Vector3.new(
        math.random(-1, 1),
        math.random(0.5, 1), -- Always launch upward
        math.random(-1, 1)
    ).Unit
    
    local bodyVelocity = sporeModel.PrimaryPart:FindFirstChild("BodyVelocity")
    if bodyVelocity then
        bodyVelocity.Velocity = launchDirection * CONFIG.SPORE_LAUNCH_FORCE
        
        -- Stop physics after a short time
        task.spawn(function()
            task.wait(CONFIG.SPORE_PHYSICS_DELAY)
            if bodyVelocity and bodyVelocity.Parent then
                bodyVelocity.Velocity = Vector3.new(0, 0, 0)
            end
        end)
    end
end

function MushroomRenderService:_startSporeCleanup()
    self._connections.SporeCleanup = HeartbeatManager.getInstance():register(function()
        local currentTime = os.time()
        
        for sporeId, sporeData in pairs(self._sporeInstances) do
            if currentTime - sporeData.spawnTime > CONFIG.SPORE_LIFETIME then
                self:_destroySpore(sporeId)
            elseif not sporeData.model or not sporeData.model.Parent then
                -- Clean up reference if model was destroyed
                self._sporeInstances[sporeId] = nil
            end
        end
    end)
end

function MushroomRenderService:_destroySpore(sporeId)
    local sporeData = self._sporeInstances[sporeId]
    if sporeData and sporeData.model then
        sporeData.model:Destroy()
    end
    self._sporeInstances[sporeId] = nil
end

function MushroomRenderService:_destroyMushroom(mushroomId)
    local mushroom = self._mushroomInstances[mushroomId]
    if mushroom then
        mushroom:Destroy()
        self._mushroomInstances[mushroomId] = nil
    end
    
    local aiData = self._mushroomAI[mushroomId]
    if aiData and aiData.currentTween then
        aiData.currentTween:Cancel()
    end
    self._mushroomAI[mushroomId] = nil
end

function MushroomRenderService:HandleMushroomClick(mushroom, clickPosition)
    local mushroomId = mushroom:GetAttribute("MushroomId")
    if not mushroomId then
        Logger:Warn("Clicked mushroom has no MushroomId attribute")
        return
    end
    
    -- Send click event to server for validation
    if self._remoteEvents.MushroomClicked then
        self._remoteEvents.MushroomClicked:FireServer(mushroomId, clickPosition)
        Logger:Debug("Sent mushroom click to server: " .. mushroomId)
    end
end

function MushroomRenderService:HandleSporeCollection(sporeModel, collectedAmount)
    -- Find spore data
    local sporeData = nil
    local sporeId = nil
    
    for id, data in pairs(self._sporeInstances) do
        if data.model == sporeModel then
            sporeData = data
            sporeId = id
            break
        end
    end
    
    if not sporeData then
        Logger:Warn("Collected spore not found in instances")
        return
    end
    
    -- Send collection event to server
    if self._remoteEvents.SporeCollected then
        self._remoteEvents.SporeCollected:FireServer(sporeData.sporeType, collectedAmount, sporeData.area)
        Logger:Debug(string.format("Sent spore collection to server: %s x%d", sporeData.sporeType, collectedAmount))
    end
    
    -- Destroy the visual
    self:_destroySpore(sporeId)
end

function MushroomRenderService:CheckSporesCombination()
    -- Count regular spores in each area
    local sporesByArea = {}
    
    for sporeId, sporeData in pairs(self._sporeInstances) do
        if sporeData.sporeType == "spore" then
            local area = sporeData.area
            if not sporesByArea[area] then
                sporesByArea[area] = {}
            end
            table.insert(sporesByArea[area], sporeId)
        end
    end
    
    -- Check each area for combination threshold
    for area, sporeIds in pairs(sporesByArea) do
        if #sporeIds >= CONFIG.COMBINATION_THRESHOLD then
            self:_performSporeCombination(area, sporeIds)
        end
    end
end

function MushroomRenderService:_performSporeCombination(area, sporeIds)
    -- Calculate combination center
    local combinationPoint = Vector3.new(0, 0, 0)
    local validSpores = {}
    
    for i = 1, math.min(CONFIG.COMBINATION_THRESHOLD, #sporeIds) do
        local sporeId = sporeIds[i]
        local sporeData = self._sporeInstances[sporeId]
        
        if sporeData and sporeData.model and sporeData.model.PrimaryPart then
            combinationPoint = combinationPoint + sporeData.model.PrimaryPart.Position
            table.insert(validSpores, sporeId)
        end
    end
    
    if #validSpores == 0 then
        return
    end
    
    combinationPoint = combinationPoint / #validSpores
    
    -- Animate spores flying to center or destroy instantly
    if CONFIG.INSTANT_COMBINATION then
        -- Destroy spores instantly
        for _, sporeId in ipairs(validSpores) do
            self:_destroySpore(sporeId)
        end
        self:_spawnBigSpore(combinationPoint, area)
    else
        -- Animate spores flying to center
        self:_animateSporesCombination(validSpores, combinationPoint, area)
    end
    
    Logger:Info(string.format("Combined %d spores into BigSpore in %s", #validSpores, area))
end

function MushroomRenderService:_animateSporesCombination(sporeIds, targetPosition, area)
    local completedAnimations = 0
    local totalAnimations = math.min(5, #sporeIds) -- Only animate a few for performance
    
    for i = 1, totalAnimations do
        local sporeId = sporeIds[i]
        local sporeData = self._sporeInstances[sporeId]
        
        if sporeData and sporeData.model and sporeData.model.PrimaryPart then
            local spore = sporeData.model
            local distance = (targetPosition - spore.PrimaryPart.Position).Magnitude
            local duration = distance / CONFIG.SPORE_FLY_SPEED
            
            local tween = TweenService:Create(
                spore.PrimaryPart,
                TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                {Position = targetPosition}
            )
            
            tween:Play()
            tween.Completed:Connect(function()
                self:_destroySpore(sporeId)
                completedAnimations = completedAnimations + 1
                
                if completedAnimations >= totalAnimations then
                    self:_spawnBigSpore(targetPosition, area)
                end
            end)
        end
    end
    
    -- Destroy remaining spores instantly
    for i = totalAnimations + 1, #sporeIds do
        self:_destroySpore(sporeIds[i])
    end
end

function MushroomRenderService:_spawnBigSpore(position, area)
    local bigSpore = self:_createBigSporeModel()
    if not bigSpore then
        return
    end
    
    self._sporeCounter = self._sporeCounter + 1
    local sporeId = "bigspore_" .. self._sporeCounter
    bigSpore.Name = sporeId
    
    -- Position the BigSpore
    bigSpore:SetPrimaryPartCFrame(CFrame.new(position))
    
    -- Parent to area
    local areaFolder = self._plot and self._plot:FindFirstChild(area)
    if areaFolder then
        bigSpore.Parent = areaFolder
    else
        bigSpore.Parent = self._plot
    end
    
    -- Add growth animation
    self:_animateBigSporeGrowth(bigSpore)
    
    -- Tag for collection
    CollectionService:AddTag(bigSpore, "BigSpore")
    
    -- Store reference
    self._sporeInstances[sporeId] = {
        model = bigSpore,
        spawnTime = os.time(),
        sporeType = "bigspore",
        area = area
    }
    
    Logger:Debug("Spawned BigSpore: " .. sporeId)
end

function MushroomRenderService:_createBigSporeModel()
    local bigSpore = Instance.new("Model")
    
    local part = Instance.new("Part")
    part.Name = "BigSporePart"
    part.Size = Vector3.new(3, 3, 3) -- Larger than regular spores
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 215, 0) -- Gold color
    part.CanCollide = false
    part.Anchored = true
    
    part.Parent = bigSpore
    bigSpore.PrimaryPart = part
    
    return bigSpore
end

function MushroomRenderService:_animateBigSporeGrowth(bigSpore)
    if not bigSpore.PrimaryPart then
        return
    end
    
    -- Start small and grow
    bigSpore.PrimaryPart.Size = Vector3.new(0.1, 0.1, 0.1)
    
    local tween = TweenService:Create(
        bigSpore.PrimaryPart,
        TweenInfo.new(CONFIG.BIGSPORE_GROWTH_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Size = Vector3.new(3, 3, 3)}
    )
    
    tween:Play()
end

function MushroomRenderService:Cleanup()
    Logger:Info("MushroomRenderService shutting down...")
    
    -- Cleanup connections
    for name, connection in pairs(self._connections) do
        if connection then
            HeartbeatManager.getInstance():unregister(connection)
        end
    end
    
    -- Cleanup mushrooms
    for mushroomId, mushroom in pairs(self._mushroomInstances) do
        if mushroom then
            mushroom:Destroy()
        end
    end
    
    -- Cleanup spores
    for sporeId, sporeData in pairs(self._sporeInstances) do
        if sporeData.model then
            sporeData.model:Destroy()
        end
    end
    
    -- Cancel any running tweens
    for mushroomId, aiData in pairs(self._mushroomAI) do
        if aiData.currentTween then
            aiData.currentTween:Cancel()
        end
    end
    
    self._connections = {}
    self._mushroomInstances = {}
    self._sporeInstances = {}
    self._mushroomAI = {}
    
    Logger:Info("✓ MushroomRenderService shutdown complete")
end

return MushroomRenderService