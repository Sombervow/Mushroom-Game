# Fix: Fail Sound & Dev Product Prompt Issue

## Problem
Players weren't getting fail sounds or dev product prompts when they couldn't afford purchases.

## Root Cause
The purchase functions had **early return statements** that checked affordability before attempting to spend currency:

```lua
-- OLD CODE (BROKEN)
if currentSpores < upgradeCost then
    Logger:Info("Player cannot afford...")
    return  -- ❌ Early return prevented fail sound!
end

if self._dataService:SpendSpores(player, upgradeCost) then
    -- Success logic
else
    -- ❌ This fail logic never executed due to early return
    self:_playPurchaseFailSound(player)
    self:_promptDevProduct(player, "spores")
end
```

## Solution
Added fail sound and dev product prompts to **all early return cases**:

```lua
-- NEW CODE (FIXED)
if currentSpores < upgradeCost then
    Logger:Info("Player cannot afford...")
    
    -- ✅ Added fail sound and dev product prompt
    self:_playPurchaseFailSound(player)
    self:_promptDevProduct(player, "spores")
    return
end
```

## Functions Fixed

### Spore-based Purchases (Prompt Spore Pack):
1. ✅ **Spore Upgrades** - `_handleSporeUpgradePurchase()`
2. ✅ **Mushroom Purchases** - `_handleMushroomPurchase()`
3. ✅ **Area2 Unlock** - `_handlePurchaseArea2()`
4. ✅ **Area1 Mushrooms** - `_handleArea1MushroomPurchase()`
5. ✅ **Area2 Mushrooms** - `_handleArea2MushroomPurchase()`
6. ✅ **Area3 Mushrooms** - `_handleArea3MushroomPurchase()`

### Gem-based Purchases (Prompt Gem Pack):
7. ✅ **FastRunner** - `_handleFastRunnerPurchase()`
8. ✅ **PickUpRange** - `_handlePickUpRangePurchase()`
9. ✅ **FasterShrooms** - `_handleFasterShroomsPurchase()`
10. ✅ **ShinySpore** - `_handleShinySporeUpgrade()`
11. ✅ **GemHunter** - `_handleGemHunterUpgrade()`

## Result
Now when players try to buy something they can't afford:
- 🔊 **Fail sound plays** (`rbxassetid://89567959268147`)
- 💰 **Dev product prompt appears** (appropriate pack for the shop type)

## Test Cases
- ❌ Try to buy spore upgrade with 0 spores → Fail sound + Spore pack prompt
- ❌ Try to buy mushroom with insufficient spores → Fail sound + Spore pack prompt  
- ❌ Try to buy FastRunner with 0 gems → Fail sound + Gem pack prompt
- ❌ Try to buy any gem upgrade with insufficient gems → Fail sound + Gem pack prompt

All fail scenarios now work correctly!