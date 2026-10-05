-- ConsoleFX (LocalScript)
-- Animates the space computers around the reactor (only on your own screen): the bar graphs, waveform,
-- scrolling data, radar sweep and status light on every screen, the blinking antenna LED and the
-- spinning hologram toy. Screens farther than ~160 studs from you are skipped to save performance.

local RunService = game:GetService("RunService")

local ship = workspace:WaitForChild("AlienShip")
local stations = ship:WaitForChild("Stations")
local rng = Random.new()

do
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local last, stable = -1, 0
	repeat
		task.wait(0.5)
		local n = #stations:GetDescendants()
		if n == last then
			stable += 1
		else
			stable = 0
		end
		last = n
	until stable >= 3
end

local screens, leds, toys = {}, {}, {}
local pivot0 = ship:GetPivot()
for _, d in stations:GetDescendants() do
	if d:IsA("SurfaceGui") and d.Name == "ScreenGui" then
		local bg = d:FindFirstChildOfClass("Frame")
		local radar = bg and bg:FindFirstChild("Radar")
		if bg and radar then
			local s = {
				part = d.Parent,
				main = d.Parent.Name == "MainScreen",
				phase = rng:NextNumber(0, 6.28),
				sweep = radar:FindFirstChild("Sweep"),
				data = bg:FindFirstChild("Data"),
				status = bg:FindFirstChild("Status"),
				bars = {}, waves = {}, blips = {},
				nextData = 0,
			}
			for i = 1, 5 do s.bars[i] = bg:FindFirstChild("Bar" .. i) end
			for i = 1, 14 do s.waves[i] = bg:FindFirstChild("Wave" .. i) end
			for i = 1, 3 do s.blips[i] = radar:FindFirstChild("Blip" .. i) end
			table.insert(screens, s)
		end
	elseif d.Name == "ConsoleLED" and d:IsA("BasePart") then
		table.insert(leds, { part = d, phase = rng:NextNumber(0, 4) })
	elseif d.Name == "HoloToy" and d:IsA("BasePart") then
		table.insert(toys, { part = d, rel = pivot0:ToObjectSpace(d.CFrame), phase = rng:NextNumber(0, 6.28) })
	end
end

local HEX = "0123456789ABCDEF"
local function hexLine()
	local parts = {}
	for i = 1, 4 do
		local a, b = rng:NextInteger(1, 16), rng:NextInteger(1, 16)
		parts[i] = HEX:sub(a, a) .. HEX:sub(b, b)
	end
	return table.concat(parts, " ")
end

local t, acc = 0, 0
local GREEN, DIM = Color3.fromRGB(80, 255, 120), Color3.fromRGB(70, 20, 20)
local RED = Color3.fromRGB(255, 80, 80)

RunService.RenderStepped:Connect(function(dt)
	t += dt
	local pivot = ship:GetPivot()

	-- spinning holograms + blinking antenna lights (every frame, cheap)
	for _, toy in toys do
		toy.part.CFrame = pivot * toy.rel * CFrame.Angles(t * 1.2 + toy.phase, t * 1.7, 0)
	end
	for _, l in leds do
		local on = ((t * 1.6 + l.phase) % 2) < 0.35
		l.part.Color = on and RED or DIM
	end

	-- screen contents (15 times a second, only nearby screens)
	acc += dt
	if acc < 1 / 15 then
		return
	end
	acc = 0
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for _, s in screens do
		if (s.part.Position - camPos).Magnitude < 160 then
			local ph = s.phase
			if s.sweep then
				s.sweep.Rotation = (t * 130 + ph * 60) % 360
			end
			if s.main then
				for i, b in s.bars do
					local h = 0.08 + 0.38 * math.abs(math.sin(t * (1.1 + i * 0.37) + ph + i))
					b.Size = UDim2.fromScale(0.05, h)
				end
				for i, w in s.waves do
					local v = math.sin(t * 5 + i * 0.7 + ph) * math.sin(t * 1.3 + i * 0.2)
					w.Position = UDim2.fromScale(0.07 + (i - 1) * 0.0625, 0.82 + 0.07 * v)
					w.Size = UDim2.fromScale(0.035, 0.03 + 0.05 * math.abs(v))
				end
				for i, bl in s.blips do
					bl.BackgroundTransparency = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(t * 3 + i * 2 + ph))
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
	end
end)
