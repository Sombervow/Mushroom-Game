local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local InventoryClient = {}
InventoryClient.__index = InventoryClient

local player = Players.LocalPlayer

-- Client-side image fallbacks
local CLIENT_IMAGE_FALLBACKS = {
    ["Wish Star"] = "rbxassetid://106663495841758",
    ["Energy Bar"] = "rbxassetid://110491282217664", 
    ["Golden Apple"] = "rbxassetid://120295649276578",
    ["Gem Potion"] = "rbxassetid://126345409470651",
    ["Shroom Food"] = "rbxassetid://127204542535592", 
    ["Bux Potion"] = "rbxassetid://130449969956988",
    ["Apple"] = "rbxassetid://96389092320560",
    ["Bone"] = "rbxassetid://73911550220270"
}

function InventoryClient.new()
    local self = setmetatable({}, InventoryClient)
    self._connections = {}
    self._currentInventory = {}
    self._itemFrames = {}
    self._selectedItem = nil
    self._activeBoosts = {}
    self._remoteEvents = {}
    self._guiElements = {}
    self:_initialize()
    return self
end

function InventoryClient:_initialize()
    Logger:Info("InventoryClient initializing...")
    
    self:_waitForRemoteEvents()
    self:_setupGUI()
    self:_connectEvents()
    
    Logger:Info("✓ InventoryClient initialized")
end

function InventoryClient:_waitForRemoteEvents()
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local remoteEvents = shared:WaitForChild("RemoteEvents")
    local inventoryEvents = remoteEvents:WaitForChild("InventoryEvents")
    
    self._remoteEvents.UpdateInventory = inventoryEvents:WaitForChild("UpdateInventory")
    self._remoteEvents.UseItem = inventoryEvents:WaitForChild("UseItem")
    self._remoteEvents.SyncBoosts = inventoryEvents:WaitForChild("SyncBoosts")
    
    Logger:Info("✓ Inventory remote events connected")
end

function InventoryClient:_setupGUI()
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- Wait for inventory GUI
    local inventoryGui = playerGui:WaitForChild("Inventory", 10)
    if not inventoryGui then
        Logger:Error("Inventory GUI not found!")
        return
    end
    
    self._guiElements.inventoryGui = inventoryGui
    self._guiElements.inventoryFrame = inventoryGui:WaitForChild("Frame")
    self._guiElements.inventoryBackground = self._guiElements.inventoryFrame:WaitForChild("InventoryBackground")
    self._guiElements.itemsContainer = self._guiElements.inventoryBackground:WaitForChild("ItemsContainer")
    self._guiElements.itemsScrollingFrame = self._guiElements.itemsContainer:WaitForChild("Items")
    
    -- Setup ItemInfo panel
    self._guiElements.itemInfoFrame = self._guiElements.inventoryBackground:FindFirstChild("ItemInfo")
    if self._guiElements.itemInfoFrame then
        self._guiElements.itemIcon = self:_findFirstChildVariant(self._guiElements.itemInfoFrame, 
            {"ItemIcon", "Icon", "Image", "ItemImage"}) or self._guiElements.itemInfoFrame:FindFirstChildOfClass("ImageLabel")
        
        self._guiElements.itemNameLabel = self:_findFirstChildVariant(self._guiElements.itemInfoFrame, 
            {"ItemName", "Name", "Title"})
        
        self._guiElements.itemRarityLabel = self:_findFirstChildVariant(self._guiElements.itemInfoFrame, 
            {"ItemRarity", "Rarity", "Quality"})
        
        self._guiElements.itemDescriptionLabel = self:_findFirstChildVariant(self._guiElements.itemInfoFrame, 
            {"ItemDescription", "Description", "Info", "Details"})
        
        self._guiElements.useItemButton = self._guiElements.itemInfoFrame:FindFirstChild("UseItem")
        if self._guiElements.useItemButton then
            self._guiElements.useItemLabel = self._guiElements.useItemButton:FindFirstChild("Boosts") 
                or self._guiElements.useItemButton:FindFirstChildOfClass("TextLabel")
            
            if not self._guiElements.useItemLabel then
                self._guiElements.useItemLabel = Instance.new("TextLabel")
                self._guiElements.useItemLabel.Name = "Boosts"
                self._guiElements.useItemLabel.Size = UDim2.new(1, 0, 1, 0)
                self._guiElements.useItemLabel.BackgroundTransparency = 1
                self._guiElements.useItemLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                self._guiElements.useItemLabel.TextScaled = true
                self._guiElements.useItemLabel.Font = Enum.Font.SourceSansBold
                self._guiElements.useItemLabel.Text = "Use (0)"
                self._guiElements.useItemLabel.Parent = self._guiElements.useItemButton
            end
        end
        
        -- Hide ItemInfo initially
        self._guiElements.itemInfoFrame.Visible = false
    end
    
    -- Get ItemFrame template
    local guiFolder = ReplicatedStorage:FindFirstChild("GUI")
    if guiFolder then
        self._guiElements.itemFrameTemplate = guiFolder:FindFirstChild("ItemFrame")
    end
    
    Logger:Info("✓ Inventory GUI elements setup complete")
end

function InventoryClient:_findFirstChildVariant(parent, names)
    for _, name in pairs(names) do
        local child = parent:FindFirstChild(name)
        if child then return child end
    end
    return nil
end

function InventoryClient:_connectEvents()
    -- Connect remote events
    self._connections.UpdateInventory = self._remoteEvents.UpdateInventory.OnClientEvent:Connect(function(inventoryData, itemConfig)
        self:_updateInventory(inventoryData, itemConfig)
    end)
    
    self._connections.SyncBoosts = self._remoteEvents.SyncBoosts.OnClientEvent:Connect(function(boosts)
        self:_updateActiveBoosts(boosts)
    end)
    
    -- Connect UseItem button
    if self._guiElements.useItemButton then
        self._connections.UseItemButton = self._guiElements.useItemButton.MouseButton1Click:Connect(function()
            self:_onUseItemClicked()
        end)
    end
    
    Logger:Info("✓ Inventory events connected")
end

function InventoryClient:_getValidImageId(itemName, serverImageId)
    -- Check if server provided a valid ID
    if serverImageId and serverImageId ~= "" and serverImageId ~= "rbxassetid://0" then
        if not string.find(serverImageId, "_IMAGE_ID") and not string.find(serverImageId, "IMAGE_ID") then
            return serverImageId
        end
    end
    
    -- Fall back to client-side image
    local fallbackImage = CLIENT_IMAGE_FALLBACKS[itemName]
    if fallbackImage then
        Logger:Debug("Using client fallback image for " .. itemName)
        return fallbackImage
    end
    
    Logger:Warn("No image found for " .. itemName)
    return "rbxassetid://0"
end

function InventoryClient:_updateInventory(inventoryData, itemConfig)
    self._currentInventory = inventoryData or {}
    itemConfig = itemConfig or {}
    
    Logger:Debug("Updating inventory with " .. self:_countItems(self._currentInventory) .. " items")
    
    -- Track which items we've seen this update
    local seenItems = {}
    
    -- Update existing items and create new ones
    for itemName, quantity in pairs(self._currentInventory) do
        -- Filter out gem items
        if not string.find(itemName, "Gems") then
            seenItems[itemName] = true
            
            if quantity > 0 then
                self:_updateItemFrame(itemName, quantity, itemConfig[itemName])
            else
                self:_removeItemFrame(itemName)
            end
        end
    end
    
    -- Remove items that are no longer in inventory
    for itemName, _ in pairs(self._itemFrames) do
        if not seenItems[itemName] then
            self:_removeItemFrame(itemName)
        end
    end
    
    -- Check if we have any items to display
    local hasDisplayItems = false
    for itemName, quantity in pairs(self._currentInventory) do
        if not string.find(itemName, "Gems") and quantity > 0 then
            hasDisplayItems = true
            break
        end
    end
    
    -- Clear selection if no items
    if not hasDisplayItems then
        self:_clearItemDetails()
    end
    
    -- Update UseItem button
    self:_updateUseItemButton()
    
    Logger:Debug("Inventory update completed")
end

function InventoryClient:_countItems(inventory)
    local count = 0
    for itemName, quantity in pairs(inventory) do
        if not string.find(itemName, "Gems") and quantity > 0 then
            count = count + 1
        end
    end
    return count
end

function InventoryClient:_updateItemFrame(itemName, quantity, config)
    local itemFrame = self._itemFrames[itemName]
    
    if not itemFrame and self._guiElements.itemFrameTemplate then
        -- Clone template
        itemFrame = self._guiElements.itemFrameTemplate:Clone()
        itemFrame.Name = itemName
        itemFrame.Parent = self._guiElements.itemsScrollingFrame
        self._itemFrames[itemName] = itemFrame
        
        -- Store original size for animations
        local originalSize = self._guiElements.itemFrameTemplate.Size
        itemFrame.Size = UDim2.new(0, 0, 0, 0)
        
        -- Set image
        if itemFrame:IsA("ImageLabel") or itemFrame:IsA("ImageButton") then
            local validImageId = self:_getValidImageId(itemName, config and config.image)
            itemFrame.Image = validImageId
        end
        
        -- Find and update child elements
        local itemCount = self:_findFirstChildVariant(itemFrame, {"ItemCount", "Count", "Quantity", "Amount"})
        local itemNameLabel = self:_findFirstChildVariant(itemFrame, {"ItemName", "Name", "Title"})
        local itemRarity = self:_findFirstChildVariant(itemFrame, {"ItemRarity", "Rarity", "Quality"})
        
        if itemNameLabel then
            itemNameLabel.Text = itemName
        end
        
        if itemRarity and config then
            itemRarity.Text = config.rarity:upper()
            itemRarity.TextColor3 = config.color
            
            -- Update border color if it has a stroke
            local stroke = itemFrame:FindFirstChildOfClass("UIStroke")
            if stroke then
                stroke.Color = config.color
            end
        end
        
        -- Make clickable
        local function handleItemClick()
            Logger:Debug("Clicked item: " .. itemName)
            self:_showItemDetails(itemName, quantity, config)
            self:_animateItemClick(itemFrame, config and config.color or Color3.fromRGB(255, 255, 255))
        end
        
        if itemFrame:IsA("GuiButton") then
            itemFrame.MouseButton1Click:Connect(handleItemClick)
        else
            itemFrame.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    handleItemClick()
                end
            end)
        end
        
        -- Animate appearance
        local appearTween = TweenService:Create(
            itemFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = originalSize}
        )
        appearTween:Play()
        
        -- Update quantity display
        if itemCount then
            itemCount.Text = tostring(quantity)
        end
    elseif itemFrame then
        -- Update existing frame
        local itemCount = self:_findFirstChildVariant(itemFrame, {"ItemCount", "Count", "Quantity", "Amount"})
        if itemCount then
            itemCount.Text = tostring(quantity)
        end
    end
    
    -- Update selected item details if this item is currently selected
    if self._selectedItem and self._selectedItem.name == itemName then
        self._selectedItem.quantity = quantity
        self:_showItemDetails(itemName, quantity, config)
    end
end

function InventoryClient:_removeItemFrame(itemName)
    local itemFrame = self._itemFrames[itemName]
    if itemFrame then
        if self._selectedItem and self._selectedItem.name == itemName then
            self:_clearItemDetails()
        end
        
        local removeTween = TweenService:Create(
            itemFrame,
            TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
            {Size = UDim2.new(0, 0, 0, 0)}
        )
        
        removeTween:Play()
        removeTween.Completed:Connect(function()
            itemFrame:Destroy()
            self._itemFrames[itemName] = nil
        end)
    end
end

function InventoryClient:_showItemDetails(itemName, quantity, config)
    if not self._guiElements.itemInfoFrame then return end
    
    -- Show the ItemInfo frame
    self._guiElements.itemInfoFrame.Visible = true
    
    -- Update icon
    if self._guiElements.itemIcon then
        local validImageId = self:_getValidImageId(itemName, config and config.image)
        self._guiElements.itemIcon.Image = validImageId
    end
    
    -- Update name
    if self._guiElements.itemNameLabel then
        self._guiElements.itemNameLabel.Text = itemName .. " (x" .. quantity .. ")"
    end
    
    -- Update rarity
    if self._guiElements.itemRarityLabel then
        if config then
            self._guiElements.itemRarityLabel.Text = config.rarity:upper()
            if config.color then
                self._guiElements.itemRarityLabel.TextColor3 = config.color
            end
        else
            self._guiElements.itemRarityLabel.Text = "UNKNOWN"
            self._guiElements.itemRarityLabel.TextColor3 = Color3.fromRGB(128, 128, 128)
        end
    end
    
    -- Update description
    if self._guiElements.itemDescriptionLabel then
        local description = (config and config.description) or "No description available for this item."
        self._guiElements.itemDescriptionLabel.Text = description
    end
    
    -- Update selected item tracking
    self._selectedItem = {
        name = itemName,
        quantity = quantity,
        config = config
    }
    
    self:_updateUseItemButton()
    
    Logger:Debug("Updated ItemInfo for " .. itemName)
end

function InventoryClient:_clearItemDetails()
    if not self._guiElements.itemInfoFrame then return end
    
    -- Hide the ItemInfo frame
    self._guiElements.itemInfoFrame.Visible = false
    
    if self._guiElements.itemIcon then self._guiElements.itemIcon.Image = "rbxassetid://0" end
    if self._guiElements.itemNameLabel then self._guiElements.itemNameLabel.Text = "" end
    if self._guiElements.itemRarityLabel then 
        self._guiElements.itemRarityLabel.Text = ""
        self._guiElements.itemRarityLabel.TextColor3 = Color3.fromRGB(128, 128, 128)
    end
    if self._guiElements.itemDescriptionLabel then self._guiElements.itemDescriptionLabel.Text = "" end
    
    self._selectedItem = nil
    self:_updateUseItemButton()
    
    Logger:Debug("Cleared item details and hid ItemInfo")
end

function InventoryClient:_updateUseItemButton()
    if not self._guiElements.useItemLabel then return end
    
    if not self._selectedItem then
        self._guiElements.useItemLabel.Text = "Use (0)"
        if self._guiElements.useItemButton then
            self._guiElements.useItemButton.BackgroundColor3 = Color3.fromRGB(149, 165, 166) -- Gray
            self._guiElements.useItemButton.BackgroundTransparency = 0.3
        end
        return
    end
    
    local quantity = self._currentInventory[self._selectedItem.name] or 0
    self._guiElements.useItemLabel.Text = "Use (" .. quantity .. ")"
    
    if self._guiElements.useItemButton then
        if quantity > 0 then
            self._guiElements.useItemButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113) -- Green
            self._guiElements.useItemButton.BackgroundTransparency = 0.1
        else
            self._guiElements.useItemButton.BackgroundColor3 = Color3.fromRGB(149, 165, 166) -- Gray
            self._guiElements.useItemButton.BackgroundTransparency = 0.3
        end
    end
end

function InventoryClient:_onUseItemClicked()
    if not self._selectedItem then
        Logger:Debug("No item selected for use")
        return
    end
    
    local itemName = self._selectedItem.name
    local quantity = self._currentInventory[itemName] or 0
    
    if quantity <= 0 then
        Logger:Debug("No " .. itemName .. " to use")
        self:_animateButtonError(self._guiElements.useItemButton)
        return
    end
    
    Logger:Info("Using item: " .. itemName)
    self:_animateButtonClick(self._guiElements.useItemButton)
    self._remoteEvents.UseItem:FireServer(itemName)
end

function InventoryClient:_updateActiveBoosts(boosts)
    self._activeBoosts = boosts or {}
    
    -- Log active boosts for debugging
    for boostType, boost in pairs(self._activeBoosts) do
        local timeRemaining = boost.endTime - tick()
        if timeRemaining > 0 then
            Logger:Debug(string.format("Active boost: %s (%.1fx, %ds left)", boostType, boost.multiplier, math.floor(timeRemaining)))
        end
    end
end

function InventoryClient:_animateButtonClick(button)
    if not button then return end
    local originalSize = button.Size
    local scaledSize = UDim2.new(
        originalSize.X.Scale * 0.95, 
        originalSize.X.Offset * 0.95, 
        originalSize.Y.Scale * 0.95, 
        originalSize.Y.Offset * 0.95
    )
    local clickTween = TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Size = scaledSize})
    clickTween:Play()
    clickTween.Completed:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Back), {Size = originalSize}):Play()
    end)
end

function InventoryClient:_animateButtonError(button)
    if not button then return end
    local originalColor = button.BackgroundColor3
    local originalTransparency = button.BackgroundTransparency
    
    local errorTween = TweenService:Create(
        button,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            BackgroundColor3 = Color3.fromRGB(231, 76, 60), -- Red
            BackgroundTransparency = 0.1
        }
    )
    
    errorTween:Play()
    errorTween.Completed:Connect(function()
        task.wait(0.3)
        local returnTween = TweenService:Create(
            button,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                BackgroundColor3 = originalColor,
                BackgroundTransparency = originalTransparency
            }
        )
        returnTween:Play()
    end)
end

function InventoryClient:_animateItemClick(itemFrame, color)
    if not itemFrame then return end
    
    local clickEffect = Instance.new("Frame")
    clickEffect.Size = UDim2.new(1, 0, 1, 0)
    clickEffect.Position = UDim2.new(0, 0, 0, 0)
    clickEffect.BackgroundColor3 = color
    clickEffect.BackgroundTransparency = 0.7
    clickEffect.BorderSizePixel = 0
    clickEffect.ZIndex = 10
    clickEffect.Parent = itemFrame
    
    local clickCorner = Instance.new("UICorner")
    clickCorner.CornerRadius = UDim.new(0, 10)
    clickCorner.Parent = clickEffect
    
    local clickTween = TweenService:Create(
        clickEffect,
        TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 1}
    )
    clickTween:Play()
    clickTween.Completed:Connect(function()
        clickEffect:Destroy()
    end)
end

function InventoryClient:GetActiveBoosts()
    return self._activeBoosts
end

function InventoryClient:GetCurrentInventory()
    return self._currentInventory
end

function InventoryClient:Cleanup()
    Logger:Info("InventoryClient shutting down...")
    
    for _, connection in pairs(self._connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    
    Logger:Info("✓ InventoryClient shutdown complete")
end

return InventoryClient