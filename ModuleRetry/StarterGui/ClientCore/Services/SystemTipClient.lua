local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local SystemTipClient = {}
SystemTipClient.__index = SystemTipClient

function SystemTipClient.new()
    local self = setmetatable({}, SystemTipClient)
    self:_initialize()
    return self
end

function SystemTipClient:_initialize()
    Logger:Info("SystemTipClient initializing...")
    self:_setupRemoteEvent()
    Logger:Info("✓ SystemTipClient initialized")
end

function SystemTipClient:_setupRemoteEvent()
    task.spawn(function()
        local shared = ReplicatedStorage:WaitForChild("Shared", 10)
        if shared then
            local remoteEvents = shared:WaitForChild("RemoteEvents", 5)
            if remoteEvents then
                local systemTipEvent = remoteEvents:WaitForChild("SystemTip", 5)
                if systemTipEvent then
                    systemTipEvent.OnClientEvent:Connect(function(tip)
                        self:_displayTip(tip)
                    end)
                    Logger:Info("✓ Connected to SystemTip RemoteEvent")
                else
                    Logger:Warn("SystemTip RemoteEvent not found")
                end
            end
        end
    end)
end

function SystemTipClient:_displayTip(tip)
    -- Try TextChatService first (new chat system) with yellow color
    local success1, result1 = pcall(function()
        local TextChatService = game:GetService("TextChatService")
        local generalChannel = TextChatService:FindFirstChild("TextChannels") 
        if generalChannel then
            generalChannel = generalChannel:FindFirstChild("RBXGeneral")
            if generalChannel then
                -- Create a rich text version with yellow color
                local yellowTip = '<font color="rgb(255, 255, 0)">' .. tip .. '</font>'
                generalChannel:DisplaySystemMessage(yellowTip)
                return true
            end
        end
        return false
    end)
    
    if success1 and result1 then
        Logger:Debug("Displayed system tip via TextChatService: " .. tip)
        return
    end
    
    -- Fallback to SetCore (legacy chat system) 
    local success2, result2 = pcall(function()
        StarterGui:SetCore("ChatMakeSystemMessage", {
            Text = tip,
            Color = Color3.fromRGB(255, 255, 0), -- Yellow
            Font = Enum.Font.GothamBold,
            FontSize = Enum.FontSize.Size18
        })
    end)
    
    if success2 then
        Logger:Debug("Displayed system tip via SetCore: " .. tip)
    else
        Logger:Warn("Both TextChatService and SetCore failed. TextChatService: " .. tostring(result1) .. ", SetCore: " .. tostring(result2))
    end
end

function SystemTipClient:Cleanup()
    -- Nothing to clean up for this simple client
end

return SystemTipClient