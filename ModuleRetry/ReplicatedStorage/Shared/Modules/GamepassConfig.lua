local GamepassConfig = {}

GamepassConfig.GAMEPASS_IDS = {
	DOUBLE_SPORES = 1492138857, -- Replace with actual gamepass ID
	TRIPLE_SPORES = 1493212826, -- 3x spores (stacks with 2x for 5x total, requires 2x first)
	QUADRUPLE_SPORES = 1493620782, -- 4x spores (stacks with 2x+3x for 9x total, requires 3x first)
	SUPER_MAGNET = 1493554786, -- 2x pickup radius multiplier
	AUTO_TAP = 1493284788, -- Automatically clicks closest spore near player
	DOUBLE_TAPS = 1491994822, -- 2x value for spores from clicking mushrooms
	LUCKY_GEM = 1492036870, -- 2x gem spawn chance
	ULTRA_LUCKY_GEM = 1493722773, -- 3x gem spawn chance (stacks with LUCKY_GEM for 6x total)
	AUTO_COLLECT = 1493254794, -- Automatically collects all spores instantly
	VIP = 1493452807, -- VIP chat tag and 2x daily rewards
}

-- Developer Product IDs
GamepassConfig.DEV_PRODUCT_IDS = {
	DOUBLE_OFFLINE_EARNINGS = 3413686210, -- Double offline earnings dev product
	WISHES_5 = 3418869147, -- Buy 5 wishes
	WISHES_50 = 3413686208, -- Buy 50 wishes
}

return GamepassConfig