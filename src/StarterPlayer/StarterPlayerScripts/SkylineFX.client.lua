-- SkylineFX (LocalScript)
-- Brings the neon city towers (workspace.FloorSkyline.Skyline2) to life, only on your own screen:
--   * a wave of light climbs the glowing bands of every tower (each tower with its own phase)
--   * the lit windows flicker on and off like a real city at night
--   * red warning lamps blink, spire tips pulse
--   * the hologram signs flicker and glitch now and then
-- Towers stream in and out as you move, so everything is registered when it arrives.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local skyline = workspace:WaitForChild("FloorSkyline")
local folder = skyline:WaitForChild("Skyline2")
local rng = Random.new()

local bands, windows, beacons, tips, words = {}, {}, {}, {}, {}
local function register(d)
	if d:IsA("BasePart") then
		local n = d.Name
		if n == "TowerBand" then
			bands[#bands + 1] = { part = d, y = d:GetAttribute("Y") or 0, phase = (d.Position.X + d.Position.Z) * 0.004 }
		elseif n == "TowerWindow" then
			windows[#windows + 1] = { part = d, nextAt = rng:NextNumber(0, 6), lit = true }
		elseif n == "TowerBeacon" then
			beacons[#beacons + 1] = { part = d, phase = d:GetAttribute("Phase") or 0 }
		elseif n == "TowerTip" then
			tips[#tips + 1] = { part = d, light = d:FindFirstChildOfClass("PointLight"), phase = (d.Position.X + d.Position.Z) * 0.01 }
		end
	elseif d:IsA("TextLabel") and d.Name == "Word" then
		words[#words + 1] = { label = d, glitchUntil = 0 }
	end
end
for _, d in folder:GetDescendants() do register(d) end
folder.DescendantAdded:Connect(register)

local function prune(list, key)
	for i = #list, 1, -1 do
		if not list[i][key].Parent then
			table.remove(list, i)
		end
	end
end

-- the Hive Crystals spin and bob
local crystals = {}
task.spawn(function()
	local folderC = workspace:WaitForChild("HiveCrystals", 15)
	if not folderC then return end
	local TILT = CFrame.Angles(math.rad(45), 0, math.rad(35.264))
	local function regC(d)
		if d:IsA("BasePart") and d.Name:match("^Crystal_%d+$") then
			crystals[#crystals + 1] = { part = d, pos = d.Position, phase = d.Position.X * 0.01 }
		end
	end
	for _, d in folderC:GetChildren() do regC(d) end
	folderC.ChildAdded:Connect(regC)
	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		local cp = cam and cam.CFrame.Position
		local now = os.clock()
		for i = #crystals, 1, -1 do
			local c = crystals[i]
			if not c.part.Parent then
				table.remove(crystals, i)
			elseif cp and (c.pos - cp).Magnitude < 1600 then
				c.part.CFrame = CFrame.new(c.pos + Vector3.new(0, math.sin(now * 1.6 + c.phase) * 0.8, 0)) * CFrame.Angles(0, now * 0.9 + c.phase, 0) * TILT
			end
		end
	end)
end)

local t, acc, pruneAt = 0, 0, 6
local FAR = (Players.LocalPlayer:GetAttribute("LowSpec") == true) and 1400 or 3200 -- only animate what is within this distance of the camera
RunService.Heartbeat:Connect(function(dt)
	t += dt
	acc += dt
	if acc < 1 / 15 then
		return
	end
	acc = 0
	local cam = workspace.CurrentCamera
	local cp = cam and cam.CFrame.Position or Vector3.zero

	if t >= pruneAt then
		pruneAt = t + 6
		prune(bands, "part") prune(windows, "part") prune(beacons, "part") prune(tips, "part") prune(words, "label")
	end

	for _, b in bands do
		local p = b.part
		if (p.Position - cp).Magnitude < FAR then
			local wave = 0.5 + 0.5 * math.sin(t * 1.8 - b.y * 0.03 + b.phase)
			p.Transparency = 0.12 + 0.62 * (1 - wave)
		end
	end
	for _, w in windows do
		if t >= w.nextAt then
			w.nextAt = t + rng:NextNumber(1.5, 8)
			w.lit = rng:NextNumber() > 0.3
			w.part.Transparency = w.lit and 0.08 or 0.85
		end
	end
	for _, b in beacons do
		b.part.Transparency = (math.sin(t * 3.2 + b.phase) > 0.2) and 0 or 0.93
	end
	for _, tp in tips do
		if tp.light then
			tp.light.Brightness = 0.7 + 0.5 * math.sin(t * 2.4 + tp.phase)
		end
	end
	for _, w in words do
		local l = w.label
		if t < w.glitchUntil then
			l.TextTransparency = 0.55
		else
			l.TextTransparency = 0.04 + 0.08 * math.sin(t * 5 + l.AbsolutePosition.X * 0.01)
			if rng:NextNumber() < 0.004 then
				w.glitchUntil = t + 0.12
			end
		end
	end
end)
