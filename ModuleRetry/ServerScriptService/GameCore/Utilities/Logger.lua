local Logger = {}

local LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

local CURRENT_LOG_LEVEL = LOG_LEVELS.INFO
local LOG_PREFIX = "[GameCore]"

local function formatMessage(level, message)
    local timestamp = os.date("%H:%M:%S", tick())
    local levelName = ""
    
    for name, value in pairs(LOG_LEVELS) do
        if value == level then
            levelName = name
            break
        end
    end
    
    return string.format("[%s] %s [%s]: %s", timestamp, LOG_PREFIX, levelName, message)
end

local function shouldLog(level)
    return level >= CURRENT_LOG_LEVEL
end

function Logger:SetLogLevel(level)
    if LOG_LEVELS[level] then
        CURRENT_LOG_LEVEL = LOG_LEVELS[level]
    end
end

function Logger:Debug(message)
    if shouldLog(LOG_LEVELS.DEBUG) then
        print(formatMessage(LOG_LEVELS.DEBUG, message))
    end
end

function Logger:Info(message)
    if shouldLog(LOG_LEVELS.INFO) then
        print(formatMessage(LOG_LEVELS.INFO, message))
    end
end

function Logger:Warn(message)
    if shouldLog(LOG_LEVELS.WARN) then
        warn(formatMessage(LOG_LEVELS.WARN, message))
    end
end

function Logger:Error(message)
    if shouldLog(LOG_LEVELS.ERROR) then
        error(formatMessage(LOG_LEVELS.ERROR, message), 0)
    end
end

return Logger