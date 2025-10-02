local Validator = {}

function Validator:IsPositiveNumber(value)
    return type(value) == "number" and value >= 0 and value == value and value ~= math.huge
end

function Validator:IsValidInteger(value)
    return type(value) == "number" and value == math.floor(value) and value >= 0 and value ~= math.huge
end

function Validator:IsValidDecimalCurrency(value)
    -- Allows decimal numbers with up to 2 decimal places for currency
    return type(value) == "number" and value >= 0 and value == value and value ~= math.huge
end

function Validator:RoundToTwoDecimals(value)
    return math.floor(value * 100 + 0.5) / 100
end

function Validator:IsValidTimestamp(value)
    return type(value) == "number" and value >= 0 and value <= tick() + 86400
end

function Validator:IsValidPlotId(plotId)
    return type(plotId) == "number" and plotId >= 1 and plotId <= 6 and plotId == math.floor(plotId)
end

function Validator:DeepCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = self:DeepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

function Validator:ValidatePlayerData(data, defaultData)
    if type(data) ~= "table" then
        return self:DeepCopy(defaultData)
    end
    
    local validatedData = self:DeepCopy(defaultData)
    
    -- Validate basic currency data (now supports decimals)
    if self:IsValidDecimalCurrency(data.Spores) then
        validatedData.Spores = self:RoundToTwoDecimals(math.min(data.Spores, 1000000000))
    end
    
    if self:IsValidDecimalCurrency(data.Gems) then
        validatedData.Gems = self:RoundToTwoDecimals(math.min(data.Gems, 1000000000))
    end
    
    -- Validate RobuxSpent
    if self:IsValidInteger(data.RobuxSpent) then
        validatedData.RobuxSpent = math.min(data.RobuxSpent, 1000000000)
    end
    
    -- Validate timestamps
    if self:IsValidTimestamp(data.LastSave) then
        validatedData.LastSave = data.LastSave
    end
    
    -- Validate version
    if type(data.Version) == "number" and data.Version >= 1 then
        validatedData.Version = data.Version
    end
    
    -- Validate plot assignment
    if self:IsValidPlotId(data.AssignedPlot) then
        validatedData.AssignedPlot = data.AssignedPlot
    end
    
    -- Validate spore upgrade levels
    if self:IsValidInteger(data.SporeUpgradeLevel) then
        validatedData.SporeUpgradeLevel = math.min(data.SporeUpgradeLevel, 1000) -- Cap at 1000 levels
    end
    
    if self:IsValidInteger(data.Area1SporeUpgradeLevel) then
        validatedData.Area1SporeUpgradeLevel = math.min(data.Area1SporeUpgradeLevel, 1000) -- Cap at 1000 levels
    end
    
    if self:IsValidInteger(data.Area2SporeUpgradeLevel) then
        validatedData.Area2SporeUpgradeLevel = math.min(data.Area2SporeUpgradeLevel, 1000) -- Cap at 1000 levels
    end
    
    if self:IsValidInteger(data.FastRunnerLevel) then
        validatedData.FastRunnerLevel = math.min(data.FastRunnerLevel, 1000) -- Cap at 1000 levels
    end
    
    if self:IsValidInteger(data.PickUpRangeLevel) then
        validatedData.PickUpRangeLevel = math.min(data.PickUpRangeLevel, 1000) -- Cap at 1000 levels
    end
    
    if self:IsValidInteger(data.FasterShroomsLevel) then
        validatedData.FasterShroomsLevel = math.min(data.FasterShroomsLevel, 1000) -- Cap at 1000 levels
    end
    
    if self:IsValidInteger(data.ShinySporeLevel) then
        validatedData.ShinySporeLevel = math.min(data.ShinySporeLevel, 1000) -- Cap at 1000 levels
    end
    
    if self:IsValidInteger(data.GemHunterLevel) then
        validatedData.GemHunterLevel = math.min(data.GemHunterLevel, 1000) -- Cap at 1000 levels
    end
    
    -- FIXED: Preserve PlotObjects and ObjectCounters from saved data
    if type(data.PlotObjects) == "table" then
        validatedData.PlotObjects = self:DeepCopy(data.PlotObjects)
        
        -- Ensure PlotObjects has the right structure
        if type(validatedData.PlotObjects.Mushrooms) ~= "table" then
            validatedData.PlotObjects.Mushrooms = {}
        end
        if type(validatedData.PlotObjects.Spores) ~= "table" then
            validatedData.PlotObjects.Spores = {}
        end
        if type(validatedData.PlotObjects.Area2Mushrooms) ~= "table" then
            validatedData.PlotObjects.Area2Mushrooms = {}
        end
        if type(validatedData.PlotObjects.Area2Spores) ~= "table" then
            validatedData.PlotObjects.Area2Spores = {}
        end
        if type(validatedData.PlotObjects.Area3Mushrooms) ~= "table" then
            validatedData.PlotObjects.Area3Mushrooms = {}
        end
        if type(validatedData.PlotObjects.Area3Spores) ~= "table" then
            validatedData.PlotObjects.Area3Spores = {}
        end
    end
    
    -- FIXED: Preserve ObjectCounters from saved data
    if type(data.ObjectCounters) == "table" then
        validatedData.ObjectCounters = {}
        
        if self:IsValidInteger(data.ObjectCounters.MushroomCounter) then
            validatedData.ObjectCounters.MushroomCounter = data.ObjectCounters.MushroomCounter
        else
            validatedData.ObjectCounters.MushroomCounter = 0
        end
        
        if self:IsValidInteger(data.ObjectCounters.SporeCounter) then
            validatedData.ObjectCounters.SporeCounter = data.ObjectCounters.SporeCounter
        else
            validatedData.ObjectCounters.SporeCounter = 0
        end
    end
    
    -- Validate WishData from saved data
    if type(data.WishData) == "table" then
        validatedData.WishData = {}
        
        -- Validate wishes count (no cap for purchased wishes)
        if self:IsValidInteger(data.WishData.wishes) then
            validatedData.WishData.wishes = math.min(data.WishData.wishes, 1000000) -- Cap at 1M to prevent exploits
        else
            validatedData.WishData.wishes = 0
        end
        
        -- Validate lastWishTime timestamp
        if self:IsValidTimestamp(data.WishData.lastWishTime) then
            validatedData.WishData.lastWishTime = data.WishData.lastWishTime
        else
            validatedData.WishData.lastWishTime = os.time()
        end
        
        -- Validate inventory
        if type(data.WishData.inventory) == "table" then
            validatedData.WishData.inventory = self:DeepCopy(data.WishData.inventory)
        else
            validatedData.WishData.inventory = {}
        end
    end
    
    -- Validate DailyRewards from saved data
    if type(data.DailyRewards) == "table" then
        validatedData.DailyRewards = {}
        
        -- Validate startDay
        if self:IsValidInteger(data.DailyRewards.startDay) then
            validatedData.DailyRewards.startDay = data.DailyRewards.startDay
        else
            validatedData.DailyRewards.startDay = 0
        end
        
        -- Validate lastClaimDay
        if self:IsValidInteger(data.DailyRewards.lastClaimDay) then
            validatedData.DailyRewards.lastClaimDay = data.DailyRewards.lastClaimDay
        else
            validatedData.DailyRewards.lastClaimDay = 0
        end
        
        -- Validate claimedDays table
        if type(data.DailyRewards.claimedDays) == "table" then
            validatedData.DailyRewards.claimedDays = {}
            for day, claimed in pairs(data.DailyRewards.claimedDays) do
                if type(day) == "number" and day >= 1 and day <= 15 and type(claimed) == "boolean" then
                    validatedData.DailyRewards.claimedDays[day] = claimed
                end
            end
        else
            validatedData.DailyRewards.claimedDays = {}
        end
    end
    
    -- Validate Area2 data
    if type(data.Area2Unlocked) == "boolean" then
        validatedData.Area2Unlocked = data.Area2Unlocked
    end
    
    -- Validate Area3 data
    if type(data.Area3Unlocked) == "boolean" then
        validatedData.Area3Unlocked = data.Area3Unlocked
    end
    
    if self:IsValidInteger(data.Area1MushroomCount) then
        validatedData.Area1MushroomCount = data.Area1MushroomCount
    end
    
    if self:IsValidInteger(data.Area2MushroomCount) then
        validatedData.Area2MushroomCount = data.Area2MushroomCount
    end
    
    if self:IsValidInteger(data.Area3MushroomCount) then
        validatedData.Area3MushroomCount = data.Area3MushroomCount
    end
    
    -- Validate mushroom shop levels
    if self:IsValidInteger(data.Area1MushroomShopLevel) then
        validatedData.Area1MushroomShopLevel = data.Area1MushroomShopLevel
    end
    
    if self:IsValidInteger(data.Area2MushroomShopLevel) then
        validatedData.Area2MushroomShopLevel = data.Area2MushroomShopLevel
    end
    
    if self:IsValidInteger(data.Area3MushroomShopLevel) then
        validatedData.Area3MushroomShopLevel = data.Area3MushroomShopLevel
    end
    
    -- Validate tutorial data
    if type(data.TutorialCompleted) == "boolean" then
        validatedData.TutorialCompleted = data.TutorialCompleted
    else
        -- Default to false for existing players who don't have this field yet
        validatedData.TutorialCompleted = false
    end
    
    return validatedData
end

function Validator:SanitizePlayerInput(input, inputType)
    if inputType == "currency" then
        if not self:IsPositiveNumber(input) then
            return 0
        end
        return math.min(math.floor(input), 1000000000)
    elseif inputType == "string" then
        if type(input) ~= "string" then
            return ""
        end
        return string.sub(input, 1, 100)
    elseif inputType == "plotId" then
        if not self:IsValidPlotId(input) then
            return nil
        end
        return input
    end
    
    return input
end

return Validator