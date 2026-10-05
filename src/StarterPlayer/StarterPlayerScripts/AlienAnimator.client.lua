-- AlienAnimator (LocalScript)
-- Brings the SHOP / SELL aliens and their hologram signs to life (only on your own screen):
--   aliens: breathing, head that follows you with its eyes, blinking, wiggling antennae, a spinning hologram,
--           and a gesture when you come close (the shopkeeper offers a hand, the seller waves)
--   signs : float up and down, turn to face you, spinning coins / crystals, shimmering title and a scan line
-- The ship itself floats (ShipClient moves the whole model); this script poses the moving parts on top of that.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ship = workspace:WaitForChild("AlienShip")
local aliensFolder = ship:WaitForChild("Aliens")
local rocketRoot = workspace:WaitForChild("Rocket")
local mastersFolder = rocketRoot:WaitForChild("RocketMasters", 60)
local rng = Random.new()

-- the ship is a big model that arrives piece by piece: wait until it has finished arriving
do
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local last, stable = -1, 0
	repeat
		task.wait(0.5)
		local n = #ship:GetDescendants()
		if n == last then
			stable += 1
		else
			stable = 0
		end
		last = n
	until stable >= 3
end

local function rotAbout(joint, rot)
	return CFrame.new(joint) * rot * CFrame.new(-joint)
end
local function lerp(a, b, t)
	return a + (b - a) * t
end

-- collect everything that has to move
local rigs = {}
local function collect(folder, space)
for _, m in folder:GetChildren() do
	local kind = m:IsA("Model") and m:GetAttribute("Kind")
	if kind then
		local rig = {
			model = m,
			name = m.Name,
			space = space,
			kind = kind,
			baseRel = m:GetAttribute("BaseRel"),
			parts = {},
			joints = {},
			phase = rng:NextNumber(0, 6.28),
			role = m:GetAttribute("Role"),
			mode = "type", modeUntil = os.clock() + rng:NextNumber(2, 8),
			yaw = 0, pitch = 0, gesture = 0,
			blinkStart = -10, nextBlink = os.clock() + rng:NextNumber(1, 3),
			shines = {}, scans = {}, titles = {},
		}
		for attrName, value in m:GetAttributes() do
			if attrName:sub(1, 2) == "J_" then
				rig.joints[attrName:sub(3)] = value
			end
		end
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") then
				local g = p:GetAttribute("Group")
				if g then
					table.insert(rig.parts, { part = p, group = g, rest = p:GetAttribute("Rest") })
				end
			end
		end
		if kind == "Sign" then
			local panel = m:FindFirstChild("SignPanel")
			rig.light = panel and panel:FindFirstChildOfClass("PointLight")
			for _, d in m:GetDescendants() do
				if d.Name == "TitleShine" then
					table.insert(rig.shines, d)
				elseif d.Name == "Scan" then
					table.insert(rig.scans, d)
				elseif d.Name == "Title" and d:IsA("TextLabel") then
					table.insert(rig.titles, d)
				end
			end
		end
		table.insert(rigs, rig)
	end
end
end
collect(aliensFolder, ship)
if mastersFolder then
	collect(mastersFolder, rocketRoot)
end

local t = 0

local function animateAlien(rig, base, dt, nearest, nearestDist)
	local J = rig.joints

	-- the head follows the closest player (the reactor operators watch the reactor instead)
	local targetYaw = 0.18 * math.sin(t * 0.5 + rig.phase)
	local targetPitch = 0
	local lookAt = nil
	if rig.role == "Operator" then
		lookAt = rig.ballLocal
		if nearest and nearestDist < 14 then
			lookAt = nearest
		end
	elseif rig.role == "Master" or rig.role == "Commander" then
		if nearest and nearestDist < 160 then
			lookAt = nearest
		end
	elseif nearest and nearestDist < 55 then
		lookAt = nearest
	end
	if lookAt then
		local d = lookAt - J.HeadCenter
		targetYaw = math.clamp(math.atan2(-d.X, -d.Z), -0.95, 0.95)
		targetPitch = math.clamp(math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z)), (rig.role == "Master") and -0.75 or -0.25, 0.3)
	end
	local k = math.min(dt * 6, 1)
	rig.yaw += (targetYaw - rig.yaw) * k
	rig.pitch += (targetPitch - rig.pitch) * k

	-- gesture when somebody is near
	local wantGesture = (nearest and nearestDist < (rig.role == "Operator" and 9 or (rig.role == "Master" and 140 or (rig.role == "Commander" and 45 or 32)))) and 1 or 0
	rig.gesture += (wantGesture - rig.gesture) * math.min(dt * 3, 1)
	local g = rig.gesture

	-- blinking
	local now = os.clock()
	if rig.role == "Operator" and now >= rig.modeUntil then
		-- sometimes point at the reactor instead of typing
		if rig.mode == "type" and rng:NextNumber() < 0.5 then
			rig.mode = "point"
			rig.modeUntil = now + rng:NextNumber(1.8, 3.2)
		else
			rig.mode = "type"
			rig.modeUntil = now + rng:NextNumber(4, 10)
		end
	end
	if now >= rig.nextBlink then
		rig.blinkStart = now
		rig.nextBlink = now + rng:NextNumber(2.5, 5)
	end
	local bt = (now - rig.blinkStart) / 0.16
	local blink = (bt >= 0 and bt <= 1) and math.sin(bt * math.pi) or 0

	local ph = rig.phase
	local T = {}
	T.Torso = CFrame.new(0, 0.07 * math.sin(t * 1.7 + ph), 0) * rotAbout(J.Waist, CFrame.Angles((rig.role == "Master" and -0.1 or 0) + 0.012 * math.sin(t * 1.7 + ph), 0.035 * math.sin(t * 0.6 + ph), 0))
	T.Head = T.Torso * rotAbout(J.Neck, CFrame.Angles(0, rig.yaw, 0) * CFrame.Angles(rig.pitch + 0.03 * math.sin(t * 1.1 + ph), 0, 0.02 * math.sin(t * 0.8 + ph)))
	T.LidR = T.Head * CFrame.new(0, -2.0 * blink, 0)
	T.LidL = T.LidR
	T.AntR = T.Head * rotAbout(J.AntR or Vector3.zero, CFrame.Angles(0.18 * math.sin(t * 2.4 + ph), 0, 0.14 * math.sin(t * 1.9 + ph + 1)))
	T.AntL = T.Head * rotAbout(J.AntL or Vector3.zero, CFrame.Angles(0.18 * math.sin(t * 2.2 + ph + 2), 0, 0.14 * math.sin(t * 1.7 + ph)))
	T.Holo = T.Torso * rotAbout(J.Holo, CFrame.Angles(0, t * 1.4, 0))

	-- arms
	local function arm(n, sideSign)
		local pitch1 = 0.05 * math.sin(t * 1.3 + ph + sideSign)
		local roll1 = 0.06 * sideSign
		local pitch2 = 0.1 + 0.04 * math.sin(t * 1.7 + ph)
		local roll2 = 0
		if rig.role == "Master" then
			if n == "L" then
				-- the left forearm rests on the balcony ledge
				pitch1 = 0.8 + 0.01 * math.sin(t * 1.2 + ph)
				roll1 = -0.04
				pitch2 = 0.77
			else
				-- the right hand: relaxed at the side, and a big friendly wave when you are in sight
				pitch1 = lerp(0.12 + 0.03 * math.sin(t * 1.2 + ph), 0.25, g)
				roll1 = lerp(0.14, 2.8, g)
				pitch2 = lerp(0.4 + 0.05 * math.sin(t * 1.5 + ph), 0.2, g)
				roll2 = g * 0.55 * math.sin(t * 7)
			end
		elseif rig.role == "Commander" then
			if n == "L" then
				-- reading the mission tablet in front of him
				pitch1 = 0.55 + 0.02 * math.sin(t * 1.1 + ph)
				roll1 = -0.1
				pitch2 = 1.05 + 0.03 * math.sin(t * 1.5 + ph)
			else
				-- right hand: relaxed, and a wave when you walk up
				pitch1 = lerp(0.1 + 0.03 * math.sin(t * 1.2 + ph), 0.25, g)
				roll1 = lerp(0.14, 2.5, g)
				pitch2 = lerp(0.35, 0.2, g)
				roll2 = g * 0.55 * math.sin(t * 7)
			end
		elseif rig.role == "Operator" then
			if n == "R" and rig.mode == "point" then
				pitch1, roll1, pitch2 = 1.4, 0.1, 0.15
			else
				-- typing at the console
				pitch1 = 0.85 + 0.05 * math.sin(t * 9 + ph + sideSign)
				pitch2 = 0.95 + 0.14 * math.sin(t * 11 + ph * 2 + sideSign * 1.7)
			end
			if n == "R" and g > 0.01 then
				-- wave back at somebody who walks up
				pitch1 = lerp(pitch1, 0.25, g)
				roll1 = lerp(roll1, 2.5, g)
				roll2 = g * 0.55 * math.sin(t * 7)
				pitch2 = lerp(pitch2, 0.2, g)
			end
		elseif n == "R" then
			if rig.name == "SellerAlien" then
				-- friendly wave
				pitch1 = lerp(pitch1, 0.25, g)
				roll1 = lerp(roll1, 2.5, g)
				roll2 = g * 0.55 * math.sin(t * 7)
				pitch2 = lerp(pitch2, 0.2, g)
			else
				-- offering an open hand
				pitch1 = lerp(pitch1, 0.95, g)
				pitch2 = lerp(pitch2, 1.15, g)
			end
		else
			pitch1 += 0.12 * g
		end
		local r1 = CFrame.Angles(0, 0, roll1) * CFrame.Angles(pitch1, 0, 0)
		local a1 = T.Torso * rotAbout(J["Shoulder" .. n], r1)
		local a2 = a1 * rotAbout(J["Elbow" .. n], CFrame.Angles(0, 0, roll2) * CFrame.Angles(pitch2, 0, 0))
		local a3 = a2 * rotAbout(J["Wrist" .. n], CFrame.Angles(0.12 * math.sin(t * 1.5 + ph), 0, 0))
		T["Arm" .. n .. "1"], T["Arm" .. n .. "2"], T["Arm" .. n .. "3"] = a1, a2, a3
	end
	arm("R", 1)
	arm("L", -1)

	for _, e in rig.parts do
		local tr = T[e.group]
		if tr then
			e.part.CFrame = base * tr * e.rest
		end
	end
end

local function animateSign(rig, base, dt, nearest, nearestDist)
	local J = rig.joints
	local ph = rig.phase

	-- turn to face the closest player (never all the way round)
	local targetYaw = 0
	if nearest and nearestDist < 90 then
		local d = nearest - J.Sign
		targetYaw = math.clamp(math.atan2(-d.X, -d.Z), -1.0, 1.0)
	end
	rig.yaw += (targetYaw - rig.yaw) * math.min(dt * 3, 1)

	local tSign = CFrame.new(0, 0.28 * math.sin(t * 1.3 + ph), 0) * rotAbout(J.Sign, CFrame.Angles(0, rig.yaw, 0))
	local isCoin = rig.name == "SellSign"
	for _, e in rig.parts do
		if e.group == "Sign" then
			e.part.CFrame = base * tSign * e.rest
		elseif e.group == "Icon" then
			local joint = (e.rest.Position.X > 0) and J.IconR or J.IconL
			local spin = isCoin and CFrame.Angles(0, t * 2.2, 0) or (CFrame.Angles(0, t * 1.8, 0) * CFrame.Angles(t * 1.1, 0, 0))
			e.part.CFrame = base * tSign * rotAbout(joint, spin) * e.rest
		end
	end

	-- shimmering title, scan line, rare flicker
	for _, s in rig.shines do
		s.Offset = Vector2.new(math.sin(t * 1.1 + ph) * 0.75, 0)
	end
	for _, sc in rig.scans do
		sc.Position = UDim2.fromScale(0, (t * 0.35 + ph) % 1.15)
	end
	local flicker = ((t * 0.7 + ph) % 7) < 0.12
	for _, tl in rig.titles do
		tl.TextTransparency = flicker and 0.55 or 0
	end
	if rig.light then
		rig.light.Brightness = 1 + 0.3 * math.sin(t * 2 + ph) - (flicker and 0.6 or 0)
	end
end

RunService.RenderStepped:Connect(function(dt)
	t += dt
	for _, rig in rigs do
		local pivot = rig.space:GetPivot()
		local base = pivot * rig.baseRel

		-- closest player, in the alien's own coordinate system
		local nearest, nearestDist = nil, math.huge
		for _, plr in Players:GetPlayers() do
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local lp = base:PointToObjectSpace(root.Position)
				local d = lp.Magnitude
				if d < nearestDist then
					nearest, nearestDist = lp, d
				end
			end
		end

		if rig.kind == "Alien" then
			rig.ballLocal = base:PointToObjectSpace(pivot:PointToWorldSpace(Vector3.new(0, 36, 0)))
			animateAlien(rig, base, dt, nearest, nearestDist)
		else
			animateSign(rig, base, dt, nearest, nearestDist)
		end
	end
end)
