-- WeaponServer v2: validates shots from the space weapons and plays the effects.
--   * Laser Pistol / Plasma Rifle: fast glowing bolts that fly to the target, then sparks + shock ring on impact
--   * Void Cannon: charges up (the orb swells), then fires a plasma ball that detonates in a big shockwave
--   * nearby players get camera shake from explosions, shooters get a hit marker

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

-- false: weapons only hurt NPCs / dummies (players are safe). Set to true to allow player vs player damage.
local ALLOW_PVP = false

local WEAPONS = {
	LaserPistol = { kind = "bolt", damage = 15, cooldown = 0.35, range = 320, speed = 900, length = 5, width = 0.3, color = Color3.fromRGB(80, 240, 255) },
	PlasmaRifle = { kind = "bolt", damage = 10, cooldown = 0.12, range = 380, speed = 1300, length = 7, width = 0.24, color = Color3.fromRGB(110, 255, 150) },
	StarterBlaster = { kind = "bolt", damage = 5, cooldown = 0.5, range = 240, speed = 700, length = 3, width = 0.2, color = Color3.fromRGB(150, 255, 120) },
	AetherRaygun = { kind = "bolt", damage = 75, cooldown = 0.4, range = 420, speed = 2200, length = 9, width = 0.5, color = Color3.fromRGB(0, 235, 255), chain = { jumps = 5, range = 36, falloff = 0.65 } },
	XenoFang = { kind = "bolt", damage = 14, cooldown = 0.4, range = 300, speed = 950, length = 5, width = 0.28, color = Color3.fromRGB(255, 60, 90), bleed = { ticks = 5, damage = 4, interval = 0.6 } },
	HivePiercer = { kind = "bolt", damage = 22, cooldown = 0.7, range = 520, speed = 1700, length = 14, width = 0.4, color = Color3.fromRGB(255, 200, 90), pierce = 6 },
	VoidCannon = { kind = "orb", damage = 60, cooldown = 1.8, range = 420, speed = 420, radius = 20, charge = 0.6, color = Color3.fromRGB(190, 90, 255) },

	-- the boss chest weapons ----------------------------------------------------------------------
	-- RARE
	IonRevolver = { kind = "bolt", damage = 26, cooldown = 0.5, range = 360, speed = 1500, length = 6, width = 0.34, color = Color3.fromRGB(80, 170, 255), stun = 0.35 },
	PhotonSMG = { kind = "bolt", damage = 5, cooldown = 0.07, range = 250, speed = 1800, length = 3.5, width = 0.18, color = Color3.fromRGB(255, 170, 60) },
	PulseShotgun = { kind = "bolt", damage = 8, cooldown = 0.8, range = 170, speed = 1400, length = 2.5, width = 0.16, color = Color3.fromRGB(60, 255, 200), pellets = 6, spread = 7 },
	FrostNeedler = { kind = "bolt", damage = 9, cooldown = 0.16, range = 300, speed = 1700, length = 6, width = 0.12, color = Color3.fromRGB(170, 230, 255), slow = { factor = 0.5, duration = 2.2 } },
	-- EPIC
	InfernoCannon = { kind = "bolt", damage = 16, cooldown = 0.35, range = 260, speed = 800, length = 3, width = 0.8, color = Color3.fromRGB(255, 110, 40), burn = { ticks = 5, damage = 7, interval = 0.6 }, splash = { radius = 7, damage = 10 } },
	StormCoil = { kind = "bolt", damage = 24, cooldown = 0.4, range = 330, speed = 2400, length = 8, width = 0.25, color = Color3.fromRGB(120, 170, 255), chain = { jumps = 2, range = 30, falloff = 0.7 } },
	GravitonLauncher = { kind = "orb", damage = 55, cooldown = 1.6, range = 380, speed = 500, radius = 16, color = Color3.fromRGB(200, 90, 255), slow = { factor = 0.4, duration = 3 } },
	Railbreaker = { kind = "bolt", damage = 70, cooldown = 1.1, range = 700, speed = 3500, length = 22, width = 0.35, color = Color3.fromRGB(90, 190, 255), pierce = 3 },
	VenomSpitter = { kind = "bolt", damage = 10, cooldown = 0.22, range = 280, speed = 1100, length = 3, width = 0.3, color = Color3.fromRGB(150, 255, 60), poison = { ticks = 6, damage = 5, interval = 0.6 } },
	NovaBurstRifle = { kind = "bolt", damage = 15, cooldown = 0.55, range = 380, speed = 2000, length = 5, width = 0.22, color = Color3.fromRGB(255, 120, 230), burst = { count = 3, interval = 0.06 }, splash = { radius = 5, damage = 8 } },
	-- LEGENDARY
	SolarJudgement = { kind = "bolt", damage = 150, cooldown = 1.5, range = 900, speed = 4000, length = 30, width = 0.7, color = Color3.fromRGB(255, 225, 120), pierce = 8, burn = { ticks = 6, damage = 10, interval = 0.5 } },
	TempestRepeater = { kind = "bolt", damage = 20, cooldown = 0.13, range = 340, speed = 2400, length = 7, width = 0.2, color = Color3.fromRGB(170, 200, 255), chain = { jumps = 3, range = 30, falloff = 0.6 } },
	ReapersMaw = { kind = "bolt", damage = 42, cooldown = 0.38, range = 320, speed = 1300, length = 6, width = 0.4, color = Color3.fromRGB(255, 60, 80), execute = { threshold = 0.3, mult = 2 }, lifesteal = 0.25 },
	StarfallLauncher = { kind = "orb", damage = 90, cooldown = 2.2, range = 420, speed = 520, radius = 26, color = Color3.fromRGB(255, 230, 160), meteors = { count = 5, radius = 34, damage = 40, blast = 12 } },
	-- SECRET
	EclipseReaper = { kind = "bolt", damage = 170, cooldown = 0.6, range = 520, speed = 2600, length = 16, width = 0.55, color = Color3.fromRGB(180, 110, 255), pierce = 8, lifesteal = 0.3, execute = { threshold = 0.35, mult = 1.75 }, mark = 5 },
	ChronoFracture = { kind = "orb", damage = 260, cooldown = 1.6, range = 420, speed = 700, radius = 30, color = Color3.fromRGB(255, 210, 100), rift = { radius = 30, duration = 5 } },
	GenesisCannon = { kind = "bolt", damage = 28, cooldown = 0.08, range = 520, speed = 5000, length = 40, width = 0.6, color = Color3.fromRGB(255, 120, 255), pierce = 5, chain = { jumps = 4, range = 30, falloff = 0.6 }, rainbow = true },
}

-- everything an alien-side effect can touch: the hive aliens and the mothership forces
local function forces()
	local list = {}
	for _, name in { "XenoAliens", "MothershipForces" } do
		local f = workspace:FindFirstChild(name)
		if f then
			for _, c in f:GetChildren() do list[#list + 1] = c end
		end
	end
	return list
end

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local WHITE = Color3.new(1, 1, 1)
local BALL = Enum.PartType.Ball

local remote = ReplicatedStorage:WaitForChild("WeaponFire")
local fxRemote = ReplicatedStorage:WaitForChild("WeaponFX")
local lastFire = setmetatable({}, { __mode = "k" })
local shotCount = setmetatable({}, { __mode = "k" })
local busy = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------------
-- effect helpers
----------------------------------------------------------------------
local function emptyPart(cf)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = cf
	p.Parent = workspace
	return p
end

local function neonPart(size, cf, color, shape, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.Transparency = transparency or 0
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	p.Parent = workspace
	return p
end

-- sound helpers --------------------------------------------------------
local rng = Random.new()
-- spec = { assetId, volume, playbackSpeed, reverb (optional) }
-- Sounds are played on every player's own screen (see WeaponClient): that way each listener hears the
-- shot after a realistic delay for the distance, muffled when far away, with an echo inside the rocket.
local SOUNDS = {
	LaserPistol = { fire = "pistol_fire", impact = "impact_small" },
	PlasmaRifle = { fire = "rifle_fire", impact = "impact_small" },
	StarterBlaster = { fire = "pistol_fire", impact = "impact_small" },
	AetherRaygun = { fire = "rifle_fire", impact = "impact_small" },
	XenoFang = { fire = "pistol_fire", impact = "impact_small" },
	HivePiercer = { fire = "rifle_fire", impact = "impact_small" },
	VoidCannon = { charge = "cannon_charge", fire = "cannon_fire", impact = "explosion" },
	IonRevolver = { fire = "revolver_fire", impact = "impact_small" },
	PhotonSMG = { fire = "smg_fire", impact = "impact_small" },
	PulseShotgun = { fire = "shotgun_fire", impact = "impact_small" },
	FrostNeedler = { fire = "smg_fire", impact = "impact_small" },
	InfernoCannon = { fire = "flame_fire", impact = "explosion" },
	StormCoil = { fire = "lightning_fire", impact = "impact_small" },
	GravitonLauncher = { fire = "cannon_fire", impact = "explosion" },
	Railbreaker = { fire = "rail_fire", impact = "impact_small" },
	VenomSpitter = { fire = "smg_fire", impact = "impact_small" },
	NovaBurstRifle = { fire = "rifle_fire", impact = "impact_small" },
	SolarJudgement = { fire = "holy_fire", impact = "explosion" },
	TempestRepeater = { fire = "lightning_fire", impact = "impact_small" },
	ReapersMaw = { fire = "dark_fire", impact = "impact_small" },
	StarfallLauncher = { fire = "cannon_fire", impact = "explosion" },
	EclipseReaper = { fire = "dark_fire", impact = "explosion" },
	ChronoFracture = { fire = "time_fire", impact = "explosion" },
	GenesisCannon = { fire = "genesis_fire", impact = "impact_small" },
}

local function posOf(inst)
	if typeof(inst) == "Vector3" then
		return inst
	elseif inst and inst:IsA("Attachment") then
		return inst.WorldPosition
	elseif inst and inst:IsA("BasePart") then
		return inst.Position
	end
end

-- except = the shooter (they already played the sound locally the instant they clicked)
local function playSound(where, name, except)
	if not name then
		return
	end
	local pos = posOf(where)
	if not pos then
		return
	end
	for _, p in Players:GetPlayers() do
		if p ~= except then
			fxRemote:FireClient(p, "sfx", name, pos)
		end
	end
end

local function playAt(pos, name)
	playSound(pos, name)
end

local function sparks(pos, color, count, speed)
	local p = emptyPart(CFrame.new(pos))
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.Color = ColorSequence.new(WHITE, color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.3, 0.8)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -40, 0)
	e.Rate = 0
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, 1.5)
end

local function flashLight(pos, color, range, brightness, duration)
	local p = emptyPart(CFrame.new(pos))
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	TweenService:Create(l, TweenInfo.new(duration), { Brightness = 0 }):Play()
	Debris:AddItem(p, duration + 0.1)
end

-- a flat glowing ring that expands along a surface (normal = the surface direction)
local function ringFx(pos, normal, color, endSize, duration)
	local up = (math.abs(normal.Y) > 0.99) and Vector3.xAxis or Vector3.yAxis
	local ring = neonPart(Vector3.new(0.15, 1, 1), CFrame.lookAt(pos + normal * 0.1, pos + normal * 1.1, up) * CFrame.Angles(0, -math.pi / 2, 0), color, Enum.PartType.Cylinder, 0)
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.15, endSize, endSize), Transparency = 1 }):Play()
	Debris:AddItem(ring, duration + 0.1)
end

-- who gets the credit (the hive pays the last attacker; the boss remembers every player's damage)
local function credit(model, hum, shooterChar, weaponId, amount)
	local shooter = Players:GetPlayerFromCharacter(shooterChar)
	if not shooter then return end
	hum:SetAttribute("LastAttacker", shooter.UserId)
	hum:SetAttribute("LastAttackTime", os.clock())
	hum:SetAttribute("LastWeapon", weaponId)
	if model:GetAttribute("TrackDamage") then
		local key = "Dmg_" .. shooter.UserId
		hum:SetAttribute(key, (hum:GetAttribute(key) or 0) + math.min(amount, hum.Health))
	end
end

local function hurt(model, shooterChar, damage, weaponId, cfg)
	if not model or model == shooterChar then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	if Players:GetPlayerFromCharacter(model) and not ALLOW_PVP then
		return false
	end
	if cfg and cfg.execute and model:GetAttribute("IsBoss") ~= true and hum.Health <= hum.MaxHealth * cfg.execute.threshold then
		damage *= cfg.execute.mult -- Reaper weapons: finish the weak
	end
	if (hum:GetAttribute("VulnUntil") or 0) > os.clock() then
		damage *= 1.25 -- marked by the Eclipse Reaper
	end
	if hum:GetAttribute("Invulnerable") then
		return true -- the boss is changing phase: the shot lands, but does nothing
	end
	credit(model, hum, shooterChar, weaponId, damage)
	hum:TakeDamage(damage)
	if cfg and cfg.lifesteal and shooterChar then
		local sh = shooterChar:FindFirstChildOfClass("Humanoid")
		if sh and sh.Health > 0 then
			sh.Health = math.min(sh.MaxHealth, sh.Health + damage * cfg.lifesteal)
		end
	end
	return true
end

----------------------------------------------------------------------
-- how each weapon's shot LOOKS (the numbers are in WEAPONS above)
----------------------------------------------------------------------
local STYLE = {
	StarterBlaster = { trail = 0.14, flare = 1.0 },
	LaserPistol = { trail = 0.2, flare = 1.2 },
	PlasmaRifle = { trail = 0.2, flare = 1.1, sparks = true },
	VoidCannon = { trail = 0.4, flare = 3.0 },
	XenoFang = { trail = 0.26, flare = 1.4, sparks = true },
	HivePiercer = { trail = 0.35, flare = 1.9, rings = true },
	AetherRaygun = { trail = 0.3, flare = 1.8, helix = true, h1 = Color3.fromRGB(255, 70, 225), h2 = Color3.fromRGB(150, 84, 255) },
	IonRevolver = { trail = 0.2, flare = 1.2 },
	PhotonSMG = { trail = 0.12, flare = 0.7 },
	PulseShotgun = { trail = 0.12, flare = 1.6 },
	FrostNeedler = { trail = 0.2, flare = 0.8, sparks = true },
	InfernoCannon = { trail = 0.35, flare = 1.8, sparks = true },
	StormCoil = { trail = 0.2, flare = 1.2, helix = true, h1 = Color3.fromRGB(255, 255, 255), h2 = Color3.fromRGB(120, 170, 255) },
	GravitonLauncher = { trail = 0.5, flare = 2.2 },
	Railbreaker = { trail = 0.6, flare = 1.6, rings = true },
	VenomSpitter = { trail = 0.25, flare = 1.0, sparks = true },
	NovaBurstRifle = { trail = 0.2, flare = 1.2 },
	SolarJudgement = { trail = 0.5, flare = 2.4, rings = true, sparks = true },
	TempestRepeater = { trail = 0.25, flare = 1.3, helix = true, h1 = Color3.fromRGB(255, 255, 255), h2 = Color3.fromRGB(150, 180, 255) },
	ReapersMaw = { trail = 0.35, flare = 1.6, sparks = true },
	StarfallLauncher = { trail = 0.6, flare = 2.6, sparks = true },
	EclipseReaper = { trail = 0.45, flare = 2.2, helix = true, rings = true, h1 = Color3.fromRGB(255, 255, 255), h2 = Color3.fromRGB(150, 70, 255) },
	ChronoFracture = { trail = 0.5, flare = 2.2, rings = true },
	GenesisCannon = { trail = 0.4, flare = 1.8, helix = true, sparks = true, h1 = Color3.fromRGB(255, 80, 120), h2 = Color3.fromRGB(80, 200, 255) },
}

-- a burst of light at the muzzle (a flare ball + a short cone), for everyone to see
local function muzzleBurst(origin, dir, color, scale, rapid)
	if rapid then scale = scale * 0.55 end
	local ball = neonPart(Vector3.new(0.6, 0.6, 0.6) * scale, CFrame.new(origin), WHITE, BALL, 0)
	TweenService:Create(ball, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(2.2, 2.2, 2.2) * scale, Transparency = 1 }):Play()
	Debris:AddItem(ball, 0.15)
	local cone = neonPart(Vector3.new(0.35, 0.35, 2.6) * scale, CFrame.lookAt(origin + dir * 1.2 * scale, origin + dir * 2.4 * scale), color, nil, 0.2)
	TweenService:Create(cone, TweenInfo.new(0.09), { Size = Vector3.new(0.05, 0.05, 4 * scale), Transparency = 1 }):Play()
	Debris:AddItem(cone, 0.12)
	if not rapid then ringFx(origin + dir * 0.4, dir, color, 3.2 * scale, 0.14) end
end

local function addTrail(part, color, lifetime, width)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = lifetime
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(WHITE, color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Parent = part
	return trail
end

----------------------------------------------------------------------
-- chain lightning: the Aether Raygun's shot jumps from alien to alien
----------------------------------------------------------------------
local function arcBetween(p0, p1, color)
	local TweenServiceL = game:GetService("TweenService")
	local DebrisL = game:GetService("Debris")
	local pts = { p0 }
	local d = p1 - p0
	for i = 1, 4 do
		local jitter = Vector3.new((math.random() - 0.5) * 2.6, (math.random() - 0.5) * 2.6, (math.random() - 0.5) * 2.6)
		pts[#pts + 1] = p0 + d * (i / 5) + jitter
	end
	pts[#pts + 1] = p1
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		if len > 0.05 then
			local seg = Instance.new("Part")
			seg.Anchored = true
			seg.CanCollide = false
			seg.CanQuery = false
			seg.CanTouch = false
			seg.CastShadow = false
			seg.Material = Enum.Material.Neon
			seg.Color = color
			seg.Size = Vector3.new(0.4, 0.4, len)
			seg.CFrame = CFrame.lookAt((a + b) / 2, b)
			seg.Parent = workspace
			TweenServiceL:Create(seg, TweenInfo.new(0.32), { Transparency = 1, Size = Vector3.new(0.1, 0.1, len) }):Play()
			DebrisL:AddItem(seg, 0.4)
		end
	end
end

local function chainLightning(char, firstModel, cfg)
	local hitSet = { [firstModel] = true }
	local current = firstModel:GetPivot().Position
	local dmg = cfg.damage
	for _ = 1, cfg.chain.jumps do
		local best, bd
		for _, a in forces() do
			if not hitSet[a] then
				local h = a:FindFirstChildOfClass("Humanoid")
				if h and h.Health > 0 then
					local dist = (a:GetPivot().Position - current).Magnitude
					if dist <= cfg.chain.range and (not bd or dist < bd) then best, bd = a, dist end
				end
			end
		end
		if not best then break end
		hitSet[best] = true
		dmg = dmg * cfg.chain.falloff
		local tpos = best:GetPivot().Position
		local rapid = cfg.cooldown <= 0.2
		if not rapid or rng:NextNumber() < 0.5 then arcBetween(current, tpos, cfg.color) end
		hurt(best, char, dmg, cfg.id, cfg)
		sparks(tpos, cfg.color, rapid and 4 or 10, 20)
		current = tpos
	end
end

----------------------------------------------------------------------
-- bleeding: Xeno Fang bolts leave a wound that keeps hurting for a few seconds
----------------------------------------------------------------------
local function applyBleed(model, shooterChar, cfg)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum or Players:GetPlayerFromCharacter(model) then
		return
	end
	hum:SetAttribute("BleedUntil", os.clock() + cfg.bleed.ticks * cfg.bleed.interval) -- a new hit refreshes the wound
	if hum:GetAttribute("Bleeding") then
		return
	end
	hum:SetAttribute("Bleeding", true)
	task.spawn(function()
		while hum.Parent and hum.Health > 0 and os.clock() < (hum:GetAttribute("BleedUntil") or 0) do
			task.wait(cfg.bleed.interval)
			if hum.Parent and hum.Health > 0 then
				local shooter = Players:GetPlayerFromCharacter(shooterChar)
				if shooter then
					hum:SetAttribute("LastAttacker", shooter.UserId)
					hum:SetAttribute("LastAttackTime", os.clock())
					hum:SetAttribute("LastWeapon", cfg.id)
				end
				hum:TakeDamage(cfg.bleed.damage)
				sparks(model:GetPivot().Position, Color3.fromRGB(255, 40, 70), 8, 16)
			end
		end
		hum:SetAttribute("Bleeding", nil)
	end)
end

----------------------------------------------------------------------
-- status effects: slow, stun, burning, poison, mark; splash blasts, meteors, the time rift
----------------------------------------------------------------------
local function isBoss(model)
	return model:GetAttribute("IsBoss") == true
end

local function applySlow(model, factor, duration)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or Players:GetPlayerFromCharacter(model) then return end
	if isBoss(model) then factor = math.max(factor, 0.75) end -- bosses only slow a little
	local now = os.clock()
	local cur = ((model:GetAttribute("SlowUntil") or 0) > now) and (model:GetAttribute("SlowFactor") or 1) or 1
	model:SetAttribute("SlowFactor", math.min(cur, factor))
	model:SetAttribute("SlowUntil", math.max(model:GetAttribute("SlowUntil") or 0, now + duration))
end

local function applyStun(model, duration)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or Players:GetPlayerFromCharacter(model) or isBoss(model) then return end -- bosses cannot be stunned
	model:SetAttribute("StunUntil", math.max(model:GetAttribute("StunUntil") or 0, os.clock() + duration))
end

-- damage over time: burning / poison (key = the attribute name on the humanoid)
local function applyDot(model, shooterChar, cfg, spec, key, color)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum or Players:GetPlayerFromCharacter(model) then return end
	hum:SetAttribute(key .. "Until", os.clock() + spec.ticks * spec.interval)
	if hum:GetAttribute(key) then return end
	hum:SetAttribute(key, true)
	task.spawn(function()
		while hum.Parent and hum.Health > 0 and os.clock() < (hum:GetAttribute(key .. "Until") or 0) do
			task.wait(spec.interval)
			if hum.Parent and hum.Health > 0 then
				credit(model, hum, shooterChar, cfg.id, spec.damage)
				hum:TakeDamage(spec.damage)
				sparks(model:GetPivot().Position, color, 7, 16)
			end
		end
		hum:SetAttribute(key, nil)
	end)
end

local function applyEffects(model, shooterChar, cfg)
	if not model then return end
	if cfg.bleed then applyBleed(model, shooterChar, cfg) end
	if cfg.burn then applyDot(model, shooterChar, cfg, cfg.burn, "Burn", Color3.fromRGB(255, 140, 40)) end
	if cfg.poison then applyDot(model, shooterChar, cfg, cfg.poison, "Poison", Color3.fromRGB(150, 255, 60)) end
	if cfg.slow then applySlow(model, cfg.slow.factor, cfg.slow.duration) end
	if cfg.stun then applyStun(model, cfg.stun) end
	if cfg.mark then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then hum:SetAttribute("VulnUntil", os.clock() + cfg.mark) end
	end
end

local function areaDamage(char, cfg, pos, radius, damage, skip)
	local seen, any = {}, false
	for _, part in workspace:GetPartBoundsInRadius(pos, radius) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] and model ~= skip then
			seen[model] = true
			if hurt(model, char, damage, cfg.id, cfg) then
				any = true
				applyEffects(model, char, cfg)
			end
		end
	end
	return any
end

-- a small blast (splash on bolts, Starfall meteors)
local function miniBlast(char, cfg, pos, radius, damage, skip)
	ringFx(pos, Vector3.yAxis, cfg.color, radius * 2.4, 0.35)
	sparks(pos, cfg.color, 26, 40)
	flashLight(pos, cfg.color, radius * 2.5, 5, 0.25)
	return areaDamage(char, cfg, pos, radius, damage, skip)
end

local function meteorShower(plr, char, cfg, pos)
	task.spawn(function()
		for _ = 1, cfg.meteors.count do
			task.wait(0.2)
			local off = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-1, 1))
			if off.Magnitude < 0.1 then off = Vector3.xAxis end
			local target = pos + off.Unit * rng:NextNumber(8, cfg.meteors.radius)
			local start = target + Vector3.new(rng:NextNumber(-20, 20), 90, rng:NextNumber(-20, 20))
			local rock = neonPart(Vector3.new(3, 3, 3), CFrame.new(start), Color3.fromRGB(255, 205, 130), BALL, 0)
			addTrail(rock, cfg.color, 0.4, 1.4)
			local t0, dur = os.clock(), 0.35
			while os.clock() - t0 < dur do
				rock.Position = start:Lerp(target, (os.clock() - t0) / dur)
				RunService.Heartbeat:Wait()
			end
			rock:Destroy()
			playAt(target, cfg.sounds and cfg.sounds.impact)
			if miniBlast(char, cfg, target, cfg.meteors.blast, cfg.meteors.damage) then
				fxRemote:FireClient(plr, "hit")
			end
		end
	end)
end

-- Chrono Fracture: a bubble of frozen time
local function createRift(char, cfg, pos)
	local r, dur = cfg.rift.radius, cfg.rift.duration
	local sphere = neonPart(Vector3.new(1, 1, 1) * 2, CFrame.new(pos), Color3.fromRGB(255, 220, 120), BALL, 0.8)
	sphere.Material = Enum.Material.ForceField
	local core = neonPart(Vector3.new(2.5, 2.5, 2.5), CFrame.new(pos), WHITE, BALL, 0.1)
	TweenService:Create(sphere, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(1, 1, 1) * r * 2 }):Play()
	local rings = {}
	for i = 1, 3 do
		local d = r * 2 * (0.55 + i * 0.14)
		rings[i] = neonPart(Vector3.new(0.35, d, d), CFrame.new(pos), Color3.fromRGB(255, 232, 150), Enum.PartType.Cylinder, 0.15)
	end
	ringFx(pos, Vector3.yAxis, cfg.color, r * 3, 0.5)
	task.spawn(function()
		local t0, nextFreeze = os.clock(), 0
		while os.clock() - t0 < dur do
			local t = os.clock() - t0
			for i, ring in rings do
				ring.CFrame = CFrame.new(pos) * CFrame.Angles(t * (1.1 + i * 0.5) * ((i % 2 == 0) and -1 or 1), t * 0.7 * i, t * (0.4 + i * 0.3))
			end
			if os.clock() >= nextFreeze then
				nextFreeze = os.clock() + 0.2
				for _, m in forces() do
					if (m:GetPivot().Position - pos).Magnitude <= r then
						applyStun(m, 0.35)
						applySlow(m, 0.25, 0.5)
					end
				end
			end
			task.wait(0.03)
		end
		for _, p in { sphere, core, table.unpack(rings) } do
			TweenService:Create(p, TweenInfo.new(0.35), { Transparency = 1, Size = p.Size * 1.3 }):Play()
			Debris:AddItem(p, 0.45)
		end
	end)
end

local function spreadDir(dir, degrees)
	local rot = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, rng:NextNumber(0, math.pi * 2)) * CFrame.Angles(math.rad(rng:NextNumber(0, degrees)), 0, 0)
	return rot.LookVector
end

----------------------------------------------------------------------
-- impacts
----------------------------------------------------------------------
local function boltImpact(plr, char, cfg, result)
	local pos, normal = result.Position, result.Normal
	local rapid = cfg.cooldown <= 0.2
	if not rapid or rng:NextNumber() < 0.25 then playAt(pos, cfg.sounds and cfg.sounds.impact) end
	sparks(pos, cfg.color, rapid and 5 or 16, 28)
	if not rapid or rng:NextNumber() < 0.2 then ringFx(pos, normal, cfg.color, 6, 0.28) end
	if not rapid then flashLight(pos, cfg.color, 14, 3, 0.15) end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if hurt(model, char, cfg.damage, cfg.id, cfg) then
		fxRemote:FireClient(plr, "hit")
		applyEffects(model, char, cfg)
		if cfg.chain and model then
			chainLightning(char, model, cfg)
		end
	end
	if cfg.splash then
		miniBlast(char, cfg, pos, cfg.splash.radius, cfg.splash.damage, model)
	end
end

local function explosion(plr, char, cfg, pos, normal)
	playAt(pos, cfg.sounds and cfg.sounds.impact)
	-- fireball + core flash
	local ball = neonPart(Vector3.new(3, 3, 3), CFrame.new(pos), WHITE, BALL, 0)
	TweenService:Create(ball, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(1, 1, 1) * cfg.radius * 2, Transparency = 1, Color = cfg.color }):Play()
	local core = neonPart(Vector3.new(2, 2, 2), CFrame.new(pos), WHITE, BALL, 0)
	TweenService:Create(core, TweenInfo.new(0.25), { Size = Vector3.new(1, 1, 1) * cfg.radius * 0.9, Transparency = 1 }):Play()
	Debris:AddItem(ball, 0.7)
	Debris:AddItem(core, 0.4)
	ringFx(pos, Vector3.yAxis, cfg.color, cfg.radius * 3.4, 0.7)
	ringFx(pos, normal, WHITE, cfg.radius * 2.2, 0.45)
	sparks(pos, cfg.color, 110, 80)
	sparks(pos, WHITE, 40, 45)
	flashLight(pos, cfg.color, 70, 14, 0.7)

	-- camera shake for everyone close to the blast
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - pos).Magnitude
			if d < 150 then
				fxRemote:FireClient(p, "shake", 0.15 + 0.6 * (1 - d / 150), 0.7)
			end
		end
	end

	-- area damage
	local hitSomething = areaDamage(char, cfg, pos, cfg.radius, cfg.damage)
	if hitSomething then
		fxRemote:FireClient(plr, "hit")
	end
	if cfg.meteors then meteorShower(plr, char, cfg, pos) end
	if cfg.rift then createRift(char, cfg, pos) end
end

----------------------------------------------------------------------
-- firing
----------------------------------------------------------------------
local function fireProjectile(plr, char, cfg0, origin, dir, style, thin)
	local cfg = cfg0
	if cfg0.rainbow then
		cfg = setmetatable({ color = Color3.fromHSV((os.clock() * 0.7) % 1, 0.75, 1) }, { __index = cfg0 })
	end
	local W = (cfg0.width or 0.4) * (thin and 0.7 or 1) -- (orb weapons have no width)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local result = workspace:Raycast(origin, dir * cfg.range, params)
	local hits = {}
	if result then
		hits[1] = result
	end
	if cfg.pierce and result then
		-- Hive Piercer: the bolt keeps flying THROUGH alien bodies (up to cfg.pierce of them) and stops at the first wall
		local current = result
		for _ = 1, cfg.pierce do
			local m = current.Instance:FindFirstAncestorOfClass("Model")
			local h = m and m:FindFirstChildOfClass("Humanoid")
			if not h or Players:GetPlayerFromCharacter(m) then
				break
			end
			local ex = params.FilterDescendantsInstances
			table.insert(ex, m)
			params.FilterDescendantsInstances = ex
			local left = cfg.range - (current.Position - origin).Magnitude
			if left < 1 then
				break
			end
			local nxt = workspace:Raycast(current.Position + dir * 0.5, dir * left, params)
			if not nxt then
				result = nil -- flew on into the empty distance
				break
			end
			hits[#hits + 1] = nxt
			current = nxt
			result = nxt
		end
	end
	local hitPos = (hits[#hits] and hits[#hits].Position) or (origin + dir * cfg.range)
	local dist = (hitPos - origin).Magnitude
	local travel = math.clamp(dist / cfg.speed, 0.03, 1.5)

	-- the projectile
	local visuals = {}
	if cfg.kind == "bolt" then
		visuals[1] = neonPart(Vector3.new(W * 2.6, W * 2.6, cfg.length), CFrame.new(origin), cfg.color, nil, 0.45)
		visuals[2] = neonPart(Vector3.new(W, W, cfg.length * 1.05), CFrame.new(origin), WHITE, nil, 0)
	else
		local orbPart = neonPart(Vector3.new(2.8, 2.8, 2.8), CFrame.new(origin), cfg.color, BALL, 0.15)
		visuals[1] = orbPart
		visuals[2] = neonPart(Vector3.new(1.4, 1.4, 1.4), CFrame.new(origin), WHITE, BALL, 0)
		local l = Instance.new("PointLight")
		l.Color = cfg.color
		l.Range = 26
		l.Brightness = 6
		l.Shadows = false
		l.Parent = orbPart
		local trail = Instance.new("ParticleEmitter")
		trail.Texture = SPARKLE
		trail.Color = ColorSequence.new(WHITE, cfg.color)
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) })
		trail.Lifetime = NumberRange.new(0.3, 0.6)
		trail.Speed = NumberRange.new(0, 3)
		trail.SpreadAngle = Vector2.new(180, 180)
		trail.Rate = 90
		trail.Parent = orbPart
	end

	-- every projectile leaves a glowing trail; some weapons add their own signature
	local head = visuals[1]
	if head then
		addTrail(head, cfg.color, style.trail, cfg.kind == "orb" and 1.2 or W * 1.4)
		if style.sparks then
			local em = Instance.new("ParticleEmitter")
			em.Texture = SPARKLE
			em.Color = ColorSequence.new(WHITE, cfg.color)
			em.LightEmission = 1
			em.LightInfluence = 0
			em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
			em.Lifetime = NumberRange.new(0.2, 0.45)
			em.Speed = NumberRange.new(2, 8)
			em.SpreadAngle = Vector2.new(180, 180)
			em.Rate = 120
			em.Parent = head
		end
	end
	local helix = {}
	if style.helix then
		-- the Aether Raygun: two glowing sparks spiral around the bolt
		for i = 1, 2 do
			local hb = neonPart(Vector3.new(0.5, 0.5, 0.5), CFrame.new(origin), (i == 1) and (style.h1 or cfg.color) or (style.h2 or cfg.color), BALL, 0)
			addTrail(hb, hb.Color, 0.25, 0.25)
			helix[i] = hb
			visuals[#visuals + 1] = hb
		end
	end
	local lastRing = 0

	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / travel
		if a >= 1 then
			break
		end
		local pos = origin + dir * (dist * a)
		local cf = CFrame.lookAt(pos, pos + dir)
		for _, v in visuals do
			v.CFrame = cf
		end
		if style.helix then
			local ph = (os.clock() - t0) * 46
			for i, hb in helix do
				local off = (cf.RightVector * math.cos(ph + i * math.pi) + cf.UpVector * math.sin(ph + i * math.pi)) * 1.0
				hb.CFrame = CFrame.new(pos + off)
			end
		end
		if style.rings and os.clock() - lastRing > 0.04 then
			-- the Hive Piercer's lance throws expanding shock rings along its path
			lastRing = os.clock()
			local rg = neonPart(Vector3.new(0.12, 1.5, 1.5), CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.pi / 2, 0), cfg.color, Enum.PartType.Cylinder, 0.2)
			TweenService:Create(rg, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.12, 7, 7), Transparency = 1 }):Play()
			Debris:AddItem(rg, 0.32)
		end
		RunService.Heartbeat:Wait()
	end
	for _, v in visuals do
		v:Destroy()
	end

	-- impact
	if #hits > 0 then
		if cfg.kind == "orb" then
			explosion(plr, char, cfg, hitPos, hits[#hits].Normal)
		else
			for _, r in hits do
				boltImpact(plr, char, cfg, r)
			end
		end
	end
end

local function shoot(plr, char, tool, cfg, target)
	local handle = tool:FindFirstChild("Handle")
	local hum = char:FindFirstChildOfClass("Humanoid")
	cfg.sounds = SOUNDS[tool:GetAttribute("WeaponId")]
	cfg.id = tool:GetAttribute("WeaponId")

	-- Void Cannon: the orb swells and glows while it charges
	if cfg.charge then
		busy[tool] = true
		if handle then
			playSound(handle, cfg.sounds and cfg.sounds.charge, plr)
		end
		local orb = tool:FindFirstChild("ChargeOrb")
		local light = orb and orb:FindFirstChild("CoreLight")
		local baseSize = orb and orb.Size
		local baseBrightness, baseRange = light and light.Brightness, light and light.Range
		if orb then
			TweenService:Create(orb, TweenInfo.new(cfg.charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = baseSize * 2.1 }):Play()
		end
		if light then
			TweenService:Create(light, TweenInfo.new(cfg.charge), { Brightness = 9, Range = 22 }):Play()
		end
		task.wait(cfg.charge)
		local valid = tool.Parent == char and hum and hum.Health > 0
		if orb then
			orb.Size = baseSize
		end
		if light then
			light.Brightness, light.Range = baseBrightness, baseRange
		end
		busy[tool] = nil
		if not valid then
			return
		end
	end

	local muzzle = tool:FindFirstChild("Muzzle", true)
	local origin = muzzle and muzzle.WorldPosition or (handle and handle.Position)
	if not origin then
		return
	end
	local dir = target - origin
	if dir.Magnitude < 1 then
		return
	end
	dir = dir.Unit

	local style = STYLE[cfg.id] or { trail = 0.2, flare = 1 }
	local volleys = cfg.burst and cfg.burst.count or 1
	for v = 1, volleys do
		if v > 1 then
			-- the next round of a burst
			task.wait(cfg.burst.interval)
			if tool.Parent ~= char then break end
			muzzle = tool:FindFirstChild("Muzzle", true)
			origin = muzzle and muzzle.WorldPosition or origin
			local d = target - origin
			if d.Magnitude < 1 then break end
			dir = d.Unit
		end
		-- muzzle flash + firing sound
		shotCount[tool] = (shotCount[tool] or 0) + 1
		local rapid = cfg.cooldown <= 0.2
		if not rapid or shotCount[tool] % 3 == 1 then -- automatic weapons: other players hear every 3rd shot (it was a wall of noise)
			playSound(handle or muzzle, cfg.sounds and cfg.sounds.fire, plr)
		end
		muzzleBurst(origin, dir, cfg.color, style.flare, rapid)
		if muzzle then
			local ml = muzzle:FindFirstChild("MuzzleLight")
			if ml then
				ml.Color = cfg.color
				ml.Enabled = true
				task.delay(0.07, function()
					ml.Enabled = false
				end)
			end
			local mf = muzzle:FindFirstChild("MuzzleFlash")
			if mf then
				mf:Emit(cfg.kind == "orb" and 25 or 8)
			end
		end
		local pellets = cfg.pellets or 1
		for _ = 1, pellets do
			local d = (pellets > 1) and spreadDir(dir, cfg.spread or 6) or dir
			task.spawn(fireProjectile, plr, char, cfg, origin, d, style, pellets > 1)
		end
	end
end

remote.OnServerEvent:Connect(function(plr, tool, target)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or typeof(target) ~= "Vector3" then
		return
	end
	local char = plr.Character
	if not char or tool.Parent ~= char then
		return
	end
	local cfg = WEAPONS[tool:GetAttribute("WeaponId")]
	if not cfg or busy[tool] then
		return
	end
	local now = os.clock()
	if (lastFire[tool] or 0) + cfg.cooldown * 0.85 > now then
		return
	end
	lastFire[tool] = now
	task.spawn(shoot, plr, char, tool, cfg, target)
end)
