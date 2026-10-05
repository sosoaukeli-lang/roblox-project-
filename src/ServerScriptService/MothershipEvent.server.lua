-- MothershipEvent (Script) - the hourly MOTHERSHIP invasion.
--   * every hour (first one 15 minutes after the server starts) a huge alien mothership warps in over the map
--   * it launches waves of minions (Stingers, Gunships, Brutes) and fires turrets at players
--   * after ~75 seconds the hangar opens and THE VOID SOVEREIGN - a three-phase boss with cinematic abilities - comes out
--   * kill the boss and every player who hurt it gets a personal LOOT CHEST (random weapon, with pity); if the boss is not
--     killed in time the mothership retreats
-- Test it any time:  game.Workspace:SetAttribute("MothershipSummon", true)   (server console / command bar)
-- Everything the HUD needs is published as attributes on Workspace (MS_State, MS_BossHP, MS_Next, MS_TargetPos, ...).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local assets = SS:WaitForChild("MothershipAssets")
local events = SS:WaitForChild("ProgressEvents")
local grant = events:WaitForChild("Grant")
local diedEvent = events:WaitForChild("AlienDied")
local notifyRemote = RS:WaitForChild("ProgressNotify")
local ev = RS:WaitForChild("MothershipEvent")
local rng = Random.new()

----------------------------------------------------------------------
-- settings
----------------------------------------------------------------------
-- TEST_MODE = true: the first invasion comes 20 s after you press Play, the boss appears 10 s after the ship arrives.
-- Set it to false before publishing (then: first invasion after 15 min, the boss after 75 s, then every hour).
local TEST_MODE = true
local INTERVAL = 3600 -- seconds between invasions (1 hour)
local FIRST_DELAY = TEST_MODE and 20 or 900
local WARN_TIME = TEST_MODE and 10 or 45 -- seconds of warning before the ship arrives
local SHIP_POS = Vector3.new(0, 1900, 900)
local FOCUS = Vector3.new(0, 650, 0) -- the ship faces the rocket
local BOSS_DELAY = TEST_MODE and 10 or 75 -- seconds after arrival before the hangar opens
local TIMEOUT = 15 * 60 -- the ship retreats if the boss is still alive after this long (counted from arrival)
local BOSS_HP_BASE, BOSS_HP_PER_PLAYER = 30000, 12000
local MAX_MINIONS = 24
local CHEST_LIFETIME = 600 -- an unopened chest turns into a saved chest after this long

local C3 = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local VIOLET, CRIM, GOLD, ORANGE = C3(170, 90, 255), C3(255, 50, 80), C3(232, 184, 96), C3(255, 140, 50)
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder

local forces = workspace:FindFirstChild("MothershipForces") or Instance.new("Folder")
forces.Name = "MothershipForces"
forces.Parent = workspace
local shipFolder = workspace:FindFirstChild("MothershipShip") or Instance.new("Folder")
shipFolder.Name = "MothershipShip"
shipFolder.Parent = workspace
local chestFolder = workspace:FindFirstChild("LootChests") or Instance.new("Folder")
chestFolder.Name = "LootChests"
chestFolder.Parent = workspace

local function setState(s) workspace:SetAttribute("MS_State", s) end
setState("idle")
local function now() return workspace:GetServerTimeNow() end
local function broadcast(kind, ...) ev:FireAllClients(kind, ...) end

----------------------------------------------------------------------
-- small effect helpers
----------------------------------------------------------------------
local function fxPart(size, cf, color, shape, trans, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.Transparency = trans or 0
	if shape then p.Shape = shape end
	p.CFrame = cf
	p.Parent = workspace
	return p
end
local function fade(p, t, size, trans)
	local goal = { Transparency = trans or 1 }
	if size then goal.Size = size end
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, t + 0.1)
end
local function sparks(pos, color, count, speed)
	local p = fxPart(Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), WHITE, nil, 1)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(WHITE, color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.4, 1.1)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, 1.6)
end
local sound -- (defined below)
local function blast(pos, color, radius, long)
	local ball = fxPart(Vector3.one * 4, CFrame.new(pos), WHITE, BALL, 0)
	fade(ball, long and 0.8 or 0.5, Vector3.one * radius * 2, 1)
	local core = fxPart(Vector3.one * 3, CFrame.new(pos), color, BALL, 0.1)
	fade(core, long and 1.0 or 0.6, Vector3.one * radius * 2.6, 1)
	local ring = fxPart(Vector3.new(1, 2, 2), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, CYL, 0.1)
	fade(ring, 0.7, Vector3.new(1, radius * 4, radius * 4), 1)
	sparks(pos, color, math.floor(radius * 3), radius * 4)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = radius * 3
	l.Brightness = 6
	l.Parent = ball
	-- every blast has a BOOM: big ones have a deep, long one
	local sp = fxPart(Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), WHITE, nil, 1)
	Debris:AddItem(sp, 6) -- (the boom outlives the fireball)
	sound(sp, long and 129993092121020 or 9065667699, math.clamp(radius / 22, 0.45, 1.7), long and 0.8 or math.clamp(1.4 - radius / 110, 0.7, 1.4))
	if radius >= 30 then sound(sp, 9116277954, 0.7, 0.7) end
end
sound = function(parent, id, vol, speed)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = vol or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 1500
	s.RollOffMinDistance = 80
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 8)
end

----------------------------------------------------------------------
-- who is in danger? (the rocket and the alien ship are SAFE ZONES)
----------------------------------------------------------------------
local function insideBox(model, pos, margin)
	if not model then return false end
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok then return false end
	local lp = cf:PointToObjectSpace(pos)
	return math.abs(lp.X) < size.X / 2 + margin and math.abs(lp.Y) < size.Y / 2 + margin and math.abs(lp.Z) < size.Z / 2 + margin
end
local function isSafe(pos)
	return insideBox(workspace:FindFirstChild("Rocket"), pos, 12) or insideBox(workspace:FindFirstChild("AlienShip"), pos, 12)
end
local function livePlayers()
	local list = {}
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and not isSafe(root.Position) then
			list[#list + 1] = { player = p, root = root, hum = hum }
		end
	end
	return list
end
local function nearestTarget(pos, maxDist)
	local best, bd = nil, maxDist or math.huge
	for _, e in livePlayers() do
		local d = (e.root.Position - pos).Magnitude
		if d < bd then best, bd = e, d end
	end
	return best, bd
end
local function damagePlayer(entry, amount)
	if entry.hum.Health > 0 then
		entry.hum:TakeDamage(amount)
		ev:FireClient(entry.player, "hurt", amount)
	end
end
-- BOOST DODGE: while you BOOST (fast flight) the big lasers pass through you. The server sees your speed.
local lastBoost = {}
task.spawn(function()
	while true do
		task.wait(0.08)
		for _, p in Players:GetPlayers() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and root.AssemblyLinearVelocity.Magnitude > 100 then lastBoost[p] = os.clock() end
		end
	end
end)
local function boosting(entry)
	return os.clock() - (lastBoost[entry.player] or -10) < 0.5
end
local function damageArea(pos, radius, amount, cb, beam)
	for _, e in livePlayers() do
		if (e.root.Position - pos).Magnitude <= radius then
			if beam and boosting(e) then
				ev:FireClient(e.player, "dodge") -- you flew through the laser!
			else
				damagePlayer(e, amount)
				if cb then cb(e) end
			end
		end
	end
end
local function push(entry, vector)
	if vector.X ~= vector.X or vector.Y ~= vector.Y or vector.Z ~= vector.Z or vector.Magnitude > 400 then
		vector = Vector3.yAxis * 40 -- (the direction was undefined: push straight up instead)
	end
	-- a shove in zero gravity: the client adds it to the flight velocity (see ZeroGravityFlight / FlightKick)
	entry.player:SetAttribute("FlightKick", vector + Vector3.new(0, 0, 0.001 * rng:NextNumber()))
end

----------------------------------------------------------------------
-- minions
----------------------------------------------------------------------
local MINION = {
	Stinger = { speed = 78, pay = 18, ichor = 0 },
	Gunship = { speed = 46, pay = 70, ichor = 1 },
	Brute = { speed = 30, pay = 260, ichor = 3 },
}
local function aliveMinions()
	local n = 0
	for _, m in forces:GetChildren() do
		local h = m:FindFirstChildOfClass("Humanoid")
		if m:GetAttribute("Minion") and h and h.Health > 0 then n += 1 end
	end
	return n
end
local function hpScale() return 1 + 0.3 * (#Players:GetPlayers() - 1) end

local function onMinionDeath(m, hum, kind)
	local root = m.PrimaryPart
	local pos = root and root.Position or Vector3.zero
	blast(pos, kind == "Brute" and ORANGE or CRIM, kind == "Brute" and 22 or (kind == "Gunship" and 14 or 8), kind == "Brute")
	sound(root, 9065667699, 0.8, kind == "Brute" and 0.7 or 1.2)
	local killerId = hum:GetAttribute("LastAttacker")
	local killer = killerId and Players:GetPlayerByUserId(killerId)
	if killer and (os.clock() - (hum:GetAttribute("LastAttackTime") or 0)) < 12 then
		local money = killer:FindFirstChild("leaderstats") and killer.leaderstats:FindFirstChild("Money")
		if money then money.Value += MINION[kind].pay end
		diedEvent:Fire(pos, killerId, 0, hum:GetAttribute("LastWeapon"), false)
	end
	Debris:AddItem(m, 0.1)
end

local function aimAt(root, goal, look, speed)
	local ap, ao = root:FindFirstChild("MoveAP"), root:FindFirstChild("MoveAO")
	if not ap then return end
	ap.MaxVelocity = speed
	ap.Position = goal
	local pos = root.Position
	if look and (look - pos).Magnitude > 1 then ao.CFrame = CFrame.lookAt(pos, look) end
end

local function spawnMinion(kind, pos, extraPlayers)
	local tpl = assets:FindFirstChild(kind)
	if not tpl then return end
	local m = tpl:Clone()
	local root = m.PrimaryPart
	m:PivotTo(CFrame.new(pos))
	local hum = m:FindFirstChildOfClass("Humanoid")
	hum.MaxHealth = hum.MaxHealth * hpScale()
	hum.Health = hum.MaxHealth
	hum.PlatformStand = true
	m:SetAttribute("Minion", true)
	m.Parent = forces
	pcall(function() root:SetNetworkOwner(nil) end)
	local att = Instance.new("Attachment")
	att.Name = "MoveAtt"
	att.Parent = root
	local ap = Instance.new("AlignPosition")
	ap.Name = "MoveAP"
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.MaxForce = math.huge
	ap.MaxVelocity = MINION[kind].speed
	ap.Responsiveness = 8
	ap.Position = pos
	ap.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "MoveAO"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 10
	ao.CFrame = root.CFrame
	ao.Parent = root
	hum.Died:Once(function() onMinionDeath(m, hum, kind) end)
	return m, root, hum
end

-- STINGER: dives at the nearest player and explodes
local function runStinger(m, root, hum)
	local orbit = rng:NextNumber(0, 6.28)
	while m.Parent and hum.Health > 0 and root.Parent do
		task.wait(0.1)
		local stun = (m:GetAttribute("StunUntil") or 0) > os.clock()
		local slow = ((m:GetAttribute("SlowUntil") or 0) > os.clock()) and (m:GetAttribute("SlowFactor") or 0.5) or 1
		local t, d = nearestTarget(root.Position, 2200)
		if t then
			local dir = t.root.Position - root.Position
			local speed = (d < 90 and 125 or MINION.Stinger.speed) * slow
			aimAt(root, t.root.Position, t.root.Position, stun and 0.5 or speed)
			if d < 8 and not stun then
				damageArea(root.Position, 14, 16)
				hum.Health = 0
				return
			end
		else
			orbit += 0.15
			local c = (shipFolder:FindFirstChildOfClass("Model") and shipFolder:FindFirstChildOfClass("Model").PrimaryPart.Position) or SHIP_POS
			aimAt(root, c + Vector3.new(math.cos(orbit) * 260, -120, math.sin(orbit) * 260), nil, 60)
		end
	end
end

-- a plasma bolt fired by a gunship / the ship: flies straight, hurts the first player it touches
local function plasmaBolt(origin, targetPos, speed, damage, color, size)
	local dir = (targetPos - origin)
	if dir.Magnitude < 1 then return end
	dir = dir.Unit
	local p = fxPart(Vector3.new(size, size, size * 2.4), CFrame.lookAt(origin, origin + dir), color, nil, 0.1)
	local core = fxPart(Vector3.new(size * 0.5, size * 0.5, size * 2.6), CFrame.lookAt(origin, origin + dir), WHITE, nil, 0)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, size * 0.5, 0), Vector3.new(0, -size * 0.5, 0)
	a0.Parent, a1.Parent = p, p
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = 0.3
	tr.LightEmission = 1
	tr.Color = ColorSequence.new(WHITE, color)
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	tr.Parent = p
	task.spawn(function()
		local t0, pos = os.clock(), origin
		while os.clock() - t0 < 2.2 do
			local dt = RunService.Heartbeat:Wait()
			pos += dir * speed * dt
			p.CFrame = CFrame.lookAt(pos, pos + dir)
			core.CFrame = p.CFrame
			for _, e in livePlayers() do
				if (e.root.Position - pos).Magnitude < size * 2 + 3 then
					damagePlayer(e, damage)
					blast(pos, color, 5)
					p:Destroy()
					core:Destroy()
					return
				end
			end
		end
		p:Destroy()
		core:Destroy()
	end)
end

-- GUNSHIP: keeps its distance and strafes, shooting
local function runGunship(m, root, hum)
	local strafe, lastShot = rng:NextNumber(0, 6.28), os.clock() + 1.5
	while m.Parent and hum.Health > 0 and root.Parent do
		task.wait(0.1)
		local stun = (m:GetAttribute("StunUntil") or 0) > os.clock()
		local slow = ((m:GetAttribute("SlowUntil") or 0) > os.clock()) and (m:GetAttribute("SlowFactor") or 0.5) or 1
		local t, d = nearestTarget(root.Position, 2200)
		if t then
			strafe += 0.07
			local away = root.Position - t.root.Position
			local dirAway = (away.Magnitude > 1) and away.Unit or Vector3.zAxis
			local side = dirAway:Cross(Vector3.yAxis)
			local goal = t.root.Position + dirAway * 105 + side * math.sin(strafe) * 60 + Vector3.new(0, math.cos(strafe * 0.7) * 25, 0)
			aimAt(root, goal, t.root.Position, stun and 0.5 or MINION.Gunship.speed * slow)
			if d < 230 and os.clock() - lastShot > 1.7 and not stun then
				lastShot = os.clock()
				local mz = root.Position + root.CFrame.LookVector * -16
				for _, off in { -8, 8 } do
					plasmaBolt(root.Position + root.CFrame.RightVector * off - root.CFrame.LookVector * 14, t.root.Position + t.root.AssemblyLinearVelocity * 0.25, 230, 9, VIOLET, 1.4)
				end
				sound(root, 6603571443, 0.6, 0.7)
			end
		else
			aimAt(root, root.Position + Vector3.new(0, 0, 0), nil, 10)
		end
	end
end

-- BRUTE: lumbers at you, then SLAMS (a warning ring, then a shockwave)
local function runBrute(m, root, hum)
	local lastSlam = os.clock() + 3
	while m.Parent and hum.Health > 0 and root.Parent do
		task.wait(0.1)
		local stun = (m:GetAttribute("StunUntil") or 0) > os.clock()
		local slow = ((m:GetAttribute("SlowUntil") or 0) > os.clock()) and (m:GetAttribute("SlowFactor") or 0.5) or 1
		local t, d = nearestTarget(root.Position, 2200)
		if t then
			aimAt(root, t.root.Position - (t.root.Position - root.Position).Unit * 20, t.root.Position, stun and 0.5 or MINION.Brute.speed * slow)
			if d < 40 and os.clock() - lastSlam > 4.5 and not stun then
				lastSlam = os.clock()
				local c = root.Position
				local warn = fxPart(Vector3.new(1, 2, 2), CFrame.new(c) * CFrame.Angles(0, 0, math.pi / 2), CRIM, CYL, 0.5)
				TweenService:Create(warn, TweenInfo.new(0.7), { Size = Vector3.new(1, 90, 90), Transparency = 0.8 }):Play()
				Debris:AddItem(warn, 0.8)
				task.wait(0.7)
				if hum.Health > 0 then
					blast(c, ORANGE, 40)
					sound(root, 9065667699, 1, 0.5)
					damageArea(c, 45, 26, function(e) push(e, (e.root.Position - c).Unit * 70) end)
				end
			end
		end
	end
end

local RUNNERS = { Stinger = runStinger, Gunship = runGunship, Brute = runBrute }
local function launch(kind, pos)
	local m, root, hum = spawnMinion(kind, pos)
	if m then task.spawn(function() pcall(RUNNERS[kind], m, root, hum) end) end
	return m
end

----------------------------------------------------------------------
-- the mothership: warp-in, turrets, waves of minions
----------------------------------------------------------------------
local ship, shipRoot
local running = false
local bossDead = false

local function beamBetween(p0, p1, thick, color, trans)
	local len = (p1 - p0).Magnitude
	local b = fxPart(Vector3.new(thick, thick, math.max(len, 0.1)), CFrame.lookAt((p0 + p1) / 2, p1), color, nil, trans or 0.2)
	return b
end
local function setBeam(b, p0, p1)
	local len = (p1 - p0).Magnitude
	b.Size = Vector3.new(b.Size.X, b.Size.Y, math.max(len, 0.1))
	b.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
end

local function warpIn()
	ship = assets.Mothership:Clone()
	shipRoot = ship.PrimaryPart
	local final = CFrame.lookAt(SHIP_POS, FOCUS)
	local start = final * CFrame.new(0, 600, 8000)
	ship:PivotTo(start)
	ship.Parent = shipFolder
	-- a streak of light ahead of the ship while it falls out of warp
	TweenService:Create(shipRoot, TweenInfo.new(9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { CFrame = final }):Play()
	task.delay(8.6, function()
		blast(SHIP_POS + final.LookVector * -300, VIOLET, 120, true)
		for i = 1, 3 do
			local r = fxPart(Vector3.new(4, 10, 10), CFrame.lookAt(SHIP_POS, FOCUS) * CFrame.Angles(0, math.pi / 2, 0), (i == 2) and CRIM or VIOLET, CYL, 0.1)
			TweenService:Create(r, TweenInfo.new(1.6 + i * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(4, 3000, 3000), Transparency = 1 }):Play()
			Debris:AddItem(r, 3)
		end
	end)
end

local function turretShot(entry)
	if not shipRoot or not shipRoot.Parent then return end
	-- the nearest turret to the target
	local best, bd
	for i = 1, 8 do
		local a = shipRoot:FindFirstChild("TurretMuzzle" .. i)
		if a then
			local d = (a.WorldPosition - entry.root.Position).Magnitude
			if not bd or d < bd then best, bd = a, d end
		end
	end
	if not best then return end
	local origin = best.WorldPosition
	local target = entry.root.Position
	local warn = beamBetween(origin, target, 0.8, CRIM, 0.4)
	local mark = fxPart(Vector3.one * 8, CFrame.new(target), CRIM, BALL, 0.6)
	local t0 = os.clock()
	while os.clock() - t0 < 1.25 and entry.hum.Health > 0 do
		target = entry.root.Position + entry.root.AssemblyLinearVelocity * 0.35
		setBeam(warn, origin, target)
		mark.Position = target
		mark.Size = Vector3.one * (8 + 14 * ((os.clock() - t0) / 1.25))
		RunService.Heartbeat:Wait()
	end
	warn:Destroy()
	mark:Destroy()
	local fire = beamBetween(origin, target, 7, WHITE, 0.05)
	local aura = beamBetween(origin, target, 14, CRIM, 0.55)
	fade(fire, 0.3)
	fade(aura, 0.4)
	blast(target, CRIM, 18)
	sound(shipRoot, 9065667699, 1.1, 0.8)
	damageArea(target, 18, 24, function(e) push(e, (e.root.Position - target).Unit * 40) end, true)
end

local function turretLoop()
	while running and shipRoot and shipRoot.Parent do
		task.wait(5.5)
		local list = {}
		for _, e in livePlayers() do
			if (e.root.Position - shipRoot.Position).Magnitude < 1400 then list[#list + 1] = e end
		end
		for i = 1, math.min(2, #list) do
			local e = table.remove(list, rng:NextInteger(1, #list))
			task.spawn(turretShot, e)
		end
	end
end

local function hangarPos(i)
	local a = shipRoot and shipRoot:FindFirstChild("Spawn" .. i)
	return a and a.WorldPosition or SHIP_POS
end
local function waveLoop()
	local wave = 0
	task.wait(5)
	while running and not bossDead do
		wave += 1
		local boss = workspace:GetAttribute("MS_State") == "boss"
		local plan = {}
		local nS = boss and 3 or math.min(3 + wave * 2, 11)
		local nG = boss and 1 or ((wave >= 2) and math.min(wave, 4) or 0)
		local nB = (not boss and wave >= 3) and math.min(math.floor(wave / 2), 2) or 0
		for _ = 1, nS do plan[#plan + 1] = "Stinger" end
		for _ = 1, nG do plan[#plan + 1] = "Gunship" end
		for _ = 1, nB do plan[#plan + 1] = "Brute" end
		broadcast("wave", wave, #plan)
		for _, kind in plan do
			if not running or bossDead then break end
			if aliveMinions() < MAX_MINIONS then
				local from = hangarPos(rng:NextInteger(1, 8))
				launch(kind, from)
				sound(shipRoot, 9112775375, 0.4, 1.4)
			end
			task.wait(0.55)
		end
		task.wait(boss and 26 or 16)
	end
end

----------------------------------------------------------------------
-- THE VOID SOVEREIGN
----------------------------------------------------------------------
local boss, bossRoot, bossHum
local phase = 1
local PHASE_COLOR = { VIOLET, CRIM, C3(255, 232, 170) }

local function announce(name) broadcast("ability", name, phase) end
local function bossEye() return bossRoot.CFrame * CFrame.new(0, 38, -16).Position end

local ABIL = {}

function ABIL.barrage()
	local t = nearestTarget(bossRoot.Position, 3000)
	if not t then return end
	announce("VOID BARRAGE")
	local n = ({ 8, 13, 18 })[phase]
	for i = 1, n do
		if bossHum.Health <= 0 or not t.hum.Parent then break end
		local from = bossRoot.Position + Vector3.new(rng:NextNumber(-34, 34), rng:NextNumber(0, 40), rng:NextNumber(-20, 10))
		local aim = t.root.Position + t.root.AssemblyLinearVelocity * 0.45 + Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(-10, 10), rng:NextNumber(-14, 14))
		plasmaBolt(from, aim, 175, 15, PHASE_COLOR[phase], 3.2)
		if i % 3 == 1 then broadcast("abilityFire", "barrage") end
		sparks(from, PHASE_COLOR[phase], 10, 30)
		task.wait(0.14)
	end
end

function ABIL.lance()
	local t = nearestTarget(bossRoot.Position, 3000)
	if not t then return end
	announce("VOID LANCE  -  BOOST TO DODGE!")
	local origin = bossEye()
	local aim = t.root.Position
	local warn = beamBetween(origin, origin + (aim - origin).Unit * 900, 1.0, CRIM, 0.35)
	local t0 = os.clock()
	local dir = (aim - origin).Unit
	while os.clock() - t0 < 1.7 and bossHum.Health > 0 do
		aim = t.root.Position
		dir = (aim - origin).Unit
		if os.clock() - t0 < 1.2 then setBeam(warn, origin, origin + dir * 900) end -- it follows you, then locks
		warn.Size = Vector3.new(1 + 3 * ((os.clock() - t0) / 1.7), 1 + 3 * ((os.clock() - t0) / 1.7), warn.Size.Z)
		RunService.Heartbeat:Wait()
	end
	warn:Destroy()
	broadcast("abilityFire", "lance")
	local p1 = origin + dir * 900
	local main = beamBetween(origin, p1, 18, WHITE, 0.05)
	local glow = beamBetween(origin, p1, 38, PHASE_COLOR[phase], 0.55)
	fade(main, 0.5)
	fade(glow, 0.6)
	sound(bossRoot, 9065667699, 1.4, 0.6)
	for _, e in livePlayers() do
		local rel = e.root.Position - origin
		local along = math.clamp(rel:Dot(dir), 0, 900)
		local closest = origin + dir * along
		if (e.root.Position - closest).Magnitude < 22 then
			if boosting(e) then
				ev:FireClient(e.player, "dodge") -- you flew through the Lance!
			else
				damagePlayer(e, 40)
				push(e, (e.root.Position - closest).Unit * 60)
				blast(e.root.Position, PHASE_COLOR[phase], 10)
			end
		end
	end
end

function ABIL.nova()
	announce("NOVA RING  -  GO ABOVE OR BELOW!")
	local center = bossRoot.Position
	broadcast("abilityFire", "nova")
	local ring = fxPart(Vector3.new(10, 40, 40), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), PHASE_COLOR[phase], CYL, 0.25)
	local glow = fxPart(Vector3.new(26, 40, 40), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), WHITE, CYL, 0.85)
	sound(bossRoot, 9125973257, 1.3, 0.6)
	local t0, hit = os.clock(), {}
	local DUR, MAXD = 3.0, 760
	while os.clock() - t0 < DUR and bossHum.Health > 0 do
		local a = (os.clock() - t0) / DUR
		local d = 40 + (MAXD - 40) * a
		ring.Size = Vector3.new(10, d, d)
		glow.Size = Vector3.new(26, d, d)
		ring.Transparency = 0.25 + 0.7 * a
		for _, e in livePlayers() do
			if not hit[e.player] then
				local rel = e.root.Position - center
				local flat = Vector3.new(rel.X, 0, rel.Z).Magnitude
				if math.abs(rel.Y) < 14 and math.abs(flat - d / 2) < 16 then
					hit[e.player] = true
					damagePlayer(e, 32)
					push(e, Vector3.new(rel.X, 0, rel.Z).Unit * 80)
					blast(e.root.Position, PHASE_COLOR[phase], 8)
				end
			end
		end
		RunService.Heartbeat:Wait()
	end
	ring:Destroy()
	glow:Destroy()
end

function ABIL.singularity()
	local t = nearestTarget(bossRoot.Position, 3000)
	if not t then return end
	announce("SINGULARITY  -  FLY AWAY!")
	local c = t.root.Position + Vector3.new(0, 5, 0)
	local shell = fxPart(Vector3.one * 8, CFrame.new(c), VIOLET, BALL, 0.55)
	local t0 = os.clock()
	while os.clock() - t0 < 1.6 do
		shell.Size = Vector3.one * (8 + 22 * ((os.clock() - t0) / 1.6))
		RunService.Heartbeat:Wait()
	end
	broadcast("abilityFire", "singularity")
	local core = fxPart(Vector3.one * 24, CFrame.new(c), C3(0, 0, 0), BALL, 0, Enum.Material.SmoothPlastic)
	shell.Size = Vector3.one * 34
	shell.Transparency = 0.35
	sound(bossRoot, 9112775375, 1.2, 0.5)
	local tick, dmgTick = 0, 0
	local t1 = os.clock()
	while os.clock() - t1 < 4.5 and bossHum.Health > 0 do
		task.wait(0.1)
		for _, e in livePlayers() do
			local rel = c - e.root.Position
			local d = rel.Magnitude
			if d < 260 and d > 1 then
				push(e, rel.Unit * (7 + 22 * (1 - d / 260)))
			end
			if d < 30 and os.clock() - dmgTick > 0.5 then damagePlayer(e, 7) end
		end
		if os.clock() - dmgTick > 0.5 then dmgTick = os.clock() end
		core.Size = Vector3.one * (24 + math.sin(os.clock() * 8) * 2)
	end
	broadcast("abilityFire", "collapse")
	blast(c, VIOLET, 50, true)
	damageArea(c, 48, 40, function(e) push(e, (e.root.Position - c).Unit * 90) end)
	core:Destroy()
	fade(shell, 0.5)
end

function ABIL.meteors()
	announce("METEOR RAIN")
	local list = livePlayers()
	local strikes = {}
	for _, e in list do
		for _ = 1, 3 do
			strikes[#strikes + 1] = e.root.Position + Vector3.new(rng:NextNumber(-45, 45), rng:NextNumber(-25, 25), rng:NextNumber(-45, 45))
		end
	end
	for i, pos in strikes do
		if i > 12 then break end
		task.spawn(function()
			local mark = fxPart(Vector3.one * 30, CFrame.new(pos), CRIM, BALL, 0.7)
			TweenService:Create(mark, TweenInfo.new(1.25), { Transparency = 0.2, Size = Vector3.one * 34 }):Play()
			local rock = fxPart(Vector3.one * 9, CFrame.new(pos + Vector3.new(30, 160, 20)), ORANGE, BALL, 0)
			TweenService:Create(rock, TweenInfo.new(1.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = pos }):Play()
			task.wait(1.25)
			rock:Destroy()
			mark:Destroy()
			blast(pos, ORANGE, 20)
			damageArea(pos, 17, 26, function(e) push(e, (e.root.Position - pos).Unit * 50) end)
		end)
		task.wait(0.18)
	end
end

function ABIL.summon()
	announce("THE SOVEREIGN CALLS")
	sound(bossRoot, 9112775375, 1, 0.7)
	blast(bossRoot.Position, PHASE_COLOR[phase], 30)
	local kinds = { "Stinger", "Stinger", "Stinger", "Gunship" }
	if phase >= 3 then kinds[#kinds + 1] = "Stinger" kinds[#kinds + 1] = "Brute" end
	for _, kind in kinds do
		if aliveMinions() < MAX_MINIONS + 6 then
			local off = Vector3.new(rng:NextNumber(-60, 60), rng:NextNumber(-20, 40), rng:NextNumber(-60, 60))
			launch(kind, bossRoot.Position + off)
		end
		task.wait(0.25)
	end
end

local POOL = { { "barrage", "summon" }, { "barrage", "lance", "nova", "summon", "barrage" }, { "barrage", "lance", "nova", "singularity", "meteors", "summon" } }
local COOLDOWN = { 5.0, 3.8, 2.8 }

local function phaseChange(n)
	phase = n
	boss:SetAttribute("Transforming", true)
	bossHum:SetAttribute("Invulnerable", true)
	boss:SetAttribute("Phase", n)
	broadcast("phase", n)
	sound(bossRoot, 9112775375, 1.5, 0.55)
	local c = bossRoot.Position
	for i = 1, 3 do
		local r = fxPart(Vector3.new(4, 20, 20), CFrame.new(c) * CFrame.Angles(0, 0, math.pi / 2), PHASE_COLOR[n], CYL, 0.2)
		TweenService:Create(r, TweenInfo.new(1.4 + i * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(4, 700, 700), Transparency = 1 }):Play()
		Debris:AddItem(r, 3)
		task.wait(0.35)
	end
	blast(c, PHASE_COLOR[n], 70, true)
	damageArea(c, 110, 20, function(e) push(e, (e.root.Position - c).Unit * 110) end)
	task.wait(3.2)
	bossHum:SetAttribute("Invulnerable", nil)
	boss:SetAttribute("Transforming", nil)
end

local function bossAI()
	local lastAbility, lastName, strafe = os.clock() + 4, nil, 0
	local lastAura = os.clock()
	local lastPublish = 0
	while bossHum.Health > 0 and bossRoot.Parent do
		task.wait(0.1)
		if os.clock() - lastPublish > 0.25 then
			lastPublish = os.clock()
			workspace:SetAttribute("MS_BossHP", bossHum.Health / bossHum.MaxHealth)
			workspace:SetAttribute("MS_TargetPos", bossRoot.Position)
		end
		local frac = bossHum.Health / bossHum.MaxHealth
		local want = (frac > 0.66) and 1 or ((frac > 0.33) and 2 or 3)
		if want > phase and not boss:GetAttribute("Transforming") then
			task.spawn(phaseChange, want)
			lastAbility = os.clock() + 5
		end
		local transforming = boss:GetAttribute("Transforming")
		-- movement: hover at a distance from the nearest player, strafing
		local t = nearestTarget(bossRoot.Position, 3500)
		local stand = ({ 150, 125, 100 })[phase]
		local speed = ({ 40, 52, 66 })[phase]
		if t and not transforming then
			strafe += 0.05
			local rel = bossRoot.Position - t.root.Position
			local dirAway = (rel.Magnitude > 1) and rel.Unit or Vector3.zAxis
			local side = dirAway:Cross(Vector3.yAxis)
			local goal = t.root.Position + dirAway * stand + side * math.sin(strafe) * 70 + Vector3.new(0, 30 + math.cos(strafe * 0.8) * 30, 0)
			aimAt(bossRoot, goal, t.root.Position, speed)
		elseif not transforming then
			aimAt(bossRoot, shipRoot.Position + Vector3.new(0, -240, 0), nil, 30)
		else
			aimAt(bossRoot, bossRoot.Position, nil, 2)
		end
		-- abilities
		if not transforming and os.clock() >= lastAbility then
			lastAbility = os.clock() + COOLDOWN[phase] + rng:NextNumber(0, 1.2)
			local pool = POOL[phase]
			local name
			repeat name = pool[rng:NextInteger(1, #pool)] until name ~= lastName or #pool == 1
			lastName = name
			task.spawn(function()
				local ok, err = pcall(ABIL[name])
				if not ok then warn("[MothershipEvent] ability " .. name .. ": " .. tostring(err)) end
			end)
		end
		-- phase 3: a crushing aura around the Sovereign
		if phase >= 3 and not transforming and os.clock() - lastAura > 3 then
			lastAura = os.clock()
			local c = bossRoot.Position
			local r = fxPart(Vector3.new(2, 20, 20), CFrame.new(c) * CFrame.Angles(0, 0, math.pi / 2), WHITE, CYL, 0.4)
			TweenService:Create(r, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(2, 150, 150), Transparency = 1 }):Play()
			Debris:AddItem(r, 0.8)
			damageArea(c, 75, 9, function(e) push(e, (e.root.Position - c).Unit * 55) end)
		end
	end
end

local function spawnBoss()
	setState("boss")
	phase = 1
	boss = assets.VoidSovereign:Clone()
	bossRoot = boss.PrimaryPart
	bossHum = boss:FindFirstChildOfClass("Humanoid")
	local n = #Players:GetPlayers()
	bossHum.MaxHealth = (workspace:GetAttribute("MS_DevBossHP") or (BOSS_HP_BASE + BOSS_HP_PER_PLAYER * (n - 1)))
	bossHum.Health = bossHum.MaxHealth
	bossHum.PlatformStand = true
	boss:SetAttribute("Phase", 1)
	boss.Name = "VoidSovereign"
	local bay = shipRoot:FindFirstChild("BossSpawn")
	local start = bay and bay.WorldPosition or (SHIP_POS - Vector3.new(0, 100, 0))
	boss:ScaleTo(0.04)
	bossRoot.Anchored = true
	boss:PivotTo(CFrame.lookAt(start, FOCUS))
	boss.Parent = forces
	broadcast("bossIntro", "THE VOID SOVEREIGN", start)
	-- the hangar doors open
	for _, d in shipRoot.Parent:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 and d.Part1:GetAttribute("Door") then
			TweenService:Create(d, TweenInfo.new(2.5, Enum.EasingStyle.Quad), { C0 = d.C0 * CFrame.new(d.Part1:GetAttribute("Door") * 46, 0, 0) }):Play()
		end
	end
	task.wait(2.5)
	sound(bossRoot, 9112775375, 1.6, 0.5)
	-- it materialises and descends from the belly of the ship
	local t0, DUR = os.clock(), 6
	local endPos = start + Vector3.new(0, -230, 60)
	local facing = CFrame.lookAt(endPos, FOCUS).Rotation
	local lastBlast = 0
	while os.clock() - t0 < DUR do
		local a = (os.clock() - t0) / DUR
		local ea = 1 - (1 - a) ^ 3
		boss:ScaleTo(0.04 + 0.96 * ea)
		boss:PivotTo(CFrame.new(start:Lerp(endPos, ea)) * facing)
		if os.clock() - lastBlast > 0.5 then
			lastBlast = os.clock()
			sparks(bossRoot.Position, PHASE_COLOR[1], 40, 90)
		end
		RunService.Heartbeat:Wait()
	end
	blast(bossRoot.Position, VIOLET, 90, true)
	-- physics on
	bossRoot.Anchored = false
	pcall(function() bossRoot:SetNetworkOwner(nil) end)
	local att = Instance.new("Attachment")
	att.Name = "MoveAtt"
	att.Parent = bossRoot
	local ap = Instance.new("AlignPosition")
	ap.Name = "MoveAP"
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.MaxForce = math.huge
	ap.MaxVelocity = 40
	ap.Responsiveness = 3
	ap.Position = endPos
	ap.Parent = bossRoot
	local ao = Instance.new("AlignOrientation")
	ao.Name = "MoveAO"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 5
	ao.CFrame = bossRoot.CFrame
	ao.Parent = bossRoot
	-- close the doors again
	for _, d in shipRoot.Parent:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 and d.Part1:GetAttribute("Door") then
			TweenService:Create(d, TweenInfo.new(3, Enum.EasingStyle.Quad), { C0 = d.C0 * CFrame.new(-d.Part1:GetAttribute("Door") * 46, 0, 0) }):Play()
		end
	end
	return true
end

----------------------------------------------------------------------
-- the loot chests
----------------------------------------------------------------------
local function toast(player, text, color)
	notifyRemote:FireClient(player, "toast", text, color or GOLD)
end

local function makeChest(owner, pos)
	local m = Instance.new("Model")
	m.Name = "BossChest_" .. owner.UserId
	m:SetAttribute("Owner", owner.UserId)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(6, 6, 6)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CFrame = CFrame.new(pos)
	root.Parent = m
	m.PrimaryPart = root
	local function add(name, size, cf, color, mat, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = mat or Enum.Material.Metal
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		if shape then p.Shape = shape end
		p.CFrame = root.CFrame * cf
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
		p.Parent = m
		return p
	end
	local DARKM, V3, CFn = C3(28, 22, 46), Vector3.new, CFrame.new
	add("Base", V3(7, 4.4, 5), CFn(0, -1, 0), DARKM)
	add("BaseTrim", V3(7.5, 0.8, 5.5), CFn(0, -3, 0), GOLD)
	add("Lid", V3(7, 2.4, 5), CFn(0, 2, 0), GOLD)
	add("LidTop", V3(6, 0.6, 4), CFn(0, 3.4, 0), C3(255, 226, 150))
	add("Seam", V3(7.2, 0.4, 5.2), CFn(0, 0.85, 0), VIOLET, Enum.Material.Neon)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do add("Post", V3(0.9, 5.6, 0.9), CFn(sx * 3.4, -0.2, sz * 2.4), GOLD) end
	end
	add("Lock", V3(1.4, 1.4, 1.4), CFn(0, 0.85, -2.7), WHITE, Enum.Material.Neon, Enum.PartType.Ball)
	for i = -1, 1 do add("Rune", V3(0.5, 1.4, 0.3), CFn(i * 1.8, -1.2, -2.55), VIOLET, Enum.Material.Neon) end
	local halo = add("Halo", V3(0.4, 15, 15), CFn(0, 6.5, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, Enum.Material.Neon, Enum.PartType.Cylinder)
	halo.Transparency = 0.3
	local mo = Instance.new("Motor6D")
	mo.Name = "Joint_Halo"
	mo.Part0 = root
	mo.Part1 = halo
	mo.C0 = root.CFrame:ToObjectSpace(halo.CFrame)
	mo:SetAttribute("SpinAxis", Vector3.new(1, 0, 0))
	mo:SetAttribute("SpinSpeed", 1.5)
	mo.Parent = halo
	for _, w in halo:GetChildren() do if w:IsA("WeldConstraint") then w:Destroy() end end
	-- a tall beacon so the chest can be found from far away
	add("Beacon", V3(700, 2.6, 2.6), CFn(0, 350, 0) * CFrame.Angles(0, 0, math.pi / 2), VIOLET, Enum.Material.Neon, Enum.PartType.Cylinder)
	m.Beacon.Transparency = 0.55
	local light = Instance.new("PointLight")
	light.Color = VIOLET
	light.Range = 40
	light.Brightness = 3
	light.Parent = root
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 50)
	gui.StudsOffset = Vector3.new(0, 11, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 1500
	gui.Parent = root
	local lb = Instance.new("TextLabel")
	lb.Size = UDim2.fromScale(1, 1)
	lb.BackgroundTransparency = 1
	lb.Font = Enum.Font.GothamBlack
	lb.TextScaled = true
	lb.TextColor3 = GOLD
	lb.TextStrokeTransparency = 0.3
	lb.Text = owner.DisplayName:upper() .. "'S BOSS CHEST"
	lb.Parent = gui
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "OPEN"
	prompt.ObjectText = "Boss Chest"
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m.Parent = chestFolder
	prompt.Triggered:Connect(function(player)
		if m:GetAttribute("Opening") then return end
		if player.UserId ~= owner.UserId then
			toast(player, "This chest belongs to " .. owner.DisplayName .. ".", CRIM)
			return
		end
		m:SetAttribute("Opening", true)
		local res = grant:Invoke(player, "chestOpen", true)
		if typeof(res) == "table" then
			notifyRemote:FireClient(player, "chest", res, root.CFrame)
			task.delay(0.4, function() m:Destroy() end)
		else
			m:SetAttribute("Opening", nil)
		end
	end)
	-- an unopened chest is kept for later (opened from the HUD button)
	task.delay(CHEST_LIFETIME, function()
		if m.Parent and not m:GetAttribute("Opening") then
			m:Destroy()
			if owner.Parent then
				grant:Invoke(owner, "chestAdd", 1)
				toast(owner, "Your boss chest was saved. Open it from the CHEST button.", GOLD)
			end
		end
	end)
	return m, root
end

----------------------------------------------------------------------
-- victory / retreat / the whole event
----------------------------------------------------------------------
local function contributors()
	local list, total = {}, 0
	for k, v in bossHum:GetAttributes() do
		local id = tonumber(tostring(k):match("^Dmg_(%d+)$"))
		if id and typeof(v) == "number" then
			list[#list + 1] = { id = id, dmg = v }
			total += v
		end
	end
	return list, total
end

local function clearMinions(explode)
	for _, m in forces:GetChildren() do
		local h = m:FindFirstChildOfClass("Humanoid")
		if m:GetAttribute("Minion") then
			if explode and h then h.Health = 0 else m:Destroy() end
		end
	end
end

local function shipLeave(destroy)
	if not shipRoot or not shipRoot.Parent then return end
	local sh = ship
	if destroy then
		-- the mothership breaks up in a chain of explosions, then drops away
		for i = 1, 22 do
			if not shipRoot.Parent then break end
			local lp = Vector3.new(rng:NextNumber(-90, 90), rng:NextNumber(-40, 70), rng:NextNumber(-420, 440))
			local pos = (shipRoot.CFrame * CFrame.new(lp)).Position
			blast(pos, (i % 2 == 0) and ORANGE or CRIM, rng:NextNumber(40, 80), true)
			sound(shipRoot, 9065667699, 1.2, rng:NextNumber(0.5, 0.9))
			task.wait(0.28)
		end
		blast(shipRoot.Position, WHITE, 260, true)
	end
	if shipRoot.Parent then
		TweenService:Create(shipRoot, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = shipRoot.CFrame * CFrame.new(0, destroy and -900 or 700, destroy and 0 or 9000) }):Play()
		Debris:AddItem(sh, 5.5)
	end
end

local function bossDeath()
	bossRoot.Anchored = true
	setState("victory")
	broadcast("bossDeath", bossRoot.Position)
	local c = bossRoot.Position
	for i = 1, 16 do
		blast(c + Vector3.new(rng:NextNumber(-45, 45), rng:NextNumber(-60, 60), rng:NextNumber(-35, 35)), PHASE_COLOR[phase], rng:NextNumber(12, 26))
		sound(bossRoot, 9065667699, 0.8, rng:NextNumber(0.6, 1.3))
		task.wait(0.22)
	end
	blast(c, WHITE, 150, true)
	for i = 1, 3 do
		local r = fxPart(Vector3.new(4, 20, 20), CFrame.new(c) * CFrame.Angles(0, 0, math.pi / 2), (i == 2) and GOLD or PHASE_COLOR[phase], CYL, 0.15)
		TweenService:Create(r, TweenInfo.new(1.6 + i * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(4, 1600, 1600), Transparency = 1 }):Play()
		Debris:AddItem(r, 3)
	end
	return c
end

local function victory()
	bossDead = true
	local list, total = contributors()
	local c = bossDeath()
	boss:Destroy()
	clearMinions(true)
	broadcast("victory")
	-- a personal chest for everyone who really fought
	local n = 0
	for _, e in list do
		local pl = Players:GetPlayerByUserId(e.id)
		if pl and (e.dmg >= total * 0.02 or e.dmg >= 300) then
			n += 1
			local a = n * 2.4
			local pos = c + Vector3.new(math.cos(a) * 34, 0, math.sin(a) * 34)
			local m, root = makeChest(pl, pos)
			grant:Invoke(pl, "money", 2500)
			grant:Invoke(pl, "iron", 200)
			toast(pl, "VOID SOVEREIGN DEFEATED!  +$2,500  +200 iron  -  your BOSS CHEST is waiting!", GOLD)
			notifyRemote:FireClient(pl, "guide", root, "YOUR BOSS CHEST")
		end
	end
	task.spawn(shipLeave, true)
	task.wait(8)
end

local function retreat()
	bossDead = true
	broadcast("retreat")
	if boss and boss.Parent then
		blast(bossRoot.Position, VIOLET, 60, true)
		boss:Destroy()
	end
	clearMinions(false)
	task.spawn(shipLeave, false)
	task.wait(6)
end

local function runEvent(quick)
	running = true
	bossDead = false
	-- 1) the warning
	local arrival = now() + (quick and 12 or WARN_TIME)
	workspace:SetAttribute("MS_Next", arrival)
	setState("warning")
	broadcast("warn", arrival)
	while now() < arrival do task.wait(0.5) end
	-- 2) it arrives
	setState("arriving")
	broadcast("arrive")
	warpIn()
	for _ = 1, 18 do
		workspace:SetAttribute("MS_TargetPos", shipRoot.Position)
		task.wait(0.5)
	end
	setState("active")
	local endsAt = now() + TIMEOUT
	workspace:SetAttribute("MS_EndsAt", endsAt)
	task.spawn(turretLoop)
	task.spawn(waveLoop)
	-- 3) the boss
	local t0 = os.clock()
	while os.clock() - t0 < (workspace:GetAttribute("MS_DevBossDelay") or BOSS_DELAY) do
		task.wait(1)
		workspace:SetAttribute("MS_TargetPos", shipRoot.Position)
	end
	local ok, err = pcall(spawnBoss)
	if not ok then
		warn("[MothershipEvent] boss failed: " .. tostring(err))
		retreat()
	else
		local died = false
		bossHum.Died:Once(function() died = true end)
		task.spawn(bossAI)
		while not died and now() < endsAt do task.wait(0.5) end
		if died then victory() else retreat() end
	end
	-- 4) clean up
	running = false
	clearMinions(false)
	setState("idle")
	workspace:SetAttribute("MS_BossHP", nil)
	workspace:SetAttribute("MS_TargetPos", nil)
	workspace:SetAttribute("MS_EndsAt", nil)
	if shipRoot and shipRoot.Parent then ship:Destroy() end
end

----------------------------------------------------------------------
-- the schedule
----------------------------------------------------------------------
local summon = false
workspace:GetAttributeChangedSignal("MothershipSummon"):Connect(function()
	if workspace:GetAttribute("MothershipSummon") then summon = true end
end)
local nextArrival = now() + FIRST_DELAY
workspace:SetAttribute("MS_Next", nextArrival)
task.spawn(function()
	while true do
		task.wait(1)
		if not running then
			if summon or now() >= nextArrival - WARN_TIME then
				local quick = summon
				summon = false
				workspace:SetAttribute("MothershipSummon", nil)
				local ok, err = pcall(runEvent, quick)
				if not ok then
					warn("[MothershipEvent] " .. tostring(err))
					running = false
					setState("idle")
				end
				nextArrival = now() + INTERVAL
				workspace:SetAttribute("MS_Next", nextArrival)
			end
		end
	end
end)
