local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientLogger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local LeaderboardClient = {}
LeaderboardClient.__index = LeaderboardClient

local player = Players.LocalPlayer

function LeaderboardClient.new()
	local self = setmetatable({}, LeaderboardClient)
	self._connections = {}
	self._leaderboardData = {}
	self._playerEntries = {}
	self._surfaceGui = nil
	self._scrollFrame = nil
	self:_initialize()
	return self
end

function LeaderboardClient:_initialize()
	if RunService:IsClient() then
		self:_setupRemoteEvents()
		self:_createLeaderboardUI()
		self:_requestInitialData()
		
		ClientLogger:Info("LeaderboardClient initialized successfully")
	end
end

function LeaderboardClient:_setupRemoteEvents()
	-- Wait for RemoteEvents to be created
	spawn(function()
		local shared = ReplicatedStorage:WaitForChild("Shared")
		local remoteEvents = shared:WaitForChild("RemoteEvents")
		local leaderboardEvents = remoteEvents:WaitForChild("LeaderboardEvents")
		
		local leaderboardDataUpdated = leaderboardEvents:WaitForChild("LeaderboardDataUpdated")
		local getLeaderboardData = leaderboardEvents:WaitForChild("GetLeaderboardData")
		
		self._leaderboardDataUpdated = leaderboardDataUpdated
		self._getLeaderboardData = getLeaderboardData
		
		-- Connect to data updates
		self._connections.LeaderboardDataUpdated = leaderboardDataUpdated.OnClientEvent:Connect(function(leaderboardType, data)
			if leaderboardType == "spores" then
				self:_updateLeaderboardDisplay(data)
			end
		end)
		
		ClientLogger:Debug("LeaderboardClient RemoteEvents connected")
	end)
end

function LeaderboardClient:_requestInitialData()
	spawn(function()
		wait(1) -- Give time for RemoteEvents to set up
		if self._getLeaderboardData then
			local success, data = pcall(function()
				return self._getLeaderboardData:InvokeServer("spores")
			end)
			
			if success and data then
				self:_updateLeaderboardDisplay(data)
			else
				ClientLogger:Warn("Failed to get initial leaderboard data")
			end
		end
	end)
end

function LeaderboardClient:_createLeaderboardUI()
	-- Wait for MostMoney part to exist
	spawn(function()
		local workspace = game:GetService("Workspace")
		local moneyLeaderboard = workspace:WaitForChild("MoneyLeaderboard", 30)
		if not moneyLeaderboard then
			ClientLogger:Error("MoneyLeaderboard folder not found in workspace")
			return
		end
		
		local mostMoneyPart = moneyLeaderboard:WaitForChild("MostMoney", 30)
		if not mostMoneyPart then
			ClientLogger:Error("MostMoney part not found in MoneyLeaderboard")
			return
		end
		
		-- Create Billboard GUI above the part
		local billboardGui = Instance.new("BillboardGui")
		billboardGui.Name = "LeaderboardTitle"
		billboardGui.Size = UDim2.new(0, 500, 0, 120)
		billboardGui.StudsOffset = Vector3.new(0, 12, 0)
		billboardGui.LightInfluence = 0 -- Prevent scaling with distance
		billboardGui.AlwaysOnTop = true -- Keep in front of everything
		billboardGui.Parent = mostMoneyPart
		
		-- SPORES title
		local sporesTitle = Instance.new("TextLabel")
		sporesTitle.Name = "SporesTitle"
		sporesTitle.Size = UDim2.new(1, 0, 0, 60)
		sporesTitle.Position = UDim2.new(0, 0, 0, 0)
		sporesTitle.BackgroundTransparency = 1
		sporesTitle.Text = "SPORES"
		sporesTitle.TextColor3 = Color3.fromRGB(220, 50, 50)
		sporesTitle.TextSize = 48
		sporesTitle.Font = Enum.Font.FredokaOne
		sporesTitle.TextXAlignment = Enum.TextXAlignment.Center
		sporesTitle.Parent = billboardGui
		
		-- Add stroke to SPORES title
		local sporesStroke = Instance.new("UIStroke")
		sporesStroke.Color = Color3.fromRGB(0, 0, 0)
		sporesStroke.Thickness = 4
		sporesStroke.Parent = sporesTitle
		
		-- Global Leaderboard subtitle
		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.Name = "SubtitleLabel"
		subtitleLabel.Size = UDim2.new(1, 0, 0, 40)
		subtitleLabel.Position = UDim2.new(0, 0, 0, 55)
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Text = "Global Leaderboard"
		subtitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		subtitleLabel.TextSize = 28
		subtitleLabel.Font = Enum.Font.FredokaOne
		subtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
		subtitleLabel.Parent = billboardGui
		
		-- Add stroke to subtitle
		local subtitleStroke = Instance.new("UIStroke")
		subtitleStroke.Color = Color3.fromRGB(0, 0, 0)
		subtitleStroke.Thickness = 4
		subtitleStroke.Parent = subtitleLabel
		
		-- Create SurfaceGui
		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name = "LeaderboardGui"
		surfaceGui.Face = Enum.NormalId.Front
		surfaceGui.CanvasSize = Vector2.new(800, 600)
		surfaceGui.Parent = mostMoneyPart
		self._surfaceGui = surfaceGui
		
		-- ScrollingFrame for leaderboard entries with dark transparent red background
		local scrollFrame = Instance.new("ScrollingFrame")
		scrollFrame.Name = "ScrollFrame"
		scrollFrame.Size = UDim2.new(1, -60, 1, -60) -- Padding from edges
		scrollFrame.Position = UDim2.new(0, 30, 0, 30)
		scrollFrame.BackgroundColor3 = Color3.fromRGB(150, 30, 30) -- Darker red
		scrollFrame.BackgroundTransparency = 0.5 -- Less transparent
		scrollFrame.BorderSizePixel = 0
		scrollFrame.ScrollBarThickness = 8
		scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(150, 30, 30)
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		scrollFrame.Parent = surfaceGui
		self._scrollFrame = scrollFrame
		
		local scrollCorner = Instance.new("UICorner")
		scrollCorner.CornerRadius = UDim.new(0, 15)
		scrollCorner.Parent = scrollFrame
		
		-- Layout for entries
		local listLayout = Instance.new("UIListLayout")
		listLayout.Name = "ListLayout"
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UDim.new(0, 10) -- Small gaps between players
		listLayout.Parent = scrollFrame
		
		-- Padding for scroll frame
		local scrollPadding = Instance.new("UIPadding")
		scrollPadding.PaddingLeft = UDim.new(0, 20)
		scrollPadding.PaddingRight = UDim.new(0, 20)
		scrollPadding.PaddingTop = UDim.new(0, 20)
		scrollPadding.PaddingBottom = UDim.new(0, 20)
		scrollPadding.Parent = scrollFrame
		
		ClientLogger:Debug("Leaderboard UI created successfully")
	end)
end

function LeaderboardClient:_formatSpores(amount)
	if amount >= 1000000000 then
		return string.format("%.2fB", amount / 1000000000)
	elseif amount >= 1000000 then
		return string.format("%.2fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("%.2fK", amount / 1000)
	else
		return string.format("%.0f", amount)
	end
end

function LeaderboardClient:_formatSporesLong(amount)
	-- Format with commas for full display
	local formatted = tostring(amount)
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then
			break
		end
	end
	return formatted
end

function LeaderboardClient:_createLeaderboardEntry(playerData, rank)
	-- Get template frames from ReplicatedStorage
	local replicatedStorage = game:GetService("ReplicatedStorage")
	local leaderboardStates = replicatedStorage:WaitForChild("LeaderboardStates")
	local normalTemplate = leaderboardStates:WaitForChild("NormalState")
	local activeTemplate = leaderboardStates:WaitForChild("ActiveState")
	
	-- Clone the normal state as the base
	local entryFrame = normalTemplate:Clone()
	entryFrame.Name = "Entry_" .. playerData.Name
	entryFrame.LayoutOrder = rank
	
	-- Get references to normal state elements
	local normalElements = {
		avatarFrame = entryFrame:WaitForChild("AvatarFrame"),
		avatarImage = entryFrame.AvatarFrame:WaitForChild("AvatarImage"),
		displayName = entryFrame:WaitForChild("DisplayNameLabel"),
		placement = entryFrame:WaitForChild("PlacementLabel"),
		amount = entryFrame:WaitForChild("AmountLabel"),
		hoverButton = entryFrame:WaitForChild("HoverButton")
	}
	
	-- Clone active state elements (initially hidden)
	local activeElements = {
		avatarFrame = activeTemplate.AvatarFrame:Clone(),
		avatarImage = activeTemplate.AvatarFrame.AvatarImage:Clone(),
		displayName = activeTemplate.DisplayNameLabel:Clone(),
		username = activeTemplate.UsernameLabel:Clone(),
		hoverPosition = activeTemplate.HoverPositionLabel:Clone(),
		fullAmount = activeTemplate.FullAmountLabel:Clone()
	}
	
	-- Add active elements to entry frame (hidden initially)
	for _, element in pairs(activeElements) do
		if element ~= activeElements.avatarImage then
			element.Parent = entryFrame
			element.Visible = false
			element.ZIndex = 1 -- Keep below hover button
		end
	end
	activeElements.avatarImage.Parent = activeElements.avatarFrame
	activeElements.avatarImage.ZIndex = 1
	
	-- Store original sizes for transition
	local normalSize = entryFrame.Size
	local activeSize = activeTemplate.Size
	
	-- Store original positions/sizes for all elements
	local normalStates = {}
	local activeStates = {}
	
	for name, element in pairs(normalElements) do
		if element and element ~= normalElements.hoverButton then
			normalStates[name] = {
				Size = element.Size,
				Position = element.Position,
				Visible = element.Visible
			}
		end
	end
	
	for name, element in pairs(activeElements) do
		if element then
			activeStates[name] = {
				Size = element.Size,
				Position = element.Position,
				Visible = true
			}
		end
	end
	
	-- Set up player data
	normalElements.avatarImage.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. playerData.UserId .. "&width=150&height=150&format=png"
	activeElements.avatarImage.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. playerData.UserId .. "&width=150&height=150&format=png"
	
	normalElements.displayName.Text = playerData.DisplayName or playerData.Name
	activeElements.displayName.Text = playerData.DisplayName or playerData.Name
	activeElements.username.Text = "@" .. playerData.Name
	
	normalElements.placement.Text = "#" .. rank
	activeElements.hoverPosition.Text = "#" .. rank
	
	normalElements.amount.Text = self:_formatSpores(playerData.Amount)
	activeElements.fullAmount.Text = self:_formatSporesLong(playerData.Amount)
	
	-- Apply spore-specific colors and ensure text visibility
	normalElements.amount.TextColor3 = Color3.fromRGB(200, 40, 40)  -- Red spores amount
	normalElements.placement.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White placement
	activeElements.fullAmount.TextColor3 = Color3.fromRGB(200, 40, 40)  -- Red spores amount
	activeElements.hoverPosition.TextColor3 = Color3.fromRGB(255, 255, 170)  -- Light yellow placement
	
	-- Set spore icon
	local icon = activeElements.fullAmount:FindFirstChild("Icon")
	if icon then
		icon.Image = "rbxassetid://94688317743947"
	end
	
	-- Ensure all active text elements are fully visible (not transparent)
	activeElements.fullAmount.TextTransparency = 0
	activeElements.hoverPosition.TextTransparency = 0
	activeElements.displayName.TextTransparency = 0
	activeElements.username.TextTransparency = 0
	
	-- Ensure avatar image is visible
	activeElements.avatarImage.ImageTransparency = 0
	
	-- Ensure hover button stays on top and covers entire entry
	normalElements.hoverButton.ZIndex = 10
	normalElements.hoverButton.Size = UDim2.new(1, 0, 1, 0)
	normalElements.hoverButton.Position = UDim2.new(0, 0, 0, 0)
	normalElements.hoverButton.BackgroundTransparency = 1
	normalElements.hoverButton.Text = ""
	normalElements.hoverButton.AutoButtonColor = false
	
	-- Animation settings
	local bounceInfo = TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	
	-- Prevent rapid firing
	local isHovered = false
	local isAnimating = false
	
	-- Hover function
	local function startHover()
		if isHovered or isAnimating then return end
		isHovered = true
		isAnimating = true
		
		-- Step 1: Instant swap to active layout (at normal size)
		for _, element in pairs(normalElements) do
			if element and element ~= normalElements.hoverButton then
				element.Visible = false
			end
		end
		
		for _, element in pairs(activeElements) do
			if element then
				element.Visible = true
			end
		end
		
		-- Step 2: Smooth transition to full active size
		local frameTween = TweenService:Create(entryFrame, bounceInfo, {Size = activeSize})
		frameTween:Play()
		
		-- Reset animation flag when complete
		frameTween.Completed:Connect(function()
			isAnimating = false
		end)
	end
	
	-- Leave hover function
	local function endHover()
		if not isHovered or isAnimating then return end
		isHovered = false
		isAnimating = true
		
		-- Step 1: Instant swap back to normal layout (at current hover size)
		for _, element in pairs(activeElements) do
			if element then
				element.Visible = false
			end
		end
		
		for _, element in pairs(normalElements) do
			if element and element ~= normalElements.hoverButton then
				element.Visible = true
			end
		end
		
		-- Step 2: Smooth transition back to normal size
		local frameTween = TweenService:Create(entryFrame, bounceInfo, {Size = normalSize})
		frameTween:Play()
		
		frameTween.Completed:Connect(function()
			isAnimating = false
		end)
	end
	
	-- Connect to hover button (primary method)
	normalElements.hoverButton.MouseEnter:Connect(startHover)
	normalElements.hoverButton.MouseLeave:Connect(endHover)
	
	-- Connect to entry frame as backup (secondary method)
	entryFrame.MouseEnter:Connect(startHover)
	entryFrame.MouseLeave:Connect(endHover)
	
	return entryFrame
end

function LeaderboardClient:_updateLeaderboardDisplay(data)
	if not self._scrollFrame then
		return
	end
	
	-- Clear existing entries
	for _, entry in pairs(self._playerEntries) do
		entry:Destroy()
	end
	self._playerEntries = {}
	
	self._leaderboardData = data
	
	-- Create entries for each player with fade-in animation
	for i, playerData in ipairs(self._leaderboardData) do
		local entry = self:_createLeaderboardEntry(playerData, i)
		entry.Parent = self._scrollFrame
		
		-- Start completely transparent
		entry.ImageTransparency = 1
		
		-- Make only VISIBLE child elements transparent initially (skip hidden active state elements)
		for _, child in pairs(entry:GetDescendants()) do
			if child:IsA("TextLabel") and child.Visible then
				child.TextTransparency = 1
			elseif child:IsA("ImageLabel") and child.Visible then
				child.ImageTransparency = 1
			end
		end
		
		table.insert(self._playerEntries, entry)
		
		-- Stagger the fade-in animations (0.3 seconds apart)
		spawn(function()
			wait((i - 1) * 0.3)
			
			-- Fade in the background
			local backgroundFade = TweenService:Create(entry, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = 0
			})
			backgroundFade:Play()
			
			-- Fade in all text and image elements
			for _, child in pairs(entry:GetDescendants()) do
				if child:IsA("TextLabel") and child.Visible then
					local textFade = TweenService:Create(child, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						TextTransparency = 0
					})
					textFade:Play()
				elseif child:IsA("ImageLabel") then
					local imageFade = TweenService:Create(child, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						ImageTransparency = 0
					})
					imageFade:Play()
				end
			end
		end)
	end
	
	-- Update canvas size
	local listLayout = self._scrollFrame:FindFirstChild("ListLayout")
	if listLayout then
		self._scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 30)
	end
	
	ClientLogger:Debug(string.format("Updated leaderboard display with %d players", #self._leaderboardData))
end

function LeaderboardClient:Cleanup()
	for connectionName, connection in pairs(self._connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._connections = {}
	
	if self._surfaceGui then
		self._surfaceGui:Destroy()
	end
	
	ClientLogger:Info("LeaderboardClient cleaned up")
end

return LeaderboardClient