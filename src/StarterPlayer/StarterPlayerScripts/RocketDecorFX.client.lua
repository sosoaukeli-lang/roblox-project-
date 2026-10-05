-- RocketDecorFX v2 (LocalScript)
-- Animates the decorations inside the rocket (only on your own screen):
--   * the holo monitors on the walls: bar graphs, waveform, scrolling data, radar sweep, status light
--   * the HOLOGRAPHIC SOLAR SYSTEM in the middle of the hall:
--       - six planets orbit a pulsing sun; their light trails draw the orbits, Earth has a moon, Saturn has rings
--       - glowing rings rise up the hologram column
--       - press E at the table ("Align Planets") for the PLANETARY ALIGNMENT: the planets swing into a perfect
--         line, the sun flares, an energy beam fires through them and a title appears (it also happens by
--         itself every ~70 seconds)
-- The rocket hovers (the server moves it), so everything is placed relative to the rocket every frame.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local rocket = workspace:WaitForChild("Rocket")
local decor = rocket:WaitForChild("RocketDecor")
local rng = Random.new()
local PI = math.pi

local screens = {}
local planets, moon, orbs = {}, nil, {}
local sun, sunLight, sunCentre, sunFlares, orreryBase

local function register(d)
	if d:IsA("SurfaceGui") and d.Name == "ScreenGui" then
		local bg = d:FindFirstChildOfClass("Frame")
		local radar = bg and bg:FindFirstChild("Radar")
		if bg and radar then
			local s = { part = d.Parent, phase = rng:NextNumber(0, 6.28), sweep = radar:FindFirstChild("Sweep"), data = bg:FindFirstChild("Data"), status = bg:FindFirstChild("Status"), bars = {}, waves = {}, nextData = 0 }
			for i = 1, 5 do s.bars[i] = bg:FindFirstChild("Bar" .. i) end
			for i = 1, 14 do s.waves[i] = bg:FindFirstChild("Wave" .. i) end
			table.insert(screens, s)
		end
	elseif d:IsA("BasePart") then
		if d.Name == "OrreryPlanet" then
			planets[d:GetAttribute("Idx") or (#planets + 1)] = { part = d, r = d:GetAttribute("R") or 10, speed = d:GetAttribute("Speed") or 1, idx = d:GetAttribute("Idx") or 1 }
		elseif d.Name == "OrreryMoon" then
			moon = { part = d, parent = d:GetAttribute("Parent"), r = d:GetAttribute("R"), speed = d:GetAttribute("Speed"), phase = d:GetAttribute("Phase") or 0 }
		elseif d.Name == "OrreryRingOrb" then
			table.insert(orbs, { part = d, parent = d:GetAttribute("Parent"), r = d:GetAttribute("R"), speed = d:GetAttribute("Speed"), phase = d:GetAttribute("Phase") or 0 })
		elseif d.Name == "OrrerySun" then
			sun = d
			sunLight = d:FindFirstChildOfClass("PointLight")
			sunFlares = d:FindFirstChild("Flares")
			sunCentre = d:GetAttribute("OrreryCentre")
		elseif d.Name == "OrreryBase" then
			orreryBase = d
		end
	end
end
for _, d in decor:GetDescendants() do register(d) end
decor.DescendantAdded:Connect(register)

----------------------------------------------------------------------
-- local-only extras: rising rings, alignment beam + title, the interact prompt
----------------------------------------------------------------------
local OY_RING, SUN_RING = 16.5, 33
local risers = {}
for i = 1, 3 do
	local r = Instance.new("Part")
	r.Name = "OrreryRiser"
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.CastShadow = false
	r.Shape = Enum.PartType.Cylinder
	r.Material = Enum.Material.Neon
	r.Color = Color3.fromRGB(0, 220, 255)
	r.Size = Vector3.new(0.18, 10, 10)
	r.Transparency = 1
	r.Parent = workspace
	risers[i] = r
end

local titleGui, titleScale, alignBeam, saturnAtt
local function ensureAlignFX()
	if titleGui and titleGui.Parent then
		return true
	end
	if not sun or not planets[6] then
		return false
	end
	titleGui = Instance.new("BillboardGui")
	titleGui.Size = UDim2.fromOffset(420, 90)
	titleGui.StudsOffset = Vector3.new(0, 9, 0)
	titleGui.AlwaysOnTop = false
	titleGui.LightInfluence = 0
	titleGui.MaxDistance = 150
	titleGui.Adornee = sun
	titleGui.Parent = sun
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBlack
	tl.TextScaled = true
	tl.Text = "PLANETARY ALIGNMENT"
	tl.TextColor3 = Color3.fromRGB(255, 220, 140)
	tl.Parent = titleGui
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 120, 40)
	st.Thickness = 3
	st.Parent = tl
	titleScale = Instance.new("UIScale")
	titleScale.Scale = 0
	titleScale.Parent = tl
	saturnAtt = Instance.new("Attachment")
	saturnAtt.Parent = planets[6].part
	alignBeam = Instance.new("Beam")
	alignBeam.Attachment0 = sun:FindFirstChild("SunAtt")
	alignBeam.Attachment1 = saturnAtt
	alignBeam.Width0 = 1.4
	alignBeam.Width1 = 0.5
	alignBeam.Segments = 1
	alignBeam.LightEmission = 1
	alignBeam.LightInfluence = 0
	alignBeam.FaceCamera = true
	alignBeam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(0, 220, 255))
	alignBeam.Transparency = NumberSequence.new(1)
	alignBeam.Parent = sun
	return true
end

local function makeSound(id, volume)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 200
	s.Parent = sun
	return s
end

-- alignment timeline (seconds): swing in -> hold (beam + title) -> release
local IN_T, HOLD_T, OUT_T = 1.8, 3.2, 1.8
local alignStart = nil
local nextAuto = 40
local function startAlignment()
	if alignStart or not sun or not ensureAlignFX() then
		return
	end
	alignStart = os.clock()
	local snd = makeSound(9125973433, 0.5)
	snd:Play()
	task.delay(IN_T, function()
		if sun then
			local boom = makeSound(9125973257, 0.45)
			boom:Play()
			if sunFlares then sunFlares:Emit(70) end
			game:GetService("Debris"):AddItem(boom, 5)
		end
	end)
	game:GetService("Debris"):AddItem(snd, 5)
end

-- an "Align Planets" prompt that only exists on your own screen
task.spawn(function()
	while not orreryBase do task.wait(0.5) end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AlignPrompt"
	prompt.ActionText = "Align Planets"
	prompt.ObjectText = "Holo Orrery"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = orreryBase
	prompt.Triggered:Connect(startAlignment)
end)

----------------------------------------------------------------------
-- animation loop
----------------------------------------------------------------------
local HEX = "0123456789ABCDEF"
local function hexLine()
	local parts = {}
	for i = 1, 4 do
		local a, b = rng:NextInteger(1, 16), rng:NextInteger(1, 16)
		parts[i] = HEX:sub(a, a) .. HEX:sub(b, b)
	end
	return table.concat(parts, " ")
end
local function smooth(u) return u * u * (3 - 2 * u) end

local t, acc = 0, 0
local GREEN = Color3.fromRGB(80, 255, 120)
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local pivot = rocket:GetPivot()

	-- alignment blend: 0 = normal orbits, 1 = perfect line
	local blend, hold = 0, 0
	if alignStart then
		local s = os.clock() - alignStart
		if s < IN_T then
			blend = smooth(s / IN_T)
		elseif s < IN_T + HOLD_T then
			blend, hold = 1, 1
		elseif s < IN_T + HOLD_T + OUT_T then
			blend = 1 - smooth((s - IN_T - HOLD_T) / OUT_T)
			hold = 0
		else
			alignStart = nil
			nextAuto = t + 70
		end
	elseif t >= nextAuto then
		startAlignment()
	end

	if sunCentre and sun and sun.Parent then
		-- sun
		local flare = hold == 1 and (0.5 + 0.5 * math.sin(t * 14)) or 0
		sun.CFrame = pivot * CFrame.new(sunCentre)
		sun.Size = Vector3.new(8, 8, 8) * (1 + 0.07 * math.sin(t * 3) + 0.18 * blend + 0.1 * flare)
		if sunLight then
			sunLight.Brightness = 1.2 + 0.5 * math.sin(t * 3) + 1.4 * blend
		end
		if sunFlares then
			sunFlares.Rate = 12 + 40 * blend
		end

		-- planets, in a swirl or in a line
		local offsets = {}
		for i, p in planets do
			if p.part.Parent then
				local ang = t * p.speed + i * 1.3
				local delta = ((ang + PI) % (2 * PI)) - PI
				local a = ang - delta * blend
				local off = Vector3.new(math.cos(a) * p.r, math.sin(a) * p.r * 0.12 * (1 - blend), math.sin(a) * p.r)
				offsets[i] = off
				p.part.CFrame = pivot * CFrame.new(sunCentre + off) * CFrame.Angles(0, t * 0.8, 0)
			end
		end
		if moon and offsets[moon.parent] and moon.part.Parent then
			local m = t * moon.speed + moon.phase
			local mo = Vector3.new(math.cos(m) * moon.r, 0.3 * math.sin(m * 2), math.sin(m) * moon.r)
			moon.part.CFrame = pivot * CFrame.new(sunCentre + offsets[moon.parent] + mo)
		end
		for _, o in orbs do
			if offsets[o.parent] and o.part.Parent then
				local m = t * o.speed + o.phase
				local local3 = CFrame.Angles(0.45, 0, 0.2):VectorToWorldSpace(Vector3.new(math.cos(m) * o.r, 0, math.sin(m) * o.r))
				o.part.CFrame = pivot * CFrame.new(sunCentre + offsets[o.parent] + local3)
			end
		end

		-- the alignment beam + title
		if titleGui and titleGui.Parent then
			local want = hold
			local cur = titleScale.Scale
			titleScale.Scale = cur + (want - cur) * math.min(dt * 6, 1)
			alignBeam.Transparency = NumberSequence.new(1 - 0.7 * smooth(math.clamp((titleScale.Scale - 0.1) / 0.9, 0, 1)) * (0.8 + 0.2 * math.sin(t * 30)))
		end

		-- rings that rise up the hologram column
		for i, r in risers do
			local u = (t * 0.33 + i / 3) % 1
			local yy = OY_RING + (SUN_RING - OY_RING) * u
			local d = 15 - 9 * u
			r.Size = Vector3.new(0.18, d, d)
			r.CFrame = pivot * CFrame.new(sunCentre.X, yy, sunCentre.Z) * CFrame.Angles(0, 0, PI / 2)
			r.Transparency = 0.25 + 0.75 * u * u
		end
	end

	-- monitors (15 times a second, only nearby ones)
	acc += dt
	if acc < 1 / 15 then
		return
	end
	acc = 0
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for _, s in screens do
		if s.part.Parent and (s.part.Position - camPos).Magnitude < 170 then
			local ph = s.phase
			if s.sweep then
				s.sweep.Rotation = (t * 130 + ph * 60) % 360
			end
			for i, b in s.bars do
				b.Size = UDim2.fromScale(0.05, 0.08 + 0.38 * math.abs(math.sin(t * (1.1 + i * 0.37) + ph + i)))
			end
			for i, w in s.waves do
				local v = math.sin(t * 5 + i * 0.7 + ph) * math.sin(t * 1.3 + i * 0.2)
				w.Position = UDim2.fromScale(0.07 + (i - 1) * 0.0625, 0.82 + 0.07 * v)
				w.Size = UDim2.fromScale(0.035, 0.03 + 0.05 * math.abs(v))
			end
			if s.data and t >= s.nextData then
				s.nextData = t + rng:NextNumber(0.25, 0.6)
				s.data.Text = hexLine() .. "\n" .. hexLine() .. "\n" .. hexLine() .. "\n" .. hexLine()
			end
			if s.status then
				local on = ((t + ph) % 1.2) < 0.8
				s.status.Text = on and "\u{25CF} ONLINE" or "\u{25CB} ONLINE"
				s.status.TextColor3 = on and GREEN or Color3.fromRGB(40, 120, 60)
			end
		end
	end
end)
