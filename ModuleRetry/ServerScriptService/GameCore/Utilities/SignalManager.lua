local SignalManager = {}
SignalManager.__index = SignalManager

local Signal = {}
Signal.__index = Signal

function Signal.new()
    local self = setmetatable({}, Signal)
    self._connections = {}
    return self
end

function Signal:Connect(callback)
    local connection = {
        callback = callback,
        connected = true
    }
    
    table.insert(self._connections, connection)
    
    return {
        Disconnect = function()
            connection.connected = false
            for i, conn in ipairs(self._connections) do
                if conn == connection then
                    table.remove(self._connections, i)
                    break
                end
            end
        end
    }
end

-- FIXED: Better argument handling for variable number of parameters
function Signal:Fire(...)
    local args = {...}
    local argCount = select("#", ...)
    
    for _, connection in ipairs(self._connections) do
        if connection.connected then
            spawn(function()
                if argCount == 0 then
                    connection.callback()
                elseif argCount == 1 then
                    connection.callback(args[1])
                elseif argCount == 2 then
                    connection.callback(args[1], args[2])
                elseif argCount == 3 then
                    connection.callback(args[1], args[2], args[3])
                else
                    connection.callback(unpack(args, 1, argCount))
                end
            end)
        end
    end
end

function Signal:Destroy()
    for _, connection in ipairs(self._connections) do
        connection.connected = false
    end
    self._connections = {}
end

function SignalManager.new()
    return Signal.new()
end

return SignalManager