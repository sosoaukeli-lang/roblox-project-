-- WeaponStats (ModuleScript) - what the LOADOUT screen shows for every weapon: rarity and POWER (damage per second).
-- (The real numbers used in combat are in ServerScriptService.WeaponServer: keep this table in sync when you change them.)
--   power = ( damage x shots + bonus ) / cooldown + dot
--   shots = pellets or burst size, bonus = extra damage of a shot (splash, meteors), dot = damage per second of burning / poison / bleed
local S = {}
S.MaxPower = 360 -- the full bar

S.Data = {
	["Starter Blaster"] = { rarity = "Common", damage = 5, cooldown = 0.5, special = "Free starter weapon" },
	["Laser Pistol"] = { rarity = "Rare", damage = 15, cooldown = 0.35, special = "Precise cyan beam" },
	["Plasma Rifle"] = { rarity = "Epic", damage = 10, cooldown = 0.12, special = "Automatic plasma fire" },
	["Void Cannon"] = { rarity = "Legendary", damage = 60, cooldown = 1.8, special = "Charged 20 stud blast" },
	["Xeno Fang"] = { rarity = "Epic", damage = 14, cooldown = 0.4, dot = 6.7, special = "Bleeds the target" },
	["Hive Piercer"] = { rarity = "Legendary", damage = 22, cooldown = 0.7, special = "Pierces up to 7 targets" },
	["Aether Raygun"] = { rarity = "Secret", damage = 75, cooldown = 0.4, special = "Chain lightning to 5 more targets" },
	["Ion Revolver"] = { rarity = "Rare", damage = 26, cooldown = 0.5, special = "Stuns 0.35 s" },
	["Photon SMG"] = { rarity = "Rare", damage = 5, cooldown = 0.07, special = "Automatic, never stops" },
	["Pulse Shotgun"] = { rarity = "Rare", damage = 8, shots = 6, cooldown = 0.8, special = "6 pellets, wide spread" },
	["Frost Needler"] = { rarity = "Rare", damage = 9, cooldown = 0.16, special = "Automatic, slows 50%" },
	["Inferno Cannon"] = { rarity = "Epic", damage = 16, cooldown = 0.35, bonus = 10, dot = 11.7, special = "Burns + 7 stud splash" },
	["Storm Coil"] = { rarity = "Epic", damage = 24, cooldown = 0.4, special = "Lightning chains to 2 more" },
	["Graviton Launcher"] = { rarity = "Epic", damage = 55, cooldown = 1.6, special = "16 stud blast, slows 60%" },
	["Railbreaker"] = { rarity = "Epic", damage = 70, cooldown = 1.1, special = "Pierces 3, long range" },
	["Venom Spitter"] = { rarity = "Epic", damage = 10, cooldown = 0.22, dot = 8.3, special = "Automatic, poison" },
	["Nova Burst Rifle"] = { rarity = "Epic", damage = 15, shots = 3, cooldown = 0.55, bonus = 24, special = "3-round burst + blasts" },
	["Solar Judgement"] = { rarity = "Legendary", damage = 150, cooldown = 1.5, dot = 20, special = "Pierces 8, sets them ablaze" },
	["Tempest Repeater"] = { rarity = "Legendary", damage = 20, cooldown = 0.13, special = "Automatic, chains to 3 more" },
	["Reaper's Maw"] = { rarity = "Legendary", damage = 42, cooldown = 0.38, special = "x2 below 30% health, heals you" },
	["Starfall Launcher"] = { rarity = "Legendary", damage = 90, cooldown = 2.2, bonus = 200, special = "26 stud blast + 5 meteors" },
	["Eclipse Reaper"] = { rarity = "Secret", damage = 170, cooldown = 0.6, special = "Pierces 8, marks (+25%), heals" },
	["Chrono Fracture"] = { rarity = "Secret", damage = 260, cooldown = 1.6, special = "30 stud blast + 5 s time freeze" },
	["Genesis Cannon"] = { rarity = "Secret", damage = 28, cooldown = 0.08, special = "Automatic, pierces 5, chains to 4" },
}

function S.get(tool)
	local d = S.Data[tool]
	if not d then return { rarity = "Common", damage = 0, cooldown = 1, power = 0, special = "" } end
	local shots = d.shots or 1
	local power = (d.damage * shots + (d.bonus or 0)) / d.cooldown + (d.dot or 0)
	return {
		rarity = d.rarity, damage = d.damage, shots = shots, cooldown = d.cooldown, special = d.special,
		power = math.floor(power + 0.5), shotsPerSecond = math.floor(10 / d.cooldown + 0.5) / 10,
	}
end

return S
