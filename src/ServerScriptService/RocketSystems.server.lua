-- RocketSystems: hover animation, IRIS DOOR (24 petals blossom open), engine flicker, beacon blink

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local rocket = workspace:FindFirstChild("Rocket")
if not rocket then
	rocket = workspace:WaitForChild("Rocket", 10)
	if not rocket then return end
end
local iris = rocket:WaitForChild("IrisDoor", 10)
if not iris then return end
local sensor = iris:WaitForChild("DoorSensor", 10)
if not sensor then return end

-- Capture base transform before hovering begins
local basePivot = rocket:GetPivot()
local doorCenterWorld = iris:GetAttribute("DoorCenter")
local doorCenterLocal = basePivot:PointToObjectSpace(doorCenterWorld)

local HOVER_AMP = 3
local HOVER_PERIOD = 8
local OPEN_ANGLE = math.rad(100)
local HINGE_R = 120

-- Build petal animation data: each part lerps between closed and open CFrame
local petals = {}
for _, part in iris:GetChildren() do
	if part:GetAttribute("PanelIndex") then
		local closedLocal = basePivot:ToObjectSpace(part.CFrame)
		local dir = closedLocal.XVector -- radial direction (rocket-local)
		local hinge = doorCenterLocal + dir * HINGE_R
		local axis = Vector3.new(-dir.Y, dir.X, 0) -- tangential axis in door plane
		local rot = CFrame.fromAxisAngle(axis, OPEN_ANGLE)
		local openLocal = CFrame.new(hinge) * rot * CFrame.new(-hinge) * closedLocal
		table.insert(petals, {part = part, closedLocal = closedLocal, openLocal = openLocal})
	end
end

-- AUTOMATIC DOOR: opens by itself when a player gets close, closes again when everybody left
local OPEN_DIST_OUTSIDE = 220 -- studs from the door centre, for players outside (behind the rocket)
local OPEN_DIST_INSIDE = 75   -- studs from the door centre, for players inside the rocket
local HYSTERESIS = 35         -- extra distance before an open door closes again
local CLOSE_DELAY = 1.5       -- seconds of nobody near before the door closes

local openTarget = false
local lastNear = -math.huge
local checkTimer = 0
local doorLight = sensor:FindFirstChild("DoorLight")
local doorBurst = sensor:FindFirstChild("DoorBurst")
local doorSparks = sensor:FindFirstChild("DoorSparks")
iris:SetAttribute("Open", false)

-- Door decor (Rocket.DoorDecor): warning beacons that flash while the door moves + steam vents + mechanical sounds
local decor = rocket:FindFirstChild("DoorDecor")
local decorBeacons, decorVents = {}, {}
if decor then
	for _, d in decor:GetChildren() do
		if d.Name == "DoorBeacon" then
			table.insert(decorBeacons, d)
		elseif d.Name == "DoorVent" then
			table.insert(decorVents, d)
		end
	end
end
local beaconRun = 0
local function flashBeacons(duration)
	beaconRun += 1
	local mine = beaconRun
	task.spawn(function()
		local t0 = os.clock()
		while beaconRun == mine and os.clock() - t0 < duration do
			local on = ((os.clock() - t0) * 3) % 1 < 0.5
			for _, b in decorBeacons do
				b.Transparency = on and 0.05 or 0.7
				local l = b:FindFirstChild("BeaconLight")
				if l then
					l.Enabled = on
				end
			end
			task.wait(0.08)
		end
		if beaconRun == mine then
			for _, b in decorBeacons do
				b.Transparency = 0.6
				local l = b:FindFirstChild("BeaconLight")
				if l then
					l.Enabled = false
				end
			end
		end
	end)
end
local function doorSound(id, volume, speed)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 40
	s.RollOffMaxDistance = 400
	local rv = Instance.new("ReverbSoundEffect")
	rv.DecayTime = 2.5
	rv.WetLevel = -8
	rv.Parent = s
	s.Parent = sensor
	s:Play()
	game:GetService("Debris"):AddItem(s, 6)
end

local function anyoneNear(pivot)
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local rel = pivot:PointToObjectSpace(root.Position) - doorCenterLocal
			local outside = rel.Z < 0 -- the door is at the back; outside is -Z
			local limit = outside and OPEN_DIST_OUTSIDE or OPEN_DIST_INSIDE
			if openTarget then
				limit += HYSTERESIS
			end
			if rel.Magnitude <= limit then
				return true
			end
		end
	end
	return false
end

local function setOpen(state)
	openTarget = state
	iris:SetAttribute("Open", state)
	if doorBurst then doorBurst:Emit(state and 40 or 18) end
	if doorSparks then doorSparks:Emit(state and 50 or 20) end
	-- decor: beacons flash, steam vents blow, heavy mechanical sound
	flashBeacons(3.5)
	for _, v in decorVents do
		v.Steam:Emit(state and 18 or 10)
	end
	doorSound(122710126415943, 1.0, state and 1 or 0.85)
	doorSound(4772620521, 0.5, 1.1)
	if doorLight then
		doorLight.Brightness = state and 6 or 4
		TweenService:Create(doorLight, TweenInfo.new(1.2), { Brightness = state and 2 or 1 }):Play()
	end
end

-- Engine flames + beacons
local flames, beacons = {}, {}
for _, d in rocket:GetDescendants() do
	if d.Name == "EngineFlame" then
		table.insert(flames, d)
	elseif d.Name == "Beacon" then
		table.insert(beacons, d)
	end
end

local rng = Random.new()
local clock = 0
local openAmount = 0
local flickerTimer = 0
local beaconTimer = 0
local beaconOn = true

-- The rocket has ~1000 parts; moving all of them every single frame floods the network and makes
-- walking/flying feel sluggish. 20 updates per second is smooth (each step is only ~0.1 stud).
local HOVER_UPDATES_PER_SECOND = 15
local hoverTimer = 0
local pivot = basePivot

RunService.Heartbeat:Connect(function(dt)
	clock += dt

	-- Gentle hover
	hoverTimer += dt
	if hoverTimer >= 1 / HOVER_UPDATES_PER_SECOND then
		hoverTimer = 0
		local offset = math.sin(clock * (2 * math.pi / HOVER_PERIOD)) * HOVER_AMP
		pivot = basePivot + Vector3.new(0, offset, 0)
		rocket:PivotTo(pivot)
	end

	-- Automatic door: check who is near a few times per second
	checkTimer += dt
	if checkTimer >= 0.2 then
		checkTimer = 0
		if anyoneNear(pivot) then
			lastNear = clock
			if not openTarget then
				setOpen(true)
			end
		elseif openTarget and clock - lastNear > CLOSE_DELAY then
			setOpen(false)
		end
	end

	-- Iris door: smooth approach + smoothstep easing for a dramatic blossom
	openAmount += ((openTarget and 1 or 0) - openAmount) * math.min(dt / 0.35, 1)
	local eased = openAmount * openAmount * (3 - 2 * openAmount)
	for _, p in petals do
		p.part.CFrame = pivot:ToWorldSpace(p.closedLocal:Lerp(p.openLocal, eased))
	end

	-- Engine flame flicker
	flickerTimer += dt
	if flickerTimer >= 0.08 then
		flickerTimer = 0
		for _, flame in flames do
			local pl = flame:FindFirstChildOfClass("PointLight")
			flame.Transparency = rng:NextNumber(0.15, 0.45)
			if pl then pl.Brightness = rng:NextNumber(1, 2) end
		end
	end

	-- Beacon blink
	beaconTimer += dt
	if beaconTimer >= 0.5 then
		beaconTimer = 0
		beaconOn = not beaconOn
		for _, b in beacons do
			b.Transparency = beaconOn and 0 or 0.7
			local pl = b:FindFirstChildOfClass("PointLight")
			if pl then pl.Brightness = beaconOn and 2 or 0.2 end
		end
	end
end)