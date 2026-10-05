-- MothershipFX (LocalScript)
-- Everything you SEE and HEAR of the mothership event:
--   * a countdown pill ("MOTHERSHIP IN 42:10") under the compass
--   * the DANGER alert when the ship is about to arrive (siren, red edges, hazard bars) and the big arrival cinematic
--   * the boss title card, the boss health bar with phase marks, ability warnings, phase changes, victory / retreat banners
--   * screen shake and red flashes when you are hit
-- The server (MothershipEvent) sends the events; the numbers (state, boss HP, next arrival) are Workspace attributes MS_*.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local ev = RS:WaitForChild("MothershipEvent")
local rng = Random.new()
local C3 = Color3.fromRGB
local RED, GOLD, VIOLET, WHITE = C3(255, 50, 70), C3(255, 210, 110), C3(170, 90, 255), Color3.new(1, 1, 1)
local PHASE_COLOR = { C3(170, 90, 255), C3(255, 60, 90), C3(255, 232, 170) }
local PHASE_NAME = { "I", "II", "III" }

local gui = Instance.new("ScreenGui")
gui.Name = "MothershipUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 92
gui.Parent = player:WaitForChild("PlayerGui")

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do i[k] = v end
	i.Parent = parent
	return i
end
local function label(parent, text, size, color, font, props)
	local p = { BackgroundTransparency = 1, Text = text, TextSize = size, TextColor3 = color, Font = font or Enum.Font.GothamBlack, TextWrapped = true }
	if props then for k, v in props do p[k] = v end end
	return new("TextLabel", p, parent)
end
local function sfx(id, volume, speed)
	local s = new("Sound", { SoundId = "rbxassetid://" .. id, Volume = volume or 1, PlaybackSpeed = speed or 1 }, workspace.CurrentCamera or workspace)
	s:Play()
	Debris:AddItem(s, 10)
	return s
end

----------------------------------------------------------------------
-- camera shake + flashes
----------------------------------------------------------------------
local shakeId = 0
local function shake(intensity, duration)
	shakeId += 1
	local id = shakeId
	task.spawn(function()
		local t0 = os.clock()
		while shakeId == id and os.clock() - t0 < duration do
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not hum then break end
			local fade = 1 - (os.clock() - t0) / duration
			hum.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0) * intensity * fade
			RunService.RenderStepped:Wait()
		end
		if shakeId == id then
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.CameraOffset = Vector3.zero end
		end
	end)
end

local flashFrame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50 }, gui)
local function flash(color, alpha, time)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = alpha
	TweenService:Create(flashFrame, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- red glowing screen edges (the danger vignette)
local edges = {}
local function makeEdge(anchor, pos, size, rot)
	local f = new("Frame", { AnchorPoint = anchor, Position = pos, Size = size, BackgroundColor3 = RED, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 40 }, gui)
	new("UIGradient", { Rotation = rot, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, f)
	edges[#edges + 1] = f
end
makeEdge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90)
makeEdge(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.22), -90)
makeEdge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.16, 1), 0)
makeEdge(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.16, 1), 180)
local dangerUntil, dangerPower = 0, 0.2
local function setEdgesAlpha(a)
	for _, f in edges do f.BackgroundTransparency = a end
end

----------------------------------------------------------------------
-- hazard bars + banners
----------------------------------------------------------------------
local function hazardBar(y, anchorY)
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, anchorY), Position = UDim2.fromScale(0, y), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = C3(255, 200, 30), BorderSizePixel = 0, ZIndex = 45, ClipsDescendants = true, Visible = false }, gui)
	for i = 0, 40 do
		new("Frame", { Position = UDim2.new(0, i * 90 - 20, 0, -10), Size = UDim2.new(0, 45, 3, 0), Rotation = 30, BackgroundColor3 = C3(20, 20, 20), BorderSizePixel = 0, ZIndex = 46 }, bar)
	end
	return bar
end
local topBar, bottomBar = hazardBar(0, 0), hazardBar(1, 1)
local function showHazard(duration)
	for _, b in { topBar, bottomBar } do
		b.Visible = true
		b.Size = UDim2.new(1, 0, 0, 0)
		TweenService:Create(b, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 0, 26) }):Play()
	end
	task.delay(duration, function()
		for _, b in { topBar, bottomBar } do
			TweenService:Create(b, TweenInfo.new(0.4), { Size = UDim2.new(1, 0, 0, 0) }):Play()
			task.delay(0.45, function() b.Visible = false end)
		end
	end)
end

local function banner(big, small, color, duration, y, bigSize)
	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, y or 0.3), Size = UDim2.fromScale(0.9, 0.2), BackgroundTransparency = 1, ZIndex = 48 }, gui)
	local b = label(holder, big, bigSize or 54, color, Enum.Font.GothamBlack, { Size = UDim2.fromScale(1, 0.6), TextStrokeTransparency = 0.3, TextStrokeColor3 = C3(0, 0, 0), TextTransparency = 1, ZIndex = 49 })
	local s = label(holder, small or "", 20, WHITE, Enum.Font.GothamBold, { Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.3), TextStrokeTransparency = 0.4, TextTransparency = 1, ZIndex = 49 })
	local sc = new("UIScale", { Scale = 1.5 }, holder)
	TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(b, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	TweenService:Create(s, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	task.delay(duration, function()
		TweenService:Create(b, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(s, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(holder, 0.6)
	end)
	return holder
end

-- letterbox bars for the cinematics
local function letterbox(parent, on)
	local tb = parent:FindFirstChild("LBTop") or new("Frame", { Name = "LBTop", Size = UDim2.fromScale(1, 0), BackgroundColor3 = C3(0, 0, 0), BorderSizePixel = 0, ZIndex = 44 }, parent)
	local bb = parent:FindFirstChild("LBBottom") or new("Frame", { Name = "LBBottom", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = C3(0, 0, 0), BorderSizePixel = 0, ZIndex = 44 }, parent)
	local size = UDim2.fromScale(1, on and 0.1 or 0)
	TweenService:Create(tb, TweenInfo.new(0.5), { Size = size }):Play()
	TweenService:Create(bb, TweenInfo.new(0.5), { Size = size }):Play()
end

----------------------------------------------------------------------
-- the siren
----------------------------------------------------------------------
local function siren(seconds, volume)
	local s = new("Sound", { SoundId = "rbxassetid://9125973257", Volume = volume or 0.8, Looped = true }, workspace.CurrentCamera or workspace)
	s:Play()
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds do
			s.PlaybackSpeed = 0.75 + 0.55 * (0.5 + 0.5 * math.sin((os.clock() - t0) * 5.2))
			RunService.Heartbeat:Wait()
		end
		TweenService:Create(s, TweenInfo.new(0.6), { Volume = 0 }):Play()
		Debris:AddItem(s, 0.8)
	end)
end

----------------------------------------------------------------------
-- the countdown pill and the boss bar
----------------------------------------------------------------------
local pill = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 122), Size = UDim2.fromOffset(250, 26), BackgroundColor3 = C3(8, 10, 22), BackgroundTransparency = 0.15, BorderSizePixel = 0, Visible = false, ZIndex = 20 }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 13) }, pill)
local pillStroke = new("UIStroke", { Color = C3(120, 70, 200), Thickness = 1.6 }, pill)
local pillText = label(pill, "", 14, WHITE, Enum.Font.GothamBold, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })

local bossBar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 124), Size = UDim2.fromOffset(640, 64), BackgroundTransparency = 1, Visible = false, ZIndex = 30 }, gui)
local bossName = label(bossBar, "THE VOID SOVEREIGN", 22, GOLD, Enum.Font.GothamBlack, { Size = UDim2.new(1, 0, 0, 26), TextStrokeTransparency = 0.4, ZIndex = 31 })
local bossPhase = label(bossBar, "PHASE I", 13, VIOLET, Enum.Font.GothamBold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 6), Size = UDim2.fromOffset(120, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 31 })
local barBG = new("Frame", { Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = C3(10, 8, 22), BorderSizePixel = 0, ZIndex = 31 }, bossBar)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, barBG)
new("UIStroke", { Color = GOLD, Thickness = 2 }, barBG)
local barFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = VIOLET, BorderSizePixel = 0, ZIndex = 32 }, barBG)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, barFill)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(255, 255, 255), C3(160, 160, 160)) }, barFill)
local barGhost = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(255, 255, 255), BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 31 }, barBG)
for _, x in { 0.33, 0.66 } do
	new("Frame", { Position = UDim2.fromScale(x, -0.2), Size = UDim2.new(0, 3, 1.4, 0), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 34 }, barBG)
end
local barText = label(bossBar, "", 13, WHITE, Enum.Font.GothamBold, { Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 0, 14), ZIndex = 31 })
local ghost = 1

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local state = workspace:GetAttribute("MS_State") or "idle"
	local nextAt = workspace:GetAttribute("MS_Next")
	local nowT = workspace:GetServerTimeNow()
	-- the countdown pill
	if (state == "idle" or state == "warning") and nextAt then
		pill.Visible = true
		local left = math.max(0, nextAt - nowT)
		local sec = math.floor(left + 0.5)
		local urgent = state == "warning" or left < 300
		if state == "warning" then
			pillText.Text = string.format("\u{26A0}  MOTHERSHIP ARRIVES IN %02d:%02d  \u{26A0}", sec // 60, sec % 60)
			pillText.TextColor3 = RED:Lerp(WHITE, 0.5 + 0.5 * math.sin(t * 8))
			pillStroke.Color = RED
		else
			pillText.Text = string.format("MOTHERSHIP IN  %d:%02d", sec // 60, sec % 60)
			pillText.TextColor3 = urgent and C3(255, 150, 150) or C3(190, 175, 235)
			pillStroke.Color = urgent and RED or C3(120, 70, 200)
		end
	else
		pill.Visible = false
	end
	-- the boss bar
	local bossOn = state == "boss" or state == "victory"
	bossBar.Visible = bossOn and workspace:GetAttribute("MS_BossHP") ~= nil
	if bossBar.Visible then
		local hp = math.clamp(workspace:GetAttribute("MS_BossHP") or 0, 0, 1)
		barFill.Size = UDim2.fromScale(hp, 1)
		ghost = math.max(hp, ghost - dt * 0.18)
		barGhost.Size = UDim2.fromScale(ghost, 1)
		local ph = math.clamp(workspace:GetAttribute("MS_Phase") or ((hp > 0.66) and 1 or ((hp > 0.33) and 2 or 3)), 1, 3)
		barFill.BackgroundColor3 = PHASE_COLOR[ph]
		bossPhase.Text = "PHASE " .. PHASE_NAME[ph]
		bossPhase.TextColor3 = PHASE_COLOR[ph]
		barText.Text = string.format("%d%%", math.floor(hp * 100 + 0.5))
	end
	-- the danger vignette
	if os.clock() < dangerUntil then
		local a = 1 - dangerPower * (0.5 + 0.5 * math.sin(t * 6))
		setEdgesAlpha(a)
	else
		setEdgesAlpha(1)
	end
end)

----------------------------------------------------------------------
-- the events
----------------------------------------------------------------------
local function panToShip(seconds)
	local cam = workspace.CurrentCamera
	local target = workspace:GetAttribute("MS_TargetPos")
	if not cam or not target then return end
	local start = cam.CFrame
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = (os.clock() - t0) / seconds
		if a >= 1 then
			conn:Disconnect()
			cam.CameraType = Enum.CameraType.Custom
			return
		end
		local tp = workspace:GetAttribute("MS_TargetPos") or target
		local ease = math.sin(math.clamp(a * 1.4, 0, 1) * math.pi / 2)
		local want = CFrame.lookAt(start.Position, tp)
		local back = math.clamp((a - 0.75) / 0.25, 0, 1) -- return to the player's view at the end
		local look = start:Lerp(want, ease)
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = look:Lerp(start, back)
	end)
end

ev.OnClientEvent:Connect(function(kind, a, b)
	if kind == "warn" then
		dangerUntil, dangerPower = os.clock() + 8, 0.55
		siren(6, 0.7)
		showHazard(5.5)
		banner("\u{26A0}  WARNING  \u{26A0}", "UNKNOWN VESSEL ENTERING THE SYSTEM - PREPARE FOR BATTLE", RED, 5.5, 0.28, 48)
		shake(0.15, 1.5)
	elseif kind == "arrive" then
		dangerUntil, dangerPower = os.clock() + 14, 0.8
		siren(11, 1)
		showHazard(10)
		flash(RED, 0.3, 1.2)
		sfx(9112775375, 1.5, 0.5)
		shake(0.5, 8)
		letterbox(gui, true)
		panToShip(6)
		banner("\u{26A0}  MOTHERSHIP  \u{26A0}", "DESTROY IT  -  OR LOSE EVERYTHING", RED, 8, 0.32, 72)
		task.delay(7, function() letterbox(gui, false) end)
		task.delay(8.3, function()
			flash(WHITE, 0.2, 0.9)
			sfx(9065667699, 1.6, 0.5)
			shake(0.9, 1.6)
		end)
	elseif kind == "bossIntro" then
		workspace:SetAttribute("MS_Phase", nil)
		sfx(9112775375, 1.6, 0.4)
		shake(0.4, 5)
		dangerUntil, dangerPower = os.clock() + 5, 0.4
		letterbox(gui, true)
		local holder = banner("THE VOID SOVEREIGN", "RULER OF THE VOID  -  DESTROYER OF WORLDS", GOLD, 6, 0.4, 70)
		task.delay(5.5, function() letterbox(gui, false) end)
		task.delay(6.3, function()
			flash(VIOLET, 0.2, 1)
			sfx(9125973984, 1.2, 0.6)
		end)
	elseif kind == "ability" then
		local ph = math.clamp(b or 1, 1, 3)
		banner(a, nil, PHASE_COLOR[ph]:Lerp(RED, 0.3), 2.2, 0.62, 34)
		sfx(9125974640, 0.5, 0.6)
		dangerUntil, dangerPower = os.clock() + 1.4, 0.25
	elseif kind == "phase" then
		local ph = math.clamp(a or 2, 1, 3)
		workspace:SetAttribute("MS_Phase", ph)
		flash(PHASE_COLOR[ph], 0.25, 1.4)
		shake(0.7, 3)
		sfx(9112775375, 1.6, 0.5)
		dangerUntil, dangerPower = os.clock() + 4, 0.6
		banner("PHASE " .. PHASE_NAME[ph], (ph == 2) and "THE SOVEREIGN IS ENRAGED" or "THE SOVEREIGN UNLEASHES EVERYTHING", PHASE_COLOR[ph], 4, 0.3, 64)
	elseif kind == "bossDeath" then
		shake(0.8, 5)
		letterbox(gui, true)
		sfx(9065667699, 1.6, 0.5)
		task.delay(3.5, function()
			flash(WHITE, 0, 2.2)
			sfx(9125974640, 1.4, 0.8)
			shake(1.2, 2)
		end)
		task.delay(4.5, function() letterbox(gui, false) end)
	elseif kind == "victory" then
		workspace:SetAttribute("MS_Phase", nil)
		task.delay(1.2, function()
			banner("VICTORY", "THE VOID SOVEREIGN HAS FALLEN  -  FIND YOUR CHEST", GOLD, 7, 0.3, 80)
			sfx(9125974640, 1.2, 1.1)
		end)
	elseif kind == "retreat" then
		workspace:SetAttribute("MS_Phase", nil)
		banner("THE MOTHERSHIP RETREATED", "IT WILL RETURN...", C3(180, 180, 220), 6, 0.3, 44)
	elseif kind == "hurt" then
		flash(RED, 0.72, 0.35)
		shake(0.12, 0.25)
	elseif kind == "wave" then
		banner("WAVE " .. tostring(a), tostring(b or 0) .. " HOSTILES LAUNCHED", C3(255, 160, 160), 2.2, 0.8, 26)
	end
end)

----------------------------------------------------------------------
-- SOUND DESIGN of the fight: layered, deep, with echo. Every ability has a warning sound and a release sound.
----------------------------------------------------------------------
local SoundService = game:GetService("SoundService")
local function layered(layers, volume, reverb, bass)
	local cam = workspace.CurrentCamera
	local made = {}
	for _, l in layers do
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. l[1]
		s.Volume = l[2] * (volume or 1)
		s.PlaybackSpeed = l[3]
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = bass or 0
		eq.MidGain = 0
		eq.HighGain = 0
		eq.Parent = s
		local rv = Instance.new("ReverbSoundEffect")
		rv.DecayTime = reverb or 1.8
		rv.Density = 0.9
		rv.Diffusion = 0.85
		rv.DryLevel = 0
		rv.WetLevel = -7
		rv.Parent = s
		s.Parent = cam or workspace
		s:Play()
		Debris:AddItem(s, 12)
		made[#made + 1] = s
	end
	return made
end
local SFXL = {
	lanceCharge = { { 9125973984, 1.0, 0.5 }, { 9112775375, 0.7, 0.6 } },
	lanceFire = { { 9065667699, 1.5, 0.5 }, { 9125973257, 1.2, 0.9 }, { 6290067239, 1.0, 0.7 }, { 9116277954, 0.9, 0.8 } },
	nova = { { 9125973257, 1.3, 0.5 }, { 9065667699, 1.3, 0.6 }, { 9125974640, 0.8, 0.7 } },
	singularity = { { 9112775375, 1.3, 0.4 }, { 9125973433, 0.9, 0.5 }, { 9125973984, 0.7, 0.4 } },
	collapse = { { 129993092121020, 1.6, 0.7 }, { 9065667699, 1.6, 0.5 }, { 9116277954, 1.0, 0.6 } },
	barrage = { { 6603571443, 0.8, 0.55 }, { 9125973257, 0.5, 1.8 } },
	summon = { { 9112775375, 1.3, 0.6 }, { 9125974640, 0.9, 0.6 } },
	meteors = { { 9125973257, 1.1, 1.9 }, { 9112775375, 0.9, 0.5 } },
	phase = { { 9116277954, 1.4, 0.7 }, { 129993092121020, 1.5, 0.6 }, { 9112775375, 1.6, 0.45 }, { 9125974640, 1.1, 0.5 } },
	hurt = { { 9065667699, 0.9, 2.2 }, { 9116277954, 0.45, 1.9 } },
	dodge = { { 9125973257, 1.2, 2.0 }, { 9125974640, 0.9, 2.2 } },
	roar = { { 9112775375, 2.0, 0.35 }, { 9065667699, 1.4, 0.5 }, { 9116277954, 1.1, 0.5 } },
	death = { { 129993092121020, 1.8, 0.6 }, { 9065667699, 1.6, 0.4 }, { 9112775375, 1.5, 0.4 }, { 9116277954, 1.2, 0.5 } },
}
local singularitySounds
ev.OnClientEvent:Connect(function(kind, a, b)
	if kind == "ability" then
		local name = tostring(a)
		if name:find("LANCE") then
			-- a charging whine that climbs while the beam locks onto you
			local s = layered(SFXL.lanceCharge, 1, 1.5, 3)
			TweenService:Create(s[1], TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { PlaybackSpeed = 2.4 }):Play()
		elseif name:find("BARRAGE") then
			layered(SFXL.barrage, 0.8, 1.2, 2)
		elseif name:find("CALLS") then
			layered(SFXL.summon, 1, 2, 4)
		elseif name:find("METEOR") then
			layered(SFXL.meteors, 1, 2.5, 3)
		elseif name:find("SINGULARITY") then
			layered({ { 9125973984, 1.0, 0.45 } }, 1, 2, 4)
		elseif name:find("NOVA") then
			layered({ { 9125973257, 0.8, 0.6 } }, 1, 1.5, 2)
		end
	elseif kind == "abilityFire" then
		if a == "lance" then
			layered(SFXL.lanceFire, 1, 2.2, 6)
			shake(0.5, 0.6)
		elseif a == "nova" then
			layered(SFXL.nova, 1, 2.4, 5)
			shake(0.3, 0.8)
		elseif a == "singularity" then
			singularitySounds = layered(SFXL.singularity, 1, 2.5, 6)
			for _, s in singularitySounds do s.Looped = true end
			task.delay(4.6, function()
				for _, s in singularitySounds or {} do
					TweenService:Create(s, TweenInfo.new(0.4), { Volume = 0 }):Play()
				end
			end)
			shake(0.25, 4.5)
		elseif a == "collapse" then
			layered(SFXL.collapse, 1.1, 3, 8)
			shake(0.9, 1.4)
			flash(VIOLET, 0.35, 0.9)
		elseif a == "barrage" then
			layered(SFXL.barrage, 0.7, 1.2, 2)
		end
	elseif kind == "phase" then
		layered(SFXL.phase, 1.2, 3, 8)
	elseif kind == "bossIntro" then
		layered(SFXL.roar, 1.3, 3, 8)
	elseif kind == "bossDeath" then
		layered(SFXL.death, 1.3, 3, 8)
	elseif kind == "hurt" then
		layered(SFXL.hurt, 0.7, 0.8, 3)
	elseif kind == "dodge" then
		-- you boosted THROUGH the laser
		layered(SFXL.dodge, 1, 1.2, 2)
		flash(C3(90, 255, 160), 0.7, 0.5)
		banner("DODGED!", nil, C3(120, 255, 170), 1.2, 0.62, 44)
		local cam = workspace.CurrentCamera
		if cam then
			local f0 = cam.FieldOfView
			TweenService:Create(cam, TweenInfo.new(0.12), { FieldOfView = f0 + 12 }):Play()
			task.delay(0.15, function() TweenService:Create(cam, TweenInfo.new(0.4), { FieldOfView = f0 }):Play() end)
		end
	end
end)

-- a low rumble under the whole fight, and a heartbeat in the last phase
local rumble
local lastBeat = 0
RunService.Heartbeat:Connect(function()
	local state = workspace:GetAttribute("MS_State")
	local fighting = state == "boss"
	if fighting and not rumble then
		rumble = Instance.new("Sound")
		rumble.SoundId = "rbxassetid://9112775375"
		rumble.Volume = 0
		rumble.PlaybackSpeed = 0.5
		rumble.Looped = true
		rumble.Parent = workspace.CurrentCamera or workspace
		rumble:Play()
		TweenService:Create(rumble, TweenInfo.new(3), { Volume = 0.28 }):Play()
	elseif not fighting and rumble then
		local r = rumble
		rumble = nil
		TweenService:Create(r, TweenInfo.new(2), { Volume = 0 }):Play()
		Debris:AddItem(r, 2.2)
	end
	if fighting and (workspace:GetAttribute("MS_BossHP") or 1) < 0.34 and os.clock() - lastBeat > 0.8 then
		lastBeat = os.clock()
		layered({ { 9065667699, 0.35, 2.4 } }, 1, 0.5, 6) -- the heartbeat of the last phase
	end
end)
