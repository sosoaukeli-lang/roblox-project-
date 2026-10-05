-- IronStations (v2): personal iron forges inside the rocket, one per player.
-- Each player owns one machine (and the spawn next to it). Only the owner can collect iron or upgrade it.
-- Machines are "cold" until someone owns them: no smoke, dark window, screen says OFFLINE.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local COSTS = { 100, 1000, 5000, 10000 }   -- upgrade prices
local TIMES = { 50, 40, 30, 20, 10 }       -- seconds per iron at level 0..4
local MAX_LEVEL = #COSTS
local MAX_VISIBLE_INGOTS = 12              -- ingots shown piled on the pad

local rocket = workspace:WaitForChild("Rocket")
local folder = rocket:WaitForChild("IronStations")
local fallbackSpawn = rocket:FindFirstChild("RocketSpawn") -- used if there are more players than machines
local notify = ReplicatedStorage:WaitForChild("ShipNotify")
local fxRemote = ReplicatedStorage:WaitForChild("WeaponFX")

-- Look of each level: furnace glow / hot-iron colour and the 5 lamps on the console
local GLOW_COLORS = {
	Color3.fromRGB(215, 95, 25),
	Color3.fromRGB(220, 140, 40),
	Color3.fromRGB(220, 185, 70),
	Color3.fromRGB(140, 205, 230),
	Color3.fromRGB(160, 105, 225),
}
local LAMP_COLORS = {
	Color3.fromRGB(80, 255, 120),
	Color3.fromRGB(200, 255, 80),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(255, 110, 50),
	Color3.fromRGB(200, 100, 255),
}
local LAMP_OFF = Color3.fromRGB(45, 50, 60)
local STEEL = Color3.fromRGB(175, 180, 190)
local GLOW_OFF = Color3.fromRGB(70, 40, 30)

----------------------------------------------------------------------
-- MACHINE EVOLUTION: every upgrade restyles the machine and adds new fancy parts
--   Lv.0 Iron Forge -> Lv.1 Steel Forge -> Lv.2 Golden Forge -> Lv.3 Crystal Forge -> Lv.4 QUANTUM FORGE
-- (extra parts only exist while the machine is upgraded, so unused machines stay light)
----------------------------------------------------------------------
local C = Color3.fromRGB
local GOLD = C(255, 196, 60)
local TIER_NAMES = { "IRON FORGE", "STEEL FORGE", "GOLDEN FORGE", "CRYSTAL FORGE", "QUANTUM FORGE" }
local TIER_TEXT = { C(255, 200, 60), C(200, 230, 255), C(255, 215, 60), C(130, 255, 255), C(225, 150, 255) }
local PAD_COLORS = { C(90, 120, 255), C(130, 170, 255), C(255, 200, 90), C(110, 240, 255), C(200, 130, 255) }

-- how existing parts are restyled at each level (cumulative)
local STYLE = {
	[1] = {
		FurnaceBody = { Color = C(150, 160, 190), Reflectance = 0.12 },
		CoolingTank = { Color = C(80, 150, 220), Reflectance = 0.1 },
		Chimney = { Color = C(85, 90, 110) },
	},
	[2] = {
		FurnaceBand = { Color = GOLD, Reflectance = 0.3 },
		FurnaceFrame = { Color = GOLD, Reflectance = 0.3 },
		Pipe = { Color = GOLD, Reflectance = 0.3 },
		Dropper = { Color = GOLD, Reflectance = 0.3 },
		HopperBowl = { Color = GOLD, Reflectance = 0.3 },
		ConsoleBody = { Color = C(110, 120, 150), Reflectance = 0.1 },
	},
	[3] = {
		FurnaceBody = { Color = C(200, 210, 235), Reflectance = 0.25 },
		FurnaceDome = { Color = C(150, 230, 255), Material = Enum.Material.Glass, Transparency = 0.35 },
		HopperNeck = { Color = C(200, 210, 235) },
		Chimney = { Color = C(180, 190, 215) },
	},
	[4] = {
		FurnaceBody = { Color = C(245, 248, 255), Reflectance = 0.35 },
		FurnaceBand = { Color = C(255, 226, 120), Reflectance = 0.45 },
		FurnaceDome = { Color = C(210, 160, 255), Material = Enum.Material.Glass, Transparency = 0.3 },
		Base = { Color = C(38, 34, 60) },
		Hazard = { Color = C(255, 215, 80) },
		CoolingTank = { Color = C(170, 120, 255), Reflectance = 0.3 },
		Pipe = { Color = C(255, 226, 120), Reflectance = 0.45 },
	},
}
local STYLED = {}
for _, tier in STYLE do
	for name in tier do
		STYLED[name] = true
	end
end

-- builds one extra part (it fades in) relative to the machine's floor-level centre
local function tierPart(s, list, name, size, pos, color, mat, opts)
	opts = opts or {}
	local O = s.base.CFrame * CFrame.new(0, -0.3, 0)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.Metal
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.shape then
		p.Shape = opts.shape
	end
	if opts.reflect then
		p.Reflectance = opts.reflect
	end
	p.CFrame = O * CFrame.new(pos) * (opts.rot or CFrame.identity)
	p.Transparency = 1
	p.Parent = s.machine
	TweenService:Create(p, TweenInfo.new(0.7), { Transparency = opts.trans or 0 }):Play()
	table.insert(list, p)
	return p
end
local function tierCyl(s, list, name, dia, h, pos, color, mat, opts)
	opts = opts or {}
	opts.shape = Enum.PartType.Cylinder
	opts.rot = opts.rot or CFrame.Angles(0, 0, math.pi / 2)
	return tierPart(s, list, name, Vector3.new(h, dia, dia), pos, color, mat, opts)
end

local TIER_BUILD = {}
TIER_BUILD[1] = function(s, list)
	-- glowing trim rings around the furnace
	for _, y in { 3.55, 6.65 } do
		tierCyl(s, list, "TrimRing", 8.7, 0.18, Vector3.new(0, y, -6), C(120, 220, 255), Enum.Material.Neon, { trans = 0.4 })
	end
end
TIER_BUILD[2] = function(s, list)
	-- two golden exhaust stacks
	for _, side in { -1, 1 } do
		tierCyl(s, list, "ExhaustStack", 1.2, 11, Vector3.new(side * 2.6, 6.1, -10), GOLD, Enum.Material.Metal, { reflect = 0.3 })
		tierCyl(s, list, "ExhaustCap", 1.6, 0.18, Vector3.new(side * 2.6, 11.7, -10), C(255, 160, 60), Enum.Material.Neon, { trans = 0.4 })
	end
end
TIER_BUILD[3] = function(s, list)
	-- crystal core inside the (now glass) dome, floating halos, golden corner pillars
	local core = tierPart(s, list, "CoreOrb", Vector3.new(4.2, 4.2, 4.2), Vector3.new(0, 9.6, -6), GLOW_COLORS[4], Enum.Material.Neon, { shape = Enum.PartType.Ball, trans = 0.3 })
	local l = Instance.new("PointLight")
	l.Color = GLOW_COLORS[4]
	l.Range = 18
	l.Brightness = 1.2
	l.Shadows = false
	l.Parent = core
	tierCyl(s, list, "Halo", 10, 0.2, Vector3.new(0, 18.8, -6), C(130, 245, 255), Enum.Material.Neon, { trans = 0.5 })
	tierCyl(s, list, "Halo", 8, 0.15, Vector3.new(0, 19.6, -6), C(255, 255, 255), Enum.Material.Neon, { trans = 0.6 })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			tierCyl(s, list, "Pillar", 0.9, 3.2, Vector3.new(sx * 4.4, 2.2, sz * 12.3), GOLD, Enum.Material.Metal, { reflect = 0.3 })
			tierPart(s, list, "PillarTip", Vector3.new(1, 1, 1), Vector3.new(sx * 4.4, 4.2, sz * 12.3), C(120, 245, 255), Enum.Material.Neon, { shape = Enum.PartType.Ball, trans = 0.35 })
		end
	end
end
TIER_BUILD[4] = function(s, list)
	-- light pillar, golden crown, spinning gyroscope rings, rising sparkles
	tierCyl(s, list, "LightPillar", 3.2, 62, Vector3.new(0, 46, -6), GLOW_COLORS[5], Enum.Material.Neon, { trans = 0.9 })
	for i = 0, 7 do
		local a = i * math.pi / 4
		tierPart(s, list, "CrownSpike", Vector3.new(0.45, 2.0, 0.45), Vector3.new(math.cos(a) * 2.9, 16.6, -6 + math.sin(a) * 2.9), C(255, 226, 120), Enum.Material.Metal, { reflect = 0.45 })
	end
	s.gyros = {}
	for k, def in { { 12, 0.6, 1.7 }, { 14, -0.6, -1.2 } } do
		local ring = tierCyl(s, list, "GyroRing", def[1], 0.25, Vector3.new(0, 9.6, -6), (k == 1) and C(255, 226, 120) or C(210, 160, 255), Enum.Material.Neon, { trans = 0.55 })
		table.insert(s.gyros, { part = ring, tilt = def[2], speed = def[3] })
	end
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "MaxAura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(C(255, 240, 180), C(200, 130, 255))
	aura.LightEmission = 1
	aura.LightInfluence = 0
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	aura.Lifetime = NumberRange.new(1.5, 2.5)
	aura.Speed = NumberRange.new(4, 9)
	aura.SpreadAngle = Vector2.new(15, 15)
	aura.EmissionDirection = Enum.NormalId.Top
	aura.Rate = 16
	aura.Parent = s.base
	table.insert(list, aura)
end

-- extra stuff per tier (so every upgrade adds visible new things)
local TIER_EXTRA = {}
TIER_EXTRA[1] = function(s, list)
	for _, side in { -1, 1 } do
		tierPart(s, list, "BeltRail", Vector3.new(0.3, 0.5, 8), Vector3.new(side * 1.75, 3.55, 5.6), C(120, 220, 255), Enum.Material.Neon, { trans = 0.4 })
	end
	tierCyl(s, list, "PadRing", 6, 0.15, Vector3.new(0, 0.95, 10.7), C(120, 220, 255), Enum.Material.Neon, { trans = 0.55 })
end
TIER_EXTRA[2] = function(s, list)
	-- golden ore crane over the hopper
	for _, side in { -1, 1 } do
		tierPart(s, list, "CranePost", Vector3.new(0.5, 3.4, 0.5), Vector3.new(side * 3.8, 15.9, -6), GOLD, Enum.Material.Metal, { reflect = 0.3 })
	end
	tierPart(s, list, "CraneBar", Vector3.new(8.2, 0.5, 0.5), Vector3.new(0, 17.7, -6), GOLD, Enum.Material.Metal, { reflect = 0.3 })
	tierPart(s, list, "CraneCable", Vector3.new(0.15, 1.8, 0.15), Vector3.new(0, 16.6, -6), C(40, 40, 50), Enum.Material.Metal)
	tierPart(s, list, "CraneHook", Vector3.new(0.8, 0.8, 0.8), Vector3.new(0, 15.6, -6), C(255, 160, 60), Enum.Material.Neon, { shape = Enum.PartType.Ball, trans = 0.35 })
end
TIER_EXTRA[3] = function(s, list)
	-- four crystals orbit the furnace
	s.orbiters = {}
	for i = 1, 4 do
		local crystal = tierPart(s, list, "OrbitCrystal", Vector3.new(0.9, 1.6, 0.9), Vector3.new(0, 12, -6), C(130, 245, 255), Enum.Material.Neon, { trans = 0.1 })
		table.insert(s.orbiters, crystal)
	end
end
TIER_EXTRA[4] = function(s, list)
	-- glass wings with glowing edges + glowing floor rings
	for _, side in { -1, 1 } do
		local rot = CFrame.Angles(0, 0, side * -0.35)
		tierPart(s, list, "Wing", Vector3.new(0.35, 8, 7), Vector3.new(side * 6.4, 8.6, -6), C(190, 150, 255), Enum.Material.Glass, { trans = 0.45, rot = rot })
		tierPart(s, list, "WingEdge", Vector3.new(0.45, 0.3, 7.2), Vector3.new(side * 7.77, 12.36, -6), C(255, 240, 200), Enum.Material.Neon, { rot = rot, trans = 0.4 })
	end
	tierCyl(s, list, "FloorRing", 22, 0.12, Vector3.new(0, 0.08, -6), C(200, 130, 255), Enum.Material.Neon, { trans = 0.35 })
	tierCyl(s, list, "FloorRing", 17, 0.12, Vector3.new(0, 0.1, -6), C(255, 240, 200), Enum.Material.Neon, { trans = 0.35 })
end

local function applyVisuals(s)
	local level = s.level
	if s.visualLevel == level then
		return
	end
	s.visualLevel = level

	-- remember how the stock machine looked
	if not s.orig then
		s.orig = {}
		for _, d in s.machine:GetChildren() do
			if d:IsA("BasePart") and STYLED[d.Name] then
				s.orig[d] = { Color = d.Color, Material = d.Material, Reflectance = d.Reflectance, Transparency = d.Transparency }
			end
		end
	end

	-- 1) restyle the existing parts for this level
	for part, o in s.orig do
		if part.Parent then
			local final = { Color = o.Color, Material = o.Material, Reflectance = o.Reflectance, Transparency = o.Transparency }
			for t = 1, level do
				local spec = STYLE[t] and STYLE[t][part.Name]
				if spec then
					for k, v in spec do
						final[k] = v
					end
				end
			end
			part.Material = final.Material
			part.Transparency = final.Transparency
			TweenService:Create(part, TweenInfo.new(0.6), { Color = final.Color, Reflectance = final.Reflectance }):Play()
		end
	end

	-- 2) add / remove the extra parts of each tier
	for t = 1, 4 do
		if level >= t and not s.tiers[t] then
			local list = {}
			s.tiers[t] = list
			TIER_BUILD[t](s, list)
			if TIER_EXTRA[t] then
				TIER_EXTRA[t](s, list)
			end
		elseif level < t and s.tiers[t] then
			for _, inst in s.tiers[t] do
				inst:Destroy()
			end
			s.tiers[t] = nil
			if t == 4 then
				s.gyros = nil
			end
			if t == 3 then
				s.orbiters = nil
			end
		end
	end

	-- 3) the crystal core follows the level colour; label + floor pad change with the tier
	local core = s.machine:FindFirstChild("CoreOrb")
	if core then
		local c = GLOW_COLORS[level + 1]
		TweenService:Create(core, TweenInfo.new(0.6), { Color = c }):Play()
		local pl = core:FindFirstChildOfClass("PointLight")
		if pl then
			pl.Color = c
		end
	end
	s.levelLabel.TextColor3 = TIER_TEXT[level + 1]
	if s.pad then
		TweenService:Create(s.pad, TweenInfo.new(0.6), { Color = PAD_COLORS[level + 1] }):Play()
	end
end

-- the "evolution" moment: shock rings, sound, camera shake for the owner
local EVO_SURGE, EVO_BOOM = 9125973257, 6290067239
local function evoSound(parent, id, volume, speed)
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://" .. id
	snd.Volume = volume
	snd.PlaybackSpeed = speed
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = 20
	snd.RollOffMaxDistance = 220
	local rv = Instance.new("ReverbSoundEffect")
	rv.DecayTime = 2.0
	rv.Density = 0.9
	rv.Diffusion = 0.85
	rv.DryLevel = 0
	rv.WetLevel = -8
	rv.Parent = snd
	snd.Parent = parent
	snd:Play()
	Debris:AddItem(snd, 4)
end
local function evolveFx(s, plr)
	local color = GLOW_COLORS[s.level + 1]
	local isMax = s.level >= MAX_LEVEL
	for i = 1, isMax and 3 or 1 do
		task.delay((i - 1) * 0.2, function()
			if not s.base.Parent then
				return
			end
			local ring = Instance.new("Part")
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.CastShadow = false
			ring.Shape = Enum.PartType.Cylinder
			ring.Material = Enum.Material.Neon
			ring.Color = color
			ring.Size = Vector3.new(0.25, 4, 4)
			ring.CFrame = s.base.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Parent = workspace
			TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.25, 48, 48), Transparency = 1 }):Play()
			Debris:AddItem(ring, 1)
		end)
	end
	evoSound(s.base, EVO_SURGE, 0.9, isMax and 0.85 or 1.1)
	if isMax then
		evoSound(s.base, EVO_BOOM, 0.9, 0.9)
	end
	fxRemote:FireClient(plr, "shake", isMax and 0.5 or 0.2, isMax and 1 or 0.6)
end

-- Collect the stations
local stations = {}
for _, st in folder:GetChildren() do
	local m = st:FindFirstChild("Machine")
	if m then
		local s = {
			model = st,
			number = st:GetAttribute("Number") or 0,
			spawn = st:WaitForChild("StationSpawn"),
			collector = m:WaitForChild("Collector"),
			dropper = m:WaitForChild("Dropper"),
			spoutEnd = m:WaitForChild("SpoutEnd"),
			beltStart = m:WaitForChild("BeltStart"),
			beltEnd = m:WaitForChild("BeltEnd"),
			glow = m:WaitForChild("FurnaceGlow"),
			chimneyTop = m:WaitForChild("ChimneyTop"),
			button = m:WaitForChild("UpgradeButton"),
			nameLabel = st:WaitForChild("NameAnchor"):WaitForChild("NameSign"):WaitForChild("Label"),
			lamps = {},
			ingots = {},
			machine = m,
			base = m:WaitForChild("Base"),
			pad = st:FindFirstChild("StationPad"),
			tiers = {},
			visualLevel = nil,
			level = 0,
			pending = 0,
			timer = 0,
			owner = nil,
			debounce = false,
			screenText = "",
		}
		s.prompt = s.button:WaitForChild("ProximityPrompt")
		s.light = s.glow:WaitForChild("PointLight")
		s.screen = m:WaitForChild("ConsoleScreen"):WaitForChild("ScreenGui"):WaitForChild("Info")
		s.colLabel = s.collector:WaitForChild("BillboardGui"):WaitForChild("TextLabel")
		s.levelLabel = s.dropper:WaitForChild("BillboardGui"):WaitForChild("LevelLabel")
		for i = 1, 5 do
			s.lamps[i] = m:WaitForChild("Lamp" .. i)
		end
		table.insert(stations, s)
	end
end
table.sort(stations, function(a, b)
	return a.number < b.number
end)

local function getStat(plr, name)
	local ls = plr:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(name)
end

-- Piles ingots on the pad to match how much iron is waiting
local function syncIngots(s)
	local want = math.min(s.pending, MAX_VISIBLE_INGOTS)
	while #s.ingots > want do
		table.remove(s.ingots):Destroy()
	end
	while #s.ingots < want do
		local k = #s.ingots + 1
		local layer, idx = (k - 1) // 6, (k - 1) % 6
		local col, row = idx % 3, idx // 3
		local ingot = Instance.new("Part")
		ingot.Name = "Ingot"
		ingot.Size = Vector3.new(1.2, 0.45, 0.7)
		ingot.Color = STEEL
		ingot.Material = Enum.Material.Metal
		ingot.Reflectance = 0.15
		ingot.Anchored = true
		ingot.CanCollide = false
		ingot.CanQuery = false
		ingot.CanTouch = false
		local yaw = math.sin(k * 12.9898) * 0.18
		ingot.CFrame = s.collector.CFrame * CFrame.new((col - 1) * 1.3, 0.1 + 0.225 + layer * 0.45, (row - 0.5) * 1.4) * CFrame.Angles(0, yaw, 0)
		ingot.Parent = s.model
		table.insert(s.ingots, ingot)
	end
end

local function setPower(s, on)
	s.chimneyTop.Smoke.Enabled = on
	s.chimneyTop.Embers.Enabled = on
	s.light.Enabled = on

	-- machinery hum while the machine is running; it gets higher and more powerful with every level
	local hum = s.glow:FindFirstChild("MachineHum")
	if on then
		if not hum then
			hum = Instance.new("Sound")
			hum.Name = "MachineHum"
			hum.SoundId = "rbxassetid://9112839126"
			hum.Looped = true
			hum.RollOffMode = Enum.RollOffMode.InverseTapered
			hum.RollOffMinDistance = 12
			hum.RollOffMaxDistance = 70
			local rv = Instance.new("ReverbSoundEffect")
			rv.DecayTime = 1.5
			rv.WetLevel = -12
			rv.Parent = hum
			hum.Parent = s.glow
		end
		hum.PlaybackSpeed = 0.95 + 0.05 * s.level
		hum.Volume = 0.22 + 0.04 * s.level
		if not hum.Playing then
			hum:Play()
		end
	elseif hum then
		hum:Stop()
	end
	if on then
		s.glow.Material = Enum.Material.Neon
		s.glow.Transparency = 0.2
		s.glow.Color = GLOW_COLORS[s.level + 1]
		s.light.Color = GLOW_COLORS[s.level + 1]
	else
		s.glow.Material = Enum.Material.Metal
		s.glow.Transparency = 0
		s.glow.Color = GLOW_OFF
	end
	for i, lamp in s.lamps do
		if on and i <= s.level + 1 then
			lamp.Material = Enum.Material.Neon
			lamp.Color = LAMP_COLORS[i]
		else
			lamp.Material = Enum.Material.Metal
			lamp.Color = LAMP_OFF
		end
	end
end

local function refreshScreen(s)
	local text
	if not s.owner then
		text = "OFFLINE"
	else
		local left = math.max(0, math.ceil(TIMES[s.level + 1] - s.timer))
		if s.level >= MAX_LEVEL then
			text = string.format("NEXT IRON  %ds\nMAX LEVEL", left)
		else
			text = string.format("NEXT IRON  %ds\nUPGRADE  $%d", left, COSTS[s.level + 1])
		end
	end
	if text ~= s.screenText then
		s.screenText = text
		s.screen.Text = text
	end
end

local function refresh(s)
	if s.level >= MAX_LEVEL then
		s.prompt.ObjectText = "MAX LEVEL"
		s.prompt.Enabled = false
		s.levelLabel.Text = string.format("%s (MAX)\n%ds / drop", TIER_NAMES[MAX_LEVEL + 1], TIMES[MAX_LEVEL + 1])
	else
		s.prompt.ObjectText = "Cost: " .. COSTS[s.level + 1] .. " Money"
		s.prompt.Enabled = true
		s.levelLabel.Text = string.format("%s (Lv. %d)\n%ds / drop", TIER_NAMES[s.level + 1], s.level, TIMES[s.level + 1])
	end
	s.colLabel.Text = s.pending .. " Iron"
	if s.owner then
		s.nameLabel.Text = string.format("%s  |  Station %d", s.owner.DisplayName, s.number)
	else
		s.nameLabel.Text = string.format("Station %d (Free)", s.number)
	end
	applyVisuals(s)
	setPower(s, s.owner ~= nil)
	syncIngots(s)
	refreshScreen(s)
end

local function reset(s)
	s.level, s.pending, s.timer = 0, 0, 0
end

local function stationOf(plr)
	for _, s in stations do
		if s.owner == plr then
			return s
		end
	end
end

local lastWarn = {}
local function warnNotOwner(plr, s)
	local now = os.clock()
	if (lastWarn[plr] or 0) + 3 > now then
		return
	end
	lastWarn[plr] = now
	local mine = plr:GetAttribute("StationNumber")
	local who = s.owner and (s.owner.DisplayName .. "'s") or "a free"
	local msg = string.format("This is %s machine.", who)
	if mine and mine > 0 then
		msg ..= string.format(" Yours is Station %d!", mine)
	end
	notify:FireClient(plr, msg)
end

-- Give a player the first free station
local function assign(plr)
	if stationOf(plr) then
		return
	end
	for _, s in stations do
		if not s.owner then
			s.owner = plr
			s.model:SetAttribute("OwnerUserId", plr.UserId)
			reset(s)
			refresh(s)
			plr:SetAttribute("StationNumber", s.number)
			plr.RespawnLocation = s.spawn
			return
		end
	end
	-- every machine is taken
	plr:SetAttribute("StationNumber", 0)
	plr.RespawnLocation = fallbackSpawn
end

local function release(plr)
	local s = stationOf(plr)
	if s then
		s.owner = nil
		s.model:SetAttribute("OwnerUserId", nil)
		reset(s)
		refresh(s)
	end
	lastWarn[plr] = nil
end

-- Make sure a character ends up at its own station spawn
local function onCharacter(plr, char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	task.wait(0.15)
	local s = stationOf(plr)
	local target = s and s.spawn or fallbackSpawn
	if target and root.Parent and (root.Position - target.Position).Magnitude > 25 then
		char:PivotTo(target.CFrame + Vector3.new(0, 4, 0))
	end
end

local function onPlayer(plr)
	assign(plr)
	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)
	if plr.Character then
		task.spawn(onCharacter, plr, plr.Character)
	end
end

-- Fun effects ---------------------------------------------------------------
local function pulseFurnace(s)
	s.glow.Sparks:Emit(16)
	s.light.Brightness = 3.2
	TweenService:Create(s.light, TweenInfo.new(0.5), { Brightness = 1.1 }):Play()
end

local function popup(s, text, color)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = s.collector.Position + Vector3.new(0, 4, 0)
	p.Parent = workspace
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(200, 50)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.3
	l.Text = text
	l.Parent = g
	TweenService:Create(p, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = p.Position + Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(1.1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(p, 1.3)
end

-- Upgrade cinematic: the owner's camera orbits the machine while it charges up, then it transforms
local EVO_CHARGE = 9125973984
local function upgradeSequence(s, plr)
	s.upgrading = true
	local isMax = s.level >= MAX_LEVEL
	local lead = isMax and 1.5 or 1.0
	if plr.Parent then
		fxRemote:FireClient(plr, "evolve", (s.base.CFrame * CFrame.new(0, 9, -6)).Position, s.level)
	end

	-- charge-up: the furnace glows brighter and brighter while sparks pour in
	evoSound(s.base, EVO_CHARGE, 1, 1.43 / lead)
	s.glow.UpgradeBurst:Emit(40)
	s.light.Brightness = 1.6
	TweenService:Create(s.light, TweenInfo.new(lead, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = isMax and 8 or 5.5, Range = 24 }):Play()
	for i = 1, 4 do
		task.delay(i * lead / 5, function()
			s.glow.UpgradeBurst:Emit(15)
		end)
	end
	task.wait(lead)

	-- transformation!
	refresh(s)
	s.glow.UpgradeBurst:Emit(isMax and 200 or 110)
	s.button.UpgradeSound:Play()
	evolveFx(s, plr)
	s.light.Brightness = isMax and 9 or 6
	TweenService:Create(s.light, TweenInfo.new(1.2), { Brightness = 1.1, Range = 14 }):Play()
	popup(s, isMax and "QUANTUM FORGE!" or ("Level " .. s.level .. "!"), Color3.fromRGB(120, 255, 200))
	s.upgrading = false
end

-- A hot ingot slides out of the spout, rides the belt, drops onto the pad and cools down
local function spawnDrop(s)
	local hot = GLOW_COLORS[s.level + 1]
	local ingot = Instance.new("Part")
	ingot.Size = Vector3.new(0.7, 0.45, 1.2)
	ingot.Material = Enum.Material.Neon
	ingot.Color = hot
	ingot.CanCollide = false
	ingot.CanQuery = false
	ingot.CanTouch = false
	ingot.Anchored = true
	ingot.Parent = workspace

	pulseFurnace(s)

	local T1, T2, T3 = 0.18, 0.7, 0.25
	local total = T1 + T2 + T3
	local t = 0
	while t < total do
		t += RunService.Heartbeat:Wait()
		local pos
		if t < T1 then
			pos = s.spoutEnd.Position:Lerp(s.beltStart.Position, t / T1)
		elseif t < T1 + T2 then
			pos = s.beltStart.Position:Lerp(s.beltEnd.Position, (t - T1) / T2)
		else
			local a = (t - T1 - T2) / T3
			local landing = s.collector.Position + Vector3.new(0, 0.1 + 0.225, 0)
			pos = s.beltEnd.Position:Lerp(landing, a * a)
		end
		ingot.CFrame = CFrame.new(pos)
		local cool = math.clamp(t / total, 0, 1)
		ingot.Color = hot:Lerp(STEEL, cool)
		if cool > 0.5 and ingot.Material == Enum.Material.Neon then
			ingot.Material = Enum.Material.Metal
		end
	end
	ingot:Destroy()
	if s.owner then
		s.pending += 1
		s.colLabel.Text = s.pending .. " Iron"
		syncIngots(s)
		s.collector.PadSparkle:Emit(4)
	end
end

-- Wire up each station
for _, s in stations do
	refresh(s)

	s.collector.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local plr = char and Players:GetPlayerFromCharacter(char)
		if not plr then
			return
		end
		if plr ~= s.owner then
			warnNotOwner(plr, s)
			return
		end
		if s.debounce or s.pending <= 0 then
			return
		end
		s.debounce = true
		local iron = getStat(plr, "Iron")
		if iron then
			local amount = s.pending
			iron.Value += amount
			s.pending = 0
			s.colLabel.Text = "0 Iron"
			syncIngots(s)
			s.collector.PadSparkle:Emit(26)
			s.collector.Ping:Play()
			popup(s, "+" .. amount .. " Iron", Color3.fromRGB(255, 220, 90))
		end
		task.wait(0.2)
		s.debounce = false
	end)

	s.prompt.Triggered:Connect(function(plr)
		if plr ~= s.owner then
			warnNotOwner(plr, s)
			return
		end
		if s.upgrading then
			notify:FireClient(plr, "The machine is upgrading!")
			return
		end
		if s.level >= MAX_LEVEL then
			return
		end
		local cost = COSTS[s.level + 1]
		local money = getStat(plr, "Money")
		if not money then
			return
		end
		if money.Value < cost then
			notify:FireClient(plr, string.format("Not enough money! You need $%d.", cost))
			return
		end
		money.Value -= cost
		s.level += 1
		task.spawn(upgradeSequence, s, plr)
	end)
end

-- Production loop: every owned machine drops iron on its own timer
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, s in stations do
			if s.owner then
				s.timer += 0.25
				if s.timer >= TIMES[s.level + 1] then
					s.timer = 0
					task.spawn(spawnDrop, s)
				end
			end
			refreshScreen(s)
		end
	end
end)

Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(release)
for _, plr in Players:GetPlayers() do
	onPlayer(plr)
end

-- spinning gyroscope rings on fully upgraded (Quantum) machines
local gyroAccum = 0
RunService.Heartbeat:Connect(function(dt)
	gyroAccum += dt
	if gyroAccum < 1 / 15 then
		return
	end
	gyroAccum = 0
	local now = os.clock()
	for _, s in stations do
		if s.gyros then
			local O = s.base.CFrame * CFrame.new(0, -0.3, 0)
			for _, g in s.gyros do
				if g.part.Parent then
					g.part.CFrame = O * CFrame.new(0, 9.6, -6) * CFrame.Angles(0, now * g.speed, 0) * CFrame.Angles(g.tilt, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
				end
			end
		end
		if s.orbiters then
			local O = s.base.CFrame * CFrame.new(0, -0.3, 0)
			for i, o in s.orbiters do
				if o.Parent then
					local a = now * 1.1 + i * (math.pi / 2)
					o.CFrame = O * CFrame.new(math.cos(a) * 6.8, 12 + 0.6 * math.sin(now * 2 + i), -6 + math.sin(a) * 6.8) * CFrame.Angles(now * 2, a, math.pi / 4)
				end
			end
		end
	end
end)
