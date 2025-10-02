local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Logger = require(script.Parent.Utilities.Logger)
local DataService = require(script.Parent.Services.DataService)
local PlotService = require(script.Parent.Services.PlotService)
local PlayerService = require(script.Parent.Services.PlayerService)
local MushroomDataService = require(script.Parent.Services.MushroomDataService)
local ShopService = require(script.Parent.Services.ShopService)
local OfflineEarningsService = require(script.Parent.Services.OfflineEarningsService)
local WishService = require(script.Parent.Services.WishService)
local InventoryService = require(script.Parent.Services.InventoryService)
local NotificationService = require(script.Parent.Services.NotificationService)
local DaylightService = require(script.Parent.Services.DaylightService)
local SystemChatService = require(script.Parent.Services.SystemChatService)
local DailyRewardService = require(script.Parent.Services.DailyRewardService)
local GroupRewardService = require(script.Parent.Services.GroupRewardService)
local LeaderboardService = require(script.Parent.Services.LeaderboardService)
local AdminCommands = require(script.Parent.Services.AdminCommands)
local GamepassService = require(script.Parent.Services.GamepassService)
local TutorialService = require(script.Parent.Services.TutorialService)
local StorageService = require(script.Parent.Services.StorageService)
local RobloxAnalyticsService = require(script.Parent.Services.RobloxAnalyticsService)
local RobuxMarketplaceService = require(script.Parent.Services.MarketplaceService)

local GameCore = {}

local services = {}

function GameCore:Initialize()
    Logger:Info("=== GameCore Initialization Started ===")
    
    self:_createRemoteEvents()
    self:_createRemoteFunctions()
    self:_initializeServices()
    self:_linkServices()
    
    Logger:Info("=== GameCore Initialization Complete ===")
end

function GameCore:_createRemoteEvents()
    Logger:Info("Creating RemoteEvents structure...")
    
    local shared = ReplicatedStorage:FindFirstChild("Shared")
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
    
    local dataEvents = remoteEvents:FindFirstChild("DataEvents")
    if not dataEvents then
        dataEvents = Instance.new("Folder")
        dataEvents.Name = "DataEvents"
        dataEvents.Parent = remoteEvents
        
        local currencyUpdated = Instance.new("RemoteEvent")
        currencyUpdated.Name = "CurrencyUpdated"
        currencyUpdated.Parent = dataEvents
        
        local requestPlayerData = Instance.new("RemoteEvent")
        requestPlayerData.Name = "RequestPlayerData"
        requestPlayerData.Parent = dataEvents
        
        local itemCollected = Instance.new("RemoteEvent")
        itemCollected.Name = "ItemCollected"
        itemCollected.Parent = dataEvents
        
        local collectionConfirmed = Instance.new("RemoteEvent")
        collectionConfirmed.Name = "CollectionConfirmed"
        collectionConfirmed.Parent = dataEvents
    end
    
    local plotEvents = remoteEvents:FindFirstChild("PlotEvents")
    if not plotEvents then
        plotEvents = Instance.new("Folder")
        plotEvents.Name = "PlotEvents"
        plotEvents.Parent = remoteEvents
        
        local plotAssigned = Instance.new("RemoteEvent")
        plotAssigned.Name = "PlotAssigned"
        plotAssigned.Parent = plotEvents
        
        local plotUpdated = Instance.new("RemoteEvent")
        plotUpdated.Name = "PlotUpdated"
        plotUpdated.Parent = plotEvents
    end
    
    local mushroomEvents = remoteEvents:FindFirstChild("MushroomEvents")
    if not mushroomEvents then
        mushroomEvents = Instance.new("Folder")
        mushroomEvents.Name = "MushroomEvents"
        mushroomEvents.Parent = remoteEvents
        
        local mushroomClicked = Instance.new("RemoteEvent")
        mushroomClicked.Name = "MushroomClicked"
        mushroomClicked.Parent = mushroomEvents
        
        local updateMushroomData = Instance.new("RemoteEvent")
        updateMushroomData.Name = "UpdateMushroomData"
        updateMushroomData.Parent = mushroomEvents
        
        local sporeSpawned = Instance.new("RemoteEvent")
        sporeSpawned.Name = "SporeSpawned" 
        sporeSpawned.Parent = mushroomEvents
        
        local sporeCollected = Instance.new("RemoteEvent")
        sporeCollected.Name = "SporeCollected"
        sporeCollected.Parent = mushroomEvents
    end
    
    local dailyRewardEvents = remoteEvents:FindFirstChild("DailyRewardEvents")
    if not dailyRewardEvents then
        dailyRewardEvents = Instance.new("Folder")
        dailyRewardEvents.Name = "DailyRewardEvents"
        dailyRewardEvents.Parent = remoteEvents
        
        local claimReward = Instance.new("RemoteEvent")
        claimReward.Name = "ClaimReward"
        claimReward.Parent = dailyRewardEvents
        
        local rewardClaimed = Instance.new("RemoteEvent")
        rewardClaimed.Name = "RewardClaimed"
        rewardClaimed.Parent = dailyRewardEvents
        
        local getDailyData = Instance.new("RemoteFunction")
        getDailyData.Name = "GetDailyData"
        getDailyData.Parent = dailyRewardEvents
    end
    
    local groupRewardEvents = remoteEvents:FindFirstChild("GroupRewardEvents")
    if not groupRewardEvents then
        groupRewardEvents = Instance.new("Folder")
        groupRewardEvents.Name = "GroupRewardEvents"
        groupRewardEvents.Parent = remoteEvents
        
        local claimGroupReward = Instance.new("RemoteEvent")
        claimGroupReward.Name = "ClaimGroupReward"
        claimGroupReward.Parent = groupRewardEvents
        
        local getGroupRewardStatus = Instance.new("RemoteFunction")
        getGroupRewardStatus.Name = "GetGroupRewardStatus"
        getGroupRewardStatus.Parent = groupRewardEvents
    end
    
    Logger:Info("RemoteEvents structure created successfully")
end

function GameCore:_createRemoteFunctions()
    Logger:Info("Creating RemoteFunctions structure...")
    
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local remoteFunctions = shared:FindFirstChild("RemoteFunctions")
    if not remoteFunctions then
        remoteFunctions = Instance.new("Folder")
        remoteFunctions.Name = "RemoteFunctions"
        remoteFunctions.Parent = shared
    end
    
    local getPlayerData = remoteFunctions:FindFirstChild("GetPlayerData")
    if not getPlayerData then
        getPlayerData = Instance.new("RemoteFunction")
        getPlayerData.Name = "GetPlayerData"
        getPlayerData.Parent = remoteFunctions
        
        getPlayerData.OnServerInvoke = function(player)
            if services.PlayerService then
                return services.PlayerService:GetPlayerStats(player)
            end
            return nil
        end
    end
    
    local getPlotInfo = remoteFunctions:FindFirstChild("GetPlotInfo")
    if not getPlotInfo then
        getPlotInfo = Instance.new("RemoteFunction")
        getPlotInfo.Name = "GetPlotInfo"
        getPlotInfo.Parent = remoteFunctions
        
        getPlotInfo.OnServerInvoke = function(player)
            if services.PlayerService then
                return services.PlayerService:GetPlayerPlotInfo(player)
            end
            return nil
        end
    end
    
    local getShopData = remoteFunctions:FindFirstChild("GetShopData")
    if not getShopData then
        getShopData = Instance.new("RemoteFunction")
        getShopData.Name = "GetShopData"
        getShopData.Parent = remoteFunctions
        
        getShopData.OnServerInvoke = function(player)
            if services.ShopService then
                return services.ShopService:GetShopDataForPlayer(player)
            end
            return nil
        end
    end
    
    local getGemShopData = remoteFunctions:FindFirstChild("GetGemShopData")
    if not getGemShopData then
        getGemShopData = Instance.new("RemoteFunction")
        getGemShopData.Name = "GetGemShopData"
        getGemShopData.Parent = remoteFunctions
        
        getGemShopData.OnServerInvoke = function(player)
            if services.ShopService then
                return services.ShopService:GetGemShopDataForPlayer(player)
            end
            return nil
        end
    end
    
    Logger:Info("RemoteFunctions structure created successfully")
end

function GameCore:_initializeServices()
    Logger:Info("Initializing core services...")
    
    services.DataService = DataService.new()
    Logger:Info("✓ DataService initialized")
    
    services.PlotService = PlotService.new()
    Logger:Info("✓ PlotService initialized")
    
    services.PlayerService = PlayerService.new()
    Logger:Info("✓ PlayerService initialized")
    
    services.MushroomDataService = MushroomDataService.new()
    Logger:Info("✓ MushroomDataService initialized")
    
    services.ShopService = ShopService.new()
    Logger:Info("✓ ShopService initialized")
    
    services.OfflineEarningsService = OfflineEarningsService.new()
    Logger:Info("✓ OfflineEarningsService initialized")
    
    services.WishService = WishService.new()
    Logger:Info("✓ WishService initialized")
    
    services.InventoryService = InventoryService.new()
    Logger:Info("✓ InventoryService initialized")
    
    services.NotificationService = NotificationService.new()
    Logger:Info("✓ NotificationService initialized")
    
    services.DaylightService = DaylightService.new()
    Logger:Info("✓ DaylightService initialized")
    
    services.SystemChatService = SystemChatService.new()
    Logger:Info("✓ SystemChatService initialized")
    
    services.DailyRewardService = DailyRewardService.new()
    Logger:Info("✓ DailyRewardService initialized")
    
    services.GroupRewardService = GroupRewardService.new()
    Logger:Info("✓ GroupRewardService initialized")
    
    services.LeaderboardService = LeaderboardService.new()
    Logger:Info("✓ LeaderboardService initialized")
    
    services.AdminCommands = AdminCommands
    Logger:Info("✓ AdminCommands initialized")
    
    services.GamepassService = GamepassService.new(Logger, services.DataService)
    Logger:Info("✓ GamepassService initialized")
    
    services.TutorialService = TutorialService.new()
    Logger:Info("✓ TutorialService initialized")
    
    services.StorageService = StorageService.new()
    Logger:Info("✓ StorageService initialized")
    
    services.RobloxAnalyticsService = RobloxAnalyticsService.new()
    Logger:Info("✓ RobloxAnalyticsService initialized")
    
    services.RobuxMarketplaceService = RobuxMarketplaceService.new()
    Logger:Info("✓ RobuxMarketplaceService initialized")
    
    Logger:Info("All core services initialized successfully")
end

function GameCore:_linkServices()
    Logger:Info("Linking services together...")
    
    if services.PlayerService then
        services.PlayerService:SetServices(services.DataService, services.PlotService, services.RobloxAnalyticsService)
        Logger:Info("✓ PlayerService linked with DataService, PlotService, and RobloxAnalyticsService")
    end
    
    if services.PlotService and services.DataService then
        services.PlotService:SetDataService(services.DataService)
        services.DataService:SetPlotService(services.PlotService)
        Logger:Info("✓ PlotService linked with DataService")
    end
    
    if services.MushroomDataService and services.DataService and services.PlotService and services.ShopService then
        services.MushroomDataService:SetDataService(services.DataService)
        services.MushroomDataService:SetPlotService(services.PlotService)
        services.MushroomDataService:SetShopService(services.ShopService)
        services.DataService:SetMushroomService(services.MushroomDataService)
        Logger:Info("✓ MushroomDataService linked with DataService, PlotService, and ShopService")
    end
    
    -- MushroomDataService doesn't need StorageService link (data-only service)
    
    if services.ShopService and services.DataService and services.MushroomDataService and services.GamepassService and services.NotificationService and services.RobloxAnalyticsService then
        services.ShopService:SetServices(services.DataService, services.MushroomDataService, services.GamepassService, services.NotificationService, services.RobloxAnalyticsService)
        services.DataService:SetShopService(services.ShopService)
        Logger:Info("✓ ShopService linked with DataService, MushroomDataService, GamepassService, NotificationService, and RobloxAnalyticsService")
    end
    
    if services.GamepassService and services.DataService then
        services.DataService:SetGamepassService(services.GamepassService)
        Logger:Info("✓ GamepassService linked with DataService")
    end
    
    if services.OfflineEarningsService and services.DataService then
        services.OfflineEarningsService:SetDataService(services.DataService)
        Logger:Info("✓ OfflineEarningsService linked with DataService")
    end
    
    if services.WishService and services.DataService then
        services.WishService:SetDataService(services.DataService)
        Logger:Info("✓ WishService linked with DataService")
    end
    
    if services.InventoryService and services.DataService then
        services.InventoryService:SetDataService(services.DataService)
        Logger:Info("✓ InventoryService linked with DataService")
    end
    
    if services.WishService and services.InventoryService then
        services.WishService:SetInventoryService(services.InventoryService)
        Logger:Info("✓ WishService linked with InventoryService")
    end
    
    if services.WishService and services.NotificationService then
        services.WishService:SetNotificationService(services.NotificationService)
        Logger:Info("✓ WishService linked with NotificationService")
    end
    
    if services.DaylightService and services.NotificationService then
        services.DaylightService:SetNotificationService(services.NotificationService)
        Logger:Info("✓ DaylightService linked with NotificationService")
    end
    
    if services.DailyRewardService and services.DataService and services.NotificationService and services.InventoryService then
        services.DailyRewardService:SetDataService(services.DataService)
        services.DailyRewardService:SetNotificationService(services.NotificationService)
        services.DailyRewardService:SetInventoryService(services.InventoryService)
        Logger:Info("✓ DailyRewardService linked with DataService, NotificationService, and InventoryService")
    end
    
    if services.GroupRewardService and services.DataService and services.NotificationService then
        services.GroupRewardService:SetDataService(services.DataService)
        services.GroupRewardService:SetNotificationService(services.NotificationService)
        Logger:Info("✓ GroupRewardService linked with DataService and NotificationService")
    end
    
    if services.LeaderboardService and services.DataService then
        services.LeaderboardService:SetDataService(services.DataService)
        Logger:Info("✓ LeaderboardService linked with DataService")
    end
    
    -- Initialize AdminCommands with GameCore reference
    if services.AdminCommands then
        services.AdminCommands:Initialize(self)
        Logger:Info("✓ AdminCommands initialized and connected")
    end
    
    -- Initialize GamepassService
    if services.GamepassService then
        services.GamepassService:initialize()
        services.GamepassService:linkServices(services)
        Logger:Info("✓ GamepassService initialized and linked")
    end
    
    -- Link TutorialService with DataService
    if services.TutorialService and services.DataService then
        services.TutorialService:SetDataService(services.DataService)
        Logger:Info("✓ TutorialService linked with DataService")
    end
    
    -- Link TutorialService with NotificationService for wish notifications
    if services.TutorialService and services.NotificationService then
        services.TutorialService:SetNotificationService(services.NotificationService)
        Logger:Info("✓ TutorialService linked with NotificationService")
    end
    
    -- Link TutorialService with WishService for GUI updates
    if services.TutorialService and services.WishService then
        services.TutorialService:SetWishService(services.WishService)
        Logger:Info("✓ TutorialService linked with WishService")
    end
    
    -- Link StorageService with DataService
    if services.StorageService and services.DataService then
        services.StorageService:LinkDataService(services.DataService)
        services.DataService:SetStorageService(services.StorageService)
        Logger:Info("✓ StorageService linked with DataService")
    end
    
    -- Link RobloxAnalyticsService with DataService
    if services.RobloxAnalyticsService and services.DataService then
        services.RobloxAnalyticsService:SetServices(services.DataService)
        services.DataService:SetRobloxAnalyticsService(services.RobloxAnalyticsService)
        Logger:Info("✓ RobloxAnalyticsService linked with DataService")
    end
    
    -- Link PlotService with StorageService
    if services.PlotService and services.StorageService then
        services.PlotService:SetStorageService(services.StorageService)
        Logger:Info("✓ PlotService linked with StorageService")
    end
    
    -- Link RobuxMarketplaceService with DataService and WishService
    if services.RobuxMarketplaceService and services.DataService then
        services.RobuxMarketplaceService:SetDataService(services.DataService)
        Logger:Info("✓ RobuxMarketplaceService linked with DataService")
    end
    
    if services.RobuxMarketplaceService and services.WishService then
        services.RobuxMarketplaceService:SetWishService(services.WishService)
        Logger:Info("✓ RobuxMarketplaceService linked with WishService")
    end
    
    Logger:Info("Service linking complete")
end

function GameCore:GetService(serviceName)
    return services[serviceName]
end

function GameCore:Shutdown()
    Logger:Info("=== GameCore Shutdown Started ===")
    
    for serviceName, service in pairs(services) do
        if service and service.Cleanup then
            service:Cleanup()
            Logger:Info(string.format("✓ %s cleaned up", serviceName))
        end
    end
    
    services = {}
    Logger:Info("=== GameCore Shutdown Complete ===")
end

game:BindToClose(function()
    GameCore:Shutdown()
end)

GameCore:Initialize()

return GameCore