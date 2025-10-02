local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientLogger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local StarterPackService = {}
StarterPackService.__index = StarterPackService

local player = Players.LocalPlayer

function StarterPackService.new()
	local self = setmetatable({}, StarterPackService)
	self._connections = {}
	self._wiggleTween = nil
	self._timerConnection = nil
	self._startTime = tick()
	self._duration = 45 * 60 -- 45 minutes in seconds
	self._isDestroyed = false
	
	-- UI references
	self._starterPackButton = nil
	self._timerLabel = nil
	self._starterPackGui = nil
	self._exitButton = nil
	self._verifyButton = nil
	
	-- Store original frame properties for animation
	self._originalSize = nil
	self._originalPosition = nil
	
	self:_initialize()
	return self
end

function StarterPackService:_initialize()
	if RunService:IsClient() then
		spawn(function()
			self:_findExistingUI()
			if self._starterPackButton then
				self:_setupTimer()
				self:_startWiggleAnimation()
				self:_startTimer()
				self:_connectButtons()
			end
		end)
		
		ClientLogger:Info("StarterPackService initialized successfully")
	end
end

function StarterPackService:_findExistingUI()
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Wait for and find MenuButtons GUI
	local menuButtonsGui = playerGui:WaitForChild("MenuButtons", 10)
	if not menuButtonsGui then
		ClientLogger:Error("MenuButtons GUI not found")
		return
	end
	
	-- Find Container
	local container = menuButtonsGui:WaitForChild("Container", 5)
	if not container then
		ClientLogger:Error("Container not found in MenuButtons")
		return
	end
	
	-- Find StarterPack button
	local starterPackButton = container:WaitForChild("StarterPack", 5)
	if not starterPackButton then
		ClientLogger:Error("StarterPack button not found in Container")
		return
	end
	
	self._starterPackButton = starterPackButton
	ClientLogger:Info("Found existing StarterPack button")
	
	-- Wait for and find StarterPack GUI
	local starterPackGui = playerGui:WaitForChild("StarterPack", 10)
	if not starterPackGui then
		ClientLogger:Error("StarterPack GUI not found")
		return
	end
	
	self._starterPackGui = starterPackGui
	ClientLogger:Info("Found existing StarterPack GUI")
	
	-- Find the nested structure: StarterPack/Frame/ImageLabel/ExitBTN
	local frame = starterPackGui:WaitForChild("Frame", 5)
	if frame then
		-- Store original frame properties for animations
		self._originalSize = frame.Size
		self._originalPosition = frame.Position
		ClientLogger:Info(string.format("Stored original frame properties - Size: %s, Position: %s", tostring(self._originalSize), tostring(self._originalPosition)))
		
		local imageLabel = frame:WaitForChild("ImageLabel", 5)
		if imageLabel then
			local exitButton = imageLabel:WaitForChild("ExitBTN", 5)
			if exitButton then
				self._exitButton = exitButton
				ClientLogger:Info("Found existing ExitBTN")
			else
				ClientLogger:Error("ExitBTN not found in ImageLabel")
			end
			
			local verifyButton = imageLabel:WaitForChild("VerifyBTN", 5)
			if verifyButton then
				self._verifyButton = verifyButton
				ClientLogger:Info("Found existing VerifyBTN")
			else
				ClientLogger:Error("VerifyBTN not found in ImageLabel")
			end
		else
			ClientLogger:Error("ImageLabel not found in Frame")
		end
	else
		ClientLogger:Error("Frame not found in StarterPack GUI")
	end
end

function StarterPackService:_setupTimer()
	if not self._starterPackButton then return end
	
	-- Look for existing Timer label or create one
	local timerLabel = self._starterPackButton:FindFirstChild("Timer")
	if not timerLabel then
		-- Create timer label
		timerLabel = Instance.new("TextLabel")
		timerLabel.Name = "Timer"
		timerLabel.Size = UDim2.new(1, 0, 0.3, 0)
		timerLabel.Position = UDim2.new(0, 0, 0.7, 0)
		timerLabel.BackgroundTransparency = 1
		timerLabel.Text = "45m 00s"
		timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		timerLabel.TextSize = 14
		timerLabel.Font = Enum.Font.FredokaOne
		timerLabel.TextXAlignment = Enum.TextXAlignment.Center
		timerLabel.TextYAlignment = Enum.TextYAlignment.Center
		timerLabel.Parent = self._starterPackButton
		
		-- Add text stroke
		local timerStroke = Instance.new("UIStroke")
		timerStroke.Color = Color3.fromRGB(0, 0, 0)
		timerStroke.Thickness = 2
		timerStroke.Parent = timerLabel
		
		ClientLogger:Info("Created timer label for StarterPack button")
	end
	
	self._timerLabel = timerLabel
end

function StarterPackService:_startWiggleAnimation()
	if not self._starterPackButton then return end
	
	-- Store original properties
	local originalRotation = self._starterPackButton.Rotation or 0
	local originalSize = self._starterPackButton.Size
	
	-- Create wiggle animation with fast twitches
	local function createWiggle()
		if self._isDestroyed then return end
		
		-- First twitch
		local twitch1 = TweenService:Create(
			self._starterPackButton,
			TweenInfo.new(0.05, Enum.EasingStyle.Linear),
			{Rotation = originalRotation + 6}
		)
		
		-- Second twitch (opposite direction)
		local twitch2 = TweenService:Create(
			self._starterPackButton,
			TweenInfo.new(0.05, Enum.EasingStyle.Linear),
			{Rotation = originalRotation - 6}
		)
		
		-- Third twitch
		local twitch3 = TweenService:Create(
			self._starterPackButton,
			TweenInfo.new(0.05, Enum.EasingStyle.Linear),
			{Rotation = originalRotation + 4}
		)
		
		-- Return to normal
		local returnTween = TweenService:Create(
			self._starterPackButton,
			TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Rotation = originalRotation}
		)
		
		-- Play twitches in sequence
		twitch1:Play()
		twitch1.Completed:Connect(function()
			if self._isDestroyed then return end
			twitch2:Play()
			twitch2.Completed:Connect(function()
				if self._isDestroyed then return end
				twitch3:Play()
				twitch3.Completed:Connect(function()
					if self._isDestroyed then return end
					returnTween:Play()
					
					-- Schedule next wiggle sequence
					returnTween.Completed:Connect(function()
						if not self._isDestroyed then
							wait(math.random(300, 600) / 100) -- 3-6 seconds
							createWiggle()
						end
					end)
				end)
			end)
		end)
	end
	
	-- Start first wiggle after a short delay
	spawn(function()
		wait(1)
		createWiggle()
	end)
	
	ClientLogger:Debug("Wiggle animation started for existing button")
end

function StarterPackService:_startTimer()
	self._timerConnection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - self._startTime
		local remaining = self._duration - elapsed
		
		if remaining <= 0 then
			self:_destroyStarterPack()
			return
		end
		
		self:_updateTimerDisplay(remaining)
	end)
	
	ClientLogger:Debug("Timer started")
end

function StarterPackService:_updateTimerDisplay(remainingSeconds)
	if not self._timerLabel then return end
	
	local minutes = math.floor(remainingSeconds / 60)
	local seconds = math.floor(remainingSeconds % 60)
	
	self._timerLabel.Text = string.format("%dm %02ds", minutes, seconds)
	
	-- Change color as time runs out
	if remainingSeconds < 300 then -- Last 5 minutes
		self._timerLabel.TextColor3 = Color3.fromRGB(255, 100, 100) -- Red warning
	elseif remainingSeconds < 900 then -- Last 15 minutes
		self._timerLabel.TextColor3 = Color3.fromRGB(255, 200, 100) -- Orange warning
	else
		self._timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- Normal white
	end
end

function StarterPackService:_connectButtons()
	if not self._starterPackButton or not self._starterPackGui then return end
	
	-- Connect StarterPack button to open GUI
	local buttonConnection = self._starterPackButton.MouseButton1Click:Connect(function()
		self:_openStarterPackGUI()
	end)
	table.insert(self._connections, buttonConnection)
	
	-- Connect Exit button if it exists
	if self._exitButton then
		local exitConnection = self._exitButton.MouseButton1Click:Connect(function()
			self:_closeStarterPackGUI()
		end)
		table.insert(self._connections, exitConnection)
	end
	
	-- Connect Verify button to prompt starter pack dev product
	if self._verifyButton then
		local verifyConnection = self._verifyButton.MouseButton1Click:Connect(function()
			self:_promptStarterPackPurchase()
		end)
		table.insert(self._connections, verifyConnection)
		ClientLogger:Info("VerifyBTN connected to starter pack purchase")
	end
	
	ClientLogger:Debug("Button connections established")
end

function StarterPackService:_promptStarterPackPurchase()
	ClientLogger:Info("VerifyBTN clicked - prompting starter pack purchase")
	
	-- Use MarketplaceService to prompt the starter pack dev product
	local MarketplaceService = game:GetService("MarketplaceService")
	local STARTER_PACK_PRODUCT_ID = 3413686209
	
	local success, result = pcall(function()
		MarketplaceService:PromptProductPurchase(player, STARTER_PACK_PRODUCT_ID)
	end)
	
	if success then
		ClientLogger:Info(string.format("Prompted starter pack purchase (ID: %d)", STARTER_PACK_PRODUCT_ID))
	else
		ClientLogger:Error(string.format("Failed to prompt starter pack purchase: %s", tostring(result)))
	end
end

function StarterPackService:_destroyStarterPack()
	if self._isDestroyed then return end
	
	self._isDestroyed = true
	
	-- Stop timer
	if self._timerConnection then
		self._timerConnection:Disconnect()
		self._timerConnection = nil
	end
	
	-- Close GUI if open
	if self._starterPackGui then
		self._starterPackGui.Enabled = false
	end
	
	-- Animate button destruction
	if self._starterPackButton then
		local destroyTween = TweenService:Create(
			self._starterPackButton,
			TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{
				Size = UDim2.new(0, 0, 0, 0),
				Rotation = 180,
				BackgroundTransparency = 1
			}
		)
		
		destroyTween:Play()
		destroyTween.Completed:Connect(function()
			if self._starterPackButton then
				self._starterPackButton:Destroy()
				self._starterPackButton = nil
			end
		end)
	end
	
	ClientLogger:Info("StarterPack destroyed after 45 minutes")
end

function StarterPackService:_openStarterPackGUI()
	if not self._starterPackGui or self._isDestroyed then return end
	
	ClientLogger:Info("Opening StarterPack GUI...")
	self._starterPackGui.Enabled = true
	
	-- Find the main frame for animation
	local mainFrame = self._starterPackGui:FindFirstChild("Frame")
	if mainFrame and self._originalSize and self._originalPosition then
		ClientLogger:Info(string.format("Using stored original properties - Size: %s, Position: %s", tostring(self._originalSize), tostring(self._originalPosition)))
		
		-- Start from zero size
		mainFrame.Size = UDim2.new(0, 0, 0, 0)
		mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		
		-- Animate opening using stored original properties
		local openTween = TweenService:Create(
			mainFrame,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Size = self._originalSize,
				Position = self._originalPosition
			}
		)
		
		openTween:Play()
		ClientLogger:Info("StarterPack animation started")
	else
		if not mainFrame then
			ClientLogger:Error("Frame not found in StarterPack GUI!")
		else
			ClientLogger:Error("Original properties not stored - cannot animate!")
		end
	end
	
	ClientLogger:Debug("StarterPack GUI opened")
end

function StarterPackService:_closeStarterPackGUI()
	if not self._starterPackGui then return end
	
	local mainFrame = self._starterPackGui:FindFirstChild("Frame")
	if mainFrame then
		local closeTween = TweenService:Create(
			mainFrame,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{
				Size = UDim2.new(0, 0, 0, 0),
				Position = UDim2.new(0.5, 0, 0.5, 0)
			}
		)
		
		closeTween:Play()
		closeTween.Completed:Connect(function()
			self._starterPackGui.Enabled = false
		end)
	else
		-- Fallback - just disable the GUI
		self._starterPackGui.Enabled = false
	end
	
	ClientLogger:Debug("StarterPack GUI closed")
end

function StarterPackService:GetRemainingTime()
	if self._isDestroyed then return 0 end
	
	local elapsed = tick() - self._startTime
	return math.max(0, self._duration - elapsed)
end

function StarterPackService:IsDestroyed()
	return self._isDestroyed
end

function StarterPackService:Cleanup()
	self._isDestroyed = true
	
	-- Disconnect timer
	if self._timerConnection then
		self._timerConnection:Disconnect()
		self._timerConnection = nil
	end
	
	-- Clean up connections
	for _, connection in pairs(self._connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._connections = {}
	
	ClientLogger:Info("StarterPackService cleaned up")
end

return StarterPackService