-- ReactorFX (LocalScript)
-- Brings the big energy ball in the middle of the alien ship to life (only on your own screen):
--   * gyroscope rings that precess, satellites that orbit them, shards that circle the core
--   * the core, glass and plasma shells breathe, and their colours drift cyan -> violet -> magenta -> gold
--   * crackling lightning between the core and the tesla towers
--   * 12 glowing runes circling it, 10 data cubes with light trails on tilted orbits
--   * shock-ripples rolling out over the floor + a ring of chasing light bolts around the dais
--   * every 6-10 seconds the reactor SURGES: flash, bigger core, brighter lights, sound

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ship = workspace:WaitForChild("AlienShip")
local core = ship:WaitForChild("ReactorCore")
local rng = Random.new()

-- the ship arrives piece by piece: wait until the number of parts stops changing
do
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local last, stable = -1, 0
	repeat
		task.wait(0.5)
		local n = #core:GetDescendants()
		if n == last then
			stable += 1
		else
			stable = 0
		end
		last = n
	until stable >= 3
end

local J = core:GetAttribute("J_Core") or Vector3.new(0, 36, 0)
local baseRel = core:GetAttribute("BaseRel") or CFrame.identity
local spin = { core:GetAttribute("Spin1") or 0.5, core:GetAttribute("Spin2") or -0.35, core:GetAttribute("Spin3") or 0.22 }
local WHITE = Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- collect
----------------------------------------------------------------------
local rings, sats, shards, breathers = {}, {}, {}, {}
local auras, ripples, runes, cubes, bolts = {}, {}, {}, {}, {}
local named = {}
for _, d in core:GetChildren() do
	if d:IsA("BasePart") then
		local n = d.Name
		named[n] = named[n] or d
		if n:find("^CoreRing") then
			table.insert(rings, { part = d, idx = tonumber(d:GetAttribute("Group"):match("%d+")), rest = d:GetAttribute("Rest") })
		elseif n == "Satellite" then
			table.insert(sats, {
				part = d, idx = d:GetAttribute("RingIndex") or 1, rest = d:GetAttribute("Rest"),
				axis = (d:GetAttribute("OrbitAxis") or Vector3.yAxis).Unit, speed = d:GetAttribute("OrbitSpeed") or 1,
				light = d:FindFirstChildOfClass("PointLight"),
			})
		elseif n == "Shard" then
			local rest = d:GetAttribute("Rest")
			table.insert(shards, {
				part = d, R = d:GetAttribute("R") or 20, H = d:GetAttribute("H") or 0, speed = d:GetAttribute("Speed") or 0.4,
				phase = d:GetAttribute("Phase") or 0, rot = rest - rest.Position,
			})
		elseif n == "AuraShell" then
			table.insert(auras, { part = d, idx = d:GetAttribute("Idx"), baseSize = d:GetAttribute("BaseSize"), baseTrans = d:GetAttribute("BaseTrans") })
		elseif n == "Ripple" then
			table.insert(ripples, { part = d, idx = d:GetAttribute("Idx") })
		elseif n == "Rune" then
			table.insert(runes, { part = d, idx = d:GetAttribute("Idx"), label = d:FindFirstChild("BillboardGui") and d.BillboardGui:FindFirstChild("Glyph") })
		elseif n == "DataCube" then
			table.insert(cubes, { part = d, idx = d:GetAttribute("Idx"), trail = d:FindFirstChildOfClass("Trail") })
		elseif n == "DaisBolt" then
			table.insert(bolts, { part = d, idx = d:GetAttribute("Idx") })
		end
		local bs = d:GetAttribute("BaseSize")
		if bs and (n == "CoreShell" or n == "CoreMid" or n == "CoreInner" or n == "CoreHeart") then
			table.insert(breathers, { part = d, base = bs, name = n })
		end
	end
end
local beams = {}
for _, d in core:GetDescendants() do
	if d:IsA("Beam") then
		table.insert(beams, d)
	end
end
local heart = named.CoreHeart
local heartLight = heart and heart:FindFirstChildOfClass("PointLight")
local plasma = heart and heart:FindFirstChild("PlasmaBurst")
local hum = heart and heart:FindFirstChild("ReactorHum")
if hum then
	hum:Play()
end

local function makeSound(id, volume)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 40
	s.RollOffMaxDistance = 300
	s.Parent = heart or core
	return s
end
local zapSound = makeSound(9116277954, 0.5)
local surgeSound = makeSound(9125973257, 0.8)

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local PAL = {
	Color3.fromRGB(80, 240, 255),
	Color3.fromRGB(160, 110, 255),
	Color3.fromRGB(255, 90, 230),
	Color3.fromRGB(255, 200, 110),
}
local function palette(u)
	u = u % #PAL
	local i = math.floor(u)
	local f = u - i
	f = f * f * (3 - 2 * f)
	return PAL[i + 1]:Lerp(PAL[(i + 1) % #PAL + 1], f)
end

local t = 0
local surgeStart, nextSurge = -10, 4
local nextZap = 3
local beamClock = 0

RunService.RenderStepped:Connect(function(dt)
	t += dt
	local pivot = ship:GetPivot() * baseRel
	local col = palette(t * 0.12)

	-- surge timeline
	if t >= nextSurge then
		surgeStart = t
		nextSurge = t + rng:NextNumber(6, 10)
		surgeSound.PlaybackSpeed = rng:NextNumber(0.9, 1.1)
		surgeSound:Play()
	end
	local sx = (t - surgeStart) / 1.6
	local surge = (sx >= 0 and sx <= 1) and math.sin(sx * math.pi) ^ 2 or 0

	if t >= nextZap then
		nextZap = t + rng:NextNumber(2.5, 6)
		zapSound.PlaybackSpeed = rng:NextNumber(0.8, 1.4)
		zapSound:Play()
	end

	-- gyroscope rings, satellites and shards
	local function ringT(idx)
		return CFrame.new(J) * CFrame.Angles(0, t * (spin[idx] or 0), 0) * CFrame.new(-J)
	end
	local ringTs = { ringT(1), ringT(2), ringT(3) }
	for _, r in rings do
		r.part.CFrame = pivot * ringTs[r.idx or 1] * r.rest
		r.part.Transparency = 0.2 + 0.1 * math.sin(t * 2 + (r.idx or 1)) - 0.15 * surge
	end
	for _, s in sats do
		local orbit = CFrame.new(J) * CFrame.fromAxisAngle(s.axis, t * s.speed) * CFrame.new(-J)
		s.part.CFrame = pivot * ringTs[s.idx] * orbit * s.rest
		if s.light then
			s.light.Brightness = 0.6 + 0.3 * math.sin(t * 3 + s.idx) + 1.5 * surge
		end
	end
	for _, s in shards do
		local a = s.phase + t * s.speed
		local pos = J + Vector3.new(math.cos(a) * s.R, s.H + 1.2 * math.sin(t * 0.9 + s.phase), math.sin(a) * s.R)
		s.part.CFrame = pivot * CFrame.new(pos) * s.rot * CFrame.Angles(t * 1.1 + s.phase, t * 0.7, 0)
	end

	-- breathing core + colour drift
	for _, b in breathers do
		local k
		if b.name == "CoreShell" then
			k = 1 + 0.02 * math.sin(t * 1.3)
		elseif b.name == "CoreMid" then
			k = 1 + 0.05 * math.sin(t * 2.1) + 0.12 * surge
			b.part.Color = col
		elseif b.name == "CoreInner" then
			k = 1 + 0.08 * math.sin(t * 3.3) + 0.2 * surge
			b.part.Color = col:Lerp(WHITE, 0.6)
		else
			k = 1 + 0.12 * math.sin(t * 5.2) + 0.7 * surge
		end
		b.part.Size = b.base * k
	end
	if heartLight then
		heartLight.Color = col
		heartLight.Brightness = 1.2 + 0.4 * math.sin(t * 4) + 3 * surge
	end
	if plasma then
		plasma.Rate = 45 + 160 * surge
	end

	-- plasma aura shells
	for _, a in auras do
		local k = 1 + 0.06 * math.sin(t * 1.5 + a.idx) + 0.25 * surge * (a.idx / 3)
		a.part.Size = a.baseSize * k
		a.part.Transparency = math.max(0.5, a.baseTrans - 0.1 * surge)
		a.part.Color = palette(t * 0.12 + a.idx * 0.3)
		a.part.CFrame = pivot * CFrame.new(J) * CFrame.Angles(t * 0.2 * a.idx, t * 0.3, 0)
	end

	-- floor ripples
	for _, r in ripples do
		local u = (t * 0.3 + r.idx / 3) % 1
		local dia = 20 + 135 * u
		r.part.Size = Vector3.new(0.4, dia, dia)
		r.part.CFrame = pivot * CFrame.new(0, 2.35, 0) * CFrame.Angles(0, 0, math.pi / 2)
		r.part.Transparency = 1 - 0.75 * (1 - u) ^ 2
		r.part.Color = col
	end

	-- circling runes
	for _, r in runes do
		local ang = r.idx / 12 * math.pi * 2 + t * 0.22
		local rad = 27 + 2 * math.sin(t * 0.7 + r.idx)
		local pos = Vector3.new(math.cos(ang) * rad, J.Y + 7 * math.sin(t * 0.6 + r.idx * 0.9), math.sin(ang) * rad)
		r.part.CFrame = pivot * CFrame.new(pos)
		if r.label then
			r.label.TextColor3 = palette(t * 0.12 + r.idx * 0.15)
			r.label.TextTransparency = 0.1 + 0.3 * (0.5 + 0.5 * math.sin(t * 3 + r.idx))
		end
	end

	-- data cubes with trails
	for _, c in cubes do
		local radius = 16 + c.idx * 1.9
		local speed = (c.idx % 2 == 0 and 1 or -1) * (0.95 - c.idx * 0.05)
		local a = t * speed + c.idx
		local tilt = CFrame.Angles(c.idx * 0.6, c.idx, 0)
		local pos = J + tilt:VectorToWorldSpace(Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius * 0.8))
		c.part.CFrame = pivot * CFrame.new(pos) * CFrame.Angles(t * 1.4, t * 1.1, 0)
		local cc = palette(t * 0.12 + c.idx * 0.2)
		c.part.Color = cc
		if c.trail then
			c.trail.Color = ColorSequence.new(cc, palette(t * 0.12 + c.idx * 0.2 + 1))
		end
	end

	-- chasing bolts on the dais edge
	for _, b in bolts do
		b.part.Color = palette(t * 0.12 + b.idx * 0.08)
		b.part.Transparency = 0.15 + 0.6 * (0.5 + 0.5 * math.sin(t * 4 - b.idx * 0.55)) - 0.15 * surge
	end

	-- crackling lightning (20 times a second)
	beamClock += dt
	if beamClock >= 0.05 then
		beamClock = 0
		local bc = col:Lerp(WHITE, 0.45)
		for _, b in beams do
			b.CurveSize0 = rng:NextNumber(-5, 5)
			b.CurveSize1 = rng:NextNumber(-5, 5)
			local w = rng:NextNumber(0.25, 0.75) * (1 + 0.9 * surge)
			b.Width0 = w
			b.Width1 = w
			b.Color = ColorSequence.new(bc)
			b.Transparency = NumberSequence.new(rng:NextNumber(0, 0.45))
		end
	end
end)
