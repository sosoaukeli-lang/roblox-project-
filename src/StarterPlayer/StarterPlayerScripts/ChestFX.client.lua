-- ChestFX (LocalScript)
-- The BOSS CHEST opening: a cinematic camera, the chest shaking, the lid blasting open, a case-opening style reel that slows down
-- on your weapon (real 3D models of every weapon), and a reveal that gets more dramatic the rarer the weapon is (Rare < Epic < Legendary < SECRET).
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
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- children always draw above their parent (the reel cards were drawn UNDER the dark reel)
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
-- the local chest model (client only): a floating relic chest over a glowing summoning circle, crystals orbiting it.
-- Its neon parts can change colour: while it charges they flicker through every rarity (nobody knows what is inside),
-- during the reel they glow the colour of the card under the needle, and at the end they lock on YOUR rarity.
----------------------------------------------------------------------
local CYCLE = { RARITY_COLOR.Rare, RARITY_COLOR.Epic, RARITY_COLOR.Legendary, RARITY_COLOR.Secret }
local NEON = Enum.Material.Neon

local function buildChest(cf)
	local model = Instance.new("Model")
	model.Name = "OpeningChest"
	local parts, lidParts, accents = {}, {}, {}
	local function add(list, name, size, rel, c, mat, shape, trans, accent)
		local p = part(size, cf * rel, c, mat, shape, trans)
		p.Name = name
		p.Parent = model
		list[#list + 1] = { part = p, rel = rel }
		if accent then accents[#accents + 1] = p end
		return p
	end
	local DARK, GOLD, PALE = C3(28, 22, 46), C3(232, 184, 96), C3(255, 226, 150)
	-- the body
	add(parts, "Base", Vector3.new(7, 4.4, 5), CFrame.new(0, -1, 0), DARK)
	add(parts, "BaseTrim", Vector3.new(7.6, 0.8, 5.6), CFrame.new(0, -3.1, 0), GOLD)
	add(parts, "Band", Vector3.new(7.3, 0.5, 5.3), CFrame.new(0, -1.9, 0), GOLD)
	local inside = add(parts, "Inside", Vector3.new(6.2, 0.3, 4.2), CFrame.new(0, 1.3, 0), WHITE, NEON)
	add(parts, "Seam", Vector3.new(7.2, 0.4, 5.2), CFrame.new(0, 0.85, 0), WHITE, NEON, nil, nil, true)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			add(parts, "Post", Vector3.new(0.9, 5.6, 0.9), CFrame.new(sx * 3.4, -0.2, sz * 2.4), GOLD)
			add(parts, "Foot", Vector3.new(1.3, 1.3, 1.3), CFrame.new(sx * 3.4, -3.6, sz * 2.4), PALE, Enum.Material.Metal, Enum.PartType.Ball)
		end
	end
	-- glowing runes on all four sides
	for i = -1, 1 do
		add(parts, "Rune", Vector3.new(0.5, 1.4, 0.3), CFrame.new(i * 1.8, -0.7, -2.55), WHITE, NEON, nil, nil, true)
		add(parts, "Rune", Vector3.new(0.5, 1.4, 0.3), CFrame.new(i * 1.8, -0.7, 2.55), WHITE, NEON, nil, nil, true)
	end
	for _, sz in { -1, 1 } do
		add(parts, "Rune", Vector3.new(0.3, 1.4, 0.5), CFrame.new(-3.55, -0.7, sz * 1.1), WHITE, NEON, nil, nil, true)
		add(parts, "Rune", Vector3.new(0.3, 1.4, 0.5), CFrame.new(3.55, -0.7, sz * 1.1), WHITE, NEON, nil, nil, true)
	end
	-- the lid (it hinges at the back edge): neon strips, a lock and a big diamond on top
	add(lidParts, "Lid", Vector3.new(7, 2.4, 5), CFrame.new(0, 2, 0), GOLD)
	add(lidParts, "LidTop", Vector3.new(6, 0.6, 4), CFrame.new(0, 3.4, 0), PALE)
	add(lidParts, "LidStrip", Vector3.new(6.4, 0.3, 0.3), CFrame.new(0, 3.25, -2.1), WHITE, NEON, nil, nil, true)
	add(lidParts, "LidStrip", Vector3.new(6.4, 0.3, 0.3), CFrame.new(0, 3.25, 2.1), WHITE, NEON, nil, nil, true)
	add(lidParts, "Gem", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 4.3, 0) * CFrame.Angles(0, math.rad(45), math.rad(45)), WHITE, NEON, nil, nil, true)
	add(lidParts, "Lock", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 0.85, -2.7), WHITE, NEON, Enum.PartType.Ball)
	local light = new("PointLight", { Color = WHITE, Range = 4, Brightness = 3, Shadows = false }, inside)

	-- the summoning circle under it, a ring of runes turning round it, and six crystals orbiting it
	local c0 = cf.Position
	local disc = part(Vector3.new(0.3, 19, 19), CFrame.new(c0 + Vector3.new(0, -5.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), WHITE, NEON, Enum.PartType.Cylinder, 0.6)
	disc.Parent = model
	accents[#accents + 1] = disc
	local ring, orbiters = {}, {}
	for i = 1, 16 do
		local p = part(Vector3.new(1.8, 0.35, 0.6), CFrame.new(c0), WHITE, NEON)
		p.Parent = model
		ring[i] = p
		accents[#accents + 1] = p
	end
	for i = 1, 6 do
		local p = part(Vector3.new(0.7, 2.4, 0.7), CFrame.new(c0), WHITE, NEON, nil, 0.05)
		p.Parent = model
		orbiters[i] = p
		accents[#accents + 1] = p
	end

	local hinge = CFrame.new(0, 0.85, 2.5)
	local state = { cf = cf, lid = 0, spin = 0.7, angle = 0, t = 0 }
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not model.Parent then conn:Disconnect() return end
		state.t += dt
		state.angle += dt * state.spin
		local body = state.cf * CFrame.new(0, math.sin(state.t * 2.2) * 0.35, 0) -- it hovers
		for _, e in parts do e.part.CFrame = body * e.rel end
		local lidCF = body * hinge * CFrame.Angles(state.lid, 0, 0) * hinge:Inverse()
		for _, e in lidParts do e.part.CFrame = lidCF * e.rel end
		local c = state.cf.Position
		for i, o in orbiters do
			local a = state.angle + i * math.pi / 3
			o.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 7, 0.5 + math.sin(state.t * 3 + i) * 1.2, math.sin(a) * 7)) * CFrame.Angles(state.t * 2 + i, state.t * 1.3, 0)
		end
		for i, r in ring do
			local a = -state.angle * 0.5 + i * math.pi / 8
			local pos = c + Vector3.new(math.cos(a) * 9.5, -5, math.sin(a) * 9.5)
			r.CFrame = CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z))
		end
	end)
	model.Parent = workspace
	return {
		model = model,
		light = light,
		set = function(newCf, lidAngle) state.cf = newCf; state.lid = lidAngle or 0 end,
		setSpin = function(s) state.spin = s end,
		recolor = function(c)
			for _, p in accents do p.Color = c end
			light.Color = c
		end,
		destroy = function()
			conn:Disconnect()
			model:Destroy()
		end,
	}
end

----------------------------------------------------------------------
-- weapon models: the server puts a parts-only copy of every weapon in ReplicatedStorage.WeaponPreviews
----------------------------------------------------------------------
local function findToolForPreview(toolName)
	local bp = player:FindFirstChild("Backpack")
	local stash = player:FindFirstChild("WeaponStash")
	return (bp and bp:FindFirstChild(toolName)) or (player.Character and player.Character:FindFirstChild(toolName)) or (stash and stash:FindFirstChild(toolName))
end

local function previewSource(toolName)
	local folder = RS:FindFirstChild("WeaponPreviews")
	return (folder and folder:FindFirstChild(toolName)) or findToolForPreview(toolName)
end

-- a copy of the weapon's parts, placed relative to its Handle (preview models already are)
local function buildCopy(src)
	local origin = CFrame.identity
	if src:IsA("Tool") then
		local handle = src:FindFirstChild("Handle")
		if not handle then return nil end
		origin = handle.CFrame
	end
	local copy = Instance.new("Model")
	for _, d in src:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d:Clone()
			if c then
				for _, ch in c:GetChildren() do
					if not (ch:IsA("SpecialMesh") or ch:IsA("Decal") or ch:IsA("SurfaceAppearance")) then ch:Destroy() end
				end
				c.Anchored = true
				c.CFrame = origin:ToObjectSpace(d.CFrame)
				if c.Material ~= Enum.Material.Neon and c.Material ~= Enum.Material.Glass and c.Material ~= Enum.Material.ForceField then
					c.Material = Enum.Material.SmoothPlastic
					c.Reflectance = 0
				end
				c.Parent = copy
			end
		end
	end
	if #copy:GetChildren() == 0 then
		copy:Destroy()
		return nil
	end
	return copy
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

local function swingCamera(cam, fit, t)
	local swing = math.sin(t) * 0.55 -- the weapon turns slowly towards you and away
	cam.CFrame = CFrame.lookAt(fit.center + Vector3.new(math.cos(swing) * fit.dist, fit.size.Y * 0.1, math.sin(swing) * fit.dist), fit.center)
end

-- the big turning model on the reveal card
local function weaponViewport(parent, src, position, size, aspect)
	local copy = buildCopy(src)
	if not copy then return nil end
	local vp = new("ViewportFrame", { Position = position, Size = size, BackgroundTransparency = 1, ZIndex = 6, Ambient = C3(190, 190, 215), LightColor = WHITE, LightDirection = Vector3.new(-0.7, -0.6, -0.9) }, parent)
	local wm = new("WorldModel", {}, vp)
	copy.Parent = wm
	local fov = 28
	local cam = new("Camera", { FieldOfView = fov }, vp)
	vp.CurrentCamera = cam
	local center, dist, bbSize = fitCamera(copy, aspect or 2.2, fov)
	local fit = { center = center, dist = dist, size = bbSize }
	local conn
	local a = 0
	conn = RunService.RenderStepped:Connect(function(dt)
		if not vp.Parent then conn:Disconnect() return end
		a += dt
		swingCamera(cam, fit, a * 1.1)
	end)
	return vp
end

----------------------------------------------------------------------
-- the reel cards: the real weapon model on a card in its rarity's colours.
-- Only the cards that are on screen get a 3D model (made when a card slides in, removed when it slides out).
----------------------------------------------------------------------
local REEL_W, REEL_H = 900, 224
local CARD_W, CARD_GAP = 158, 10
local STEP = CARD_W + CARD_GAP
local CARD_FOV = 30
local CARD_ASPECT = 1.45 -- width / height of the model area on a card

local cardModels = {} -- [weaponId] = { copy, center, dist, size }: made once, cloned for every card
local function cardModel(id)
	local m = cardModels[id]
	if m then return m end
	local src = previewSource(Loot.Weapons[id].tool)
	local copy = src and buildCopy(src)
	if not copy then return nil end -- not cached: the previews may simply not have arrived yet
	local center, dist, size = fitCamera(copy, CARD_ASPECT, CARD_FOV)
	m = { copy = copy, center = center, dist = dist, size = size }
	cardModels[id] = m
	return m
end

local function weaponCard(parent, id, cx)
	local w = Loot.Weapons[id]
	local rc = RARITY_COLOR[w.rarity]
	local BG = C3(14, 12, 30)
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, cx, 0.5, 0), Size = UDim2.new(0, CARD_W, 1, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(BG, rc:Lerp(BG, 0.4)) }, card)
	local stroke = new("UIStroke", { Color = rc, Thickness = 2 }, card)
	local scale = new("UIScale", { Scale = 1 }, card)
	-- a soft glow of the rarity colour behind the weapon
	local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.9, 0.5), BackgroundColor3 = rc, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 1 }, card)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
	label(card, w.rarity:upper(), 12, rc, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3, TextStrokeTransparency = 0.6 })
	label(card, w.name, 15, WHITE, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -10), Size = UDim2.new(1, -12, 0, 38), ZIndex = 3, TextStrokeTransparency = 0.4 })
	new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = rc, BorderSizePixel = 0, ZIndex = 3 }, card)
	-- darkens the card when another card wins
	local shade = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, card)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, shade)
	return { frame = card, id = id, rarity = w.rarity, stroke = stroke, scale = scale, shade = shade }
end

local function showCardModel(c)
	local m = cardModel(c.id)
	if not m then -- no model available: fall back to the icon
		c.vp = label(c.frame, Loot.Weapons[c.id].icon, 58, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromScale(0, 0.14), Size = UDim2.fromScale(1, 0.5), ZIndex = 2 })
		return
	end
	local vp = new("ViewportFrame", { Position = UDim2.fromScale(0.03, 0.13), Size = UDim2.fromScale(0.94, 0.58), BackgroundTransparency = 1, ZIndex = 2, Ambient = C3(200, 200, 225), LightColor = WHITE, LightDirection = Vector3.new(-0.7, -0.6, -0.9) }, c.frame)
	m.copy:Clone().Parent = vp
	local cam = new("Camera", { FieldOfView = CARD_FOV }, vp)
	vp.CurrentCamera = cam
	c.vp, c.cam, c.fit = vp, cam, m
end

local function hideCardModel(c)
	if c.vp then c.vp:Destroy() end
	c.vp, c.cam, c.fit = nil, nil, nil
end

-- the filler cards follow the REAL odds, so the reel never makes rare weapons look more common than they are
local function fillerId()
	local x, acc = rng:NextNumber(), 0
	for _, r in Loot.RarityOrder do
		acc += Loot.Odds[r]
		if x <= acc then
			local list = Loot.ByRarity[r]
			return list[rng:NextInteger(1, #list)]
		end
	end
	return Loot.Order[1]
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

-- set while an opening is playing: puts the camera, the character and the screen back to normal
local activeCleanup = nil

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
	if not (w and color and root and cam) then busy = false refreshButton() return end
	local base = chestCF or (root.CFrame * CFrame.new(0, 2, -30))
	local center = base.Position
	local chest = buildChest(base)
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
	-- the world behind the reel goes soft and punchy (GUI is not blurred)
	local blur = new("BlurEffect", { Size = 0 }, cam)
	local grade = new("ColorCorrectionEffect", { Contrast = 0, Saturation = 0 }, cam)
	local spiral -- the spark fountain (made in phase 1)
	local reelConn -- the reel's per-frame update (phase 3)

	local root_ui = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, gui)

	local closed = false
	local function close()
		if closed then return end
		closed = true
		activeCleanup = nil
		useCam = false
		conn:Disconnect()
		if reelConn then reelConn:Disconnect() end
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum.CameraOffset = Vector3.zero end
		if root then root.Anchored = prevAnchored end
		TweenService:Create(song, TweenInfo.new(1.5), { Volume = 0 }):Play()
		Debris:AddItem(song, 1.7)
		player:SetAttribute("BossMusic", nil)
		blur:Destroy()
		grade:Destroy()
		chest.destroy()
		if spiral then spiral:Destroy() end
		root_ui:Destroy()
		busy = false
		refreshButton()
	end
	activeCleanup = close

	local dim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(0, 0, 8), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 }, root_ui)
	local tb = new("Frame", { Size = UDim2.fromScale(1, 0), BackgroundColor3 = C3(0, 0, 0), BorderSizePixel = 0, ZIndex = 20 }, root_ui)
	local bb = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = C3(0, 0, 0), BorderSizePixel = 0, ZIndex = 20 }, root_ui)
	TweenService:Create(tb, TweenInfo.new(0.5), { Size = UDim2.fromScale(1, 0.08) }):Play()
	TweenService:Create(bb, TweenInfo.new(0.5), { Size = UDim2.fromScale(1, 0.08) }):Play()
	local flashF = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 18 }, root_ui)
	local function flash(c, a, t)
		flashF.BackgroundColor3 = c
		flashF.BackgroundTransparency = a
		TweenService:Create(flashF, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
	-- pulsing coloured edges (they take the colour that is "showing" right now)
	local shown = WHITE
	local edgeFrames = {}
	for _, spec in { { Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.25), 90 }, { Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.25), -90 }, { Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.18, 1), 0 }, { Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.18, 1), 180 } } do
		local f = new("Frame", { AnchorPoint = spec[1], Position = spec[2], Size = spec[3], BackgroundColor3 = shown, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, root_ui)
		new("UIGradient", { Rotation = spec[4], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, f)
		edgeFrames[#edgeFrames + 1] = f
	end
	local function edgePulse(a)
		for _, f in edgeFrames do
			f.BackgroundColor3 = shown
			f.BackgroundTransparency = a
			TweenService:Create(f, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
	end

	-- PHASE 1: the charge: a riser that climbs, a drumroll that speeds up, light pillars spiralling in, the chest shaking harder,
	-- the crystals orbiting faster and the colours flickering through EVERY rarity
	local riser = new("Sound", { SoundId = "rbxassetid://9125973984", Volume = 1.2, PlaybackSpeed = 0.6 }, workspace.CurrentCamera or workspace)
	riser:Play()
	local charge = 3.4
	TweenService:Create(riser, TweenInfo.new(charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { PlaybackSpeed = 2.2 }):Play()
	TweenService:Create(dim, TweenInfo.new(1.2), { BackgroundTransparency = 0.45 }):Play()
	spiral = part(Vector3.one * 0.2, CFrame.new(center), WHITE, NEON, Enum.PartType.Ball, 1)
	spiral.Parent = workspace
	local em = new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(WHITE), LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) }), Lifetime = NumberRange.new(0.7, 1.2),
		Speed = NumberRange.new(16, 26), SpreadAngle = Vector2.new(180, 180), Rate = 0,
	}, spiral)
	local pillars = {}
	for i = 1, 6 do
		local ang = i * math.pi / 3
		local p = part(Vector3.new(1, 6, 1), CFrame.new(center + Vector3.new(math.cos(ang) * 9, 3, math.sin(ang) * 9)), WHITE, NEON, nil, 0.35)
		p.Parent = workspace
		pillars[#pillars + 1] = { part = p, ang = ang }
	end
	local t0 = os.clock()
	local nextBeat, beatGap = 0, 0.55
	local nextColor, ci = 0, 0
	while os.clock() - t0 < charge do
		local a = (os.clock() - t0) / charge
		camAngle = 1.2 + a * 1.4
		camDist = 46 - 30 * a
		camHeight = 12 - 6 * a
		camFov = 62 - 16 * a
		shakeAmp = 0.05 + 0.6 * a * a
		fovPulse = math.max(0, fovPulse - 0.4)
		chest.set(base * CFrame.new(rng:NextNumber(-1, 1) * 0.3 * a, rng:NextNumber(-1, 1) * 0.2 * a, rng:NextNumber(-1, 1) * 0.3 * a), 0.07 * a * math.sin(os.clock() * 45))
		chest.setSpin(0.7 + 7 * a)
		chest.light.Range = 4 + 20 * a
		em.Rate = 40 + 260 * a
		if os.clock() >= nextColor then -- the colour roulette: faster and faster
			nextColor = os.clock() + math.max(0.05, 0.3 - 0.26 * a)
			ci = ci % #CYCLE + 1
			shown = CYCLE[ci]
			chest.recolor(shown)
			for _, pl in pillars do pl.part.Color = shown end
		end
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

	-- PHASE 2: the BURST: a camera whip, a wall of white light, rainbow rings, a fountain of sparks, the lid blown open
	chest.set(base, 0)
	chest.recolor(WHITE)
	chest.light.Range = 30
	chest.light.Brightness = 5
	shown = WHITE
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
	local beam = part(Vector3.new(600, 3, 3), CFrame.new(center + Vector3.new(0, 300, 0)) * CFrame.Angles(0, 0, math.pi / 2), WHITE, NEON, Enum.PartType.Cylinder, 0.25)
	beam.Parent = workspace
	TweenService:Create(beam, TweenInfo.new(1.6), { Size = Vector3.new(600, 14, 14), Transparency = 1 }):Play()
	Debris:AddItem(beam, 1.7)
	for i = 1, 8 do
		local ring = part(Vector3.new(1, 4, 4), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), CYCLE[(i - 1) % #CYCLE + 1], NEON, Enum.PartType.Cylinder, 0.15)
		ring.Parent = workspace
		TweenService:Create(ring, TweenInfo.new(0.6 + i * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(1, 70 + i * 32, 70 + i * 32), Transparency = 1 }):Play()
		Debris:AddItem(ring, 2.4)
	end
	em:Emit(280)
	chest.setSpin(4)
	task.spawn(function()
		local tl = os.clock()
		while os.clock() - tl < 0.35 and not closed do
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
	TweenService:Create(dim, TweenInfo.new(0.6), { BackgroundTransparency = 0.3 }):Play()

	-- PHASE 3: THE REEL. Real weapon models on rarity cards; the card under the needle grows and the chest glows its colour.
	shakeAmp = 0.15
	camFov = 50
	fovPulse = 0
	chest.setSpin(2.5)
	TweenService:Create(blur, TweenInfo.new(0.5), { Size = 16 }):Play()
	TweenService:Create(grade, TweenInfo.new(0.5), { Contrast = 0.12, Saturation = 0.25 }):Play()
	for _, id in Loot.Order do cardModel(id) end -- build every weapon's model now, not in the middle of the spin

	local vs = cam.ViewportSize
	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(REEL_W, REEL_H + 116), BackgroundTransparency = 1, ZIndex = 8 }, root_ui)
	local holderScale = new("UIScale", { Scale = 0.4 }, holder)
	local fitScale = math.min(1, (vs.X - 24) / REEL_W, (vs.Y * 0.84) / (REEL_H + 116))
	TweenService:Create(holderScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fitScale }):Play()
	local title = label(holder, "WHAT WILL IT BE?!", 36, WHITE, Enum.Font.GothamBlack, { Size = UDim2.new(1, 0, 0, 48), ZIndex = 1, TextStrokeTransparency = 0.2, TextStrokeColor3 = C3(0, 0, 0) })
	local reelFrame = new("Frame", { Position = UDim2.fromOffset(0, 56), Size = UDim2.fromOffset(REEL_W, REEL_H), BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 2 }, holder)
	new("UICorner", { CornerRadius = UDim.new(0, 18) }, reelFrame)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(22, 14, 48), C3(6, 4, 16)) }, reelFrame)
	-- the frame's border runs through every rarity colour until the reel stops
	local reelStroke = new("UIStroke", { Color = WHITE, Thickness = 5 }, reelFrame)
	local strokeGrad = new("UIGradient", { Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CYCLE[1]), ColorSequenceKeypoint.new(0.25, CYCLE[2]), ColorSequenceKeypoint.new(0.5, CYCLE[3]),
		ColorSequenceKeypoint.new(0.75, CYCLE[4]), ColorSequenceKeypoint.new(1, CYCLE[1]),
	}) }, reelStroke)
	local strip = new("Frame", { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(0, 1, 1, -32), BackgroundTransparency = 1, ZIndex = 1 }, reelFrame)
	-- the cards fade out towards both ends of the reel
	for _, side in { 0, 1 } do
		local f = new("Frame", { AnchorPoint = Vector2.new(side, 0), Position = UDim2.fromScale(side, 0), Size = UDim2.new(0, 180, 1, 0), BackgroundColor3 = C3(6, 4, 16), BorderSizePixel = 0, ZIndex = 5 }, reelFrame)
		new("UIGradient", { Rotation = (side == 0) and 0 or 180, Transparency = NumberSequence.new(0, 1) }, f)
	end
	-- the selector box and the needle in the middle
	local selector = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, CARD_W + 28, 1, -6), BackgroundTransparency = 1, ZIndex = 6 }, reelFrame)
	new("UICorner", { CornerRadius = UDim.new(0, 14) }, selector)
	local selStroke = new("UIStroke", { Color = WHITE, Thickness = 3, Transparency = 0.15 }, selector)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 16, 1, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 7 }, reelFrame)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 8 }, reelFrame)
	local pointers = {}
	for _, y in { 56, 56 + REEL_H } do
		local d = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(26, 26), Rotation = 45, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, holder)
		new("UIStroke", { Color = C3(10, 8, 24), Thickness = 3 }, d)
		pointers[#pointers + 1] = d
	end
	-- the odds, always in view while it spins
	local legend = new("Frame", { Position = UDim2.fromOffset(0, 56 + REEL_H + 16), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, ZIndex = 1 }, holder)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10) }, legend)
	for _, r in Loot.RarityOrder do
		local rc = RARITY_COLOR[r]
		local chip = new("TextLabel", { Size = UDim2.fromOffset(160, 28), BackgroundColor3 = rc:Lerp(C3(10, 10, 24), 0.75), Text = r:upper() .. "  " .. math.floor(Loot.Odds[r] * 100 + 0.5) .. "%", Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = rc }, legend)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, chip)
		new("UIStroke", { Color = rc, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
	end

	local N, WIN = 52, 44
	local CENTER = REEL_W / 2
	local cards = {}
	for i = 1, N do
		local id = (i == WIN) and res.id or fillerId()
		cards[i] = weaponCard(strip, id, (i - 1) * STEP + CARD_W / 2)
	end
	local startX = CENTER - CARD_W / 2 -- card 1 starts under the needle
	local endX = CENTER + rng:NextNumber(-1, 1) * (CARD_W / 2 - 18) - (WIN - 1) * STEP - CARD_W / 2
	strip.Position = UDim2.fromOffset(startX, 16)

	local locked = false
	local reelT = 0
	reelConn = RunService.RenderStepped:Connect(function(dt)
		reelT += dt
		local sx = strip.Position.X.Offset
		for i, c in cards do
			local cx = sx + (i - 1) * STEP + CARD_W / 2
			local onScreen = cx > -CARD_W and cx < REEL_W + CARD_W
			if onScreen and not c.vp then
				showCardModel(c)
			elseif not onScreen and c.vp then
				hideCardModel(c)
			end
			if not locked then
				local k = math.clamp(1 - math.abs(cx - CENTER) / STEP, 0, 1)
				c.scale.Scale = 1 + 0.08 * k
				c.stroke.Thickness = 2 + 3 * k
			end
			if c.cam then swingCamera(c.cam, c.fit, reelT * 1.6 + i) end
		end
		if not locked then
			strokeGrad.Rotation = (reelT * 260) % 360
			title.TextColor3 = CYCLE[math.floor(reelT * 8) % #CYCLE + 1]:Lerp(WHITE, 0.35)
		end
	end)

	local reelTime = 5.2
	TweenService:Create(strip, TweenInfo.new(reelTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(endX, 16) }):Play()
	sfx(9125973257, 1.0, 1.3)
	task.spawn(function()
		local last = -1
		local tt = os.clock()
		while os.clock() - tt < reelTime and not closed do
			local idx = math.floor((CENTER - strip.Position.X.Offset) / STEP)
			if idx ~= last then
				last = idx
				local prog = (os.clock() - tt) / reelTime
				sfx(6603571443, 0.3, 2.4 + prog * 1.6) -- the ticks climb in pitch as the reel slows down
				sfx(9116277954, 0.06 + prog * 0.1, 3.2)
				local c = cards[idx + 1]
				if c then -- the chest, the selector and the screen edges glow the colour of the card under the needle
					shown = RARITY_COLOR[c.rarity]
					chest.recolor(shown)
					selStroke.Color = shown
					for _, d in pointers do d.BackgroundColor3 = shown end
				end
				if prog > 0.55 then edgePulse(0.75) end
			end
			RunService.RenderStepped:Wait()
		end
	end)
	task.wait(reelTime + 0.2)

	-- THE LOCK: every other card goes dark, yours jumps out, everything turns your rarity's colour
	locked = true
	shown = color
	local winCard = cards[WIN]
	strokeGrad:Destroy()
	reelStroke.Color = color
	selStroke.Color = color
	selStroke.Thickness = 5
	for _, d in pointers do d.BackgroundColor3 = color end
	chest.recolor(color)
	title.Text = (rarity == "Secret") and "S E C R E T !" or (rarity:upper() .. "!")
	title.TextColor3 = color
	local titleScale = new("UIScale", { Scale = 1.6 }, title)
	TweenService:Create(titleScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	for i, c in cards do
		if i ~= WIN then
			c.scale.Scale = 1
			c.stroke.Thickness = 2
			TweenService:Create(c.shade, TweenInfo.new(0.3), { BackgroundTransparency = 0.4 }):Play()
		end
	end
	winCard.stroke.Color = WHITE
	TweenService:Create(winCard.scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.13 }):Play()
	TweenService:Create(winCard.stroke, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6, Color = color }):Play()
	sfx(9065667699, 1.1, 1.0)
	sfx(9116277954, 0.9, 1.4)
	flash(color, 0.35, 0.5)
	edgePulse(0.25)
	shakeAmp = 0.8
	task.wait(1.1)

	-- PHASE 4: the reveal, bigger the rarer the weapon is
	reelConn:Disconnect()
	reelConn = nil
	holder:Destroy()
	TweenService:Create(blur, TweenInfo.new(0.4), { Size = 10 }):Play()
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
	-- the chest answers: a pillar of your rarity's light, shockwaves and a burst of sparks (all bigger the rarer it is)
	em.Color = ColorSequence.new(WHITE, color)
	em:Emit(70 * rank)
	chest.setSpin(1 + rank)
	local pillar = part(Vector3.new(600, 4 + 4 * rank, 4 + 4 * rank), CFrame.new(center + Vector3.new(0, 300, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, NEON, Enum.PartType.Cylinder, 0.15)
	pillar.Parent = workspace
	TweenService:Create(pillar, TweenInfo.new(2.4), { Size = Vector3.new(600, 8 + 8 * rank, 8 + 8 * rank), Transparency = 1 }):Play()
	Debris:AddItem(pillar, 2.5)
	for i = 1, 1 + rank do
		local ring = part(Vector3.new(1, 4, 4), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), (i % 2 == 0) and WHITE or color, NEON, Enum.PartType.Cylinder, 0.15)
		ring.Parent = workspace
		TweenService:Create(ring, TweenInfo.new(0.7 + i * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(1, 80 + i * 45, 80 + i * 45), Transparency = 1 }):Play()
		Debris:AddItem(ring, 2.2)
	end
	confetti(root_ui, ({ 30, 70, 120, 200 })[rank], { color, WHITE, C3(255, 214, 110), color:Lerp(WHITE, 0.5) })
	if secret or legendary then lightRays(root_ui, color, secret and 16 or 10) end
	local CARD_SIZE = Vector2.new(660, 470)
	local cardFit = math.min(1, (vs.X - 24) / CARD_SIZE.X, (vs.Y - 40) / (CARD_SIZE.Y + 70))
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y), BackgroundColor3 = C3(8, 8, 20), BackgroundTransparency = 0.04, BorderSizePixel = 0, ZIndex = 10 }, root_ui)
	new("UICorner", { CornerRadius = UDim.new(0, 22) }, card)
	local cs = new("UIStroke", { Color = color, Thickness = 4 }, card)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(C3(10, 10, 24), 0.7), C3(8, 8, 20)) }, card)
	local sc = new("UIScale", { Scale = 0.15 }, card)
	card.Rotation = -6
	TweenService:Create(sc, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = cardFit }):Play()
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
	-- a soft glow behind the weapon, then the real model, big and turning (duplicates show their model too)
	local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(330, 205), Size = UDim2.fromOffset(500, 150), BackgroundColor3 = color, BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 5 }, card)
	new("UICorner", { CornerRadius = UDim.new(0, 75) }, glow)
	TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.65, Size = UDim2.fromOffset(560, 170) }):Play()
	local src = previewSource(w.tool)
	if not (src and weaponViewport(card, src, UDim2.fromOffset(40, 112), UDim2.fromOffset(580, 190), 580 / 190)) then
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

	-- the button hangs under the card, so it scales with it on small screens
	local closeBtn = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 16), Size = UDim2.fromOffset(240, 46), BackgroundColor3 = color, Text = "CONTINUE", Font = Enum.Font.GothamBlack, TextSize = 19, TextColor3 = C3(10, 10, 24), ZIndex = 12 }, card)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, closeBtn)
	closeBtn.Activated:Connect(close)
	task.delay(18, close)
	task.delay(1.2, function()
		if closed then return end
		UserInputService.InputBegan:Once(function() close() end)
	end)
end

notifyRemote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "chest" and typeof(a) == "table" then
		local ok, err = pcall(playOpening, a, typeof(b) == "CFrame" and b or nil)
		if not ok then
			-- never leave the player stuck with a frozen camera
			warn("[ChestFX] " .. tostring(err))
			if activeCleanup then activeCleanup() end
			busy = false
			refreshButton()
		end
	end
end)
