-- WeaponForge v2: a space weapon forge next to every iron machine, with a full crafting sequence.
-- It only starts when its owner brings the resources (Iron + Money). Crafting phases:
--   INTAKE  (resources stream from the tanks into the chamber)
--   FORGING (robot arms weld, lightning arcs, alarms, steam)
--   ASSEMBLING (a scanner sweeps the chamber while a hologram of the weapon materialises)
--   CALIBRATING (flicker, alarms speed up)  ->  shockwave, steam blast, hologram reveal, weapon delivered.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- name shown on the console, resources needed, crafting time in seconds
local RECIPES = {
	{ id = "LaserPistol", name = "LASER PISTOL", iron = 5, money = 100, time = 10, color = Color3.fromRGB(80, 240, 255) },
	{ id = "PlasmaRifle", name = "PLASMA RIFLE", iron = 20, money = 500, time = 16, color = Color3.fromRGB(110, 255, 150) },
	{ id = "VoidCannon", name = "VOID CANNON", iron = 60, money = 2000, time = 26, color = Color3.fromRGB(190, 90, 255) },
}

local COLOR_OFF = Color3.fromRGB(150, 150, 160)
local COLOR_IDLE = Color3.fromRGB(255, 190, 80)
local COLOR_WORK = Color3.fromRGB(100, 255, 150)
local COLOR_BAD = Color3.fromRGB(255, 110, 120)
local LIGHT_OFF = Color3.fromRGB(60, 60, 70)
local ORB_IDLE = Color3.fromRGB(35, 45, 70)
local TANK_IRON = Color3.fromRGB(200, 120, 60)
local TANK_ENERGY = Color3.fromRGB(60, 200, 255)

local T = 0.6              -- base plate thickness
local L1, L2 = 2.6, 1.1    -- robot arm segment lengths
local PI = math.pi
local rng = Random.new()

local rocket = workspace:WaitForChild("Rocket")
local stationsF = rocket:WaitForChild("IronStations")
local weapons = ServerStorage:WaitForChild("Weapons")
local notify = ReplicatedStorage:WaitForChild("ShipNotify")
local fxRemote = ReplicatedStorage:WaitForChild("WeaponFX")

-- sounds (Creator Store audio)
local SND = {
	powerUp = 9125974640,
	scan = 9125973433,
	arc = 9116277954,
	steam = 4772620521,
	surge = 9125973257,
	release = 122710126415943,
	deny = 6603571443,
	hum = 9112839126,
	boom = 6290067239,
	boom2 = 129993092121020,
	tick = 6603571443,
}
local function playSound(parent, id, volume, speed, life, fadeAfter)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 15
	s.RollOffMaxDistance = 170
	-- indoor echo so the sounds feel like they happen in a big metal hall
	local rv = Instance.new("ReverbSoundEffect")
	rv.DecayTime = 1.8
	rv.Density = 0.9
	rv.Diffusion = 0.85
	rv.DryLevel = 0
	rv.WetLevel = -10
	rv.Parent = s
	s.Parent = parent
	s:Play()
	if fadeAfter then
		task.delay(fadeAfter, function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(0.6), { Volume = 0 }):Play()
			end
		end)
	end
	Debris:AddItem(s, life or 4)
	return s
end

local templates = {}
for _, t in weapons:GetChildren() do
	templates[t:GetAttribute("WeaponId")] = t
end

local function getStat(plr, name)
	local ls = plr:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(name)
end

local function owns(plr, id)
	for _, container in { plr:FindFirstChildOfClass("Backpack"), plr.Character, plr:FindFirstChild("StarterGear") } do
		if container then
			for _, c in container:GetChildren() do
				if c:IsA("Tool") and c:GetAttribute("WeaponId") == id then
					return true
				end
			end
		end
	end
	return false
end

local function give(plr, id)
	local template = templates[id]
	if not template then
		warn("WeaponForge: no tool template for " .. id)
		return false
	end
	local backpack = plr:FindFirstChildOfClass("Backpack")
	if backpack then
		template:Clone().Parent = backpack
	end
	local gear = plr:FindFirstChild("StarterGear")
	if gear then
		template:Clone().Parent = gear -- keeps the weapon after you respawn
	end
	return true
end

-- Collect the forges --------------------------------------------------------
local forges = {}
for _, st in stationsF:GetChildren() do
	local m = st:FindFirstChild("Forge")
	if m then
		local f = {
			st = st, model = m, crafting = false, token = 0,
			base = m:WaitForChild("Base"),
			orb = m:WaitForChild("Orb"),
			ring1 = m:WaitForChild("Ring1"),
			ring2 = m:WaitForChild("Ring2"),
			status = m:WaitForChild("StatusLight"),
			tray = m:WaitForChild("OutputTray"),
			scan = m:WaitForChild("ScanPlane"),
			tankIron = m:WaitForChild("TankIron"),
			tankEnergy = m:WaitForChild("TankEnergy"),
			arms = {}, alarms = { m:WaitForChild("AlarmL"), m:WaitForChild("AlarmR") },
			steams = { m:WaitForChild("SteamL"), m:WaitForChild("SteamR") }, arcs = {},
		}
		f.light = f.orb:WaitForChild("ForgeLight")
		f.charge = f.orb:WaitForChild("Charge")
		f.done = f.tray:WaitForChild("Done")
		f.screen = m:WaitForChild("ConsoleScreen"):WaitForChild("ScreenGui"):WaitForChild("Info")
		f.intakeIron = f.orb:WaitForChild("IntakeIron")
		f.intakeEnergy = f.orb:WaitForChild("IntakeEnergy")
		for i = 1, 6 do
			f.arcs[i] = f.orb:WaitForChild("Arc" .. i)
		end
		for _, side in { -1, 1 } do
			local s = side < 0 and "L" or "R"
			table.insert(f.arms, {
				side = side, phase = side * 0.8,
				upper = m:WaitForChild("ArmUpper" .. s),
				lower = m:WaitForChild("ArmLower" .. s),
				tip = m:WaitForChild("ArmTip" .. s),
			})
		end
		table.insert(forges, f)
	end
end

local function originOf(f)
	return f.base.CFrame * CFrame.new(0, -T / 2, 0) -- floor-top centre of the forge
end

local function setScreen(f, text, color)
	f.screen.Text = text
	f.screen.TextColor3 = color
end

-- Robot arm: blend 0 = folded (idle), 1 = reaching the chamber and welding
local function poseArm(f, a, blend, t)
	local O = originOf(f)
	local sway = math.sin(t * 2.2 + a.phase) * 0.35
	local yaw = a.side * (PI / 2 + sway * blend)
	local p1 = 1.5 + (1.0 + 0.2 * math.sin(t * 3 + a.phase) - 1.5) * blend
	local p2 = -2.6 + (-0.35 + 0.35 * math.sin(t * 5 + a.phase * 2) + 2.6) * blend
	local sh = O * CFrame.new(a.side * 4.7, T + 1.2, -1.5) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(p1, 0, 0)
	a.upper.CFrame = sh * CFrame.new(0, 0, -L1 / 2)
	local el = sh * CFrame.new(0, 0, -L1) * CFrame.Angles(p2, 0, 0)
	a.lower.CFrame = el * CFrame.new(0, 0, -L2 / 2)
	a.tip.CFrame = el * CFrame.new(0, 0, -L2 - 0.3)
end

local function steam(f, count)
	for _, v in f.steams do
		v.Steam:Emit(count)
	end
	if count >= 12 then
		playSound(f.steams[1], SND.steam, math.clamp(count / 40, 0.4, 1), 1.1, 2.5, 1.7)
	end
end

local function setAlarms(f, on)
	for _, a in f.alarms do
		a.Transparency = on and 0 or 0.6
		a.AlarmLight.Enabled = on
	end
end

local function setIdle(f)
	f.orb.Material = Enum.Material.SmoothPlastic
	f.orb.Color = ORB_IDLE
	f.orb.Transparency = 0.3
	f.orb.Size = Vector3.new(2.4, 2.4, 2.4)
	f.light.Enabled = false
	f.charge.Rate = 0
	f.intakeIron.Enabled = false
	f.intakeEnergy.Enabled = false
	for _, arc in f.arcs do
		arc.Enabled = false
	end
	f.scan.Transparency = 1
	f.tankIron.Material, f.tankIron.Color = Enum.Material.Metal, TANK_IRON
	f.tankEnergy.Material, f.tankEnergy.Color = Enum.Material.Metal, TANK_ENERGY
	setAlarms(f, false)
	for _, a in f.arms do
		poseArm(f, a, 0, 0)
		a.tip.WeldLight.Enabled = false
	end
	if f.st:GetAttribute("OwnerUserId") then
		f.status.Material = Enum.Material.Neon
		f.status.Color = Color3.fromRGB(255, 60, 60) -- red: waiting for resources
		setScreen(f, "STANDBY\nBRING RESOURCES", COLOR_IDLE)
	else
		f.status.Material = Enum.Material.Metal
		f.status.Color = LIGHT_OFF
		setScreen(f, "OFFLINE", COLOR_OFF)
	end
end

-- shows a message for a few seconds, then goes back to idle
local function showMessage(f, text, color, seconds)
	f.token += 1
	local token = f.token
	setScreen(f, text, color)
	task.delay(seconds, function()
		if f.token == token and not f.crafting then
			setIdle(f)
		end
	end)
end

-- A see-through copy of the weapon, built from the tool template
local function makeHologram(f, recipe)
	local tmpl = templates[recipe.id]
	local m = Instance.new("Model")
	m.Name = "Hologram"
	local handle
	for _, d in tmpl:GetChildren() do
		if d:IsA("BasePart") then
			local c = d:Clone()
			for _, x in c:GetChildren() do
				x:Destroy() -- welds, lights, emitters
			end
			c.Anchored = true
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = false
			c.CastShadow = false
			c.Material = Enum.Material.Neon
			c.Color = recipe.color
			c.Transparency = 0.45
			c.Parent = m
			if d.Name == "Handle" then
				handle = c
			end
		end
	end
	m.PrimaryPart = handle
	-- not inside the rocket model: the rocket's hover would keep re-positioning it and fight the smooth reveal animation
	m.Parent = workspace
	return m
end

local function setHoloTransparency(holo, value)
	for _, p in holo:GetChildren() do
		if p:IsA("BasePart") then
			p.Transparency = value
		end
	end
end

local function shockwave(f, color)
	local O = originOf(f)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Size = Vector3.new(0.3, 4, 4)
	ring.CFrame = O * CFrame.new(0, T + 1, -1.5) * CFrame.Angles(0, 0, PI / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, 26, 26), Transparency = 1 }):Play()
	Debris:AddItem(ring, 1)
end

-- a flat ring of light that expands from a point (used for the launch / landing flashes)
local function ringAt(pos, color, diameter)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Size = Vector3.new(0.3, 3, 3)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, PI / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, diameter, diameter), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.9)
end

-- The crafting sequence -----------------------------------------------------
local function craft(f, plr, recipe)
	f.crafting = true
	f.token += 1
	if f.holo then
		f.holo:Destroy()
		f.holo = nil
	end
	local color = recipe.color
	f.orb.Material = Enum.Material.Neon
	f.orb.Color = color
	f.orb.Transparency = 0.15
	f.light.Color = color
	f.light.Enabled = true
	f.charge.Color = ColorSequence.new(color)
	f.charge.Rate = 40
	f.status.Material = Enum.Material.Neon
	f.status.Color = COLOR_WORK
	local humSound = playSound(f.orb, SND.hum, 0.4, 1, 120) -- machinery rumble while it works
	humSound.Looped = true

	-- CINEMATIC: the crafting player's camera swoops around the forge (see ForgeCinematic), the chamber
	-- light turns the weapon's colour and a tall column of light rises to the ceiling
	local O0 = originOf(f)
	local chamberPos = (O0 * CFrame.new(0, T + 4, -1.5)).Position
	if plr.Parent then
		fxRemote:FireClient(plr, "forgeStart", chamberPos, recipe.name, color, recipe.time)
	end
	local top = f.model:FindFirstChild("ChamberTop")
	local idle = top and top:FindFirstChild("IdleGlow")
	if idle then
		idle.Color = color
		idle.Brightness = 2
		idle.Range = 34
	end
	local column = Instance.new("Part")
	column.Name = "LightColumn"
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	column.CastShadow = false
	column.Shape = Enum.PartType.Cylinder
	column.Material = Enum.Material.Neon
	column.Color = color
	column.Size = Vector3.new(70, 3.4, 3.4)
	column.CFrame = O0 * CFrame.new(0, T + 42, -1.5) * CFrame.Angles(0, 0, PI / 2)
	column.Transparency = 1
	column.Parent = f.model
	TweenService:Create(column, TweenInfo.new(1.5), { Transparency = 0.9 }):Play()
	shockwave(f, color)
	playSound(f.orb, SND.powerUp, 1, 1, 3.5)
	steam(f, 25)

	-- COUNTDOWN: a big floating readout above the machine that everybody can see
	local countPart = Instance.new("Part")
	countPart.Name = "CountdownAnchor"
	countPart.Anchored = true
	countPart.CanCollide = false
	countPart.CanQuery = false
	countPart.CanTouch = false
	countPart.CastShadow = false
	countPart.Transparency = 1
	countPart.Size = Vector3.new(1, 1, 1)
	countPart.CFrame = O0 * CFrame.new(0, T + 17, -1.5)
	countPart.Parent = f.model
	local bb = Instance.new("BillboardGui")
	bb.Name = "Countdown"
	bb.Size = UDim2.fromOffset(300, 190)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 400
	bb.Adornee = countPart
	bb.Parent = countPart
	local cdRoot = Instance.new("Frame")
	cdRoot.AnchorPoint = Vector2.new(0.5, 0.5)
	cdRoot.Position = UDim2.fromScale(0.5, 0.5)
	cdRoot.Size = UDim2.fromScale(1, 1)
	cdRoot.BackgroundTransparency = 1
	cdRoot.Parent = bb
	local cdScale = Instance.new("UIScale")
	cdScale.Parent = cdRoot
	local cdName = Instance.new("TextLabel")
	cdName.Size = UDim2.fromScale(1, 0.2)
	cdName.BackgroundTransparency = 1
	cdName.Font = Enum.Font.Code
	cdName.TextScaled = true
	cdName.TextColor3 = color
	cdName.TextStrokeTransparency = 0.4
	cdName.Text = recipe.name
	cdName.Parent = cdRoot
	local cdCount = Instance.new("TextLabel")
	cdCount.Position = UDim2.fromScale(0, 0.18)
	cdCount.Size = UDim2.fromScale(1, 0.56)
	cdCount.BackgroundTransparency = 1
	cdCount.Font = Enum.Font.GothamBlack
	cdCount.TextScaled = true
	cdCount.TextColor3 = Color3.new(1, 1, 1)
	cdCount.Text = tostring(math.ceil(recipe.time))
	cdCount.Parent = cdRoot
	local cdStroke = Instance.new("UIStroke")
	cdStroke.Color = color
	cdStroke.Thickness = 4
	cdStroke.Parent = cdCount
	local cdBarBG = Instance.new("Frame")
	cdBarBG.Position = UDim2.fromScale(0.1, 0.77)
	cdBarBG.Size = UDim2.fromScale(0.8, 0.07)
	cdBarBG.BackgroundColor3 = Color3.new(0, 0, 0)
	cdBarBG.BackgroundTransparency = 0.45
	cdBarBG.BorderSizePixel = 0
	cdBarBG.Parent = cdRoot
	local cdBarCorner = Instance.new("UICorner")
	cdBarCorner.CornerRadius = UDim.new(0.5, 0)
	cdBarCorner.Parent = cdBarBG
	local cdBarFill = Instance.new("Frame")
	cdBarFill.Size = UDim2.fromScale(0, 1)
	cdBarFill.BackgroundColor3 = color
	cdBarFill.BorderSizePixel = 0
	cdBarFill.Parent = cdBarBG
	local cdBarCorner2 = Instance.new("UICorner")
	cdBarCorner2.CornerRadius = UDim.new(0.5, 0)
	cdBarCorner2.Parent = cdBarFill
	local cdPhase = Instance.new("TextLabel")
	cdPhase.Position = UDim2.fromScale(0, 0.87)
	cdPhase.Size = UDim2.fromScale(1, 0.12)
	cdPhase.BackgroundTransparency = 1
	cdPhase.Font = Enum.Font.Code
	cdPhase.TextScaled = true
	cdPhase.TextColor3 = Color3.fromRGB(200, 215, 255)
	cdPhase.Text = ""
	cdPhase.Parent = cdRoot

	local start = os.clock()
	local last = start
	local spin1, spin2, armBlend = 0, 0, 0
	local lastText, phaseName = "", ""
	local nextWeld, nextSteam, nextArcSound = 0, 3, 0
	local holo
	local LABEL = { INTAKE = "DRAWING RESOURCES", FORGING = "FORGING", ASSEMBLING = "ASSEMBLING", CALIBRATING = "CALIBRATING" }

	while true do
		local now = os.clock()
		local dt = now - last
		last = now
		local e = now - start
		local p = e / recipe.time
		if p >= 1 then
			break
		end

		local phase = (p < 0.15 and "INTAKE") or (p < 0.6 and "FORGING") or (p < 0.9 and "ASSEMBLING") or "CALIBRATING"
		if phase ~= phaseName then
			phaseName = phase
			if phase == "ASSEMBLING" then
				holo = makeHologram(f, recipe)
				f.holo = holo
				holo:ScaleTo(0.15)
				f.scan.Transparency = 0.35
				f.orb.Transparency = 0.7
				playSound(f.orb, SND.scan, 0.8, 0.85, 3)
				steam(f, 12)
			end
			if phase ~= "INTAKE" then
				f.intakeIron.Enabled = false
				f.intakeEnergy.Enabled = false
				f.tankIron.Material, f.tankIron.Color = Enum.Material.Metal, TANK_IRON
				f.tankEnergy.Material, f.tankEnergy.Color = Enum.Material.Metal, TANK_ENERGY
			end
		end

		-- console readout
		local left = math.ceil(recipe.time - e)
		local text = string.format("%s\n%s  %ds", LABEL[phase], recipe.name, left)
		if text ~= lastText then
			lastText = text
			setScreen(f, text, COLOR_WORK)
		end

		-- floating countdown above the machine: last 3 seconds beep, grow and turn red
		if cdCount.Parent then
			local txt = tostring(left)
			if cdCount.Text ~= txt then
				cdCount.Text = txt
				if left <= 3 then
					playSound(f.orb, SND.tick, 0.9, 1.6 + (3 - left) * 0.3, 1.5)
					steam(f, 6)
				end
			end
			local frac = (recipe.time - e) % 1
			if left <= 3 then
				cdScale.Scale = 1 + 0.4 * frac * frac
				cdCount.TextColor3 = Color3.fromRGB(255, 90, 90):Lerp(Color3.new(1, 1, 1), 1 - frac)
			else
				cdScale.Scale = 1
				cdCount.TextColor3 = Color3.new(1, 1, 1)
			end
			cdBarFill.Size = UDim2.fromScale(math.clamp(p, 0, 1), 1)
			cdPhase.Text = LABEL[phase]
		end

		-- orb + energy rings (faster while forging)
		local intensity = (phase == "FORGING" and 1) or (phase == "CALIBRATING" and 1.3) or (phase == "ASSEMBLING" and 0.6) or 0.3
		spin1 += dt * (2 + 6 * intensity)
		spin2 -= dt * (1.5 + 5 * intensity)
		local c = f.orb.CFrame
		f.ring1.CFrame = c * CFrame.Angles(0, spin1, 0) * CFrame.Angles(0.5, 0, 0) * CFrame.Angles(0, 0, PI / 2)
		f.ring2.CFrame = c * CFrame.Angles(0, spin2, 0) * CFrame.Angles(-0.5, 0, 0) * CFrame.Angles(0, 0, PI / 2)
		local baseSize = (phase == "ASSEMBLING" or phase == "CALIBRATING") and 1.5 or 2.4
		f.orb.Size = Vector3.new(1, 1, 1) * (baseSize + 0.25 * math.sin(e * 7))
		f.light.Brightness = (phase == "FORGING" or phase == "CALIBRATING") and rng:NextNumber(3, 6.5) or 2.5

		-- INTAKE: resources stream from the tanks into the chamber
		if phase == "INTAKE" then
			f.intakeIron.Enabled = true
			f.intakeEnergy.Enabled = true
			local flick = (e * 10) % 1 < 0.5
			f.tankIron.Material = flick and Enum.Material.Neon or Enum.Material.Metal
			f.tankIron.Color = Color3.fromRGB(255, 150, 60)
			f.tankEnergy.Material = flick and Enum.Material.Metal or Enum.Material.Neon
			f.tankEnergy.Color = Color3.fromRGB(90, 230, 255)
		end

		-- FORGING: arms weld, lightning arcs, steam, alarms
		local target = (phase == "FORGING") and 1 or 0
		armBlend += (target - armBlend) * math.min(dt * 4, 1)
		for _, a in f.arms do
			poseArm(f, a, armBlend, e)
		end
		if phase == "FORGING" and e >= nextWeld then
			nextWeld = e + 0.2
			local a = f.arms[(math.floor(e / 0.2) % 2) + 1]
			a.tip.Weld:Emit(10)
			a.tip.WeldLight.Enabled = true
			task.delay(0.07, function()
				a.tip.WeldLight.Enabled = false
			end)
		end
		local arcsOn = phase == "FORGING" or phase == "CALIBRATING"
		if arcsOn and e >= nextArcSound then
			nextArcSound = e + rng:NextNumber(0.7, 1.3)
			playSound(f.orb, SND.arc, 0.6, rng:NextNumber(0.9, 1.3), 2.5)
		end		for _, arc in f.arcs do
			arc.Enabled = arcsOn and rng:NextNumber() < 0.65
			if arc.Enabled then
				arc.CurveSize0 = rng:NextNumber(-3, 3)
				arc.CurveSize1 = rng:NextNumber(-3, 3)
			end
		end
		if phase == "FORGING" and e >= nextSteam then
			nextSteam += 4
			steam(f, 14)
		end
		local alarmRate = phase == "CALIBRATING" and 8 or 3
		setAlarms(f, phase ~= "INTAKE" and (e * alarmRate) % 1 < 0.5)

		-- ASSEMBLING / CALIBRATING: scanner + materialising hologram
		if holo and holo.Parent then
			local O = originOf(f)
			f.scan.CFrame = O * CFrame.new(0, T + 1.2 + 6 * (0.5 + 0.5 * math.sin(e * 3.5)), -1.5) * CFrame.Angles(0, 0, PI / 2)
			local grow = math.clamp((p - 0.6) / 0.25, 0, 1)
			holo:ScaleTo(0.15 + 0.7 * grow)
			holo:PivotTo(c * CFrame.Angles(0, e * 1.6, 0))
			if phase == "CALIBRATING" then
				setHoloTransparency(holo, rng:NextNumber(0.25, 0.75))
			end
		end

		task.wait(1 / 15)
	end

	---------------------------------------------------------------
	-- Finale: shockwave, steam blast, hologram reveal, delivery
	---------------------------------------------------------------
	humSound:Destroy()
	f.orb.Size = Vector3.new(2.4, 2.4, 2.4)
	f.scan.Transparency = 1
	for _, arc in f.arcs do
		arc.Enabled = false
	end
	setAlarms(f, false)
	steam(f, 60)
	shockwave(f, color)
	task.delay(0.2, function() shockwave(f, color:Lerp(Color3.new(1, 1, 1), 0.3)) end)
	task.delay(0.4, function() shockwave(f, color) end)
	playSound(f.orb, SND.surge, 1.3, 1, 3)
	playSound(f.orb, SND.boom, 1.3, 0.9, 4)
	playSound(f.orb, SND.boom2, 0.8, 1.1, 4)
	playSound(f.tray, SND.release, 1, 1, 4)
	-- a fountain of sparks erupts from the chamber
	local fountain = Instance.new("ParticleEmitter")
	fountain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fountain.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	fountain.LightEmission = 0.5
	fountain.LightInfluence = 0
	fountain.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	fountain.Lifetime = NumberRange.new(1.2, 2.2)
	fountain.Speed = NumberRange.new(35, 75)
	fountain.Acceleration = Vector3.new(0, -38, 0)
	fountain.SpreadAngle = Vector2.new(35, 35)
	fountain.EmissionDirection = Enum.NormalId.Top
	fountain.Rate = 0
	fountain.Parent = f.orb
	fountain:Emit(150)
	Debris:AddItem(fountain, 3)
	-- the countdown turns into a big "FORGED!" that pops out
	cdCount.Text = "FORGED!"
	cdCount.TextColor3 = color
	cdPhase.Text = recipe.name .. " READY"
	cdBarFill.Size = UDim2.fromScale(1, 1)
	cdScale.Scale = 0.3
	TweenService:Create(cdScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.5 }):Play()
	task.delay(5.6, function()
		if countPart.Parent then
			countPart:Destroy()
		end
	end)
	if plr.Parent then
		fxRemote:FireClient(plr, "forgeReveal", f.tray.Position + Vector3.new(0, 3.2, 0), recipe.name, color)
		fxRemote:FireClient(plr, "shake", 0.6, 1.2)
	end
	-- the light column fades, the chamber light goes back to its calm blue
	column.Transparency = 0.78
	column.Size = Vector3.new(70, 9, 9)
	TweenService:Create(column, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(70, 2, 2) }):Play()
	Debris:AddItem(column, 1.6)
	if idle then
		idle.Color = Color3.fromRGB(120, 220, 255)
		idle.Brightness = 0.9
		idle.Range = 24
	end
	f.done:Emit(70)
	for _, a in f.arms do
		a.tip.Weld:Emit(25)
	end

	local delivered = plr.Parent ~= nil and give(plr, recipe.id)
	if delivered then
		notify:FireClient(plr, string.format("Crafted the %s! Check your backpack.", recipe.name))
	end

	f.crafting = false
	setIdle(f)
	showMessage(f, delivered and "DONE!\nCHECK YOUR BACKPACK" or "DONE!", COLOR_WORK, 4)
	-- blinding flash of light from the chamber
	f.light.Color = color
	f.light.Brightness = 4
	f.light.Enabled = true
	TweenService:Create(f.light, TweenInfo.new(1.2), { Brightness = 0 }):Play()
	task.delay(1.3, function()
		if not f.crafting then
			f.light.Enabled = false
		end
	end)

	-- the finished weapon BLASTS out of the chamber, hangs above the machine, then glides down onto the tray.
	-- The smooth 60 FPS motion is played on every client (WeaponShowFX); the server only keeps time here.
	if holo and holo.Parent then
		f.holo = holo
		setHoloTransparency(holo, 0.25)
		holo:ScaleTo(1.0)
		local SHOW = 6.0
		fxRemote:FireAllClients("weaponShow", holo, f.tray, color, SHOW, recipe.name, recipe.id)
		task.delay(0.9, function()
			ringAt(f.tray.Position + Vector3.new(0, 15, 0), color, 34)
			playSound(f.orb, SND.powerUp, 0.7, 1.4, 3)
		end)
		task.delay(3.7, function()
			ringAt(f.tray.Position + Vector3.new(0, 0.6, 0), color, 24)
			playSound(f.tray, SND.release, 0.7, 1.2, 3)
		end)
		local t0 = os.clock()
		while holo.Parent and f.holo == holo and os.clock() - t0 < SHOW do
			task.wait(0.1)
		end
		if holo.Parent then
			for _, part in holo:GetChildren() do
				if part:IsA("BasePart") then
					TweenService:Create(part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				end
			end
			Debris:AddItem(holo, 0.7)
		end
		if f.holo == holo then
			f.holo = nil
		end
	end
end

local function onButton(f, plr, recipe)
	if f.st:GetAttribute("OwnerUserId") ~= plr.UserId then
		notify:FireClient(plr, "This isn't your forge! Find your own station.")
		return
	end
	if f.crafting then
		notify:FireClient(plr, "The forge is busy crafting!")
		return
	end
	if owns(plr, recipe.id) then
		notify:FireClient(plr, "You already own the " .. recipe.name .. "!")
		return
	end
	local iron, money = getStat(plr, "Iron"), getStat(plr, "Money")
	if not iron or not money then
		return
	end
	if iron.Value < recipe.iron or money.Value < recipe.money then
		-- no resources, no power: the machine stays off
		showMessage(f, string.format("NEED RESOURCES\n%d IRON + $%d", recipe.iron, recipe.money), COLOR_BAD, 3)
		playSound(f.status, SND.deny, 0.6, 0.35, 2)
		setAlarms(f, true)
		task.delay(0.6, function()
			if not f.crafting then
				setAlarms(f, false)
			end
		end)
		notify:FireClient(plr, string.format("Not enough resources! %s needs %d Iron + $%d.", recipe.name, recipe.iron, recipe.money))
		return
	end
	iron.Value -= recipe.iron
	money.Value -= recipe.money
	task.spawn(craft, f, plr, recipe)
end

-- the glass dome of a button sinks in with a click and the ring flashes
local function pressAnim(btn)
	if btn:GetAttribute("Pressing") then
		return
	end
	btn:SetAttribute("Pressing", true)
	local idx = btn.Name:match("%d+")
	local core = btn.Parent:FindFirstChild("BtnCore" .. idx)
	local ring = btn.Parent:FindFirstChild("BtnRing" .. idx)
	local down = Vector3.new(0, -0.22, 0)
	local function nudge(delta)
		-- small relative steps (the rocket hovers, so absolute tweens would drift the button out of place)
		if btn.Parent then
			btn.CFrame += delta
		end
		if core and core.Parent then
			core.CFrame += delta
		end
	end
	if core then
		local l = core:FindFirstChildOfClass("PointLight")
		if l then
			l.Brightness = 4
			TweenService:Create(l, TweenInfo.new(0.5), { Brightness = 1.1 }):Play()
		end
	end
	if ring then
		ring.Transparency = 0
	end
	playSound(btn, SND.tick, 0.55, 2.6, 1)
	task.spawn(function()
		for _ = 1, 3 do
			nudge(down / 3)
			task.wait(0.025)
		end
		task.wait(0.12)
		for _ = 1, 5 do
			nudge(-down / 5)
			task.wait(0.03)
		end
		btn:SetAttribute("Pressing", nil)
	end)
end

-- Wire up every forge
for _, f in forges do
	for i, recipe in RECIPES do
		local btn = f.model:WaitForChild("Btn" .. i)
		local label = btn:WaitForChild("BillboardGui"):WaitForChild("Label")
		label.Text = string.format("%s\n%d IRON + $%d", recipe.name, recipe.iron, recipe.money)
		local prompt = btn:WaitForChild("CraftPrompt")
		prompt.ObjectText = recipe.name
		prompt.ActionText = "Craft"
		prompt.Triggered:Connect(function(plr)
			pressAnim(btn)
			onButton(f, plr, recipe)
		end)
	end
	f.st:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		if not f.crafting then
			setIdle(f)
		end
	end)
	setIdle(f)
end
