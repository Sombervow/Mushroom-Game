local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)
local CollectionService = require(script.Parent.Services.CollectionService)
local MushroomHoverService = require(script.Parent.Services.MushroomHoverService)
local MushroomRenderService = require(script.Parent.Services.MushroomRenderService)
local MushroomInteractionService = require(script.Parent.Services.MushroomInteractionServiceNew)
local OfflineEarningsClient = require(script.Parent.Services.OfflineEarningsClient)
local GamepassClient = require(script.Parent.Services.GamepassClient)
local ButtonManager = require(script.Parent.Services.ButtonManager)
local UIManager = require(script.Parent.Services.UIManager)
local ShopClient = require(script.Parent.Services.ShopClient)
-- local GemShopClient = require(script.Parent.Services.GemShopClient) -- Disabled
local MoneyManager = require(script.Parent.Services.MoneyManager)
local WishClient = require(script.Parent.Services.WishClient)
local InventoryClient = require(script.Parent.Services.InventoryClient)
local NotificationClient = require(script.Parent.Services.NotificationClient)
local MusicService = require(script.Parent.Services.MusicService)
local DailyRewardClient = require(script.Parent.Services.DailyRewardClient)
local SystemTipClient = require(script.Parent.Services.SystemTipClient)
local ActiveBoostService = require(script.Parent.Services.ActiveBoostService)
local Area2AnimationClient = require(script.Parent.Services.Area2AnimationClient)
local LeaderboardClient = require(script.Parent.Services.LeaderboardClient)
local GemsLeaderboardClient = require(script.Parent.Services.GemsLeaderboardClient)
local RobuxLeaderboardClient = require(script.Parent.Services.RobuxLeaderboardClient)
local StarterPackService = require(script.Parent.Services.StarterPackService)
local UIStrokeScaler = require(script.Parent.Services.UIStrokeScaler)
local LoadingScreenService = require(script.Parent.Services.LoadingScreenService)
local TutorialClient = require(script.Parent.Services.TutorialClient)

local ClientCore = {}

local services = {}
local player = Players.LocalPlayer

function ClientCore:Initialize()
    Logger:Info("=== ClientCore Initialization Started ===")
    
    -- Initialize loading screen first
    services.LoadingScreenService = LoadingScreenService.new()
    Logger:Info("✓ LoadingScreenService initialized")
    
    self:_waitForServerSetup()
    self:_initializeServices()
    
    Logger:Info("=== ClientCore Initialization Complete ===")
end

function ClientCore:_waitForServerSetup()
    Logger:Info("Waiting for server setup...")
    
    -- Wait for essential RemoteEvents/Functions to be created by server
    local shared = ReplicatedStorage:WaitForChild("Shared", 10)
    if shared then
        shared:WaitForChild("RemoteEvents", 5)
        shared:WaitForChild("RemoteFunctions", 5)
        Logger:Info("Server setup confirmed")
    else
        Logger:Warn("Server setup timeout - proceeding anyway")
    end
end

function ClientCore:_initializeServices()
    Logger:Info("Initializing client services...")
    
    services.CollectionService = CollectionService.new()
    Logger:Info("✓ CollectionService initialized")
    
    services.MushroomRenderService = MushroomRenderService.new()
    Logger:Info("✓ MushroomRenderService initialized")
    
    services.MushroomHoverService = MushroomHoverService.new()
    Logger:Info("✓ MushroomHoverService initialized")
    
    services.MushroomInteractionService = MushroomInteractionService.new()
    Logger:Info("✓ MushroomInteractionService initialized")
    
    services.GamepassClient = GamepassClient.new()
    Logger:Info("✓ GamepassClient initialized")
    
    services.ButtonManager = ButtonManager.new()
    Logger:Info("✓ ButtonManager initialized")
    
    services.UIManager = UIManager.new()
    Logger:Info("✓ UIManager initialized")
    
    services.ShopClient = ShopClient.new()
    Logger:Info("✓ ShopClient initialized")
    
    -- GemShopClient disabled - ShopClient handles all gem shop functionality
    -- services.GemShopClient = GemShopClient.new()
    Logger:Info("✓ GemShopClient disabled - handled by ShopClient")
    
    services.OfflineEarningsClient = OfflineEarningsClient.new()
    Logger:Info("✓ OfflineEarningsClient initialized")
    
    services.MoneyManager = MoneyManager.new()
    Logger:Info("✓ MoneyManager initialized")
    
    services.WishClient = WishClient.new()
    Logger:Info("✓ WishClient initialized")
    
    services.InventoryClient = InventoryClient.new()
    Logger:Info("✓ InventoryClient initialized")
    
    services.NotificationClient = NotificationClient.new()
    Logger:Info("✓ NotificationClient initialized")
    
    services.MusicService = MusicService.new()
    Logger:Info("✓ MusicService initialized")
    
    Logger:Info("Creating DailyRewardClient...")
    services.DailyRewardClient = DailyRewardClient.new()
    Logger:Info("✓ DailyRewardClient created: " .. tostring(services.DailyRewardClient ~= nil))
    
    services.SystemTipClient = SystemTipClient.new()
    Logger:Info("✓ SystemTipClient initialized")
    
    services.ActiveBoostService = ActiveBoostService.new()
    Logger:Info("✓ ActiveBoostService initialized")
    
    services.Area2AnimationClient = Area2AnimationClient.new()
    Logger:Info("✓ Area2AnimationClient initialized")
    
    services.LeaderboardClient = LeaderboardClient.new()
    Logger:Info("✓ LeaderboardClient initialized")
    
    services.GemsLeaderboardClient = GemsLeaderboardClient.new()
    Logger:Info("✓ GemsLeaderboardClient initialized")
    
    services.RobuxLeaderboardClient = RobuxLeaderboardClient.new()
    Logger:Info("✓ RobuxLeaderboardClient initialized")
    
    services.StarterPackService = StarterPackService.new()
    Logger:Info("✓ StarterPackService initialized")
    
    -- Initialize UIStrokeScaler early to catch all UI elements
    services.UIStrokeScaler = UIStrokeScaler.new()
    Logger:Info("✓ UIStrokeScaler initialized")
    
    services.TutorialClient = TutorialClient.new()
    Logger:Info("✓ TutorialClient initialized")
    
    if services.DailyRewardClient and services.DailyRewardClient.SetUIManager then
        Logger:Info("✓ DailyRewardClient has SetUIManager method")
    else
        Logger:Error("✗ DailyRewardClient missing SetUIManager method")
    end
    
    -- Link services
    self:_linkServices()
    
    Logger:Info("All client services initialized successfully")
end

function ClientCore:_linkServices()
    Logger:Info("Linking client services...")
    
    -- Link MushroomInteractionService with MushroomRenderService and CollectionService
    if services.MushroomInteractionService and services.MushroomRenderService then
        services.MushroomInteractionService:SetMushroomRenderService(services.MushroomRenderService)
        Logger:Info("✓ MushroomInteractionService linked with MushroomRenderService")
    end
    
    if services.MushroomInteractionService and services.CollectionService then
        services.MushroomInteractionService:SetCollectionService(services.CollectionService)
        Logger:Info("✓ MushroomInteractionService linked with CollectionService")
    end
    
    -- Link ShopClient with CollectionService for PickUpRange upgrades
    if services.ShopClient and services.CollectionService then
        services.ShopClient:SetCollectionService(services.CollectionService)
        Logger:Info("✓ ShopClient linked with CollectionService")
    end
    
    -- Link GamepassClient with OfflineEarningsClient
    if services.OfflineEarningsClient and services.GamepassClient then
        services.OfflineEarningsClient:SetGamepassService(services.GamepassClient)
        Logger:Info("✓ OfflineEarningsClient linked with GamepassClient")
    end
    
    -- Auto-register offline earnings buttons with ButtonManager
    if services.ButtonManager and services.OfflineEarningsClient then
        -- Give a moment for UI to be created, then register buttons
        spawn(function()
            wait(1)
            self:_registerOfflineEarningsButtons()
        end)
    end
    
    -- Link DailyRewardClient with UIManager and NotificationClient
    if services.DailyRewardClient and services.UIManager then
        services.DailyRewardClient:SetUIManager(services.UIManager)
        Logger:Info("✓ DailyRewardClient linked with UIManager")
    end
    
    if services.DailyRewardClient and services.NotificationClient then
        services.DailyRewardClient:SetNotificationClient(services.NotificationClient)
        Logger:Info("✓ DailyRewardClient linked with NotificationClient")
    end
    
    -- Link OfflineEarningsClient with DailyRewardClient for auto-open functionality
    if services.OfflineEarningsClient and services.DailyRewardClient then
        services.OfflineEarningsClient:SetDailyRewardClient(services.DailyRewardClient)
        Logger:Info("✓ OfflineEarningsClient linked with DailyRewardClient")
    end
    
    -- Link services with LoadingScreenService
    if services.LoadingScreenService then
        if services.OfflineEarningsClient then
            services.OfflineEarningsClient:SetLoadingScreenService(services.LoadingScreenService)
            Logger:Info("✓ OfflineEarningsClient linked with LoadingScreenService")
        end
        
        if services.DailyRewardClient then
            services.DailyRewardClient:SetLoadingScreenService(services.LoadingScreenService)
            Logger:Info("✓ DailyRewardClient linked with LoadingScreenService")
        end
        
        if services.TutorialClient then
            services.TutorialClient:SetLoadingScreenService(services.LoadingScreenService)
            Logger:Info("✓ TutorialClient linked with LoadingScreenService")
        end
    end
    
    -- Link InventoryClient with ActiveBoostService for boost notifications
    if services.InventoryClient and services.ActiveBoostService then
        -- No direct linking needed - ActiveBoostService listens to remote events
        Logger:Info("✓ ActiveBoostService connected to inventory events")
    end
    
    -- Link UIManager with GamepassClient for dynamic pricing
    if services.UIManager and services.GamepassClient then
        services.UIManager:SetGamepassClient(services.GamepassClient)
        Logger:Info("✓ UIManager linked with GamepassClient for dynamic pricing")
    end
    
    -- Link ShopClient with GamepassClient for dev product purchases
    if services.ShopClient and services.GamepassClient then
        services.ShopClient:SetGamepassClient(services.GamepassClient)
        Logger:Info("✓ ShopClient linked with GamepassClient for dev product purchases")
    end
    
    Logger:Info("Client service linking complete")
end

function ClientCore:_registerOfflineEarningsButtons()
    local buttonManager = services.ButtonManager
    local offlineClient = services.OfflineEarningsClient
    
    if not buttonManager or not offlineClient then return end
    
    -- Try to find and register offline earnings buttons
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local offlineEarningsGui = playerGui:FindFirstChild("OfflineEarnings")
    
    if offlineEarningsGui then
        local container = offlineEarningsGui:FindFirstChild("Container")
        if container then
            local claimSpores = container:FindFirstChild("ClaimSpores")
            local doubleSpores = container:FindFirstChild("DoubleSpores")
            
            if claimSpores and claimSpores:IsA("GuiButton") then
                buttonManager:RegisterButton(claimSpores)
                Logger:Info("✓ Registered ClaimSpores button")
            end
            
            if doubleSpores and doubleSpores:IsA("GuiButton") then
                buttonManager:RegisterButton(doubleSpores)
                Logger:Info("✓ Registered DoubleSpores button")
            end
        end
    end
end

function ClientCore:GetService(serviceName)
    return services[serviceName]
end

-- Debug function to manually rescan mushrooms
function ClientCore:RescanMushrooms()
    if services.MushroomHoverService and services.MushroomHoverService.ForceRescan then
        local result = services.MushroomHoverService:ForceRescan()
        Logger:Info(string.format("Rescan complete: %d -> %d mushrooms (+%d)", result.before, result.after, result.found))
        return result
    else
        Logger:Warn("MushroomHoverService not available or missing ForceRescan method")
    end
end

-- Debug function to check highlight status
function ClientCore:CheckHighlights()
    if services.MushroomHoverService and services.MushroomHoverService.GetStatus then
        local status = services.MushroomHoverService:GetStatus()
        Logger:Info(string.format("Hover Status: %d mushrooms tracked, current: %s, initialized: %s", 
            status.trackedMushrooms, status.currentHovered, tostring(status.isInitialized)))
        return status
    else
        Logger:Warn("MushroomHoverService not available or missing GetStatus method")
    end
end

function ClientCore:Shutdown()
    Logger:Info("=== ClientCore Shutdown Started ===")
    
    for serviceName, service in pairs(services) do
        if service and service.Cleanup then
            service:Cleanup()
            Logger:Info(string.format("✓ %s cleaned up", serviceName))
        end
    end
    
    services = {}
    Logger:Info("=== ClientCore Shutdown Complete ===")
end

-- Debug functions (can be called directly from console)
function CheckHighlights()
    print("[DEBUG] Running CheckHighlights...")
    print("[DEBUG] Services table exists: " .. tostring(services ~= nil))
    if services then
        print("[DEBUG] MushroomHoverService exists: " .. tostring(services.MushroomHoverService ~= nil))
        if services.MushroomHoverService then
            print("[DEBUG] GetStatus method exists: " .. tostring(services.MushroomHoverService.GetStatus ~= nil))
            if services.MushroomHoverService.GetStatus then
                local success, status = pcall(function()
                    return services.MushroomHoverService:GetStatus()
                end)
                if success then
                    print(string.format("[DEBUG] Hover Status: %d mushrooms, current: %s, initialized: %s", 
                        status.trackedMushrooms, status.currentHovered, tostring(status.isInitialized)))
                    return status
                else
                    print("[DEBUG] Error calling GetStatus: " .. tostring(status))
                end
            else
                print("[DEBUG] GetStatus method missing")
            end
        else
            print("[DEBUG] MushroomHoverService not found in services")
        end
    else
        print("[DEBUG] Services table is nil")
    end
end

function RescanMushrooms()
    print("[DEBUG] Running RescanMushrooms...")
    if services.MushroomHoverService and services.MushroomHoverService.ForceRescan then
        local result = services.MushroomHoverService:ForceRescan()
        print(string.format("[DEBUG] Rescan: %d -> %d mushrooms (+%d)", result.before, result.after, result.found))
        return result
    else
        print("[DEBUG] MushroomHoverService not available")
    end
end

function GetMushroomService()
    return services.MushroomHoverService
end

function GetInteractionService()
    return services.MushroomInteractionService
end

-- Initialize when player loads
if player then
    -- Make functions available globally immediately
    _G.CheckHighlights = CheckHighlights
    _G.RescanMushrooms = RescanMushrooms
    _G.GetMushroomService = GetMushroomService
    _G.GetInteractionService = GetInteractionService
    print("[DEBUG] Global functions registered: CheckHighlights(), RescanMushrooms(), GetMushroomService(), GetInteractionService()")
    
    -- Initialize services
    local success, err = pcall(function()
        ClientCore:Initialize()
    end)
    
    if not success then
        print("[ERROR] ClientCore initialization failed: " .. tostring(err))
    else
        print("[DEBUG] ClientCore initialized successfully")
    end
end

return ClientCore