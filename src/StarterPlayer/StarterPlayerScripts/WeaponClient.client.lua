-- WeaponClient v4: shooting, cinematic camera effects and a realistic sound engine.
--
-- SOUND ENGINE: every shot / impact is played on your own machine so it can be physically believable:
--   * several layers per sound (crack + zap + low thump), a little random pitch each time
--   * the sound arrives LATE when it is far away (speed of sound), quieter, and muffled (distant sounds lose their highs)
--   * an echo (reverb) that is longer for big weapons and explosions; extra bass on the heavy ones
--   * you hear your own shots instantly, others' shots come from the server with their position

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remote = ReplicatedStorage:WaitForChild("WeaponFire")
local fxRemote = ReplicatedStorage:WaitForChild("WeaponFX")
local rng = Random.new()

local BASE_FOV = 70
local SPEED_OF_SOUND = 1100 -- studs per second (a realistic delay without being annoying)
local FIRE_DELAY = { VoidCannon = 0.6 } -- the cannon charges before it fires
local PROFILE = {
	LaserPistol = { punch = 2.5 },
	PlasmaRifle = { punch = 1.5 },
	StarterBlaster = { punch = 1.0 },
	AetherRaygun = { punch = 2.4 },
	IonRevolver = { punch = 3.0 }, PhotonSMG = { punch = 0.8 }, PulseShotgun = { punch = 4.0 }, FrostNeedler = { punch = 1.0 },
	InfernoCannon = { punch = 2.5 }, StormCoil = { punch = 2.0 }, GravitonLauncher = { punch = 3.5 }, Railbreaker = { punch = 4.5 },
	VenomSpitter = { punch = 1.0 }, NovaBurstRifle = { punch = 1.6 },
	SolarJudgement = { punch = 5.0 }, TempestRepeater = { punch = 1.2 }, ReapersMaw = { punch = 2.6 }, StarfallLauncher = { punch = 4.0 },
	EclipseReaper = { punch = 4.5 }, ChronoFracture = { punch = 4.0 }, GenesisCannon = { punch = 1.4 },
	XenoFang = { punch = 1.8 },
	HivePiercer = { punch = 3.5 },
	VoidCannon = { punch = -14, flash = Color3.fromRGB(190, 90, 255), cinematic = true },
}
-- which sound each weapon plays when YOU fire it
local OWN_SOUNDS = {
	LaserPistol = { fire = "pistol_fire" },
	PlasmaRifle = { fire = "rifle_fire" },
	StarterBlaster = { fire = "pistol_fire" },
	AetherRaygun = { fire = "rifle_fire" },
	IonRevolver = { fire = "revolver_fire" }, PhotonSMG = { fire = "smg_fire" }, PulseShotgun = { fire = "shotgun_fire" }, FrostNeedler = { fire = "smg_fire" },
	InfernoCannon = { fire = "flame_fire" }, StormCoil = { fire = "lightning_fire" }, GravitonLauncher = { fire = "cannon_fire" }, Railbreaker = { fire = "rail_fire" },
	VenomSpitter = { fire = "smg_fire" }, NovaBurstRifle = { fire = "rifle_fire" },
	SolarJudgement = { fire = "holy_fire" }, TempestRepeater = { fire = "lightning_fire" }, ReapersMaw = { fire = "dark_fire" }, StarfallLauncher = { fire = "cannon_fire" },
	EclipseReaper = { fire = "dark_fire" }, ChronoFracture = { fire = "time_fire" }, GenesisCannon = { fire = "genesis_fire" },
	XenoFang = { fire = "pistol_fire" },
	HivePiercer = { fire = "rifle_fire" },
	VoidCannon = { charge = "cannon_charge", fire = "cannon_fire" },
}

----------------------------------------------------------------------
-- sound library: layers = { assetId, volume, pitch }
----------------------------------------------------------------------
local SFX = {
	pistol_fire = {
		layers = { { 6603571443, 0.9, 1.0 }, { 134876319507428, 0.3, 1.8 }, { 6290067239, 0.2, 2.8 } },
		reverb = 1.3, volume = 1,
	},
	rifle_fire = {
		layers = { { 134876319507428, 0.7, 1.35 }, { 6603571443, 0.3, 1.7 }, { 6290067239, 0.16, 3.0 } },
		reverb = 1.1, volume = 1,
	},
	cannon_charge = {
		layers = { { 9125973984, 1.0, 2.3 }, { 9116277954, 0.35, 0.8 } },
		reverb = 1.0, volume = 1,
	},
	cannon_fire = {
		layers = { { 9065667699, 1.5, 0.5 }, { 6290067239, 0.9, 1.7 }, { 9125973257, 0.45, 1.4 } },
		reverb = 2.6, bass = 6, volume = 1.1,
	},
	revolver_fire = { layers = { { 9065667699, 0.9, 1.5 }, { 6603571443, 0.8, 0.8 }, { 6290067239, 0.3, 2.0 } }, reverb = 1.6, bass = 3, volume = 1 },
	smg_fire = { layers = { { 134876319507428, 0.55, 1.9 }, { 6603571443, 0.22, 2.3 } }, reverb = 0.8, volume = 0.9 },
	shotgun_fire = { layers = { { 9065667699, 1.0, 1.15 }, { 134876319507428, 0.8, 0.9 }, { 6290067239, 0.4, 1.6 } }, reverb = 1.4, bass = 4, volume = 1.05 },
	flame_fire = { layers = { { 9125973257, 0.8, 0.7 }, { 9116277954, 0.5, 0.9 }, { 134876319507428, 0.5, 0.8 } }, reverb = 1.2, bass = 2, volume = 1 },
	lightning_fire = { layers = { { 9116277954, 1.0, 1.4 }, { 6603571443, 0.6, 2.0 }, { 9125973257, 0.4, 1.8 } }, reverb = 1.5, volume = 1 },
	rail_fire = { layers = { { 9065667699, 1.2, 1.6 }, { 6603571443, 0.8, 0.7 }, { 9125973984, 0.4, 2.5 } }, reverb = 2.0, bass = 3, volume = 1.1 },
	holy_fire = { layers = { { 9125973257, 1.2, 1.0 }, { 6603571443, 0.6, 0.8 }, { 9125974640, 0.5, 1.2 } }, reverb = 2.2, bass = 3, volume = 1.1 },
	dark_fire = { layers = { { 9065667699, 0.9, 1.3 }, { 9116277954, 0.5, 0.6 }, { 6290067239, 0.6, 1.0 } }, reverb = 2.4, bass = 4, volume = 1 },
	time_fire = { layers = { { 9125973433, 1.0, 0.9 }, { 9125974640, 0.8, 1.5 }, { 6603571443, 0.4, 0.6 } }, reverb = 3.0, volume = 1.1 },
	genesis_fire = { layers = { { 9125973257, 1.1, 1.2 }, { 9125974640, 1.0, 1.0 }, { 9116277954, 0.6, 1.6 }, { 6603571443, 0.5, 1.4 } }, reverb = 2.5, bass = 3, volume = 1.15 },
	impact_small = {
		layers = { { 6603571443, 0.3, 2.3 }, { 9116277954, 0.22, 2.0 } },
		reverb = 0.9, volume = 1,
	},
	explosion = {
		layers = { { 6290067239, 1.5, 1.0 }, { 129993092121020, 0.8, 0.75 }, { 9116277954, 0.35, 0.6 } },
		reverb = 3.2, bass = 8, volume = 1.2,
	},
}

-- preload everything so the first shot isn't late
task.spawn(function()
	local list, folder, seen = {}, Instance.new("Folder"), {}
	local extra = { 9125974640, 9125973433, 4772620521, 122710126415943, 9112839126, 9125446543, 9116328633 }
	local ids = {}
	for _, spec in SFX do
		for _, layer in spec.layers do
			table.insert(ids, layer[1])
		end
	end
	for _, id in extra do
		table.insert(ids, id)
	end
	for _, id in ids do
		if not seen[id] then
			seen[id] = true
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. id
			s.Parent = folder
			table.insert(list, s)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	folder:Destroy()
end)

local function playSfx(name, pos, mul)
	local spec = SFX[name]
	local cam = workspace.CurrentCamera
	if not spec or not cam or typeof(pos) ~= "Vector3" then
		return
	end
	local dist = (pos - cam.CFrame.Position).Magnitude
	local delay = math.clamp(dist / SPEED_OF_SOUND, 0, 1.8)
	-- far sounds lose their high frequencies
	local muffle = -math.clamp((dist - 50) / 7, 0, 30)
	task.delay(delay, function()
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.Position = pos
		holder.Parent = workspace
		local pitchJitter = rng:NextNumber(0.95, 1.05)
		for _, layer in spec.layers do
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. layer[1]
			s.Volume = layer[2] * spec.volume * (mul or 1)
			s.PlaybackSpeed = layer[3] * pitchJitter
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 20
			s.RollOffMaxDistance = 450
			local eq = Instance.new("EqualizerSoundEffect")
			eq.LowGain = spec.bass or 0
			eq.MidGain = 0
			eq.HighGain = muffle
			eq.Parent = s
			local rv = Instance.new("ReverbSoundEffect")
			rv.DecayTime = spec.reverb
			rv.Density = 0.9
			rv.Diffusion = 0.85
			rv.DryLevel = 0
			rv.WetLevel = -9 + math.clamp(dist / 120, 0, 5) -- more echo the further away it is
			rv.Parent = s
			s.Parent = holder
			s:Play()
		end
		Debris:AddItem(holder, 7)
	end)
end

fxRemote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "sfx" then
		playSfx(a, b)
	end
end)

----------------------------------------------------------------------
-- UI: hit marker, letterbox bars, screen flash
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "WeaponFX"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local marker = Instance.new("Frame")
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Position = UDim2.fromScale(0.5, 0.5)
marker.Size = UDim2.fromOffset(44, 44)
marker.BackgroundTransparency = 1
marker.Visible = false
marker.Parent = gui
for _, sx in { -1, 1 } do
	for _, sy in { -1, 1 } do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5 + sx * 0.3, 0.5 + sy * 0.3)
		line.Size = UDim2.fromOffset(3, 12)
		line.Rotation = 45 * sx * sy
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BorderSizePixel = 0
		line.Parent = marker
	end
end
local hitToken = 0
local function showHit()
	hitToken += 1
	local token = hitToken
	marker.Visible = true
	task.delay(0.13, function()
		if hitToken == token then
			marker.Visible = false
		end
	end)
end

local function makeBar(anchorY)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0, anchorY)
	f.Position = UDim2.fromScale(0, anchorY)
	f.Size = UDim2.fromScale(1, 0)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.ZIndex = 5
	f.Parent = gui
	return f
end
local topBar, bottomBar = makeBar(0), makeBar(1)
local function letterbox(show, time)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local size = UDim2.fromScale(1, show and 0.09 or 0)
	TweenService:Create(topBar, info, { Size = size }):Play()
	TweenService:Create(bottomBar, info, { Size = size }):Play()
end

local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.ZIndex = 4
flashFrame.Parent = gui
local function screenFlash(color, alpha, time)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = alpha
	TweenService:Create(flashFrame, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

----------------------------------------------------------------------
-- camera: shake + field-of-view punches
----------------------------------------------------------------------
local shakeId = 0
local function shake(intensity, duration)
	shakeId += 1
	local id = shakeId
	task.spawn(function()
		local t0 = os.clock()
		while shakeId == id and os.clock() - t0 < duration do
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not hum then
				break
			end
			local fade = 1 - (os.clock() - t0) / duration
			hum.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0) * intensity * fade
			RunService.RenderStepped:Wait()
		end
		if shakeId == id then
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.CameraOffset = Vector3.zero
			end
		end
	end)
end

-- where the shot goes: the mouse / the tap on screen; with a gamepad: the centre of the screen
local UserInputService = game:GetService("UserInputService")
-- AIM ASSIST: while you hold a weapon, the enemy closest to your crosshair (mouse / finger / screen centre) gets a soft lock:
-- a red ring shows it, and your shots go to it. It makes shooting while you fly (and move) much easier.
-- Turn it off with:  game.Players.LocalPlayer:SetAttribute("AimAssist", false)
local AIM_RADIUS = 0.15 -- of the screen height, plus the size of the enemy on screen
local lockedRoot = nil
local lockRing = Instance.new("Frame")
lockRing.AnchorPoint = Vector2.new(0.5, 0.5)
lockRing.BackgroundTransparency = 1
lockRing.Visible = false
lockRing.Size = UDim2.fromOffset(60, 60)
lockRing.ZIndex = 3
lockRing.Parent = gui
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(1, 0)
ringCorner.Parent = lockRing
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = Color3.fromRGB(255, 80, 90)
ringStroke.Thickness = 2.5
ringStroke.Parent = lockRing
local ringDot = Instance.new("Frame")
ringDot.AnchorPoint = Vector2.new(0.5, 0.5)
ringDot.Position = UDim2.fromScale(0.5, 0.5)
ringDot.Size = UDim2.fromOffset(6, 6)
ringDot.BackgroundColor3 = Color3.fromRGB(255, 80, 90)
ringDot.BorderSizePixel = 0
ringDot.Parent = lockRing
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = ringDot

local function holdingWeapon()
	local ch = player.Character
	local tool = ch and ch:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("WeaponId") ~= nil
end
RunService.RenderStepped:Connect(function()
	lockedRoot = nil
	local cam = workspace.CurrentCamera
	if not cam or player:GetAttribute("AimAssist") == false or not holdingWeapon() then
		lockRing.Visible = false
		return
	end
	local vp = cam.ViewportSize
	local aim = UserInputService:GetLastInputType().Name:find("Gamepad") and Vector2.new(vp.X / 2, vp.Y / 2) or UserInputService:GetMouseLocation()
	local pxPerStud = vp.Y / (2 * math.tan(math.rad(cam.FieldOfView) / 2))
	local best, bestScore, bestSize
	for _, name in { "XenoAliens", "MothershipForces" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			for _, m in folder:GetChildren() do
				local hum = m:FindFirstChildOfClass("Humanoid")
				local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
				if hum and hum.Health > 0 and root then
					local v, on = cam:WorldToViewportPoint(root.Position)
					if on and v.Z > 0 and v.Z < 900 then
						local size = math.clamp(m:GetExtentsSize().Magnitude * 0.5 / v.Z * pxPerStud, 26, vp.Y * 0.3)
						local d = (Vector2.new(v.X, v.Y) - aim).Magnitude
						if d < vp.Y * AIM_RADIUS + size and (not bestScore or d < bestScore) then
							best, bestScore, bestSize = root, d, size
							lockRing.Position = UDim2.fromOffset(v.X, v.Y)
						end
					end
				end
			end
		end
	end
	lockedRoot = best
	lockRing.Visible = best ~= nil
	if best then
		local s = bestSize * 2
		lockRing.Size = UDim2.fromOffset(s, s)
	end
end)

local function aimPoint()
	if lockedRoot and lockedRoot.Parent then
		return lockedRoot.Position
	end
	if UserInputService:GetLastInputType().Name:find("Gamepad") then
		local cam = workspace.CurrentCamera
		local vp = cam.ViewportSize
		local ray = cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }
		local res = workspace:Raycast(ray.Origin, ray.Direction * 1500, params)
		return res and res.Position or (ray.Origin + ray.Direction * 600)
	end
	return mouse.Hit.Position
end

local fovTween
local function setFov(target, time, style, direction)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if fovTween then
		fovTween:Cancel()
	end
	fovTween = TweenService:Create(cam, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), { FieldOfView = target })
	fovTween:Play()
end

fxRemote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "hit" then
		showHit()
	elseif kind == "shake" then
		shake(a or 0.3, b or 0.5)
	end
end)

----------------------------------------------------------------------
-- weapon recoil + per-shot cinematics
----------------------------------------------------------------------
local baseGrip = setmetatable({}, { __mode = "k" })

local function muzzlePos(tool)
	local m = tool:FindFirstChild("Muzzle", true)
	if m and m:IsA("Attachment") then
		return m.WorldPosition
	end
	local h = tool:FindFirstChild("Handle")
	return h and h.Position
end

local function flightRecoil(tool)
	-- shooting while you FLY: every shot pushes you back (zero gravity), with a burst of thruster sparks behind you
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local fv = root and root:FindFirstChild("FlightVelocity")
	if not (fv and fv.Enabled) then
		return
	end
	local cam = workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or root.CFrame.LookVector
	local r = tool:GetAttribute("Recoil") or 1
	player:SetAttribute("FlightKick", -look * (4 + 10 * r) * ((tool:GetAttribute("Auto") == true) and 0.35 or 1))
	local ml = tool:FindFirstChild("MuzzleLight", true)
	local color = ml and ml.Color or Color3.fromRGB(0, 230, 255)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.lookAt(root.Position - look * 1.5, root.Position - look * 3)
	part.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Speed = NumberRange.new(14, 34)
	e.SpreadAngle = Vector2.new(24, 24)
	e.EmissionDirection = Enum.NormalId.Front
	e.Rate = 0
	e.Parent = part
	e:Emit(16)
	game:GetService("Debris"):AddItem(part, 1)
end

local function kick(tool)
	local id = tool:GetAttribute("WeaponId")
	local prof = PROFILE[id] or {}
	tool:SetAttribute("ShotPulse", (tool:GetAttribute("ShotPulse") or 0) + 1) -- the weapon's glow / vents / display react (WeaponDetailFX)
	flightRecoil(tool)

	local r = tool:GetAttribute("Recoil") or 1
	local rapid = tool:GetAttribute("Auto") == true
	if rapid then r = r * 0.5 end
	local base = baseGrip[tool]
	if not base then
		base = tool.Grip
		baseGrip[tool] = base
	end
	pcall(function()
		tool.Grip = base * CFrame.new(0, 0.05 * r, 0.35 * r) * CFrame.Angles(math.rad(6 * r), 0, 0)
		TweenService:Create(tool, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Grip = base }):Play()
	end)

	local s = (tool:GetAttribute("Shake") or 0.05) * (rapid and 0.3 or 1)
	shake(s, 0.18 + s * 0.6)

	if prof.cinematic then
		setFov(BASE_FOV - prof.punch, 0.05)
		screenFlash(prof.flash, 0.45, 0.35)
		task.delay(0.06, function()
			setFov(BASE_FOV, 0.9, Enum.EasingStyle.Quint)
		end)
		task.delay(0.8, function()
			letterbox(false, 0.5)
		end)
	elseif prof.punch and not rapid then
		setFov(BASE_FOV - prof.punch, 0.04)
		task.delay(0.04, function()
			setFov(BASE_FOV, 0.16)
		end)
	end
end

----------------------------------------------------------------------
-- hooking up the tools
----------------------------------------------------------------------
local hooked = setmetatable({}, { __mode = "k" })

local function hook(tool)
	if not tool:IsA("Tool") or tool:GetAttribute("WeaponId") == nil or hooked[tool] then
		return
	end
	hooked[tool] = true
	local id = tool:GetAttribute("WeaponId")
	local auto = tool:GetAttribute("Auto") == true
	local rate = tool:GetAttribute("Cooldown") or 0.4
	local delay = FIRE_DELAY[id] or 0
	local own = OWN_SOUNDS[id] or {}
	local held = false

	tool.Activated:Connect(function()
		held = true
		repeat
			if tool.Parent ~= player.Character then
				break
			end
			remote:FireServer(tool, aimPoint())
			if delay > 0 then
				-- cinematic charge-up: the camera slowly pushes in and the letterbox bars slide in
				letterbox(true, 0.3)
				setFov(BASE_FOV - 12, delay, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				local origin = muzzlePos(tool)
				if origin and own.charge then
					playSfx(own.charge, origin)
				end
				task.delay(delay, function()
					if tool.Parent == player.Character then
						local p = muzzlePos(tool)
						if p and own.fire then
							playSfx(own.fire, p)
						end
						kick(tool)
					else
						letterbox(false, 0.3)
						setFov(BASE_FOV, 0.4)
					end
				end)
			else
				local p = muzzlePos(tool)
				if p and own.fire then
					playSfx(own.fire, p, auto and 0.5 or 1)
				end
				kick(tool)
			end
			if not auto then
				break
			end
			task.wait(rate)
		until not held
	end)
	tool.Deactivated:Connect(function()
		held = false
	end)
	tool.Unequipped:Connect(function()
		held = false
		if delay > 0 then
			letterbox(false, 0.3)
			setFov(BASE_FOV, 0.4)
		end
	end)
end

local function watch(container)
	for _, c in container:GetChildren() do
		hook(c)
	end
	container.ChildAdded:Connect(hook)
end

local function onCharacter(char)
	watch(char)
	watch(player:WaitForChild("Backpack"))
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end
