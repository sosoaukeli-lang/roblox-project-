-- AlienHive v3 (Script) - FIVE hives (workspace.AlienHives.AlienHive1 ... AlienHive5)
--   * every hive sends out its own wave of 3 XENO REAPERS (sometimes 4) every 30 minutes
--   * the hives are staggered (one starts every 6 minutes) so something is always coming; the first wave of
--     hive 1 comes 90 seconds after the server starts, so you see it right away
--   * the hive roars, its eye flares, everybody gets an ALIEN INVASION banner, each Reaper bursts out of the gate
--   * Reapers hover around their hive, roar when they spot you, dash at you and claw you
--   * every Reaper you kill pays $30; quick kills in a row give KILL STREAK banners; clearing a wave gives WAVE CLEARED
-- Testing: set the attribute SpawnNow = true on any hive model (e.g. workspace.AlienHives.AlienHive3) to send its wave now.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WAVE_INTERVAL = 30 * 60 -- seconds between the waves of ONE hive
local FIRST_WAVE = 90 -- seconds after the server starts (hive 1)
local STAGGER = 6 * 60 -- every next hive starts this much later
local REWARD = 30 -- money per kill
local ALLOW_ATTACK = true -- Reapers claw players (false = harmless Reapers)
local ALIEN_DAMAGE = 8
local ATTACK_COOLDOWN = 1.8
local ATTACK_RANGE = 10
local DASH_RANGE = 28
local AGGRO_RANGE = 140
local LEASH = 900 -- how far from its hive a Reaper will follow you
local MOVE_SPEED = 34
local DASH_SPEED = 90
local MAX_ALIVE = 24
local TITAN_SCALE = 2.4 -- the Xeno Titan boss (summoned by the TITAN SLAYER mission)
local TITAN_HEALTH = 1800
local TITAN_DAMAGE = 22
local STREAK_WINDOW = 6 -- seconds between kills to keep a streak

local container = workspace:WaitForChild("AlienHives")
local template = ServerStorage:WaitForChild("AlienTemplates"):WaitForChild("Xeno")
local hiveEvent = ReplicatedStorage:WaitForChild("HiveEvent")
local fxRemote = ReplicatedStorage:WaitForChild("WeaponFX")
local progressEvents = ServerStorage:WaitForChild("ProgressEvents")
local diedEvent = progressEvents:WaitForChild("AlienDied")
local clearedEvent = progressEvents:WaitForChild("WaveCleared")

local aliens = Instance.new("Folder")
aliens.Name = "XenoAliens"
aliens.Parent = workspace
local rng = Random.new()
local streaks = {} -- [userId] = { t = last kill time, n = streak }

local function sound(parent, id, volume, speed)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 40
	s.RollOffMaxDistance = 500
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 8)
end

local function fxPart(pos)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	return p
end

local function ringAt(pos, color, diameter, duration)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Size = Vector3.new(0.4, 3, 3)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, diameter, diameter), Transparency = 1 }):Play()
	Debris:AddItem(ring, duration + 0.1)
end

local function sparksAt(pos, c1, c2, count, speed)
	local fx = fxPart(pos)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(c1, c2)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.6, 1.4)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Rate = 0
	e.Parent = fx
	e:Emit(count)
	local l = Instance.new("PointLight")
	l.Color = c2
	l.Range = 40
	l.Brightness = 5
	l.Shadows = false
	l.Parent = fx
	TweenService:Create(l, TweenInfo.new(0.6), { Brightness = 0 }):Play()
	Debris:AddItem(fx, 2)
	return fx
end

local function shakeNear(pos, radius, strength, seconds)
	for _, p in Players:GetPlayers() do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			local d = (r.Position - pos).Magnitude
			if d < radius then
				fxRemote:FireClient(p, "shake", strength * (1 - d / radius) + 0.05, seconds)
			end
		end
	end
end

local function countAlive(hiveIndex)
	local n = 0
	for _, a in aliens:GetChildren() do
		local h = a:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 and (not hiveIndex or a:GetAttribute("Hive") == hiveIndex) then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------
-- one hive
----------------------------------------------------------------------
local function runHive(hive, index)
	local gate = hive:WaitForChild("HiveGate")
	local body = hive:WaitForChild("HiveBody")
	local eye = hive:WaitForChild("HiveEye")
	local beacon = hive:FindFirstChild("HiveBeacon")
	local timerLabel = hive:WaitForChild("HiveSignAnchor"):WaitForChild("HiveSign"):WaitForChild("Timer")

	local hiveCF = hive:GetAttribute("BaseCF") or (body.CFrame * CFrame.new(0, -14, 0)) -- the hive's own frame (-Z = the gate side)
	local home = hiveCF * (hive:GetAttribute("HomeLocal") or Vector3.new(0, 28, 0))
	local gateInside = hiveCF * (hive:GetAttribute("GateInside") or Vector3.new(0, 13, -47))
	local gateFront = hiveCF * (hive:GetAttribute("GateFront") or Vector3.new(0, 16, -70))
	local eyeColor = hive:GetAttribute("Accent") or Color3.fromRGB(255, 70, 60)
	local GATE_LIGHT = 1.2
	workspace:SetAttribute("HivePos" .. index, hiveCF.Position) -- the compass on every player's screen points to the nearest one
	workspace:SetAttribute("HiveColor" .. index, hive:GetAttribute("Accent") or Color3.fromRGB(255, 70, 80))

	local waveId, waveKills = 0, 0
	local waveKillers = {}

	local function onDeath(alien, root, hum)
		local pos = root.Position
		local killerId = hum:GetAttribute("LastAttacker")
		if killerId and os.clock() - (hum:GetAttribute("LastAttackTime") or 0) < 120 then
			local killer = Players:GetPlayerByUserId(killerId)
			local stats = killer and killer:FindFirstChild("leaderstats")
			local money = stats and stats:FindFirstChild("Money")
			if money then
				money.Value += REWARD
				local s = streaks[killerId]
				if s and os.clock() - s.t <= STREAK_WINDOW then
					s.n += 1
				else
					s = { n = 1 }
					streaks[killerId] = s
				end
				s.t = os.clock()
				hiveEvent:FireClient(killer, "kill", s.n, REWARD)
			end
		end
		local credited = (killerId and os.clock() - (hum:GetAttribute("LastAttackTime") or 0) < 120) and killerId or nil
		if alien:GetAttribute("Wave") == waveId then
			waveKills += 1
			if credited then waveKillers[credited] = true end
		end
		diedEvent:Fire(pos, credited, index, hum:GetAttribute("LastWeapon"), alien:GetAttribute("Titan") == true)

		local fx = sparksAt(pos, Color3.fromRGB(150, 255, 90), Color3.fromRGB(255, 40, 70), 100, 60)
		ringAt(pos, Color3.fromRGB(255, 60, 80), 46, 0.6)
		ringAt(pos, Color3.fromRGB(150, 255, 90), 28, 0.45)
		sound(fx, 6290067239, 0.8, 1.2)
		sound(fx, 9065667699, 0.5, 1.4)
		shakeNear(pos, 140, 0.25, 0.5)
		TweenService:Create(eye, TweenInfo.new(0.12), { Color = Color3.fromRGB(255, 255, 255) }):Play()
		task.delay(0.15, function()
			TweenService:Create(eye, TweenInfo.new(0.5), { Color = eyeColor }):Play()
		end)

		local tag = fxPart(pos + Vector3.new(0, 4, 0))
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(7, 2.6)
		bb.AlwaysOnTop = false
		bb.LightInfluence = 0
		bb.MaxDistance = 400
		bb.Adornee = tag
		bb.Parent = tag
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBlack
		tl.TextScaled = true
		tl.Text = "+$" .. REWARD
		tl.TextColor3 = Color3.fromRGB(255, 215, 80)
		tl.TextStrokeTransparency = 0.2
		tl.Parent = bb
		TweenService:Create(tag, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = tag.Position + Vector3.new(0, 9, 0) }):Play()
		TweenService:Create(tl, TweenInfo.new(1.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(tag, 1.8)

		for _, d in alien:GetDescendants() do
			if d:IsA("WeldConstraint") then d:Destroy() end
		end
		for _, d in alien:GetDescendants() do
			if d:IsA("BasePart") then
				d.Massless = false
				d.Anchored = false
				d.CanCollide = false
				d.AssemblyLinearVelocity = (d.Position - pos).Unit * rng:NextNumber(14, 40) + Vector3.new(0, rng:NextNumber(5, 20), 0)
				d.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
				if d.Name ~= "HumanoidRootPart" then
					TweenService:Create(d, TweenInfo.new(1.3), { Transparency = 1 }):Play()
				end
			elseif d:IsA("ParticleEmitter") or d:IsA("PointLight") or d:IsA("BillboardGui") or d:IsA("Trail") then
				d.Enabled = false
			end
		end
		Debris:AddItem(alien, 1.6)
	end

	local function spawnAlien(titan)
		local alien = template:Clone()
		local root = alien.PrimaryPart
		local hum = alien:FindFirstChildOfClass("Humanoid")
		alien:SetAttribute("IsXeno", true)
		alien:SetAttribute("Wave", waveId)
		alien:SetAttribute("Hive", index)
		if titan then
			alien:SetAttribute("Titan", true)
			alien:ScaleTo(TITAN_SCALE)
			hum.MaxHealth = TITAN_HEALTH
			hum.Health = TITAN_HEALTH
			local hp = root:FindFirstChild("HP")
			if hp then
				hp.Size = UDim2.fromScale(16, 3.4)
				hp.StudsOffsetWorldSpace = Vector3.new(0, 24, 0)
				hp.MaxDistance = 1200
				for _, d in hp:GetDescendants() do
					if d:IsA("TextLabel") then
						d.Text = "XENO TITAN"
						d.TextColor3 = Color3.fromRGB(255, 200, 90)
					end
				end
			end
		end
		local dmg = titan and TITAN_DAMAGE or ALIEN_DAMAGE
		local atkRange = titan and 24 or ATTACK_RANGE
		local dashRange = titan and 70 or DASH_RANGE
		local speedScale = titan and 0.7 or 1
		alien:PivotTo(CFrame.lookAt(gateInside, gateFront))
		alien.Parent = aliens
		root:SetNetworkOwner(nil)

		sparksAt(gateInside + (gateFront - gateInside) * 0.3, Color3.fromRGB(150, 255, 90), Color3.fromRGB(110, 255, 100), 60, 50)
		ringAt(gateInside, Color3.fromRGB(110, 255, 100), 40, 0.7)
		sound(root, 9112775375, 0.9, 0.8 + rng:NextNumber(0, 0.3))
		shakeNear(gateInside, 160, 0.2, 0.4)

		local att = Instance.new("Attachment")
		att.Parent = root
		local ap = Instance.new("AlignPosition")
		ap.Mode = Enum.PositionAlignmentMode.OneAttachment
		ap.Attachment0 = att
		ap.Position = gateInside
		ap.MaxForce = 1e8
		ap.MaxVelocity = MOVE_SPEED
		ap.Responsiveness = 10
		ap.ApplyAtCenterOfMass = true
		ap.Parent = root
		local ao = Instance.new("AlignOrientation")
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = att
		ao.CFrame = root.CFrame
		ao.MaxTorque = 1e8
		ao.Responsiveness = 10
		ao.MaxAngularVelocity = 6
		ao.Parent = root

		local fill = root:FindFirstChild("HP") and root.HP:FindFirstChild("Fill", true)
		hum.HealthChanged:Connect(function(h)
			if fill then
				local f = math.clamp(h / hum.MaxHealth, 0, 1)
				fill.Size = UDim2.fromScale(f, 1)
				fill.BackgroundColor3 = Color3.fromRGB(255, 40, 70):Lerp(Color3.fromRGB(255, 200, 60), 1 - f)
			end
		end)
		local dead = false
		hum.Died:Connect(function()
			if dead then return end
			dead = true
			onDeath(alien, root, hum)
		end)

		task.spawn(function()
			local emergeUntil = os.clock() + 3
			local lastAttack, dashUntil = 0, 0
			local orbit = rng:NextNumber(0, math.pi * 2)
			local roared = false
			local eyeGlow = alien:FindFirstChild("EyeL") and alien.EyeL:FindFirstChild("EyeGlow")
			while alien.Parent and hum.Health > 0 and root.Parent do
				task.wait(0.1)
				local pos = root.Position
				local target, tdist = nil, math.huge
				for _, p in Players:GetPlayers() do
					local ch = p.Character
					local r = ch and ch:FindFirstChild("HumanoidRootPart")
					local h = ch and ch:FindFirstChildOfClass("Humanoid")
					if r and h and h.Health > 0 then
						local d = (r.Position - pos).Magnitude
						if d < tdist then
							target, tdist = r, d
						end
					end
				end
				local goal, look
				if os.clock() < emergeUntil then
					goal, look = gateFront, gateFront + (gateFront - gateInside)
				elseif target and tdist < AGGRO_RANGE and (target.Position - home).Magnitude < LEASH then
					if not roared then
						roared = true
						sound(root, 9112775375, 1, 0.6 + rng:NextNumber(0, 0.2))
					end
					local dir = target.Position - pos
					local dist = dir.Magnitude
					goal = target.Position - dir.Unit * 5
					look = target.Position
					if ALLOW_ATTACK and dist < dashRange and os.clock() - lastAttack >= ATTACK_COOLDOWN and (alien:GetAttribute("StunUntil") or 0) < os.clock() then
						dashUntil = os.clock() + 0.35
					end
					if ALLOW_ATTACK and dist < atkRange and os.clock() - lastAttack >= ATTACK_COOLDOWN and (alien:GetAttribute("StunUntil") or 0) < os.clock() then
						lastAttack = os.clock()
						local th = target.Parent:FindFirstChildOfClass("Humanoid")
						if th and th.Health > 0 then
							th:TakeDamage(dmg)
							sparksAt(target.Position, Color3.fromRGB(255, 120, 120), Color3.fromRGB(255, 40, 70), 26, 24)
							ringAt(target.Position, Color3.fromRGB(255, 60, 80), 12, 0.3)
							sound(root, 9065667699, 0.35, 2)
						end
					end
				else
					orbit += 0.05
					goal = home + Vector3.new(math.cos(orbit) * 78, math.sin(orbit * 1.7) * 10, math.sin(orbit) * 78)
					look = goal
				end
				local slow = ((alien:GetAttribute("SlowUntil") or 0) > os.clock()) and (alien:GetAttribute("SlowFactor") or 0.5) or 1 -- the Void Contrail / Frost Needler / Graviton slow aliens
				local stunnedNow = (alien:GetAttribute("StunUntil") or 0) > os.clock() -- Ion Revolver / Chrono Fracture stun
				ap.MaxVelocity = stunnedNow and 0.5 or (((os.clock() < dashUntil) and DASH_SPEED or MOVE_SPEED) * slow * speedScale)
				ap.Responsiveness = (os.clock() < dashUntil) and 30 or 10
				ap.Position = goal
				if (look - pos).Magnitude > 1 then
					ao.CFrame = CFrame.lookAt(pos, Vector3.new(look.X, pos.Y + (look.Y - pos.Y) * 0.3, look.Z))
				end
				if eyeGlow then
					eyeGlow.Brightness = 0.7 + rng:NextNumber(0, 0.7)
				end
			end
		end)
		return alien
	end

	local waveRunning = false
	local function startWave()
		if waveRunning then return end
		waveRunning = true
		waveId += 1
		waveKills = 0
		waveKillers = {}
		local myWave = waveId
		local count = (rng:NextNumber() < 0.3) and 4 or 3
		hiveEvent:FireAllClients("wave", count, index)

		local gl = gate:FindFirstChildOfClass("PointLight")
		TweenService:Create(gate, TweenInfo.new(0.6), { Transparency = 0.02 }):Play()
		TweenService:Create(eye, TweenInfo.new(0.5), { Color = Color3.fromRGB(255, 255, 255) }):Play()
		if beacon then
			TweenService:Create(beacon, TweenInfo.new(0.6), { Transparency = 0.35 }):Play()
		end
		if gl then gl.Brightness = 5 end
		sound(gate, 9112775375, 1, 0.9)
		sound(gate, 9065667699, 0.8, 0.6)
		shakeNear(gateInside, 320, 0.45, 1.6)
		task.wait(2.2)
		TweenService:Create(eye, TweenInfo.new(1.2), { Color = eyeColor }):Play()
		for i = 1, count do
			if countAlive() < MAX_ALIVE then spawnAlien() end
			task.wait(1.6)
		end
		task.wait(1)
		TweenService:Create(gate, TweenInfo.new(1.5), { Transparency = 0.35 }):Play()
		if beacon then
			TweenService:Create(beacon, TweenInfo.new(2), { Transparency = 0.82 }):Play()
		end
		if gl then
			TweenService:Create(gl, TweenInfo.new(1.5), { Brightness = GATE_LIGHT }):Play()
		end
		waveRunning = false

		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 900 do
				task.wait(1)
				local mine = 0
				for _, a in aliens:GetChildren() do
					local h = a:FindFirstChildOfClass("Humanoid")
					if a:GetAttribute("Hive") == index and a:GetAttribute("Wave") == myWave and h and h.Health > 0 then
						mine += 1
					end
				end
				if mine == 0 then
					if waveKills > 0 then
						hiveEvent:FireAllClients("cleared", waveKills, index)
						local ids = {}
						for id in waveKillers do ids[#ids + 1] = id end
						clearedEvent:Fire(index, ids)
					end
					return
				end
			end
		end)
	end

	local function startTitan()
		if hive:GetAttribute("TitanAlive") then return end
		hive:SetAttribute("TitanAlive", true)
		hiveEvent:FireAllClients("titan", index)
		local gl = gate:FindFirstChildOfClass("PointLight")
		TweenService:Create(gate, TweenInfo.new(0.6), { Transparency = 0.02 }):Play()
		TweenService:Create(eye, TweenInfo.new(0.5), { Color = Color3.fromRGB(255, 255, 255) }):Play()
		if beacon then TweenService:Create(beacon, TweenInfo.new(0.6), { Transparency = 0.2 }):Play() end
		if gl then gl.Brightness = 6 end
		sound(gate, 9112775375, 1, 0.55)
		sound(gate, 9065667699, 1, 0.45)
		shakeNear(gateInside, 600, 0.7, 2.6)
		task.wait(3)
		local titan = spawnAlien(true)
		local hum = titan:FindFirstChildOfClass("Humanoid")
		hum.Died:Connect(function() hive:SetAttribute("TitanAlive", nil) end)
		titan.AncestryChanged:Connect(function(_, parent) if not parent then hive:SetAttribute("TitanAlive", nil) end end)
		task.wait(3)
		TweenService:Create(gate, TweenInfo.new(1.5), { Transparency = 0.35 }):Play()
		TweenService:Create(eye, TweenInfo.new(1.2), { Color = eyeColor }):Play()
		if beacon then TweenService:Create(beacon, TweenInfo.new(2), { Transparency = 0.82 }):Play() end
		if gl then TweenService:Create(gl, TweenInfo.new(1.5), { Brightness = GATE_LIGHT }):Play() end
	end

	local nextWave = os.clock() + FIRST_WAVE + (index - 1) * STAGGER
	while true do
		task.wait(1)
		if hive:GetAttribute("SpawnNow") then
			hive:SetAttribute("SpawnNow", false)
			task.spawn(startWave)
		end
		if hive:GetAttribute("SpawnTitan") then
			hive:SetAttribute("SpawnTitan", false)
			task.spawn(startTitan)
		end
		local left = math.max(0, math.ceil(nextWave - os.clock()))
		if left <= 0 then
			task.spawn(startWave)
			nextWave = os.clock() + WAVE_INTERVAL
			left = WAVE_INTERVAL
		end
		local alive = countAlive(index)
		workspace:SetAttribute("HiveNext" .. index, workspace:GetServerTimeNow() + left) -- read by the compass (HiveFX)
		workspace:SetAttribute("HiveAlive" .. index, alive)
		local clock = string.format("%02d:%02d", left // 60, left % 60)
		if alive > 0 then
			timerLabel.Text = string.format("\u{2620} %d ALIVE   NEXT %s", alive, clock)
			timerLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
		else
			timerLabel.Text = "NEXT INVASION  " .. clock
			timerLabel.TextColor3 = Color3.fromRGB(255, 220, 220)
		end
	end
end

for _, hive in container:GetChildren() do
	local index = hive:GetAttribute("Index")
	if index then
		task.spawn(runHive, hive, index)
	end
end
