-- Monetization (ModuleScript) - everything that costs Robux, in ONE place.
--
-- HOW TO ACTIVATE (once, in Creator Hub > your experience > Monetization):
--   1. Create the GAME PASS and the DEVELOPER PRODUCTS listed below, each with EXACTLY the price written next to it.
--   2. Copy each one's ID into the `id = 0` of its entry here.
--   While an id is 0 the item is "not set up yet": real players cannot buy it, but in Roblox Studio a purchase is SIMULATED
--   (TEST_MODE) so you can test the whole flow for free.
-- Nothing here is random: every pack and bundle has fixed contents, and the contents are shown to the player before buying.
local RunService = game:GetService("RunService")
local Mon = {}

Mon.TEST_MODE = RunService:IsStudio() -- simulated purchases for products whose id is still 0 (only inside Studio)

-- SKIP A MISSION: price grows by 30 R$ for every difficulty level  (difficulty 1 = 29, 2 = 59, 3 = 89, ...)
Mon.BASE_SKIP = 29
Mon.SKIP_STEP = 30
function Mon.skipPrice(difficulty)
	return Mon.BASE_SKIP + Mon.SKIP_STEP * (math.max(1, difficulty or 1) - 1)
end
Mon.MAX_DIFFICULTY = 6

-- GAME PASS (a permanent unlock, bought once)
Mon.Passes = {
	AetherRaygun = {
		id = 0, price = 399, name = "SECRET WEAPON", item = "AetherRaygun",
		tagline = "CLASSIFIED. A weapon that is in no catalog. Its shots arc between aliens like lightning.",
	},
}

-- DEVELOPER PRODUCTS (can be bought again and again)
Mon.Products = {}
for d = 1, Mon.MAX_DIFFICULTY do
	Mon.Products["skip_" .. d] = { id = 0, price = Mon.skipPrice(d), kind = "skip", difficulty = d, name = "Skip a mission (difficulty " .. d .. ")" }
end
Mon.Products.bundle_starter = {
	id = 0, price = 99, kind = "bundle", name = "STARTER BUNDLE", tag = "GREAT START", accent = { 0, 220, 255 },
	tagline = "Everything a new hunter needs.",
	items = { "SolarContrail" }, money = 10000, iron = 1000,
}
Mon.Products.bundle_hunter = {
	id = 0, price = 249, kind = "bundle", name = "HUNTER BUNDLE", tag = "POPULAR", accent = { 190, 90, 255 },
	tagline = "Fangs and sight: the hunter's kit.",
	items = { "XenoFang", "OracleHorns" }, money = 30000, iron = 3000,
}
Mon.Products.bundle_legend = {
	id = 0, price = 799, kind = "bundle", name = "LEGEND BUNDLE", tag = "BEST VALUE", accent = { 255, 200, 90 },
	tagline = "ALL six gear items + the secret weapon + a fortune.",
	items = { "SolarContrail", "OracleHorns", "VoidContrail", "XenoFang", "ArchonCrown", "HivePiercer" }, raygun = true, money = 150000, iron = 10000,
}
Mon.Products.money_s = { id = 0, price = 49, kind = "pack", name = "MONEY PACK  S", tagline = "A pocket of space cash.", money = 20000, accent = { 120, 255, 160 } }
Mon.Products.money_m = { id = 0, price = 199, kind = "pack", name = "MONEY PACK  M", tagline = "Serious funding.", money = 100000, accent = { 120, 255, 160 } }
Mon.Products.money_l = { id = 0, price = 499, kind = "pack", name = "MONEY PACK  L", tagline = "A whole space bank.", money = 300000, accent = { 120, 255, 160 } }
Mon.Products.energy_cell = { id = 0, price = 19, kind = "energy", name = "ENERGY CELL", tagline = "Refills your BOOST bar instantly.", accent = { 0, 220, 255 } }

-- THE BOSS CHEST: a random weapon (the same odds as the chest the boss drops: Rare 52%, Epic 30%, Legendary 14%, Secret 4%, with bad-luck protection).
-- Because it is a paid random item, the odds are shown before buying and it is hidden for accounts where Roblox restricts paid random items.
Mon.Products.boss_chest = { id = 0, price = 1899, kind = "chest", name = "BOSS CHEST", tagline = "A random weapon from the boss loot table.", accent = { 255, 210, 110 } }
Mon.ChestKey = "boss_chest"

-- display order of the store
Mon.Bundles = { "bundle_starter", "bundle_hunter", "bundle_legend" }
Mon.Packs = { "money_s", "money_m", "money_l", "energy_cell" }

function Mon.keyForProductId(id)
	if not id or id == 0 then return nil end
	for key, p in Mon.Products do
		if p.id == id then return key end
	end
	return nil
end
function Mon.isConfigured(key)
	local p = Mon.Products[key] or Mon.Passes[key]
	return p ~= nil and p.id ~= 0
end

return Mon
