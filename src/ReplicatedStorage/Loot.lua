-- Loot (ModuleScript) - the boss chest: the 17 weapons, their rarity, the drop odds and the "pity" safety nets.
-- (The numbers a weapon actually uses - damage, cooldown, effects - are in ServerScriptService.WeaponServer.)
local Loot = {}

-- chance of each rarity per chest (they add up to 1). The odds are shown to the player when the chest opens.
Loot.Odds = { Rare = 0.52, Epic = 0.30, Legendary = 0.14, Secret = 0.04 }
Loot.RarityOrder = { "Rare", "Epic", "Legendary", "Secret" }
-- safety nets: at most this many chests without a Legendary-or-better / without a Secret
Loot.Pity = { Legendary = 12, Secret = 60 }
-- if you already own the weapon you get money instead
Loot.DuplicateMoney = { Rare = 4000, Epic = 12000, Legendary = 40000, Secret = 150000 }

Loot.Weapons = {
	-- RARE ---------------------------------------------------------------
	IonRevolver = { name = "ION REVOLVER", tool = "Ion Revolver", rarity = "Rare", icon = "\u{1F4A0}",
		desc = "A heavy six-shooter loaded with ion cells.", stat = "26 damage per shot, stuns the target for 0.35 s" },
	PhotonSMG = { name = "PHOTON SMG", tool = "Photon SMG", rarity = "Rare", icon = "\u{1F4A1}",
		desc = "A compact sub-machine gun that never stops.", stat = "Automatic, 5 damage x 14 shots per second" },
	PulseShotgun = { name = "PULSE SHOTGUN", tool = "Pulse Shotgun", rarity = "Rare", icon = "\u{1F4A5}",
		desc = "Six pellets of pulsed light. Devastating up close.", stat = "6 pellets x 8 damage, wide spread" },
	FrostNeedler = { name = "FROST NEEDLER", tool = "Frost Needler", rarity = "Rare", icon = "\u{2744}",
		desc = "Needles of liquid cold that slow everything they touch.", stat = "Automatic, 9 damage, slows targets by 50%" },
	-- EPIC ---------------------------------------------------------------
	InfernoCannon = { name = "INFERNO CANNON", tool = "Inferno Cannon", rarity = "Epic", icon = "\u{1F525}",
		desc = "Spits a fireball that burns long after it hits.", stat = "16 damage + splash + burning (5 x 7 damage)" },
	StormCoil = { name = "STORM COIL", tool = "Storm Coil", rarity = "Epic", icon = "\u{26A1}",
		desc = "A tesla coil in a gun. The lightning jumps.", stat = "24 damage, chains to 2 more targets" },
	GravitonLauncher = { name = "GRAVITON LAUNCHER", tool = "Graviton Launcher", rarity = "Epic", icon = "\u{1F300}",
		desc = "Fires a crushing sphere of gravity.", stat = "55 damage in a 16 stud blast, slows 60% for 3 s" },
	Railbreaker = { name = "RAILBREAKER", tool = "Railbreaker", rarity = "Epic", icon = "\u{1F3AF}",
		desc = "A magnetic rail that punches through armour.", stat = "70 damage, pierces 3 targets, very long range" },
	VenomSpitter = { name = "VENOM SPITTER", tool = "Venom Spitter", rarity = "Epic", icon = "\u{1F40D}",
		desc = "Alien venom, bottled and weaponised.", stat = "Automatic, 10 damage + poison (6 x 5 damage)" },
	NovaBurstRifle = { name = "NOVA BURST RIFLE", tool = "Nova Burst Rifle", rarity = "Epic", icon = "\u{2728}",
		desc = "Three-round bursts that explode on impact.", stat = "3 x 15 damage per burst + small blasts" },
	-- LEGENDARY ----------------------------------------------------------
	SolarJudgement = { name = "SOLAR JUDGEMENT", tool = "Solar Judgement", rarity = "Legendary", icon = "\u{2600}",
		desc = "A beam of captured sunlight. Nothing stands in its way.", stat = "150 damage, pierces 8 targets, sets them ablaze" },
	TempestRepeater = { name = "TEMPEST REPEATER", tool = "Tempest Repeater", rarity = "Legendary", icon = "\u{1F32A}",
		desc = "A storm that fires back. Lightning leaps between enemies.", stat = "Automatic, 20 damage, chains to 3 more targets" },
	ReapersMaw = { name = "REAPER'S MAW", tool = "Reaper's Maw", rarity = "Legendary", icon = "\u{1F480}",
		desc = "It feeds on the weak and gives you their strength.", stat = "42 damage, x2 below 30% health, heals you 25% of damage" },
	StarfallLauncher = { name = "STARFALL LAUNCHER", tool = "Starfall Launcher", rarity = "Legendary", icon = "\u{1F320}",
		desc = "Calls a falling star - and its children.", stat = "90 damage blast, then 5 meteors rain down around it" },
	-- SECRET -------------------------------------------------------------
	EclipseReaper = { name = "ECLIPSE REAPER", tool = "Eclipse Reaper", rarity = "Secret", icon = "\u{1F311}",
		desc = "Cuts through the light itself. What it marks, falls.", stat = "170 damage, pierces 8, marked enemies take +25%, heals you 30%" },
	ChronoFracture = { name = "CHRONO FRACTURE", tool = "Chrono Fracture", rarity = "Secret", icon = "\u{231B}",
		desc = "A crack in time. Everything inside it stands still.", stat = "260 damage, 30 stud blast + a time rift that freezes enemies for 5 s" },
	GenesisCannon = { name = "GENESIS CANNON", tool = "Genesis Cannon", rarity = "Secret", icon = "\u{1F308}",
		desc = "The first light, aimed. A beam of every colour at once.", stat = "Automatic rainbow beam, 28 damage, pierces 5, chains to 4 more" },
}
Loot.Order = {
	"IonRevolver", "PhotonSMG", "PulseShotgun", "FrostNeedler",
	"InfernoCannon", "StormCoil", "GravitonLauncher", "Railbreaker", "VenomSpitter", "NovaBurstRifle",
	"SolarJudgement", "TempestRepeater", "ReapersMaw", "StarfallLauncher",
	"EclipseReaper", "ChronoFracture", "GenesisCannon",
}

Loot.ByRarity = {}
for _, id in Loot.Order do
	local r = Loot.Weapons[id].rarity
	Loot.ByRarity[r] = Loot.ByRarity[r] or {}
	table.insert(Loot.ByRarity[r], id)
end
Loot.ByTool = {}
for id, w in Loot.Weapons do Loot.ByTool[w.tool] = id end

-- roll one chest. `state` = { sinceLegendary = n, sinceSecret = n, owned = { [id] = true } }
-- returns weaponId, rarity, wasPity
function Loot.roll(state, rng)
	rng = rng or Random.new()
	local rarity, pity = nil, false
	if (state.sinceSecret or 0) >= Loot.Pity.Secret - 1 then
		rarity, pity = "Secret", true
	elseif (state.sinceLegendary or 0) >= Loot.Pity.Legendary - 1 then
		-- Legendary or better (Secret keeps its normal chance among them)
		local sec = Loot.Odds.Secret / (Loot.Odds.Secret + Loot.Odds.Legendary)
		rarity, pity = (rng:NextNumber() < sec) and "Secret" or "Legendary", true
	else
		local x, acc = rng:NextNumber(), 0
		for _, r in Loot.RarityOrder do
			acc += Loot.Odds[r]
			if x <= acc then rarity = r break end
		end
		rarity = rarity or "Rare"
	end
	local list = Loot.ByRarity[rarity]
	-- prefer a weapon the player does not own yet (so chests feel rewarding), but not always
	local fresh = {}
	for _, id in list do
		if not (state.owned and state.owned[id]) then fresh[#fresh + 1] = id end
	end
	local pool = (#fresh > 0 and rng:NextNumber() < 0.75) and fresh or list
	return pool[rng:NextInteger(1, #pool)], rarity, pity
end

return Loot
