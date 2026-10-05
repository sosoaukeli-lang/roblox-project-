-- FloorFX (LocalScript) v3 (streaming-safe)
-- Brings the neon world around the floor to life (only on your own screen):
--   * a wave of brightness travels outward along every grid line, colours drift cyan / violet / magenta
--   * 4 big shock-rings roll out from under the rocket
--   * 48 light pulses with glowing trails race along the grid lines
--   * the beacon pylons and the three ring gates pulse
--   * aurora ribbons ripple in colour across the sky
--   * glowing motes drift up around you when you are near the floor
-- The map uses instance streaming, so pieces of the floor arrive and leave as you move: everything is
-- registered when it arrives (ChildAdded / DescendantAdded) instead of being collected once at the start.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local grid = workspace:WaitForChild("FloorGrid")
local skyline = workspace:WaitForChild("FloorSkyline")

local BASE_TRANS = { Minor = 0.4, Major = 0.15, Super = 0.25 }
local CYAN, VIOLET, MAG = Color3.fromRGB(0, 200, 255), Color3.fromRGB(130, 110, 255), Color3.fromRGB(255, 70, 220)
local GOLD = Color3.fromRGB(255, 200, 90)
local PAL = { CYAN, VIOLET, MAG, GOLD }
local function palette(u)
	u = u % #PAL
	local i = math.floor(u)
	local f = u - i
	f = f * f * (3 - 2 * f)
	return PAL[i + 1]:Lerp(PAL[(i + 1) % #PAL + 1], f)
end

local lines, ripples, pylons, pulses, gates, ribbons = {}, {}, {}, {}, {}, {}

local function registerGrid(d)
	local kind = d:GetAttribute("Kind")
	if kind == "Minor" or kind == "Major" or kind == "Super" then
		table.insert(lines, { part = d, kind = kind, dist = math.abs(d:GetAttribute("Pos") or 0) })
	elseif kind == "Ripple" then
		table.insert(ripples, { part = d, idx = d:GetAttribute("Idx") or 1 })
	elseif d.Name == "Pylon" and d:IsA("BasePart") and d.Size.Y > 100 then
		table.insert(pylons, { part = d, light = d:FindFirstChildOfClass("PointLight"), phase = (d.Position.X + d.Position.Z) * 0.01 })
	end
end
local function registerSky(d)
	if d.Name == "DataPulse" and d:IsA("BasePart") then
		table.insert(pulses, {
			part = d, alongZ = d:GetAttribute("AlongZ"), line = d:GetAttribute("Line") or 0,
			speed = d:GetAttribute("Speed") or 200, off = d:GetAttribute("Off") or 0, trail = d:FindFirstChildOfClass("Trail"),
		})
	elseif d.Name == "RingGate" and d:IsA("BasePart") then
		table.insert(gates, { part = d, phase = d.Position.Magnitude * 0.01 })
	elseif d.Name == "AuroraRibbon" and d:IsA("Beam") then
		table.insert(ribbons, { beam = d, idx = d:GetAttribute("Idx") or 1 })
	end
end
for _, d in grid:GetChildren() do registerGrid(d) end
grid.ChildAdded:Connect(registerGrid)
for _, d in skyline:GetDescendants() do registerSky(d) end
skyline.DescendantAdded:Connect(registerSky)

-- landmarks (pylons + ring gates) are a persistent model: always loaded, visible from the rocket
local landmarks = workspace:WaitForChild("Landmarks")
for _, d in landmarks:GetChildren() do
	registerGrid(d)
	registerSky(d)
end
landmarks.ChildAdded:Connect(function(d)
	registerGrid(d)
	registerSky(d)
end)

-- drop entries whose part has streamed out again
local function prune(list, key)
	for i = #list, 1, -1 do
		if not list[i][key].Parent then
			table.remove(list, i)
		end
	end
end

-- glowing motes that follow you (a local-only part with an emitter)
local moteHost = Instance.new("Part")
moteHost.Name = "FloorMotes"
moteHost.Anchored = true
moteHost.CanCollide = false
moteHost.CanQuery = false
moteHost.CanTouch = false
moteHost.Transparency = 1
moteHost.Size = Vector3.new(320, 1, 320)
moteHost.Position = Vector3.new(0, 3, 0)
moteHost.Parent = workspace
local motes = Instance.new("ParticleEmitter")
motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
motes.Shape = Enum.ParticleEmitterShape.Box
motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
motes.EmissionDirection = Enum.NormalId.Top
motes.Color = ColorSequence.new(CYAN, MAG)
motes.LightEmission = 1
motes.LightInfluence = 0
motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 1.1), NumberSequenceKeypoint.new(1, 0) })
motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.1), NumberSequenceKeypoint.new(1, 1) })
motes.Lifetime = NumberRange.new(5, 9)
motes.Speed = NumberRange.new(1, 4)
motes.SpreadAngle = Vector2.new(40, 40)
motes.Rate = 110
motes.Enabled = false
motes.Parent = moteHost

local t, acc, pruneAt = 0, 0, 5
RunService.RenderStepped:Connect(function(dt)
	t += dt

	-- every frame: rings, racing pulses, motes position
	for _, r in ripples do
		local u = (t * 0.11 + r.idx / 4) % 1
		local d = 120 + 1920 * u
		r.part.Size = Vector3.new(0.5, d, d)
		r.part.CFrame = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2)
		r.part.Transparency = 1 - 0.55 * (1 - u) ^ 2
		r.part.Color = CYAN:Lerp(MAG, u)
	end
	for _, p in pulses do
		local c = ((p.off + t * p.speed) % 4096) - 2048
		if p.alongZ then
			p.part.CFrame = CFrame.new(p.line, 1.4, c)
		else
			p.part.CFrame = CFrame.new(c, 1.4, p.line)
		end
	end
	local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if root and root.Position.Y < 250 then
		moteHost.Position = Vector3.new(root.Position.X, 3, root.Position.Z)
		motes.Enabled = true
	else
		motes.Enabled = false
	end

	if t >= pruneAt then
		pruneAt = t + 5
		prune(lines, "part")
		prune(ripples, "part")
		prune(pylons, "part")
		prune(pulses, "part")
		prune(gates, "part")
		prune(ribbons, "beam")
	end

	-- 12 times a second: grid, pylons, gates, aurora, pulse colours
	acc += dt
	if acc < 1 / 12 then
		return
	end
	acc = 0
	local s = 0.5 + 0.5 * math.sin(t * 0.2)
	local minorColor = CYAN:Lerp(VIOLET, s)
	local majorColor = MAG:Lerp(VIOLET, 1 - s)
	for _, l in lines do
		local wave = 0.5 + 0.5 * math.sin(t * 1.6 - l.dist * 0.006)
		l.part.Transparency = BASE_TRANS[l.kind] + 0.28 * wave
		if l.kind == "Minor" then
			l.part.Color = minorColor
		elseif l.kind == "Major" then
			l.part.Color = majorColor
		end
	end
	for _, p in pylons do
		local k = 0.5 + 0.5 * math.sin(t * 2 + p.phase)
		p.part.Transparency = 0.2 + 0.3 * k
		if p.light then
			p.light.Brightness = 1 + 1.2 * k
		end
	end
	for _, g in gates do
		g.part.Transparency = 0.1 + 0.3 * (0.5 + 0.5 * math.sin(t * 3 - g.phase))
	end
	for _, r in ribbons do
		local u = t * 0.07 + r.idx * 0.9
		r.beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, palette(u)),
			ColorSequenceKeypoint.new(0.5, palette(u + 1.3)),
			ColorSequenceKeypoint.new(1, palette(u + 2.6)),
		})
		r.beam.Width0 = 360 + 80 * math.sin(t * 0.3 + r.idx)
		r.beam.Width1 = 120 + 40 * math.sin(t * 0.4 + r.idx * 2)
	end
	for _, p in pulses do
		if p.trail then
			local c = palette(t * 0.15 + p.line * 0.002)
			p.trail.Color = ColorSequence.new(c, c)
			p.part.Color = c
		end
	end
end)
