-- Test script to verify storage limit functionality
print("=== STORAGE LIMIT TEST ===")

-- Simulate the storage service behavior
local StorageService = {}
StorageService.playerAreaStorage = {}

-- Mock constants
local Constants = {
    STORAGE = {
        MAX_SPORES_PER_AREA = 1000,
        AREAS = {"Area1", "Area2", "Area3"}
    }
}

function StorageService:GetAreaSporeCount(player, area)
    local userId = player.UserId
    if not self.playerAreaStorage[userId] then
        self.playerAreaStorage[userId] = {}
    end
    return self.playerAreaStorage[userId][area] or 0
end

function StorageService:CanSpawnSporeInArea(player, area)
    local currentCount = self:GetAreaSporeCount(player, area)
    return currentCount < Constants.STORAGE.MAX_SPORES_PER_AREA
end

function StorageService:OnSporeSpawned(player, area)
    local userId = player.UserId
    if not self.playerAreaStorage[userId] then
        self.playerAreaStorage[userId] = {}
    end
    
    self.playerAreaStorage[userId][area] = (self.playerAreaStorage[userId][area] or 0) + 1
    print(string.format("Spore spawned in %s for %s. Count: %d", area, player.Name, self.playerAreaStorage[userId][area]))
end

-- Test scenarios
local testPlayer = {UserId = 12345, Name = "TestPlayer"}

print("\n1. Testing empty area (should allow spawning)")
local canSpawn = StorageService:CanSpawnSporeInArea(testPlayer, "Area1")
print("Can spawn in empty Area1:", canSpawn)

print("\n2. Testing normal spawning")
for i = 1, 5 do
    if StorageService:CanSpawnSporeInArea(testPlayer, "Area1") then
        StorageService:OnSporeSpawned(testPlayer, "Area1")
    else
        print("Storage full, cannot spawn spore", i)
    end
end

print("\n3. Testing near-full capacity")
-- Fill up to near limit
for i = 1, 990 do
    StorageService:OnSporeSpawned(testPlayer, "Area1")
end
print("Current count after filling:", StorageService:GetAreaSporeCount(testPlayer, "Area1"))

print("\n4. Testing capacity limit")
for i = 1, 15 do
    if StorageService:CanSpawnSporeInArea(testPlayer, "Area1") then
        StorageService:OnSporeSpawned(testPlayer, "Area1")
        print(string.format("Spawned spore %d, count: %d", i, StorageService:GetAreaSporeCount(testPlayer, "Area1")))
    else
        print(string.format("STORAGE FULL: Cannot spawn spore %d, count: %d", i, StorageService:GetAreaSporeCount(testPlayer, "Area1")))
    end
end

print("\n5. Testing different areas (should be independent)")
local area2CanSpawn = StorageService:CanSpawnSporeInArea(testPlayer, "Area2")
print("Can spawn in Area2 while Area1 is full:", area2CanSpawn)

print("\n=== TEST COMPLETE ===")
print("Expected behavior:")
print("- Empty areas should allow spawning")
print("- Should track spore counts per area per player")
print("- Should prevent spawning when area reaches 1000 spores")
print("- Different areas should be independent")