-- RocketFX (LocalScript) v2
-- * makes the rocket's neon lights flow with colour (cyan -> blue -> purple -> magenta)
-- * spins colour around the three energy rings
-- * door: rim lights turn green while the door is open, the docking-guide rings pulse toward the door,
--   and the sign above the door shows OPEN / CLOSED
-- Only changes colours/text on your own screen.

local RunService = game:GetService("RunService")

local rocket = workspace:WaitForChild("Rocket")

-- The rocket is a big model that arrives on your screen piece by piece. Wait until it has finished
-- arriving (the number of parts stops changing) before collecting the lights to animate.
do
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local lastCount, stableFor = -1, 0
	repeat
		task.wait(0.5)
		local n = #rocket:GetDescendants()
		if n == lastCount then
			stableFor += 1
		else
			stableFor = 0
		end
		lastCount = n
	until stableFor >= 3
end
local fx = rocket:WaitForChild("CoolUpgrades", 10)
local ringsFolder = fx and fx:FindFirstChild("EnergyRings")
local dockFolder = fx and fx:FindFirstChild("DockGuide")
local iris = rocket:WaitForChild("IrisDoor", 10)
local sensor = iris and iris:FindFirstChild("DoorSensor")
local signLabel = sensor and sensor:FindFirstChild("DoorSign") and sensor.DoorSign:FindFirstChild("Label")

local HUE_MIN, HUE_RANGE = 0.5, 0.38            -- cyan (0.5) up to magenta (0.88)
local OPEN_HUE_MIN, OPEN_HUE_RANGE = 0.33, 0.12 -- green to cyan-green while the door is open
local UPDATES_PER_SECOND = 30

local AXIS_Y = 19 -- the hull's centre line (rocket-local Y)
local pivot0 = rocket:GetPivot()

-- Neon parts that flow with colour
local CHASE_NAMES = {
	Stripe = true, DoorRim = true, DoorEdge = true, SealTrim = true,
	FinSideEdge = true, FinBottomEdge = true, Window = true, NoseTip = true, MastTip = true,
	MastBarA = true, MastBarB = true,
	RibGlow = true, SpineGlow = true, AisleStrip = true, OrreryRing = true, WindowFrame = true,
}
local DOOR_NAMES = { DoorRim = true, DoorEdge = true }
local chase = {}
for _, d in rocket:GetDescendants() do
	if d:IsA("BasePart") and CHASE_NAMES[d.Name] and d.Material == Enum.Material.Neon then
		local rel = pivot0:PointToObjectSpace(d.Position)
		local angle = math.atan2(rel.Y - AXIS_Y, rel.X)
		table.insert(chase, { part = d, phase = rel.Z * 0.012 - angle, door = DOOR_NAMES[d.Name] == true })
	end
end

local function collectBeams(container)
	local list = {}
	if container then
		for _, d in container:GetDescendants() do
			if d:IsA("Beam") then
				table.insert(list, { beam = d, ring = d:GetAttribute("Ring"), seg = d:GetAttribute("Seg") })
			end
		end
	end
	return list
end
local beams = collectBeams(ringsFolder)
local dockBeams = collectBeams(dockFolder)

-- door decor: status lamps (amber when closed, green chase when open) + the emblem that fades when the door opens
local decor = rocket:FindFirstChild("DoorDecor")
local doorLamps, emblems = {}, {}
if decor then
	for _, d in decor:GetChildren() do
		if d.Name == "DoorLamp" then
			local rel = pivot0:PointToObjectSpace(d.Position)
			table.insert(doorLamps, { part = d, phase = math.atan2(rel.Y - AXIS_Y, rel.X) })
		elseif d.Name == "DoorEmblem" then
			table.insert(emblems, { part = d, base = d.Transparency, text = d:FindFirstChild("EmblemText") })
		end
	end
end

local SEGMENTS = 48
local t, accum, doorBlend = 0, 0, 0
local lastOpen = nil

RunService.Heartbeat:Connect(function(dt)
	t += dt
	accum += dt
	if accum < 1 / UPDATES_PER_SECOND then
		return
	end
	local step = accum
	accum = 0

	-- door state (set by the server script)
	local isOpen = iris ~= nil and iris:GetAttribute("Open") == true
	doorBlend += ((isOpen and 1 or 0) - doorBlend) * math.min(step * 3, 1)
	if signLabel and isOpen ~= lastOpen then
		lastOpen = isOpen
		signLabel.Text = isOpen and "DOCKING BAY\n<font color='#6dffb0'>OPEN</font>" or "DOCKING BAY\n<font color='#ff7a8a'>CLOSED</font>"
	end

	-- flowing neon
	for _, c in chase do
		local wave = 0.5 + 0.5 * math.sin(t * 1.6 - c.phase)
		local hue = HUE_MIN + HUE_RANGE * wave
		if c.door then
			local openWave = 0.5 + 0.5 * math.sin(t * 5 - c.phase)
			hue += (OPEN_HUE_MIN + OPEN_HUE_RANGE * openWave - hue) * doorBlend
		end
		c.part.Color = Color3.fromHSV(hue, 0.85, 1)
	end

	-- energy rings around the hull
	for _, b in beams do
		local dir = (b.ring % 2 == 0) and -1 or 1
		local wave = 0.5 + 0.5 * math.sin(t * 2.4 * dir - b.seg * (2 * math.pi / SEGMENTS) * 2 + b.ring * 1.7)
		b.beam.Color = ColorSequence.new(Color3.fromHSV(HUE_MIN + HUE_RANGE * wave, 0.8, 1))
		b.beam.Transparency = NumberSequence.new(0.55 - 0.5 * wave)
	end

	-- docking guide: dim blue while closed; green pulses travelling toward the door while open
	for _, b in dockBeams do
		local pulse = 0.5 + 0.5 * math.sin(t * 5 - (3 - b.ring) * 1.3)
		local hue = 0.62 + (0.4 - 0.62) * doorBlend
		b.beam.Color = ColorSequence.new(Color3.fromHSV(hue, 0.8, 1))
		b.beam.Transparency = NumberSequence.new(0.82 - doorBlend * 0.77 * pulse)
	end

	-- door status lamps + emblem
	for _, l in doorLamps do
		local chase = 0.5 + 0.5 * math.sin(t * 6 - l.phase * 2)
		local pulseClosed = 0.75 + 0.25 * math.sin(t * 2.2 + l.phase)
		local v = pulseClosed + (0.4 + 0.6 * chase - pulseClosed) * doorBlend
		local hue = 0.08 + (0.36 - 0.08) * doorBlend
		l.part.Color = Color3.fromHSV(hue, 0.9, v)
	end
	for _, e in emblems do
		e.part.Transparency = e.base + (1 - e.base) * doorBlend
		if e.text then
			e.text.Enabled = doorBlend < 0.5
		end
	end
end)
