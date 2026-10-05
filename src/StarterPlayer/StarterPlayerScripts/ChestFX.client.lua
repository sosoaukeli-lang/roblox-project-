-- ChestFX (LocalScript)
-- The BOSS CHEST opening: a cinematic camera, the chest shaking, the lid blasting open, a case-opening style reel that slows down
-- on your weapon, and a reveal that gets more dramatic the rarer the weapon is (Rare < Epic < Legendary < SECRET).
-- Also the CHEST button (bottom right) for chests that were saved because you did not open them in time.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local Loot = require(RS:WaitForChild("Loot"))
local Items = require(RS:WaitForChild("Items"))
local player = Players.LocalPlayer
local notifyRemote = RS:WaitForChild("ProgressNotify")
local stateRemote = RS:WaitForChild("ProgressState")
local actionRemote = RS:WaitForChild("ProgressAction")
local rng = Random.new()
local C3 = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

local RARITY_COLOR = {
	Rare = C3(90, 170, 255), Epic = C3(190, 100, 255), Legendary = C3(255, 200, 80), Secret = C3(255, 60, 90),
}

local gui = Instance.new("ScreenGui")
gui.Name = "ChestUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 96
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
end
local function part(size, cf, color, material, shape, trans)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Transparency = trans or 0
	if shape then p.Shape = shape end
	return p
end

----------------------------------------------------------------------
-- the chest button (saved chests)
----------------------------------------------------------------------
local chestCount = 0
local busy = false
local btn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.52, 0), Size = UDim2.fromOffset(178, 54), BackgroundColor3 = C3(30, 20, 60),
	Text = "", AutoButtonColor = true, Visible = false, ZIndex = 30,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, btn)
local btnStroke = new("UIStroke", { Color = C3(255, 210, 110), Thickness = 2.4 }, btn)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(70, 40, 130), C3(26, 16, 54)) }, btn)
label(btn, "\u{1F4E6}", 30, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(40, 38), ZIndex = 31 })
local btnTitle = label(btn, "BOSS CHEST", 15, C3(255, 210, 110), Enum.Font.GothamBlack, { Position = UDim2.fromOffset(52, 6), Size = UDim2.new(1, -56, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 })
local btnSub = label(btn, "x1  -  TAP TO OPEN", 12, WHITE, Enum.Font.GothamBold, { Position = UDim2.fromOffset(52, 26), Size = UDim2.new(1, -56, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 })
local function refreshButton()
	btn.Visible = chestCount > 0 and not busy
	btnSub.Text = "x" .. chestCount .. "  -  TAP TO OPEN"
end
TweenService:Create(btnStroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 4, Transparency = 0.35 }):Play()
stateRemote.OnClientEvent:Connect(function(data)
	if typeof(data) == "table" and data.chests ~= nil then
		chestCount = data.chests
		refreshButton()
	end
end)
task.spawn(function()
	local ok, a, c = pcall(function() return actionRemote:InvokeServer("state") end)
	if ok and typeof(c) == "number" then
		chestCount = c
		refreshButton()
	end
end)
btn.Activated:Connect(function()
	if busy then return end
	actionRemote:InvokeServer("openChest") -- the server answers with a "chest" notification
end)

----------------------------------------------------------------------
-- the local chest model (client only)
----------------------------------------------------------------------
local function buildChest(cf, color)
	local model = Instance.new("Model")
	model.Name = "OpeningChest"
	local parts = {}
	local function add(name, size, rel, c, mat, shape, trans)
		local p = part(size, cf * rel, c, mat, shape, trans)
		p.Name = name
		p.Parent = model
		parts[name] = { part = p, rel = rel }
		return p
	end
	local DARK, GOLD = C3(28, 22, 46), C3(232, 184, 96)
	add("Base", Vector3.new(7, 4.4, 5), CFrame.new(0, -1, 0), DARK)
	add("BaseTrim", Vector3.new(7.5, 0.8, 5.5), CFrame.new(0, -3, 0), GOLD)
	add("Inside", Vector3.new(6.2, 0.3, 4.2), CFrame.new(0, 1.3, 0), WHITE, Enum.Material.Neon)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do add("Post" .. sx .. sz, Vector3.new(0.9, 5.6, 0.9), CFrame.new(sx * 3.4, -0.2, sz * 2.4), GOLD) end
	end
	add("Seam", Vector3.new(7.2, 0.4, 5.2), CFrame.new(0, 0.85, 0), color, Enum.Material.Neon)
	for i = -1, 1 do add("Rune" .. i, Vector3.new(0.5, 1.4, 0.3), CFrame.new(i * 1.8, -1.2, -2.55), color, Enum.Material.Neon) end
	-- the lid hinges at the back edge
	local lid = Instance.new("Model")
	local lidParts = {}
	local function addLid(name, size, rel, c, mat, shape)
		local p = part(size, cf * rel, c, mat, shape)
		p.Name = name
		p.Parent = model
		lidParts[#lidParts + 1] = { part = p, rel = rel }
	end
	addLid("Lid", Vector3.new(7, 2.4, 5), CFrame.new(0, 2, 0), GOLD)
	addLid("LidTop", Vector3.new(6, 0.6, 4), CFrame.new(0, 3.4, 0), C3(255, 226, 150))
	addLid("Lock", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 0.85, -2.7), WHITE, Enum.Material.Neon, Enum.PartType.Ball)
	local hinge = CFrame.new(0, 0.85, 2.5)
	local function setLid(angle)
		for _, lp in lidParts do
			lp.part.CFrame = cf * hinge * CFrame.Angles(angle, 0, 0) * hinge:Inverse() * lp.rel
		end
	end
	local function setCFrame(newCf, lidAngle)
		cf = newCf
		for _, e in parts do e.part.CFrame = cf * e.rel end
		setLid(lidAngle or 0)
	end
	model.Parent = workspace
	return { model = model, set = setCFrame, parts = parts }
end

----------------------------------------------------------------------
-- the reel + the reveal
----------------------------------------------------------------------
local function weaponCard(parent, id, w, x)
	local c = RARITY_COLOR[w.rarity]
	local card = new("Frame", { Position = UDim2.new(0, x, 0, 0), Size = UDim2.new(0, 124, 1, 0), BackgroundColor3 = c:Lerp(C3(10, 10, 24), 0.55), BorderSizePixel = 0 }, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
	new("UIStroke", { Color = c, Thickness = 2.4 }, card)
	new("Frame", { Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = c, BorderSizePixel = 0 }, card)
	label(card, w.icon, 54, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(1, 0.5), TextScaled = false })
	label(card, w.name, 13, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromScale(0.04, 0.62), Size = UDim2.fromScale(0.92, 0.28) })
	return card
end

local function typeText(lb, text, perChar)
	task.spawn(function()
		for i = 1, #text do
			lb.Text = text:sub(1, i)
			task.wait(perChar)
		end
	end)
end

local function lightRays(parent, color, count)
	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1200, 1200), BackgroundTransparency = 1, ZIndex = 1 }, parent)
	for i = 1, count do
		local r = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 16, 1, 0), BackgroundColor3 = color, BackgroundTransparency = 0.6, BorderSizePixel = 0, Rotation = i * 180 / count, ZIndex = 1 }, holder)
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }), Rotation = 90 }, r)
	end
	TweenService:Create(holder, TweenInfo.new(14, Enum.EasingStyle.Linear), { Rotation = 180 }):Play()
	return holder
end

local function findToolForPreview(toolName)
	local bp = player:FindFirstChild("Backpack")
	local stash = player:FindFirstChild("WeaponStash")
	return (bp and bp:FindFirstChild(toolName)) or (player.Character and player.Character:FindFirstChild(toolName)) or (stash and stash:FindFirstChild(toolName))
end

-- the bounds of the weapon WITHOUT the few far-away decorations (floating shards, halos): so the weapon itself fills the frame
local function trimmedBounds(copy)
	local parts, wsum, centroid = {}, 0, Vector3.zero
	for _, p in copy:GetChildren() do
		if p:IsA("BasePart") then
			local v = math.max(p.Size.X * p.Size.Y * p.Size.Z, 1e-4)
			parts[#parts + 1] = p
			wsum += v
			centroid += p.Position * v
		end
	end
	centroid /= math.max(wsum, 1e-4)
	table.sort(parts, function(a, b) return (a.Position - centroid).Magnitude > (b.Position - centroid).Magnitude end)
	local skip = math.floor(#parts * 0.08)
	local mn, mx = Vector3.one * math.huge, Vector3.one * -math.huge
	for i = skip + 1, #parts do
		local p = parts[i]
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local q = p.CFrame:PointToWorldSpace(Vector3.new(sx, sy, sz) * p.Size / 2)
					mn = Vector3.new(math.min(mn.X, q.X), math.min(mn.Y, q.Y), math.min(mn.Z, q.Z))
					mx = Vector3.new(math.max(mx.X, q.X), math.max(mx.Y, q.Y), math.max(mx.Z, q.Z))
				end
			end
		end
	end
	return CFrame.new((mn + mx) / 2), mx - mn
end

-- AUTO-FIT: the camera distance at which EVERY corner of the weapon stays inside the frame while it swings
local function fitCamera(copy, aspect, fov)
	local bbCF, bbSize = trimmedBounds(copy)
	local center = bbCF.Position
	local corners = {}
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				corners[#corners + 1] = bbCF:PointToWorldSpace(Vector3.new(sx, sy, sz) * bbSize / 2)
			end
		end
	end
	local tanH = math.tan(math.rad(fov / 2))
	local function fits(angle, dist)
		local pos = center + Vector3.new(math.cos(angle) * dist, bbSize.Y * 0.1, math.sin(angle) * dist)
		local look = (center - pos).Unit
		local right = look:Cross(Vector3.yAxis).Unit
		local up = right:Cross(look)
		for _, q in corners do
			local v = q - pos
			local depth = v:Dot(look)
			if depth < 0.05 then return false end
			if math.abs(v:Dot(right) / depth / (tanH * aspect)) > 0.92 or math.abs(v:Dot(up) / depth / tanH) > 0.86 then return false end
		end
		return true
	end
	local function minDist(angle)
		local lo, hi = 0.5, math.max(bbSize.X, bbSize.Y, bbSize.Z) * 40
		for _ = 1, 28 do
			local mid = (lo + hi) / 2
			if fits(angle, mid) then hi = mid else lo = mid end
		end
		return hi
	end
	local dist = 0
	for _, ang in { -0.55, 0, 0.55 } do dist = math.max(dist, minDist(ang)) end
	return center, dist, bbSize
end

local function weaponViewport(parent, tool, position, size, aspect)
	local vp = new("ViewportFrame", { Position = position, Size = size, BackgroundTransparency = 1, ZIndex = 6, Ambient = C3(190, 190, 215), LightColor = C3(255, 255, 255), LightDirection = Vector3.new(-0.7, -0.6, -0.9) }, parent)
	local wm = new("WorldModel", {}, vp)
	local copy = Instance.new("Model")
	local handle = tool:FindFirstChild("Handle")
	local h0 = handle.CFrame
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d:Clone()
			for _, ch in c:GetChildren() do
				if not ch:IsA("SpecialMesh") then ch:Destroy() end
			end
			c.Anchored = true
			c.CFrame = h0:ToObjectSpace(d.CFrame)
			if c.Material ~= Enum.Material.Neon and c.Material ~= Enum.Material.Glass and c.Material ~= Enum.Material.ForceField then
				c.Material = Enum.Material.SmoothPlastic
				c.Reflectance = 0
			end
			c.Parent = copy
		end
	end
	copy.Parent = wm
	local fov = 28
	local cam = new("Camera", { FieldOfView = fov }, vp)
	vp.CurrentCamera = cam
	local center, dist, bbSize = fitCamera(copy, aspect or 2.2, fov)
	local conn
	local a = 0
	conn = RunService.RenderStepped:Connect(function(dt)
		if not vp.Parent then conn:Disconnect() return end
		a += dt
		local swing = math.sin(a * 1.1) * 0.55 -- the weapon turns slowly towards you and away
		cam.CFrame = CFrame.lookAt(center + Vector3.new(math.cos(swing) * dist, bbSize.Y * 0.1, math.sin(swing) * dist), center)
	end)
	return vp
end

-- confetti raining over the screen (gets denser the rarer the weapon)
local function confetti(parent, count, colors)
	for i = 1, count do
		local p = new("Frame", { Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18)), Position = UDim2.new(math.random(), 0, 0, -30), Rotation = math.random(0, 360), BackgroundColor3 = colors[math.random(1, #colors)], BorderSizePixel = 0, ZIndex = 16 }, parent)
		task.delay(math.random() * 1.2, function()
			if not p.Parent then return end
			TweenService:Create(p, TweenInfo.new(2.2 + math.random() * 1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(p.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0), Rotation = p.Rotation + math.random(-540, 540) }):Play()
			Debris:AddItem(p, 4.2)
		end)
	end
end

local function playOpening(res, chestCF)
	if busy then return end
	busy = true
	refreshButton()
	local w = Loot.Weapons[res.id]
	local rarity = res.rarity
	local color = RARITY_COLOR[rarity]
	local rank = ({ Rare = 1, Epic = 2, Legendary = 3, Secret = 4 })[rarity] or 1
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if not (root and cam) then busy = false refreshButton() return end
	local base = chestCF or (root.CFrame * CFrame.new(0, 2, -30))
	local center = base.Position
	local chest = buildChest(base, color)
	local prevAnchored = root.Anchored
	root.Anchored = true
	player:SetAttribute("BossMusic", true) -- the normal background music ducks
	-- the opening song: the same heavy track as the boss fight, starts quiet and swells
	local song = new("Sound", { SoundId = "rbxassetid://1837853076", Volume = 0, Looped = true }, workspace.CurrentCamera or workspace)
	song:Play()
	TweenService:Create(song, TweenInfo.new(3), { Volume = 0.8 }):Play()
	local camAngle, camDist, camHeight, camFov = 1.2, 46, 12, 62
	local shakeAmp = 0
	local fovPulse = 0
	local useCam = true
	local conn = RunService.RenderStepped:Connect(function()
		if not useCam then return end
		cam.CameraType = Enum.CameraType.Scriptable
		local offs = Vector3.new(math.cos(camAngle) * camDist, camHeight, math.sin(camAngle) * camDist)
		local sh = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * shakeAmp
		cam.CFrame = CFrame.lookAt(center + offs + sh, center + Vector3.new(0, 1.5, 0))
		cam.FieldOfView = camFov - fovPulse
	end)

	local root_ui = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, gui)
	local dim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(0, 0, 8), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 }, root_ui)
	local tb = new("Frame", { Size = UDim2.fromScale(1, 0), BackgroundColor3 = C3(0, 0, 0), BorderSizePixel = 0, ZIndex = 20 }, root_ui)
	local bb = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = C3(0, 0, 0), BorderSizePixel = 0, ZIndex = 20 }, root_ui)
	TweenService:Create(tb, TweenInfo.new(0.5), { Size = UDim2.fromScale(1, 0.1) }):Play()
	TweenService:Create(bb, TweenInfo.new(0.5), { Size = UDim2.fromScale(1, 0.1) }):Play()
	local flashF = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 18 }, root_ui)
	local function flash(c, a, t)
		flashF.BackgroundColor3 = c
		flashF.BackgroundTransparency = a
		TweenService:Create(flashF, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
	-- pulsing coloured edges
	local edgeFrames = {}
	for _, spec in { { Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.25), 90 }, { Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.25), -90 }, { Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.18, 1), 0 }, { Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.18, 1), 180 } } do
		local f = new("Frame", { AnchorPoint = spec[1], Position = spec[2], Size = spec[3], BackgroundColor3 = color, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, root_ui)
		new("UIGradient", { Rotation = spec[4], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, f)
		edgeFrames[#edgeFrames + 1] = f
	end
	local function edgePulse(a)
		for _, f in edgeFrames do
			f.BackgroundTransparency = a
			TweenService:Create(f, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
	end

	-- PHASE 1: the charge: a riser that climbs, a drumroll that speeds up, light pillars growing round the chest, the chest shaking harder
	local riser = new("Sound", { SoundId = "rbxassetid://9125973984", Volume = 1.2, PlaybackSpeed = 0.6 }, workspace.CurrentCamera or workspace)
	riser:Play()
	local charge = 3.2
	TweenService:Create(riser, TweenInfo.new(charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { PlaybackSpeed = 2.2 }):Play()
	TweenService:Create(dim, TweenInfo.new(1.2), { BackgroundTransparency = 0.45 }):Play()
	local spiral = part(Vector3.one * 0.2, CFrame.new(center), WHITE, Enum.Material.Neon, Enum.PartType.Ball, 1)
	spiral.Parent = workspace
	local em = new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(WHITE, color), LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) }), Lifetime = NumberRange.new(0.7, 1.2),
		Speed = NumberRange.new(16, 26), SpreadAngle = Vector2.new(180, 180), Rate = 0,
	}, spiral)
	local pillars = {}
	for i = 1, 6 do
		local ang = i * math.pi / 3
		local p = part(Vector3.new(1, 6, 1) * 1, CFrame.new(center + Vector3.new(math.cos(ang) * 9, 3, math.sin(ang) * 9)), color, Enum.Material.Neon, nil, 0.35)
		p.Parent = workspace
		pillars[#pillars + 1] = { part = p, ang = ang }
	end
	local t0 = os.clock()
	local nextBeat, beatGap = 0, 0.55
	while os.clock() - t0 < charge do
		local a = (os.clock() - t0) / charge
		camAngle = 1.2 + a * 1.4
		camDist = 46 - 30 * a
		camHeight = 12 - 6 * a
		camFov = 62 - 16 * a
		shakeAmp = 0.05 + 0.6 * a * a
		fovPulse = math.max(0, fovPulse - 0.4)
		chest.set(base * CFrame.new(rng:NextNumber(-1, 1) * 0.3 * a, rng:NextNumber(-1, 1) * 0.2 * a, rng:NextNumber(-1, 1) * 0.3 * a), 0.07 * a * math.sin(os.clock() * 45))
		chest.parts.Seam.part.Color = color:Lerp(WHITE, a)
		em.Rate = 40 + 260 * a
		for _, pl in pillars do
			local h = 6 + 46 * a
			pl.part.Size = Vector3.new(0.8 + a * 1.4, h, 0.8 + a * 1.4)
			pl.part.Position = center + Vector3.new(math.cos(pl.ang + a * 3) * (9 - 3 * a), h / 2 - 3, math.sin(pl.ang + a * 3) * (9 - 3 * a))
		end
		if os.clock() - t0 >= nextBeat then -- the drumroll
			nextBeat = (os.clock() - t0) + beatGap
			beatGap = math.max(0.12, beatGap * 0.84)
			sfx(9065667699, 0.5 + 0.4 * a, 2.0 + 0.8 * a)
			fovPulse = 3 + 4 * a
			edgePulse(0.55 - 0.3 * a)
		end
		RunService.RenderStepped:Wait()
	end
	em.Rate = 0
	riser:Destroy()

	-- PHASE 2: the BURST: a camera whip, a wall of light, rings, a fountain of sparks, the lid blown open
	chest.set(base, 0)
	sfx(129993092121020, 1.5, 0.9)
	sfx(9065667699, 1.5, 0.55)
	sfx(9125974640, 1.3, 1.1)
	sfx(9125973257, 1.0, 0.8)
	flash(WHITE, 0, 1.0)
	shakeAmp = 1.8
	camAngle, camDist, camHeight, camFov = 2.5, 22, 7, 56
	fovPulse = -8
	for _, pl in pillars do
		TweenService:Create(pl.part, TweenInfo.new(0.9), { Transparency = 1, Size = Vector3.new(0.2, 80, 0.2) }):Play()
		Debris:AddItem(pl.part, 1)
	end
	local beam = part(Vector3.new(600, 3, 3), CFrame.new(center + Vector3.new(0, 300, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon, Enum.PartType.Cylinder, 0.25)
	beam.Parent = workspace
	TweenService:Create(beam, TweenInfo.new(2), { Size = Vector3.new(600, 18, 18), Transparency = 1 }):Play()
	Debris:AddItem(beam, 2.1)
	for i = 1, 5 do
		local ring = part(Vector3.new(1, 4, 4), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), (i % 2 == 0) and WHITE or color, Enum.Material.Neon, Enum.PartType.Cylinder, 0.15)
		ring.Parent = workspace
		TweenService:Create(ring, TweenInfo.new(0.7 + i * 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(1, 80 + i * 45, 80 + i * 45), Transparency = 1 }):Play()
		Debris:AddItem(ring, 2.2)
	end
	em:Emit(280)
	task.spawn(function()
		local tl = os.clock()
		while os.clock() - tl < 0.35 do
			chest.set(base, ((os.clock() - tl) / 0.35) * 2.0)
			RunService.RenderStepped:Wait()
		end
		chest.set(base, 2.0)
	end)
	task.spawn(function() -- the fountain keeps going while the reel spins
		em.Speed = NumberRange.new(30, 52)
		em.Rate = 90
		task.wait(5)
		em.Rate = 0
	end)
	task.wait(0.8)
	TweenService:Create(dim, TweenInfo.new(0.6), { BackgroundTransparency = 0.25 }):Play()

	-- PHASE 3: the reel
	shakeAmp = 0.2
	camFov = 50
	fovPulse = 0
	local reelFrame = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(780, 172), BackgroundColor3 = C3(8, 8, 20), BackgroundTransparency = 0.15, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 8 }, root_ui)
	new("UICorner", { CornerRadius = UDim.new(0, 16) }, reelFrame)
	local reelStroke = new("UIStroke", { Color = color, Thickness = 3.5 }, reelFrame)
	TweenService:Create(reelStroke, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 7 }):Play()
	local strip = new("Frame", { Size = UDim2.new(0, 1, 1, -12), Position = UDim2.fromOffset(0, 6), BackgroundTransparency = 1, ZIndex = 8 }, reelFrame)
	local ids = {}
	for _, id in Loot.Order do ids[#ids + 1] = id end
	local N, WIN = 46, 38
	local cardW, gap = 124, 8
	for i = 1, N do
		local id = (i == WIN) and res.id or ids[rng:NextInteger(1, #ids)]
		weaponCard(strip, id, Loot.Weapons[id], (i - 1) * (cardW + gap))
	end
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 12 }, reelFrame)
	for _, sgn in { -1, 1 } do
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, sgn == -1 and 0 or 1, 0), Size = UDim2.fromOffset(22, 22), Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 13 }, reelFrame)
	end
	local title = label(root_ui, "WHAT WILL IT BE?!", 30, WHITE, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -104), Size = UDim2.fromOffset(600, 44), ZIndex = 9 })
	task.spawn(function()
		while title.Parent do
			title.TextColor3 = (title.TextColor3 == WHITE) and color or WHITE
			task.wait(0.12)
		end
	end)
	local endX = -((WIN - 1) * (cardW + gap) + cardW / 2) + 390 + rng:NextNumber(-40, 40)
	strip.Position = UDim2.fromOffset(390, 6)
	local reelTime = 4.4
	TweenService:Create(strip, TweenInfo.new(reelTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(endX, 6) }):Play()
	sfx(9125973257, 1.0, 1.3)
	task.spawn(function()
		local last = 0
		local tt = os.clock()
		while os.clock() - tt < reelTime do
			local idx = math.floor((390 - strip.Position.X.Offset) / (cardW + gap))
			if idx ~= last then
				last = idx
				local prog = (os.clock() - tt) / reelTime
				sfx(6603571443, 0.3, 2.4 + prog * 1.6) -- the ticks climb in pitch as the reel slows down
				sfx(9116277954, 0.06 + prog * 0.1, 3.2)
				if prog > 0.6 then edgePulse(0.7) end
			end
			RunService.RenderStepped:Wait()
		end
	end)
	task.wait(reelTime + 0.25)
	-- the reel locks: a thump and a flash
	sfx(9065667699, 1.1, 1.0)
	flash(color, 0.4, 0.5)
	shakeAmp = 0.8
	task.wait(0.45)

	-- PHASE 4: the reveal, bigger the rarer the weapon is
	reelFrame:Destroy()
	title:Destroy()
	local secret, legendary, epic = rarity == "Secret", rarity == "Legendary", rarity == "Epic"
	if secret then
		TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.02 }):Play()
		for i = 1, 8 do
			flash((i % 2 == 0) and WHITE or color, 0.1, 0.22)
			sfx(9116277954, 1.2, rng:NextNumber(0.6, 1.5))
			sfx(9065667699, 1.0, rng:NextNumber(0.5, 1.0))
			shakeAmp = 2.2
			task.wait(0.15)
		end
		sfx(9112775375, 1.6, 0.45)
		sfx(129993092121020, 1.6, 0.7)
		sfx(9125974640, 1.4, 0.7)
	elseif legendary then
		flash(color, 0.1, 1.1)
		sfx(129993092121020, 1.3, 1.0)
		sfx(9125974640, 1.3, 0.9)
		sfx(9112775375, 1.0, 0.7)
		shakeAmp = 1.4
	elseif epic then
		flash(color, 0.35, 0.8)
		sfx(9125974640, 1.1, 1.2)
		sfx(9116277954, 1.0, 1.0)
		shakeAmp = 0.8
	else
		flash(color, 0.55, 0.6)
		sfx(9125974640, 0.8, 1.5)
		shakeAmp = 0.4
	end
	edgePulse(0.2)
	camAngle, camDist, camHeight, camFov = 3.1, 32, 14, 62
	confetti(root_ui, ({ 30, 70, 120, 200 })[rank], { color, WHITE, C3(255, 214, 110), color:Lerp(WHITE, 0.5) })
	if secret or legendary then lightRays(root_ui, color, secret and 16 or 10) end
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(660, 470), BackgroundColor3 = C3(8, 8, 20), BackgroundTransparency = 0.04, BorderSizePixel = 0, ZIndex = 10 }, root_ui)
	new("UICorner", { CornerRadius = UDim.new(0, 22) }, card)
	local cs = new("UIStroke", { Color = color, Thickness = 4 }, card)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(C3(10, 10, 24), 0.7), C3(8, 8, 20)) }, card)
	local sc = new("UIScale", { Scale = 0.15 }, card)
	card.Rotation = -6
	TweenService:Create(sc, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(card, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	TweenService:Create(cs, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 9, Transparency = 0.4 }):Play()
	local tag = label(card, secret and "S E C R E T" or rarity:upper(), secret and 38 or 28, color, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 46), ZIndex = 11 })
	if secret then
		task.spawn(function()
			while tag.Parent do
				tag.TextColor3 = (math.random() < 0.3) and WHITE or color
				tag.Position = UDim2.fromOffset(rng:NextInteger(-3, 3), 12 + rng:NextInteger(-2, 2))
				task.wait(0.06)
			end
		end)
	end
	if not res.duplicate then
		local new_ = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(70, 26), BackgroundColor3 = C3(255, 214, 110), Text = "NEW!", Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = C3(20, 14, 4), ZIndex = 12, Rotation = 8 }, card)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, new_)
	end
	local name = label(card, "", 42, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 52), ZIndex = 11 })
	typeText(name, w.name, secret and 0.08 or 0.035)
	local tool = (not res.duplicate) and findToolForPreview(w.tool)
	if tool and tool:FindFirstChild("Handle") then
		-- a soft glow behind the weapon, then the real model, big and turning
		local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(330, 205), Size = UDim2.fromOffset(500, 150), BackgroundColor3 = color, BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 5 }, card)
		new("UICorner", { CornerRadius = UDim.new(0, 75) }, glow)
		TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.65, Size = UDim2.fromOffset(560, 170) }):Play()
		weaponViewport(card, tool, UDim2.fromOffset(40, 112), UDim2.fromOffset(580, 190), 580 / 190)
	else
		label(card, w.icon, 110, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 130), Size = UDim2.new(1, 0, 0, 150), ZIndex = 11 })
	end
	label(card, w.desc, 17, C3(215, 225, 245), Enum.Font.Gotham, { Position = UDim2.fromOffset(40, 312), Size = UDim2.new(1, -80, 0, 40), ZIndex = 11 })
	label(card, w.stat, 15, C3(255, 210, 120), Enum.Font.GothamBold, { Position = UDim2.fromOffset(40, 352), Size = UDim2.new(1, -80, 0, 40), ZIndex = 11 })
	local foot
	if res.duplicate then
		foot = "DUPLICATE  -  you already own it:  +$" .. tostring(res.money)
	else
		foot = (res.stashed and "ADDED TO YOUR ARMORY  (hotbar full - equip it in LOADOUT)" or "ADDED TO YOUR BACKPACK") .. (res.pity and "   (bad-luck protection!)" or "")
	end
	label(card, foot, 16, res.duplicate and C3(255, 200, 120) or C3(120, 255, 170), Enum.Font.GothamBlack, { Position = UDim2.fromOffset(20, 396), Size = UDim2.new(1, -40, 0, 26), ZIndex = 11 })
	label(card, "Chance per chest:  Rare 52%   Epic 30%   Legendary 14%   Secret 4%   (a Legendary is guaranteed every 12 chests)", 11, C3(150, 165, 195), Enum.Font.Gotham, { Position = UDim2.fromOffset(16, 436), Size = UDim2.new(1, -32, 0, 22), ZIndex = 11 })

	local closeBtn = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 258), Size = UDim2.fromOffset(240, 44), BackgroundColor3 = color, Text = "CONTINUE", Font = Enum.Font.GothamBlack, TextSize = 19, TextColor3 = C3(10, 10, 24), ZIndex = 12 }, root_ui)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, closeBtn)
	local closed = false
	local function close()
		if closed then return end
		closed = true
		useCam = false
		conn:Disconnect()
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum.CameraOffset = Vector3.zero end
		if root then root.Anchored = prevAnchored end
		TweenService:Create(song, TweenInfo.new(1.5), { Volume = 0 }):Play()
		Debris:AddItem(song, 1.7)
		player:SetAttribute("BossMusic", nil)
		chest.model:Destroy()
		spiral:Destroy()
		root_ui:Destroy()
		busy = false
		refreshButton()
	end
	closeBtn.Activated:Connect(close)
	task.delay(18, close)
	task.delay(1.2, function()
		UserInputService.InputBegan:Once(function() close() end)
	end)
end

notifyRemote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "chest" and typeof(a) == "table" then
		pcall(playOpening, a, typeof(b) == "CFrame" and b or nil)
	end
end)
