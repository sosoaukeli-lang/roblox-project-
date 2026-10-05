-- WeaponShowFX v2 (LocalScript)
-- The reveal of a freshly forged weapon, played smoothly on every player's screen (60 FPS):
--   1. the weapon ASSEMBLES: its parts fly in from all directions with glowing trails and snap together
--      while it blasts up out of the chamber (with a little digital flicker as it materialises)
--   2. it hangs and spins above the machine; three energy orbs with light trails circle it and a holographic
--      INFO CARD pops up (power / speed / range bars fill up)
--   3. a soft tractor beam from the tray guides it down in a graceful spiral; the orbs spiral in with it
--   4. it lands with a sparkle burst, the orbs dissolve, and it floats calmly above the tray
-- (moving it from the server was choppy). Lights are soft on purpose.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local fxRemote = ReplicatedStorage:WaitForChild("WeaponFX")
local rng = Random.new()

local function easeOutCubic(u) return 1 - (1 - u) ^ 3 end
local function easeOutBack(u)
	local c1, c3 = 1.2, 2.2
	return 1 + c3 * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end
local function smooth(u) return u * u * (3 - 2 * u) end
local function clamp01(x) return math.clamp(x, 0, 1) end

local STATS = {
	LaserPistol = { power = "15", powerBar = 0.25, speed = "0.35 s", speedBar = 0.55, range = "320", rangeBar = 0.70 },
	PlasmaRifle = { power = "10", powerBar = 0.17, speed = "AUTO", speedBar = 0.95, range = "380", rangeBar = 0.80 },
	VoidCannon = { power = "60 AoE", powerBar = 1.00, speed = "1.8 s", speedBar = 0.15, range = "300", rangeBar = 0.60 },
}

-- the holographic info card above the weapon
local function makeCard(anchor, color, name, stats)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(300, 172)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 160
	bb.Adornee = anchor
	bb.Parent = anchor
	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(8, 10, 26)
	root.BackgroundTransparency = 0.22
	root.Parent = bb
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0.07, 0); corner.Parent = root
	local stroke = Instance.new("UIStroke"); stroke.Color = color; stroke.Thickness = 2.5; stroke.Transparency = 0.15; stroke.Parent = root
	local scale = Instance.new("UIScale"); scale.Scale = 0; scale.Parent = root

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromScale(0.05, 0.05)
	title.Size = UDim2.fromScale(0.9, 0.24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	title.Text = name or "WEAPON"
	title.Parent = root
	local fills = {}
	local rows = {
		{ "POWER", stats.power, stats.powerBar },
		{ "SPEED", stats.speed, stats.speedBar },
		{ "RANGE", stats.range, stats.rangeBar },
	}
	for i, r in rows do
		local y = 0.34 + (i - 1) * 0.215
		local lab = Instance.new("TextLabel")
		lab.Position = UDim2.fromScale(0.06, y)
		lab.Size = UDim2.fromScale(0.2, 0.15)
		lab.BackgroundTransparency = 1
		lab.Font = Enum.Font.Code
		lab.TextScaled = true
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.TextColor3 = Color3.fromRGB(190, 205, 235)
		lab.Text = r[1]
		lab.Parent = root
		local bg = Instance.new("Frame")
		bg.Position = UDim2.fromScale(0.28, y + 0.03)
		bg.Size = UDim2.fromScale(0.44, 0.09)
		bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		bg.BackgroundTransparency = 0.4
		bg.BorderSizePixel = 0
		bg.Parent = root
		local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(0.5, 0); bgc.Parent = bg
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Parent = bg
		local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0.5, 0); fc.Parent = fill
		local val = Instance.new("TextLabel")
		val.Position = UDim2.fromScale(0.75, y)
		val.Size = UDim2.fromScale(0.2, 0.15)
		val.BackgroundTransparency = 1
		val.Font = Enum.Font.GothamBold
		val.TextScaled = true
		val.TextXAlignment = Enum.TextXAlignment.Right
		val.TextColor3 = Color3.new(1, 1, 1)
		val.Text = r[2]
		val.Parent = root
		table.insert(fills, { fill = fill, value = r[3], delay = 0.25 + (i - 1) * 0.15 })
	end
	return { gui = bb, scale = scale, fills = fills }
end

local function trailOn(part, color, lifetime, width)
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, width * 0.5, 0); a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -width * 0.5, 0); a1.Parent = part
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = lifetime
	tr.LightEmission = 0.6
	tr.FaceCamera = true
	tr.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.3), color)
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	tr.Parent = part
	return tr, a0, a1
end

local function play(holo, tray, color, duration, name, id)
	if not holo.Parent or not tray.Parent then
		return
	end
	local startPos = holo:GetPivot().Position
	local handle = holo.PrimaryPart
	local base = holo:GetPivot()

	-- every piece of the weapon, with where it should end up and where it starts (scattered)
	local pieces = {}
	for _, p in holo:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(pieces, {
				part = p, rel = base:ToObjectSpace(p.CFrame), size = p.Size, trans = p.Transparency,
				scatter = (p == handle) and Vector3.zero or (rng:NextUnitVector() * rng:NextNumber(5, 9)),
			})
			if p ~= handle then
				local tr = trailOn(p, color, 0.45, math.max(0.3, math.min(p.Size.X, p.Size.Y, p.Size.Z)))
				Debris:AddItem(tr, 1.6)
			end
		end
	end

	-- local-only helpers: an invisible anchor that follows the weapon (sparks, soft light, card, beam end)
	local FX = Instance.new("Part")
	FX.Anchored = true
	FX.CanCollide = false
	FX.CanQuery = false
	FX.CanTouch = false
	FX.CastShadow = false
	FX.Transparency = 1
	FX.Size = Vector3.new(1, 1, 1)
	FX.Position = startPos
	FX.Parent = workspace
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4), color)
	sparks.LightEmission = 0.6
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.5, 1.0)
	sparks.Speed = NumberRange.new(3, 9)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 0
	sparks.Parent = FX
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 26
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = FX

	local stats = STATS[id] or STATS.LaserPistol
	local card = makeCard(FX, color, name, stats)

	-- three orbiting energy orbs with light trails
	local orbs = {}
	for i = 1, 3 do
		local o = Instance.new("Part")
		o.Shape = Enum.PartType.Ball
		o.Size = Vector3.new(0.55, 0.55, 0.55)
		o.Anchored = true
		o.CanCollide = false
		o.CanQuery = false
		o.CanTouch = false
		o.CastShadow = false
		o.Material = Enum.Material.Neon
		o.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
		o.Transparency = 1
		o.Position = startPos
		o.Parent = workspace
		trailOn(o, color, 0.8, 0.5)
		table.insert(orbs, o)
	end

	-- tractor beam from the tray up to the weapon (soft)
	local trayAtt = Instance.new("Attachment")
	trayAtt.Position = Vector3.new(0, 0.3, 0)
	trayAtt.Parent = tray
	local fxAtt = Instance.new("Attachment")
	fxAtt.Parent = FX
	local beam = Instance.new("Beam")
	beam.Attachment0 = trayAtt
	beam.Attachment1 = fxAtt
	beam.Width0 = 2.8
	beam.Width1 = 0.35
	beam.Segments = 1
	beam.LightEmission = 0.5
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(1)
	beam.Parent = FX

	local APEX = 15
	local function above(off)
		return tray.Position + Vector3.new(0, off, 0)
	end
	local ASSEMBLE, BLAST, HANG_END, GLIDE_END = 0.9, 0.6, 2.5, 3.7

	local t0 = os.clock()
	local prev, spin = t0, 0
	local cardShown, landed, assembledDone, burst = false, false, false, false
	local nextGlitch, glitchUntil = t0 + 1.6, 0
	local conn
	local function cleanup()
		if conn then conn:Disconnect() end
		FX:Destroy()
		for _, o in orbs do o:Destroy() end
		trayAtt:Destroy()
	end
	conn = RunService.RenderStepped:Connect(function()
		if not holo.Parent or not tray.Parent then
			cleanup()
			return
		end
		local now = os.clock()
		local s = now - t0
		local dt = now - prev
		prev = now
		if s >= duration + 0.5 then
			cleanup()
			return
		end

		-- where the weapon is
		local pos, spinSpeed, light = nil, 2, 0.9
		local tilt = 0.12
		if s < BLAST then
			pos = startPos:Lerp(above(APEX), easeOutCubic(s / BLAST))
			spinSpeed, light, tilt = 14, 1.8, 0.0
			sparks:Emit(1)
		elseif s < HANG_END then
			pos = above(APEX + 0.7 * math.sin((s - BLAST) * 2.4))
			spinSpeed, light, tilt = 5, 1.2 + 0.3 * math.sin(s * 6), 0.2 + 0.08 * math.sin(s * 1.7)
			if rng:NextNumber() < 0.1 then sparks:Emit(1) end
		elseif s < GLIDE_END then
			local u = smooth((s - HANG_END) / (GLIDE_END - HANG_END))
			local hangEnd = above(APEX + 0.7 * math.sin((HANG_END - BLAST) * 2.4))
			pos = hangEnd:Lerp(above(3.2), u)
			local radius = math.sin(u * math.pi) * 2.6
			local a = (s - HANG_END) * 5.5
			pos += Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			spinSpeed, light, tilt = 7 - 4.5 * u, 1.4, 0.2 * (1 - u) + 0.12 * u
			if rng:NextNumber() < 0.35 then sparks:Emit(1) end
		else
			if not landed then
				landed = true
				sparks:Emit(24)
			end
			pos = above(3.2 + 0.28 * math.sin((s - GLIDE_END) * 2.5))
			spinSpeed, light, tilt = 1.8, 0.9, 0.12
		end
		spin += spinSpeed * dt
		local target = CFrame.new(pos) * CFrame.Angles(0, spin, 0) * CFrame.Angles(tilt, 0, 0)

		-- the weapon assembles piece by piece during the first moments, with a little digital flicker
		local a = clamp01(s / ASSEMBLE)
		if a < 1 then
			local e = easeOutBack(a)
			for _, pc in pieces do
				pc.part.CFrame = target * (CFrame.new(pc.scatter * (1 - e)) * pc.rel)
				pc.part.Size = pc.size * (0.45 + 0.55 * clamp01(e))
				pc.part.Transparency = math.clamp(0.9 + (pc.trans - 0.9) * e + (rng:NextNumber() < 0.25 and 0.25 or 0), 0, 1)
			end
		else
			if not assembledDone then
				assembledDone = true
				for _, pc in pieces do
					pc.part.Size = pc.size
				end
				sparks:Emit(30)
				burst = true
			end
			holo:PivotTo(target)
		end

		-- occasional hologram glitch while it hangs up there
		if s > ASSEMBLE and s < HANG_END then
			if now >= nextGlitch then
				nextGlitch = now + rng:NextNumber(1.2, 2.0)
				glitchUntil = now + 0.1
			end
			local g = now < glitchUntil
			for _, pc in pieces do
				pc.part.Transparency = g and math.clamp(pc.trans + 0.45, 0, 1) or pc.trans
			end
		elseif s >= HANG_END and assembledDone then
			for _, pc in pieces do
				pc.part.Transparency = pc.trans
			end
		end

		-- the info card
		if s >= 1.1 and not cardShown then
			cardShown = true
			TweenService:Create(card.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			for _, f in card.fills do
				task.delay(f.delay, function()
					TweenService:Create(f.fill, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.fromScale(f.value, 1) }):Play()
				end)
			end
		end
		if s >= duration - 0.5 and cardShown then
			cardShown = false
			TweenService:Create(card.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end

		-- orbs circle the weapon (they spiral in during the glide and dissolve when it lands)
		if s >= ASSEMBLE then
			local radius = 3.4
			if s >= HANG_END then
				radius = 3.4 * (1 - 0.55 * smooth(clamp01((s - HANG_END) / (GLIDE_END - HANG_END))))
			end
			for i, o in orbs do
				if s < GLIDE_END + 0.1 then
					o.Transparency = 0
					local ang = s * (3 + i * 0.6) + i * 2.094
					local tiltPlane = CFrame.Angles(i * 0.9, 0, i * 0.5)
					o.Position = pos + tiltPlane:VectorToWorldSpace(Vector3.new(math.cos(ang) * radius, 0, math.sin(ang) * radius))
				elseif o.Transparency < 1 then
					o.Transparency = 1
					sparks:Emit(6)
				end
			end
		end

		-- tractor beam: fades in as it starts to descend, out before the end
		local beamAlpha = clamp01((s - HANG_END) / 0.5) * clamp01((duration - 0.3 - s) / 0.6)
		beam.Transparency = NumberSequence.new(1 - 0.18 * beamAlpha)

		FX.Position = pos
		glow.Brightness = light
	end)
end

fxRemote.OnClientEvent:Connect(function(kind, holo, tray, color, duration, name, id)
	if kind == "weaponShow" and typeof(holo) == "Instance" and typeof(tray) == "Instance" and typeof(color) == "Color3" then
		task.spawn(play, holo, tray, color, duration or 6.0, name, id)
	end
end)
