-- Items (ModuleScript) - the catalog everything else reads: rarities, items, missions.
local C3 = Color3.fromRGB
local Items = {}

Items.Rarities = {
	Common = { name = "COMMON", color = C3(0, 220, 255), order = 1 },
	Rare = { name = "RARE", color = C3(110, 255, 150), order = 2 },
	Epic = { name = "EPIC", color = C3(190, 90, 255), order = 3 },
	Legendary = { name = "LEGENDARY", color = C3(255, 200, 90), order = 4 },
	Mythic = { name = "MYTHIC", color = C3(255, 70, 90), order = 5 },
}

-- slot: "Trail" (flight trail, equipped) | "Passive" (equipped) | "Weapon" (a tool you get in your backpack)
Items.List = {
	SolarContrail = {
		name = "SOLAR CONTRAIL", slot = "Trail", rarity = "Rare", price = 1200, mission = "first_blood", icon = "\u{2600}",
		desc = "Your flight trail turns to solar fire. Aliens that cross it BURN.",
		stat = "Burn: 12 damage / second on aliens touching your trail",
		trailColors = { C3(255, 255, 220), C3(255, 190, 60), C3(255, 80, 30) },
	},
	OracleHorns = {
		name = "ORACLE HORNS", slot = "Passive", rarity = "Epic", price = 3500, mission = "ichor_run", icon = "\u{1F441}",
		desc = "The Oracle's gift. You see every alien through walls, with its health bar.",
		stat = "X-ray sight on aliens within 600 studs",
	},
	VoidContrail = {
		name = "VOID CONTRAIL", slot = "Trail", rarity = "Epic", price = 4000, mission = "crystal_climb", icon = "\u{25C9}",
		desc = "A trail of the void. Aliens close to you are dragged to HALF speed.",
		stat = "Slow: -50% speed on aliens within 45 studs",
		trailColors = { C3(235, 220, 255), C3(160, 90, 255), C3(40, 10, 90) },
	},
	XenoFang = {
		name = "XENO FANG", slot = "Weapon", tool = "Xeno Fang", rarity = "Epic", price = 5000, mission = "fang_hunter", icon = "\u{1F5E1}",
		desc = "A pistol grown from alien bone. Every hit leaves a wound that keeps bleeding.",
		stat = "14 damage + bleed (5 x 4 damage over 3 seconds)",
	},
	ArchonCrown = {
		name = "ARCHON'S CROWN", slot = "Passive", rarity = "Legendary", price = 15000, mission = "hive_breaker", icon = "\u{1F451}",
		desc = "Worn by the master of the forge. Every kill pays more.",
		stat = "+$10 for every alien you kill ($40 instead of $30)",
	},
	HivePiercer = {
		name = "HIVE PIERCER", slot = "Weapon", tool = "Hive Piercer", rarity = "Legendary", price = 20000, mission = "titan_slayer", icon = "\u{26A1}",
		desc = "A lance of golden light that does not stop at the first body.",
		stat = "22 damage, pierces up to 7 aliens in a line",
	},
}
Items.Order = { "SolarContrail", "OracleHorns", "VoidContrail", "XenoFang", "ArchonCrown", "HivePiercer" }

-- Missions. type: kill | collect | wave | titan.   filter: hive (index) / weapon (WeaponId) / resource
Items.Missions = {
	first_blood = {
		name = "FIRST BLOOD", tier = "Rare", type = "kill", target = 10, requires = nil,
		brief = "The hives are breeding faster than we can count. Show me you can spill alien blood. Kill 10 Xeno Reapers.",
		short = "Kill 10 aliens", reward = { money = 300, iron = 20 }, unlocks = "SolarContrail",
	},
	ichor_run = {
		name = "ICHOR RUN", tier = "Epic", type = "collect", filter = { resource = "Ichor" }, target = 10, requires = "first_blood",
		brief = "Their blood glows green. Our scientists want it. Collect 10 Xeno Ichor - it drops from every alien you kill.",
		short = "Collect 10 Xeno Ichor", reward = { money = 500, iron = 30 }, unlocks = "OracleHorns",
	},
	crystal_climb = {
		name = "CRYSTAL CLIMB", tier = "Epic", type = "collect", filter = { resource = "Crystal" }, target = 8, requires = "ichor_run",
		brief = "Hive Crystals grow on the highest towers of the neon city. Fly up and take 8 of them. Do not look down.",
		short = "Collect 8 Hive Crystals from the towers", reward = { money = 800, iron = 40 }, unlocks = "VoidContrail",
	},
	fang_hunter = {
		name = "FANG HUNTER", tier = "Epic", type = "kill", filter = { weapon = "StarterBlaster" }, target = 25, requires = "crystal_climb",
		brief = "Anyone can kill with a legendary gun. Kill 25 aliens with your Starter Blaster and I will give you something with teeth.",
		short = "Kill 25 aliens with the Starter Blaster", reward = { money = 1200, iron = 60 }, unlocks = "XenoFang",
	},
	hive_breaker = {
		name = "HIVE BREAKER", tier = "Legendary", type = "wave", target = 4, requires = "fang_hunter",
		brief = "Break their waves. Destroy EVERY alien of a hive's wave, four times. You must kill at least one of them yourself.",
		short = "Clear 4 waves", reward = { money = 3000, iron = 100 }, unlocks = "ArchonCrown",
	},
	titan_slayer = {
		name = "TITAN SLAYER", tier = "Legendary", type = "titan", target = 1, requires = "hive_breaker",
		brief = "The hives have grown something enormous. When you accept, a XENO TITAN will rise from the nearest hive. Kill it. Bring friends.",
		short = "Slay the Xeno Titan", reward = { money = 5000, iron = 200 }, unlocks = "HivePiercer",
	},
}
Items.MissionOrder = { "first_blood", "ichor_run", "crystal_climb", "fang_hunter", "hive_breaker", "titan_slayer" }

-- repeatable bounties, one per hive
for i = 1, 5 do
	local id = "bounty_" .. i
	Items.Missions[id] = {
		name = "HIVE " .. i .. " BOUNTY", tier = "Rare", type = "kill", filter = { hive = i }, target = 12, repeatable = true, requires = "first_blood",
		brief = "Hive " .. i .. " is out of control. Kill 12 aliens that came out of it. Paid every time.",
		short = "Kill 12 aliens from Hive " .. i, reward = { money = 600, iron = 25 },
	}
	table.insert(Items.MissionOrder, id)
end

function Items.rarityColor(rarity)
	return (Items.Rarities[rarity] or Items.Rarities.Common).color
end

-- SECRET rarity + the secret weapon (sold only for Robux, never shown in the normal shop)
Items.Rarities.Secret = { name = "SECRET", color = C3(255, 60, 90), order = 6 }
Items.List.AetherRaygun = {
	name = "AETHER RAYGUN", slot = "Weapon", tool = "Aether Raygun", rarity = "Secret", secret = true, icon = "\u{2605}",
	desc = "A weapon from no catalog. Each shot arcs through the aliens like lightning.",
	stat = "75 damage + chain lightning: jumps to 5 more aliens within 36 studs (65% damage each)",
}

-- every mission has a difficulty (1-6). Skipping a mission costs Robux: 29 + 30 per difficulty level (see Monetization)
local DIFFICULTY = { first_blood = 1, ichor_run = 2, crystal_climb = 3, fang_hunter = 4, hive_breaker = 5, titan_slayer = 6 }
for id, mission in Items.Missions do
	mission.difficulty = DIFFICULTY[id] or 1
end

return Items
