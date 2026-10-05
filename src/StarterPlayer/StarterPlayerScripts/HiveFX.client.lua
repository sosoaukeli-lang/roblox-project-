-- HiveFX v2 (LocalScript) - everything you see and hear of the alien hives on your own screen:
--   * the hives come alive: each giant eye follows YOU, veins / horn tips pulse, the gates breathe
--   * a compass at the top of the screen points to the NEAREST hive and shows how far it is
--   * ALIEN INVASION banner + red flash + siren when a wave starts, WAVE CLEARED when you finish it
--   * KILL banners for every Reaper you kill: ALIEN SLAIN, DOUBLE KILL, TRIPLE KILL ... RAMPAGE
-- (banner text sits on a dark plate and the outlines fade WITH the text, so it is always readable)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hiveEvent = ReplicatedStorage:WaitForChild("HiveEvent")
local C3 = Color3.fromRGB

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HiveUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 90
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = C3(255, 30, 40)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Parent = gui
local fg = Instance.new("UIGradient")
fg.Rotation = 90
fg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.35, 0.85), NumberSequenceKeypoint.new(0.65, 0.85), NumberSequenceKeypoint.new(1, 0) })
fg.Parent = flash

-- big banner on a dark plate
local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.17)
banner.Size = UDim2.fromScale(0.3, 0.075)
do local lim = Instance.new("UISizeConstraint") lim.MinSize = Vector2.new(300, 58) lim.MaxSize = Vector2.new(620, 110) lim.Parent = banner end
banner.BackgroundColor3 = C3(12, 4, 16)
banner.BackgroundTransparency = 1
banner.BorderSizePixel = 0
banner.Parent = gui
local bannerCorner = Instance.new("UICorner"); bannerCorner.CornerRadius = UDim.new(0.12, 0); bannerCorner.Parent = banner
local bannerStroke = Instance.new("UIStroke"); bannerStroke.Thickness = 2; bannerStroke.Color = C3(255, 70, 80); bannerStroke.Transparency = 1; bannerStroke.Parent = banner
local bannerScale = Instance.new("UIScale")
bannerScale.Scale = 0
bannerScale.Parent = banner
local bTitle = Instance.new("TextLabel")
bTitle.Position = UDim2.fromScale(0.03, 0.06)
bTitle.Size = UDim2.fromScale(0.94, 0.56)
bTitle.BackgroundTransparency = 1
bTitle.Font = Enum.Font.GothamBlack
bTitle.TextScaled = true
bTitle.TextColor3 = C3(255, 70, 80)
bTitle.TextTransparency = 1
bTitle.Text = ""
bTitle.Parent = banner
local bStroke = Instance.new("UIStroke")
bStroke.Thickness = 3
bStroke.Color = C3(20, 0, 6)
bStroke.Transparency = 1
bStroke.Parent = bTitle
local bSub = Instance.new("TextLabel")
bSub.Position = UDim2.fromScale(0.03, 0.66)
bSub.Size = UDim2.fromScale(0.94, 0.28)
bSub.BackgroundTransparency = 1
bSub.Font = Enum.Font.GothamBold
bSub.TextScaled = true
bSub.TextColor3 = C3(255, 240, 240)
bSub.TextTransparency = 1
bSub.Text = ""
bSub.Parent = banner
local bSubStroke = Instance.new("UIStroke")
bSubStroke.Thickness = 2
bSubStroke.Color = C3(20, 0, 6)
bSubStroke.Transparency = 1
bSubStroke.Parent = bSub

-- kill banner
local kill = Instance.new("Frame")
kill.AnchorPoint = Vector2.new(0.5, 0.5)
kill.Position = UDim2.fromScale(0.5, 0.34)
kill.Size = UDim2.fromScale(0.4, 0.075)
kill.BackgroundTransparency = 1
kill.Parent = gui
local killScale = Instance.new("UIScale")
killScale.Scale = 0
killScale.Parent = kill
local kTitle = Instance.new("TextLabel")
kTitle.Size = UDim2.fromScale(1, 1)
kTitle.BackgroundTransparency = 1
kTitle.Font = Enum.Font.GothamBlack
kTitle.TextScaled = true
kTitle.TextColor3 = C3(255, 215, 80)
kTitle.TextTransparency = 1
kTitle.Text = ""
kTitle.Parent = kill
local kStroke = Instance.new("UIStroke")
kStroke.Thickness = 3
kStroke.Color = C3(30, 8, 0)
kStroke.Transparency = 1
kStroke.Parent = kTitle

-- COMPASS: a dial with a big arrow, the hive's name, what it is doing (invasion / next wave countdown) and the distance
local compass = Instance.new("Frame")
compass.Name = "Compass"
compass.AnchorPoint = Vector2.new(0.5, 0)
compass.Position = UDim2.new(0.5, 0, 0, 10)
compass.Size = UDim2.fromOffset(380, 92)
compass.BackgroundColor3 = C3(8, 10, 26)
compass.BackgroundTransparency = 0.12
compass.BorderSizePixel = 0
compass.Parent = gui
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 16); cc.Parent = compass
local pill = compass -- (older code refers to the pill)
local ps = Instance.new("UIStroke"); ps.Color = C3(255, 70, 90); ps.Thickness = 2; ps.Transparency = 0.15; ps.Parent = compass
local cg = Instance.new("UIGradient"); cg.Rotation = 90; cg.Color = ColorSequence.new(C3(22, 24, 52), C3(8, 10, 24)); cg.Parent = compass

local dial = Instance.new("Frame")
dial.AnchorPoint = Vector2.new(0, 0.5)
dial.Position = UDim2.new(0, 12, 0.5, 0)
dial.Size = UDim2.fromOffset(76, 76)
dial.BackgroundColor3 = C3(14, 16, 36)
dial.BorderSizePixel = 0
dial.Parent = compass
local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0.5, 0); dc.Parent = dial
local dialStroke = Instance.new("UIStroke"); dialStroke.Color = C3(255, 70, 90); dialStroke.Thickness = 2.5; dialStroke.Parent = dial
local pulse = Instance.new("Frame")
pulse.AnchorPoint = Vector2.new(0.5, 0.5)
pulse.Position = UDim2.fromScale(0.5, 0.5)
pulse.Size = UDim2.fromScale(1, 1)
pulse.BackgroundTransparency = 1
pulse.BorderSizePixel = 0
pulse.Parent = dial
local pc2 = Instance.new("UICorner"); pc2.CornerRadius = UDim.new(0.5, 0); pc2.Parent = pulse
local pulseStroke = Instance.new("UIStroke"); pulseStroke.Color = C3(255, 70, 90); pulseStroke.Thickness = 2; pulseStroke.Transparency = 1; pulseStroke.Parent = pulse
-- the arrow: a big triangle with a dark outline, it rotates
local arrowHolder = Instance.new("Frame")
arrowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
arrowHolder.Position = UDim2.fromScale(0.5, 0.5)
arrowHolder.Size = UDim2.fromScale(1, 1)
arrowHolder.BackgroundTransparency = 1
arrowHolder.Parent = dial
local arrow = Instance.new("TextLabel")
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Position = UDim2.fromScale(0.5, 0.44)
arrow.Size = UDim2.fromScale(1, 1)
arrow.BackgroundTransparency = 1
arrow.Font = Enum.Font.GothamBlack
arrow.TextSize = 92
arrow.TextColor3 = C3(255, 70, 90)
arrow.Text = "\u{25B2}"
arrow.Parent = arrowHolder
local arrowStroke = Instance.new("UIStroke"); arrowStroke.Color = C3(0, 0, 0); arrowStroke.Thickness = 2.5; arrowStroke.Parent = arrow
local tail = Instance.new("Frame")
tail.AnchorPoint = Vector2.new(0.5, 0)
tail.Position = UDim2.fromScale(0.5, 0.58)
tail.Size = UDim2.fromOffset(9, 20)
tail.BackgroundColor3 = C3(255, 70, 90)
tail.BorderSizePixel = 0
tail.Parent = arrowHolder
local tailStroke = Instance.new("UIStroke"); tailStroke.Color = C3(0, 0, 0); tailStroke.Thickness = 2; tailStroke.Parent = tail

local hiveName = Instance.new("TextLabel")
hiveName.Position = UDim2.fromOffset(100, 6)
hiveName.Size = UDim2.new(1, -110, 0, 32)
hiveName.BackgroundTransparency = 1
hiveName.Font = Enum.Font.GothamBlack
hiveName.TextSize = 29
hiveName.TextXAlignment = Enum.TextXAlignment.Left
hiveName.TextColor3 = C3(255, 70, 90)
hiveName.Text = "ALIEN HIVE"
hiveName.Parent = compass
local statusText = Instance.new("TextLabel")
statusText.Position = UDim2.fromOffset(100, 40)
statusText.Size = UDim2.new(1, -110, 0, 24)
statusText.BackgroundTransparency = 1
statusText.Font = Enum.Font.GothamBold
statusText.TextSize = 19
statusText.TextXAlignment = Enum.TextXAlignment.Left
statusText.TextColor3 = C3(235, 240, 255)
statusText.Text = ""
statusText.Parent = compass
local distText = Instance.new("TextLabel")
distText.Position = UDim2.fromOffset(100, 66)
distText.Size = UDim2.new(1, -110, 0, 20)
distText.BackgroundTransparency = 1
distText.Font = Enum.Font.Gotham
distText.TextSize = 15
distText.TextXAlignment = Enum.TextXAlignment.Left
distText.TextColor3 = C3(170, 185, 215)
distText.Text = ""
distText.Parent = compass
local pillText = statusText -- (older code refers to these names)
local timeLeft = 1e9

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function beep(id, volume, speed)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
end

local bannerToken = 0
local function showBanner(title, sub, color, hold)
	bannerToken += 1
	local my = bannerToken
	bTitle.Text = title
	bTitle.TextColor3 = color
	bSub.Text = sub or ""
	bannerStroke.Color = color
	-- everything visible at once (text, outlines, plate)
	bTitle.TextTransparency = 0
	bSub.TextTransparency = 0
	bStroke.Transparency = 0
	bSubStroke.Transparency = 0
	bannerStroke.Transparency = 0.2
	banner.BackgroundTransparency = 0.35
	bannerScale.Scale = 0.2
	TweenService:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(hold, function()
		if my ~= bannerToken then return end
		-- everything fades together: text, outlines AND plate
		local ti = TweenInfo.new(0.6)
		TweenService:Create(bTitle, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(bSub, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(bStroke, ti, { Transparency = 1 }):Play()
		TweenService:Create(bSubStroke, ti, { Transparency = 1 }):Play()
		TweenService:Create(bannerStroke, ti, { Transparency = 1 }):Play()
		TweenService:Create(banner, ti, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(bannerScale, ti, { Scale = 1.1 }):Play()
	end)
end

local killToken = 0
local STREAK_NAMES = { "ALIEN SLAIN", "DOUBLE KILL", "TRIPLE KILL", "QUAD KILL", "RAMPAGE!" }
local function showKill(streak, reward)
	killToken += 1
	local my = killToken
	kTitle.Text = STREAK_NAMES[math.min(streak, #STREAK_NAMES)] .. "   +$" .. reward
	kTitle.TextColor3 = C3(255, 215, 80):Lerp(C3(255, 80, 80), math.clamp((streak - 1) / 4, 0, 1))
	kTitle.TextTransparency = 0
	kStroke.Transparency = 0
	killScale.Scale = 0.3
	TweenService:Create(killScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 + math.min(streak - 1, 4) * 0.08 }):Play()
	beep(6603571443, 0.35, 2.0 + 0.25 * math.min(streak, 4))
	task.delay(1.8, function()
		if my ~= killToken then return end
		TweenService:Create(kTitle, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(kStroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	end)
end

local function redFlash(strength, seconds)
	flash.BackgroundTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(seconds), { BackgroundTransparency = 1 }):Play()
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		local old = cc.TintColor
		cc.TintColor = C3(255, 150, 150)
		TweenService:Create(cc, TweenInfo.new(seconds + 1.2), { TintColor = old }):Play()
	end
end

hiveEvent.OnClientEvent:Connect(function(kind, a, b)
	if kind == "wave" then
		redFlash(0.22, 1.2)
		showBanner("\u{2620} ALIEN INVASION \u{2620}", "HIVE " .. tostring(b) .. "  -  " .. a .. " XENO REAPERS HAVE ESCAPED", C3(255, 90, 100), 4.2)
		for i = 0, 2 do
			task.delay(i * 0.55, function()
				beep(9125973433, 0.55, 0.5)
				redFlash(0.08, 0.35)
			end)
		end
	elseif kind == "titan" then
		redFlash(0.3, 1.6)
		showBanner("\u{2620} XENO TITAN \u{2620}", "HIVE " .. tostring(a) .. "  -  SOMETHING ENORMOUS HAS AWAKENED", C3(255, 200, 90), 5)
		for i = 0, 4 do
			task.delay(i * 0.5, function() beep(9125973433, 0.45, 0.4) redFlash(0.1, 0.35) end)
		end
	elseif kind == "kill" then
		showKill(a, b)
	elseif kind == "cleared" then
		showBanner("WAVE CLEARED", "HIVE " .. tostring(b) .. "  -  " .. a .. " aliens destroyed,  $" .. (a * 30) .. " earned", C3(120, 255, 150), 3.5)
		beep(9125974640, 0.6, 1.2)
	end
end)

----------------------------------------------------------------------
-- the living hives + compass
----------------------------------------------------------------------
local known = {}
local veins, tips, gates, shards, searches = {}, {}, {}, {}, {}
local hiveEyes = {} -- [hiveModel] = { eye, iris, pupil, offX, offY }
local function scan()
	local container = workspace:FindFirstChild("AlienHives")
	if not container then return end
	for _, hive in container:GetChildren() do
		local H = hiveEyes[hive]
		if not H then
			H = { offX = 0, offY = 0 }
			hiveEyes[hive] = H
		end
		for _, d in hive:GetChildren() do
			if d:IsA("BasePart") and not known[d] then
				known[d] = true
				if d.Name == "HiveVein" then
					table.insert(veins, { part = d, phase = d.Position.Y * 0.08 + d.Position.X * 0.03 })
				elseif d.Name == "HiveSpikeTip" or d.Name == "HiveHornTip" or d.Name == "HiveCrownTip" or d.Name == "HiveClawTip" or d.Name == "HiveTuskTip" then
					table.insert(tips, { part = d, phase = d.Position.X * 0.05 + d.Position.Z * 0.04, accent = hive:GetAttribute("Accent") or C3(255, 70, 80) })
				elseif d.Name == "HiveShard" then
					table.insert(shards, { part = d, base = hive:GetAttribute("BaseCF"), r = d:GetAttribute("R"), y = d:GetAttribute("Y"), speed = d:GetAttribute("Speed"), phase = d:GetAttribute("Phase") })
				elseif d.Name == "HiveSearch" then
					table.insert(searches, { part = d, base = hive:GetAttribute("BaseCF"), eyeLocal = d:GetAttribute("EyeLocal"), dir = d:GetAttribute("Dir"), phase = hive:GetAttribute("Index") * 1.7 })
				elseif d.Name == "HiveGate" then
					table.insert(gates, d)
				elseif d.Name == "HiveEye" then
					H.eye = d
				elseif d.Name == "HiveIris" then
					H.iris = { part = d }
				elseif d.Name == "HivePupil" then
					H.pupil = { part = d }
				end
			end
		end
		if H.eye and H.eye.Parent then
			for _, e in { H.iris, H.pupil } do
				if e and e.part.Parent and not e.rel then
					e.rel = H.eye.CFrame:ToObjectSpace(e.part.CFrame)
				end
			end
		end
	end
end

local t, scanAcc = 0, 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	scanAcc += dt
	if scanAcc > 1.5 then
		scanAcc = 0
		scan()
	end
	local cam = workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

	-- COMPASS: points to the hive that is invading right now, or to the next one that is going to spawn
	if root and cam then
		local now = workspace:GetServerTimeNow()
		local rp = root.Position
		local cands = {}
		for i = 1, 12 do
			local hp = workspace:GetAttribute("HivePos" .. i)
			if hp then
				local nextAt = workspace:GetAttribute("HiveNext" .. i)
				cands[#cands + 1] = {
					i = i, pos = hp, dist = (Vector3.new(hp.X, 0, hp.Z) - Vector3.new(rp.X, 0, rp.Z)).Magnitude,
					alive = workspace:GetAttribute("HiveAlive" .. i) or 0, countdown = nextAt and math.max(0, nextAt - now) or 1e9,
					color = workspace:GetAttribute("HiveColor" .. i) or C3(255, 70, 90),
				}
			end
		end
		local target, mode
		for _, c in cands do
			if c.alive > 0 and (not target or c.dist < target.dist) then
				target, mode = c, "active"
			end
		end
		if not target then
			local soonest
			for _, c in cands do
				if not soonest or c.countdown < soonest.countdown then soonest = c end
			end
			target, mode = soonest, "next"
			if soonest then
				-- if another hive spawns within a minute of the soonest one and is closer to you, point to that one
				for _, c in cands do
					if c.countdown <= soonest.countdown + 60 and c.dist < target.dist then target = c end
				end
			end
		end
		-- while the mothership is here the compass points at it (and at the boss once it is out)
		local msState, msPos = workspace:GetAttribute("MS_State"), workspace:GetAttribute("MS_TargetPos")
		if msPos and (msState == "active" or msState == "arriving" or msState == "boss") then
			target = { i = 0, pos = msPos, dist = (msPos - rp).Magnitude, alive = 0, countdown = 0, color = C3(255, 60, 90), ms = true, boss = msState == "boss" }
			mode = "ms"
		end
		if target then
			local flat = Vector3.new(target.pos.X - rp.X, 0, target.pos.Z - rp.Z)
			local lp = cam.CFrame:VectorToObjectSpace(flat.Magnitude > 0 and flat.Unit or Vector3.zero)
			arrowHolder.Rotation = math.deg(math.atan2(lp.X, -lp.Z))
			local urgent = (mode == "active") or target.countdown < 20
			local col = urgent and C3(255, 70, 90):Lerp(target.color, 0.35) or target.color
			arrow.TextColor3 = col
			tail.BackgroundColor3 = col
			dialStroke.Color = col
			ps.Color = col
			hiveName.TextColor3 = col
			hiveName.Text = target.ms and (target.boss and "VOID SOVEREIGN" or "MOTHERSHIP") or ("HIVE " .. target.i)
			if mode == "ms" then
				local hp = workspace:GetAttribute("MS_BossHP")
				statusText.Text = (target.boss and hp) and string.format("\u{2620}  BOSS  %d%%", math.floor(hp * 100 + 0.5)) or "\u{26A0}  INVASION  -  DESTROY IT"
				statusText.TextColor3 = C3(255, 120, 130)
			elseif mode == "active" then
				statusText.Text = "\u{2620}  INVASION  -  " .. target.alive .. " ALIVE"
				statusText.TextColor3 = C3(255, 120, 130)
			else
				local sec = math.floor(target.countdown + 0.5)
				statusText.Text = string.format("NEXT WAVE  %02d:%02d", sec // 60, sec % 60)
				statusText.TextColor3 = (target.countdown < 20) and C3(255, 140, 120) or C3(235, 240, 255)
			end
			local d = math.floor(target.dist + 0.5)
			local ds = tostring(d):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
			distText.Text = ds .. " studs away"
			-- a pulse ring on the dial when it matters
			local k = (t * 1.1) % 1
			if urgent then
				pulse.Size = UDim2.fromScale(1 + 0.45 * k, 1 + 0.45 * k)
				pulseStroke.Color = col
				pulseStroke.Transparency = 0.15 + 0.85 * k
			else
				pulseStroke.Transparency = 1
			end
			ps.Transparency = 0.15 + 0.15 * math.sin(t * 3)
		end
	end

	-- every eye follows you
	if root then
		for hive, H in hiveEyes do
			local eye = H.eye
			if eye and eye.Parent then
				local dir = eye.CFrame:VectorToObjectSpace((root.Position - eye.Position).Unit)
				local tx = math.clamp(dir.X * 14, -7, 7)
				local ty = math.clamp(dir.Y * 10, -4.5, 4.5)
				H.offX += (tx - H.offX) * math.min(dt * 6, 1)
				H.offY += (ty - H.offY) * math.min(dt * 6, 1)
				for _, e in { H.iris, H.pupil } do
					if e and e.part.Parent and e.rel then
						e.part.CFrame = eye.CFrame * e.rel * CFrame.new(H.offX, H.offY, 0)
					end
				end
			end
		end
	end

	-- pulses
	for _, v in veins do
		if v.part.Parent then
			v.part.Transparency = 0.2 + 0.25 * (0.5 + 0.5 * math.sin(t * 2.2 - v.phase))
		end
	end
	for _, v in tips do
		if v.part.Parent then
			local k = 0.5 + 0.5 * math.sin(t * 3 + v.phase)
			v.part.Color = v.accent:Lerp(C3(255, 255, 255), 0.5 * k)
		end
	end
	for _, s in shards do
		if s.part.Parent and s.base then
			local a = s.phase + t * s.speed
			s.part.CFrame = s.base * CFrame.new(math.cos(a) * s.r, s.y + math.sin(t * 0.7 + s.phase) * 3, math.sin(a) * s.r) * CFrame.Angles(t * 0.5 + s.phase, a, 0.3)
		end
	end
	for _, s in searches do
		if s.part.Parent and s.base and s.eyeLocal then
			local ang = t * 0.22 + s.phase
			s.part.CFrame = s.base * CFrame.Angles(0, ang, 0) * CFrame.lookAt(s.eyeLocal, s.eyeLocal + s.dir) * CFrame.new(0, 0, -180)
		end
	end
	for _, g in gates do
		if g.Parent and g.Transparency > 0.2 then
			g.Transparency = 0.3 + 0.12 * math.sin(t * 3)
		end
	end
end)
