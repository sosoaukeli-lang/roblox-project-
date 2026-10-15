-- Config (ModuleScript) - constants shared by the server and the clients.
local Config = {}

Config.GameName = "Night Thief"

Config.MaxHouses = 8 -- one house per player, so this is also the server's player cap
Config.StartCash = 100

-- House upgrade path (Phase 8). Only level 1 is built in Phase 1, but the data is
-- saved per player and MapBuilder already reads its size from here.
-- Slots must be a multiple of 4: MapBuilder lays them out in rows of 4.
Config.HouseLevels = {
	{ Name = "كوخ", Slots = 4, Width = 24, Depth = 24 },
	{ Name = "بيت", Slots = 8, Width = 28, Depth = 28 },
	{ Name = "قصر", Slots = 12, Width = 32, Depth = 34 },
	{ Name = "قلعة", Slots = 16, Width = 36, Depth = 40 },
}
Config.MaxHouseLevel = #Config.HouseLevels

-- Roof colour of each house, so a player can say "my house is the blue one".
Config.HouseColors = {
	{ Name = "أحمر", Color = Color3.fromRGB(196, 54, 54) },
	{ Name = "أزرق", Color = Color3.fromRGB(52, 105, 200) },
	{ Name = "أخضر", Color = Color3.fromRGB(60, 160, 80) },
	{ Name = "أصفر", Color = Color3.fromRGB(230, 190, 50) },
	{ Name = "برتقالي", Color = Color3.fromRGB(234, 126, 40) },
	{ Name = "بنفسجي", Color = Color3.fromRGB(135, 80, 190) },
	{ Name = "وردي", Color = Color3.fromRGB(230, 120, 170) },
	{ Name = "تركوازي", Color = Color3.fromRGB(50, 180, 180) },
}

return Config
