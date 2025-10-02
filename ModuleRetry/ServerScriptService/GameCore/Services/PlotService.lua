local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(script.Parent.Parent.Utilities.Logger)
local Validator = require(script.Parent.Parent.Utilities.Validator)

local PlotService = {}
PlotService.__index = PlotService

local MAX_PLOTS = 6
local plotAssignments = {}
local assignedPlots = {}
local spawnPoints = {}

local plotAssignedEvent = nil

function PlotService.new()
    local self = setmetatable({}, PlotService)
    self._connections = {}
    self._dataService = nil
    self:_initialize()
    return self
end

function PlotService:_initialize()
    self:_setupRemoteEvents()
    self:_cacheSpawnPoints()
    
    self._connections.PlayerAdded = Players.PlayerAdded:Connect(function(player)
        self:_onPlayerJoined(player)
    end)
    
    -- Note: PlayerRemoving is now handled by DataService to ensure proper save order
    
    Logger:Info("PlotService initialized successfully")
end

function PlotService:_setupRemoteEvents()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared then
        local remoteEvents = shared:FindFirstChild("RemoteEvents")
        if remoteEvents then
            local plotEvents = remoteEvents:FindFirstChild("PlotEvents")
            if plotEvents then
                plotAssignedEvent = plotEvents:FindFirstChild("PlotAssigned")
            end
        end
    end
    
    if not plotAssignedEvent then
        Logger:Warn("PlotAssigned RemoteEvent not found - plot assignments will not be sent to client")
    end
end

function PlotService:_cacheSpawnPoints()
    spawnPoints = {}
    
    for i = 1, MAX_PLOTS do
        local spawnPointName = "SpawnPoint" .. i
        local spawnPoint = Workspace:FindFirstChild(spawnPointName)
        
        if spawnPoint then
            spawnPoints[i] = spawnPoint
            Logger:Debug(string.format("Cached spawn point %d at position %s", i, tostring(spawnPoint.Position)))
        else
            Logger:Error(string.format("SpawnPoint%d not found in Workspace", i))
        end
    end
    
    Logger:Info(string.format("Cached %d spawn points", #spawnPoints))
end

function PlotService:_getNextAvailablePlot()
    for plotId = 1, MAX_PLOTS do
        if not assignedPlots[plotId] then
            return plotId
        end
    end
    return nil
end

function PlotService:_createPlotForPlayer(player, plotId)
    local plotTemplate = Workspace:FindFirstChild("PlayerPlots"):FindFirstChild("PlotTemplate")
    
    if not plotTemplate then
        Logger:Error("PlotTemplate not found in Workspace.PlayerPlots")
        return false
    end
    
    local spawnPoint = spawnPoints[plotId]
    if not spawnPoint then
        Logger:Error(string.format("SpawnPoint%d not available", plotId))
        return false
    end
    
    local newPlot = plotTemplate:Clone()
    newPlot.Name = "Plot_" .. player.Name
    newPlot.Parent = Workspace:FindFirstChild("PlayerPlots")
    
    -- Ensure PrimaryPart is properly set after cloning
    if not newPlot.PrimaryPart then
        -- Try to find a suitable part to set as PrimaryPart
        local mainPart = newPlot:FindFirstChild("MainPart") or newPlot:FindFirstChildOfClass("Part")
        if mainPart then
            newPlot.PrimaryPart = mainPart
        else
            Logger:Error(string.format("No suitable PrimaryPart found for plot %s", newPlot.Name))
            return false
        end
    end
    
    newPlot:SetPrimaryPartCFrame(CFrame.new(spawnPoint.Position))
    
    self:_updatePlayerSign(newPlot, player)
    
    Logger:Info(string.format("Created plot for player %s at SpawnPoint%d", player.Name, plotId))
    return true
end

function PlotService:_onPlayerJoined(player)
    local availablePlot = self:_getNextAvailablePlot()
    
    if not availablePlot then
        Logger:Warn(string.format("No available plots for player %s - server full", player.Name))
        player:Kick("Server is full! Please try again later.")
        return
    end
    
    local success = self:_createPlotForPlayer(player, availablePlot)
    if not success then
        Logger:Error(string.format("Failed to create plot for player %s", player.Name))
        player:Kick("Failed to create your plot. Please rejoin.")
        return
    end
    
    plotAssignments[player.UserId] = availablePlot
    assignedPlots[availablePlot] = player.UserId
    
    -- Store the plot assignment to set in data when it's loaded
    self._pendingPlotAssignments = self._pendingPlotAssignments or {}
    self._pendingPlotAssignments[player.UserId] = availablePlot
    
    if plotAssignedEvent then
        plotAssignedEvent:FireClient(player, availablePlot)
    end
    
    Logger:Info(string.format("Assigned plot %d to player %s", availablePlot, player.Name))
end

-- Called by DataService after saving player data to cleanup the plot
function PlotService:CleanupPlayerPlot(player)
    Logger:Debug(string.format("CleanupPlayerPlot called for %s", player.Name))
    local assignedPlot = plotAssignments[player.UserId]
    
    -- Cleanup storage tracking for the player
    if self._storageService then
        self._storageService:CleanupPlayer(player)
    end
    
    if assignedPlot then
        self:_cleanupPlayerPlot(player, assignedPlot)
        
        plotAssignments[player.UserId] = nil
        assignedPlots[assignedPlot] = nil
        
        Logger:Info(string.format("Cleaned up plot %d for leaving player %s", assignedPlot, player.Name))
    else
        Logger:Warn(string.format("Plot not found for player %s", player.Name))
    end
end

function PlotService:_cleanupPlayerPlot(player, plotId)
    local plotName = "Plot_" .. player.Name
    local playerPlot = Workspace:FindFirstChild("PlayerPlots"):FindFirstChild(plotName)
    
    if playerPlot then
        playerPlot:Destroy()
        Logger:Debug(string.format("Destroyed plot %s", plotName))
    end
end

function PlotService:GetPlayerPlot(player)
    return plotAssignments[player.UserId]
end

function PlotService:GetPlotSpawnPoint(plotId)
    if not Validator:IsValidPlotId(plotId) then
        return nil
    end
    
    return spawnPoints[plotId]
end

function PlotService:GetPlayerSpawnPoint(player)
    local plotId = self:GetPlayerPlot(player)
    if not plotId then
        return nil
    end
    
    return self:GetPlotSpawnPoint(plotId)
end

function PlotService:TeleportPlayerToPlot(player, plotId)
    plotId = plotId or self:GetPlayerPlot(player)
    
    if not plotId then
        Logger:Warn(string.format("No plot assigned to player %s for teleportation", player.Name))
        return false
    end
    
    local spawnPoint = self:GetPlotSpawnPoint(plotId)
    if not spawnPoint then
        Logger:Error(string.format("SpawnPoint%d not found for player %s", plotId, player.Name))
        return false
    end
    
    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        player.Character.HumanoidRootPart.CFrame = CFrame.new(spawnPoint.Position + Vector3.new(0, 5, 0))
        Logger:Debug(string.format("Teleported player %s to plot %d", player.Name, plotId))
        return true
    else
        Logger:Warn(string.format("Cannot teleport player %s - character not found", player.Name))
        return false
    end
end

function PlotService:GetActivePlots()
    local activePlots = {}
    for userId, plotId in pairs(plotAssignments) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            activePlots[plotId] = {
                player = player,
                userId = userId,
                plotId = plotId
            }
        end
    end
    return activePlots
end

function PlotService:GetAvailablePlots()
    local available = {}
    for i = 1, MAX_PLOTS do
        if not assignedPlots[i] then
            table.insert(available, i)
        end
    end
    return available
end

function PlotService:ForceReassignPlot(player, newPlotId)
    if not Validator:IsValidPlotId(newPlotId) then
        Logger:Warn(string.format("Invalid plot ID for reassignment: %s", tostring(newPlotId)))
        return false
    end
    
    if assignedPlots[newPlotId] then
        Logger:Warn(string.format("Plot %d is already assigned", newPlotId))
        return false
    end
    
    local oldPlotId = plotAssignments[player.UserId]
    if oldPlotId then
        self:_cleanupPlayerPlot(player, oldPlotId)
        assignedPlots[oldPlotId] = nil
    end
    
    local success = self:_createPlotForPlayer(player, newPlotId)
    if not success then
        return false
    end
    
    plotAssignments[player.UserId] = newPlotId
    assignedPlots[newPlotId] = player.UserId
    
    if plotAssignedEvent then
        plotAssignedEvent:FireClient(player, newPlotId)
    end
    
    Logger:Info(string.format("Reassigned player %s from plot %s to plot %d", 
        player.Name, tostring(oldPlotId), newPlotId))
    
    return true
end

function PlotService:SetDataService(dataService)
    self._dataService = dataService
    
    -- Listen for when player data is loaded
    if dataService and dataService.PlayerDataLoaded then
        self._connections.PlayerDataLoaded = dataService.PlayerDataLoaded:Connect(function(player, playerData)
            self:_onPlayerDataLoaded(player, playerData)
        end)
    end
    
    Logger:Debug("PlotService linked with DataService")
end

function PlotService:SetStorageService(storageService)
    self._storageService = storageService
    Logger:Debug("PlotService linked with StorageService")
end

function PlotService:_onPlayerDataLoaded(player, playerData)
    local userId = player.UserId
    self._pendingPlotAssignments = self._pendingPlotAssignments or {}
    
    local pendingPlot = self._pendingPlotAssignments[userId]
    if pendingPlot and self._dataService then
        self._dataService:SetAssignedPlot(player, pendingPlot)
        self._pendingPlotAssignments[userId] = nil
        Logger:Debug(string.format("Set pending plot assignment %d for player %s", pendingPlot, player.Name))
    end
    
    -- Check if Area2 is already unlocked and remove walls if necessary
    if playerData and playerData.Area2Unlocked then
        self:_removeArea2Walls(player)
        Logger:Info(string.format("Area2 already unlocked for returning player %s - removed walls", player.Name))
    end
    
    -- Check if Area3 is already unlocked and remove walls if necessary
    if playerData and playerData.Area3Unlocked then
        self:_removeArea3Walls(player)
        Logger:Info(string.format("Area3 already unlocked for returning player %s - removed walls", player.Name))
    end
    
    -- Initialize storage tracking for the player
    if self._storageService then
        self._storageService:InitializePlayerStorage(player)
    end
end

function PlotService:_removeArea2Walls(player)
    -- Get player's plot
    local playerPlots = Workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then
        Logger:Error("PlayerPlots not found for wall removal")
        return
    end
    
    local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
    if not playerPlot then
        Logger:Error(string.format("Plot not found for player %s for wall removal", player.Name))
        return
    end
    
    local area2 = playerPlot:FindFirstChild("Area2")
    if not area2 then
        Logger:Error(string.format("Area2 not found in plot for player %s", player.Name))
        return
    end
    
    -- Remove walls (Wall1, Wall2, Wall3, Wall4) and PurchaseWall
    local wallsRemoved = 0
    
    -- Remove the numbered walls
    for i = 1, 4 do
        local wall = area2:FindFirstChild("Wall" .. i)
        if wall then
            wall:Destroy()
            wallsRemoved = wallsRemoved + 1
            Logger:Debug(string.format("Removed Wall%d from %s's Area2", i, player.Name))
        end
    end
    
    -- Remove the PurchaseWall
    local purchaseWall = area2:FindFirstChild("PurchaseWall")
    if purchaseWall then
        purchaseWall:Destroy()
        wallsRemoved = wallsRemoved + 1
        Logger:Debug(string.format("Removed PurchaseWall from %s's Area2", player.Name))
    end
    
    Logger:Info(string.format("Removed %d walls (including PurchaseWall) from %s's Area2", wallsRemoved, player.Name))
end

function PlotService:_removeArea3Walls(player)
    -- Get player's plot
    local playerPlots = Workspace:FindFirstChild("PlayerPlots")
    if not playerPlots then
        Logger:Error("PlayerPlots not found for Area3 wall removal")
        return
    end
    
    local playerPlot = playerPlots:FindFirstChild("Plot_" .. player.Name)
    if not playerPlot then
        Logger:Error(string.format("Plot not found for player %s for Area3 wall removal", player.Name))
        return
    end
    
    local area3 = playerPlot:FindFirstChild("Area3")
    if not area3 then
        Logger:Error(string.format("Area3 not found in plot for player %s", player.Name))
        return
    end
    
    -- Remove walls (Wall1, Wall2, Wall3, Wall4) and PurchaseWall
    local wallsRemoved = 0
    
    -- Remove the numbered walls
    for i = 1, 4 do
        local wall = area3:FindFirstChild("Wall" .. i)
        if wall then
            wall:Destroy()
            wallsRemoved = wallsRemoved + 1
            Logger:Debug(string.format("Removed Wall%d from %s's Area3", i, player.Name))
        end
    end
    
    -- Remove the PurchaseWall
    local purchaseWall = area3:FindFirstChild("PurchaseWall")
    if purchaseWall then
        purchaseWall:Destroy()
        wallsRemoved = wallsRemoved + 1
        Logger:Debug(string.format("Removed PurchaseWall from %s's Area3", player.Name))
    end
    
    Logger:Info(string.format("Removed %d walls (including PurchaseWall) from %s's Area3", wallsRemoved, player.Name))
end

function PlotService:_updatePlayerSign(plot, player)
    local playerSign = plot:FindFirstChild("PlayerSign")
    if not playerSign then
        Logger:Warn(string.format("PlayerSign not found in plot for %s", player.Name))
        return
    end
    
    local main = playerSign:FindFirstChild("Main")
    if not main then
        Logger:Warn(string.format("Main part not found in PlayerSign for %s", player.Name))
        return
    end
    
    local surfaceGui = main:FindFirstChild("SurfaceGui")
    if not surfaceGui then
        Logger:Warn(string.format("SurfaceGui not found in PlayerSign for %s", player.Name))
        return
    end
    
    local frame = surfaceGui:FindFirstChild("Frame")
    if not frame then
        Logger:Warn(string.format("Frame not found in SurfaceGui for %s", player.Name))
        return
    end
    
    -- Update PlayerID with avatar
    local playerIdImage = frame:FindFirstChild("PlayerID")
    if playerIdImage and playerIdImage:IsA("ImageLabel") then
        local avatarUrl = self:_getPlayerAvatarUrl(player.UserId)
        playerIdImage.Image = avatarUrl
        Logger:Debug(string.format("Updated avatar for %s", player.Name))
    else
        Logger:Warn(string.format("PlayerID ImageLabel not found for %s", player.Name))
    end
    
    -- Update User with display name
    local userLabel = frame:FindFirstChild("User")
    if userLabel and userLabel:IsA("TextLabel") then
        userLabel.Text = player.DisplayName .. "'s"
        Logger:Debug(string.format("Updated display name for %s", player.Name))
    else
        Logger:Warn(string.format("User TextLabel not found for %s", player.Name))
    end
    
    Logger:Info(string.format("Updated PlayerSign for %s", player.Name))
end

function PlotService:_getPlayerAvatarUrl(userId)
    -- Roblox avatar URL format for headshots
    return "https://www.roblox.com/headshot-thumbnail/image?userId=" .. userId .. "&width=420&height=420&format=png"
end

function PlotService:Cleanup()
    for connectionName, connection in pairs(self._connections) do
        if connection then
            connection:Disconnect()
        end
    end
    self._connections = {}
    
    Logger:Info("PlotService cleaned up")
end

return PlotService