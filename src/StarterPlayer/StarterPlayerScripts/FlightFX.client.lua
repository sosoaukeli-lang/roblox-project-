-- FlightFX (LocalScript)
-- Makes flying feel real and cinematic, and gives take-off and landing their own effects.
-- (It does not change how you move - ZeroGravityFlight still does that. It only watches the flight.)
--
-- WHILE FLYING
--   * the camera: field of view widens with speed, banks into turns and strafes, a light shake when boosting,
--     and a slow floaty bob when you hover
--   * speed lines rush past you at high speed, a glowing contrail follows your body, tunnel-vision edges darken the screen
--   * wind that gets louder / higher with your speed, plus a sci-fi air swirl when you boost (Left Shift)
--   * a small flight display (altitude + speed + BOOST)
-- TAKE-OFF  : a shock ring and sparks burst at your feet, field-of-view punch, whoosh
-- LANDING   : the harder you hit, the bigger: shock rings across the ground, a spray of sparks, a puff of dust,
--             a flash of light, camera thud with a field-of-view squeeze, and a heavy impact sound

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local C3 = Color3.fromRGB
local rng = Random.new()

local BASE_FOV = 70
local ItemsCatalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Items"))
local MAX_FOV_EXTRA = 24 -- extra field of view at full boost speed
local CYAN, MAG, WHITE = C3(0, 220, 255), C3(255, 80, 225), C3(255, 255, 255)

----------------------------------------------------------------------
-- sounds
----------------------------------------------------------------------
local function makeLoop(id)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	return s
end
local windLoop = makeLoop(88733565266906)
local swirlLoop = makeLoop(9119462999)
local function playOnce(id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
end

----------------------------------------------------------------------
-- HUD: flight display + tunnel-vision edges
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "FlightHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local edges = {}
for _, e in { { UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), 0 }, { UDim2.fromScale(0.16, 1), UDim2.fromScale(0.84, 0), 180 }, { UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0), 90 }, { UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0.8), 270 } } do
	local f = Instance.new("Frame")
	f.Size = e[1]
	f.Position = e[2]
	f.BackgroundColor3 = C3(0, 25, 50)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = e[3]
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	table.insert(edges, f)
end

local hud = Instance.new("Frame")
hud.AnchorPoint = Vector2.new(0.5, 1)
hud.Position = UDim2.new(0.5, 0, 1, -96)
hud.Size = UDim2.fromOffset(300, 34)
hud.BackgroundColor3 = C3(6, 10, 26)
hud.BackgroundTransparency = 1
hud.BorderSizePixel = 0
hud.Parent = gui
local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0.5, 0); hc.Parent = hud
local hs = Instance.new("UIStroke"); hs.Color = CYAN; hs.Thickness = 1.5; hs.Transparency = 1; hs.Parent = hud
local hudText = Instance.new("TextLabel")
hudText.Size = UDim2.fromScale(1, 1)
hudText.BackgroundTransparency = 1
hudText.Font = Enum.Font.GothamBold
hudText.TextScaled = true
hudText.TextColor3 = C3(200, 245, 255)
hudText.TextTransparency = 1
hudText.Text = ""
hudText.Parent = hud
local hp = Instance.new("UIPadding"); hp.PaddingTop = UDim.new(0.2, 0); hp.PaddingBottom = UDim.new(0.2, 0); hp.Parent = hudText

-- the BOOST energy bar under the display
local barBG = Instance.new("Frame")
barBG.AnchorPoint = Vector2.new(0.5, 1)
barBG.Position = UDim2.new(0.5, 0, 1, -82)
barBG.Size = UDim2.fromOffset(260, 8)
barBG.BackgroundColor3 = C3(0, 0, 0)
barBG.BackgroundTransparency = 1
barBG.BorderSizePixel = 0
barBG.Parent = gui
local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(0.5, 0); bgc.Parent = barBG
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = CYAN
barFill.BackgroundTransparency = 1
barFill.BorderSizePixel = 0
barFill.Parent = barBG
local bfc = Instance.new("UICorner"); bfc.CornerRadius = UDim.new(0.5, 0); bfc.Parent = barFill

----------------------------------------------------------------------
-- effect helpers
----------------------------------------------------------------------
local function fxPart(pos)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	return p
end

local function ringAt(pos, color, d0, d1, duration)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Size = Vector3.new(0.35, d0, d0)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, d1, d1), Transparency = 1 }):Play()
	Debris:AddItem(ring, duration + 0.1)
end

local function burstAt(pos, c1, c2, count, vMin, vMax, gravity, upward)
	local fx = fxPart(pos)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(c1, c2)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.5, 1.2)
	e.Speed = NumberRange.new(vMin, vMax)
	e.SpreadAngle = upward and Vector2.new(55, 55) or Vector2.new(180, 180)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -gravity, 0)
	e.Rate = 0
	e.Parent = fx
	e:Emit(count)
	Debris:AddItem(fx, 2)
	return fx
end

local function dustAt(pos, count)
	local fx = fxPart(pos + Vector3.new(0, 1, 0))
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(C3(110, 90, 190), C3(40, 30, 90))
	e.LightEmission = 0.5
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(14, 30)
	e.SpreadAngle = Vector2.new(90, 90)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Parent = fx
	e:Emit(count)
	Debris:AddItem(fx, 3)
end

local function flashAt(pos, color, brightness, duration)
	local fx = fxPart(pos + Vector3.new(0, 2, 0))
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = 50
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = fx
	TweenService:Create(l, TweenInfo.new(duration), { Brightness = 0 }):Play()
	Debris:AddItem(fx, duration + 0.1)
end

----------------------------------------------------------------------
-- character-bound pieces: contrail + speed lines
----------------------------------------------------------------------
local char, hum, root, flightVel
local trail, trailLight
local streakPart, streaks

local function setupCharacter(character)
	char = character
	hum = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")
	flightVel = nil

	-- the glowing contrail behind the body
	local a0 = Instance.new("Attachment"); a0.Name = "ContrailA"; a0.Position = Vector3.new(0, 1.1, 0.6); a0.Parent = root
	local a1 = Instance.new("Attachment"); a1.Name = "ContrailB"; a1.Position = Vector3.new(0, -1.1, 0.6); a1.Parent = root
	trail = Instance.new("Trail")
	trail.Name = "FlightContrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.7
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.4, CYAN), ColorSequenceKeypoint.new(1, MAG) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Enabled = false
	trail.Parent = root
	trailLight = Instance.new("PointLight")
	trailLight.Color = CYAN
	trailLight.Range = 14
	trailLight.Brightness = 0
	trailLight.Shadows = false
	trailLight.Parent = root
end
player.CharacterAdded:Connect(setupCharacter)
if player.Character then
	setupCharacter(player.Character)
end

-- speed lines: an emitter ahead of the camera whose particles rush back past you
streakPart = Instance.new("Part")
streakPart.Name = "FlightStreaks"
streakPart.Anchored = true
streakPart.CanCollide = false
streakPart.CanQuery = false
streakPart.CanTouch = false
streakPart.Transparency = 1
streakPart.Size = Vector3.new(120, 80, 2)
streakPart.Parent = workspace
streaks = Instance.new("ParticleEmitter")
streaks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
streaks.Shape = Enum.ParticleEmitterShape.Box
streaks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
streaks.EmissionDirection = Enum.NormalId.Front
streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
streaks.Squash = NumberSequence.new(-0.9)
streaks.Color = ColorSequence.new(WHITE, CYAN)
streaks.LightEmission = 1
streaks.LightInfluence = 0
streaks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.4) })
streaks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.35), NumberSequenceKeypoint.new(1, 1) })
streaks.Lifetime = NumberRange.new(0.5, 0.8)
streaks.Speed = NumberRange.new(-100, -100)
streaks.Rate = 0
streaks.Parent = streakPart

----------------------------------------------------------------------
-- flight state
----------------------------------------------------------------------
local flying, wasFlying = false, false
local boosting, wasBoosting = false, false
local hist = {} -- recent speeds { t, speed } to know how hard a landing is
local fovPunch = 0 -- extra field of view that fades away
local shakeAmp = 0 -- camera shake that fades away
local roll, lastLook = 0, nil
local fovRecoverUntil = 0
local landDip = 0 -- the camera drops a little on impact and rises back
local smoothSpeed = 0
local t = 0

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(maxDist)
	if not root then return nil end
	groundParams.FilterDescendantsInstances = { char, streakPart }
	return workspace:Raycast(root.Position, Vector3.new(0, -maxDist, 0), groundParams)
end

local function isVehicle(inst)
	local rocket = workspace:FindFirstChild("Rocket")
	local ship = workspace:FindFirstChild("AlienShip")
	return (rocket ~= nil and inst:IsDescendantOf(rocket)) or (ship ~= nil and inst:IsDescendantOf(ship))
end

local function onTakeoff()
	local hit = groundBelow(14)
	if hit and not isVehicle(hit.Instance) then
		ringAt(hit.Position, CYAN, 4, 46, 0.55)
		ringAt(hit.Position, WHITE, 3, 24, 0.4)
		dustAt(hit.Position, 10)
		burstAt(hit.Position, WHITE, CYAN, 40, 20, 55, 40, true)
	end
	flashAt(root.Position, CYAN, 2.5, 0.4)
	fovPunch += 12
	shakeAmp = math.max(shakeAmp, 0.25)
	playOnce(9125973257, 0.45, 1.5) -- surge
	playOnce(9065667699, 0.25, 1.6)
end

local function onLanding(impact)
	local hit = groundBelow(12)
	if not hit or isVehicle(hit.Instance) then
		return -- stepping back into the rocket / ship: no impact
	end
	local k = math.clamp(impact / 120, 0.2, 1)
	local pos = hit.Position
	ringAt(pos, CYAN, 4, 50 + 110 * k, 0.5 + 0.4 * k)
	task.delay(0.08, function() ringAt(pos, MAG, 3, 30 + 70 * k, 0.5 + 0.3 * k) end)
	task.delay(0.16, function() ringAt(pos, WHITE, 2, 18 + 40 * k, 0.4) end)
	burstAt(pos, WHITE, CYAN, math.floor(40 + 120 * k), 25, 40 + 60 * k, 110, false)
	burstAt(pos, MAG, C3(120, 80, 255), math.floor(20 + 50 * k), 15, 35 + 40 * k, 90, true)
	dustAt(pos, math.floor(10 + 22 * k))
	flashAt(pos, WHITE, 2 + 4 * k, 0.45)
	shakeAmp = math.max(shakeAmp, 0.6 * k + 0.1)
	landDip = 0.5 * k + 0.3
	fovPunch -= 10 * k -- a quick squeeze
	playOnce(9065667699, 0.35 + 0.5 * k, 0.8 + 0.2 * (1 - k))
	playOnce(6290067239, 0.2 + 0.3 * k, 1.5)
	playOnce(9125973984, 0.18, 1.8)
end

local function onBoostStart()
	fovPunch += 6
	shakeAmp = math.max(shakeAmp, 0.3)
	playOnce(9125974640, 0.4, 1.3)
	if root then
		burstAt(root.Position, WHITE, MAG, 40, 30, 70, 0, false)
	end
end

player:GetAttributeChangedSignal("BoostLocked"):Connect(function()
	if player:GetAttribute("BoostLocked") == true then
		shakeAmp = math.max(shakeAmp, 0.25)
		fovPunch -= 6
		playOnce(9125973984, 0.5, 0.6) -- the boost cuts out
	else
		playOnce(9125974640, 0.3, 1.7) -- the boost is ready again
	end
end)

----------------------------------------------------------------------
-- per-frame work
----------------------------------------------------------------------
local hudAcc = 0
local function step(dt)
	t += dt
	local cam = workspace.CurrentCamera
	if not (root and root.Parent and hum and hum.Health > 0) then
		windLoop.Volume = 0
		swirlLoop.Volume = 0
		return
	end
	if not flightVel or not flightVel.Parent then
		flightVel = root:FindFirstChild("FlightVelocity")
	end
	flying = flightVel ~= nil and flightVel.Enabled and workspace.Gravity < 1
	local velocity = root.AssemblyLinearVelocity
	local speed = flying and velocity.Magnitude or 0
	smoothSpeed += (speed - smoothSpeed) * math.min(dt * 5, 1)
	boosting = flying and player:GetAttribute("Boosting") == true and speed > 60

	-- remember the last second of speeds (landing strength)
	hist[#hist + 1] = { t = t, v = speed }
	while #hist > 0 and t - hist[1].t > 1.8 do table.remove(hist, 1) end
	local recentMax = 0
	for _, h in hist do recentMax = math.max(recentMax, h.v) end

	if flying and not wasFlying then
		onTakeoff()
	end
	if wasFlying and not flying then
		onLanding(recentMax)
		fovRecoverUntil = t + 1.6
	end
	if boosting and not wasBoosting then
		onBoostStart()
	end
	wasFlying, wasBoosting = flying, boosting

	-- the contrail + glow
	if trail then
		trail.Enabled = flying and smoothSpeed > 22
		trail.Lifetime = math.clamp(0.35 + smoothSpeed / 140, 0.35, 1.1)
		local tid = player:GetAttribute("TrailId")
		local def = tid and tid ~= "" and ItemsCatalog.List[tid]
		if def and def.trailColors then
			-- an equipped trail item (Solar / Void ...): its own three colours, brighter when boosting
			local c = def.trailColors
			local k = boosting and 0.35 or 0
			trail.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c[1]:Lerp(WHITE, k)), ColorSequenceKeypoint.new(0.45, c[2]:Lerp(WHITE, k * 0.6)), ColorSequenceKeypoint.new(1, c[3]) })
		else
			trail.Color = boosting and ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.3, MAG), ColorSequenceKeypoint.new(1, C3(120, 60, 255)) })
				or ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.4, CYAN), ColorSequenceKeypoint.new(1, MAG) })
		end
	end
	if trailLight then
		trailLight.Color = boosting and MAG or CYAN
		trailLight.Brightness = flying and math.clamp((smoothSpeed - 20) / 90, 0, 1) * 0.9 or 0
	end

	-- speed lines in front of the camera
	local rate = 0
	if flying and smoothSpeed > 38 and cam then
		local dir = velocity.Magnitude > 1 and velocity.Unit or cam.CFrame.LookVector
		streakPart.CFrame = CFrame.lookAt(cam.CFrame.Position + dir * 75, cam.CFrame.Position + dir * 76)
		streaks.Speed = NumberRange.new(-(smoothSpeed + 40), -(smoothSpeed + 40))
		streaks.Color = boosting and ColorSequence.new(WHITE, MAG) or ColorSequence.new(WHITE, CYAN)
		rate = math.clamp((smoothSpeed - 38) * 1.6, 0, 160) * (player:GetAttribute("FXScale") or 1)
	end
	streaks.Rate = rate

	-- sound: wind rises with speed, the air swirl joins in when boosting
	local sv = flying and math.clamp(smoothSpeed / 130, 0, 1) or 0
	windLoop.Volume += (sv * 0.55 - windLoop.Volume) * math.min(dt * 4, 1)
	windLoop.PlaybackSpeed = 0.85 + sv * 0.5
	local bv = boosting and 0.35 or 0
	swirlLoop.Volume += (bv - swirlLoop.Volume) * math.min(dt * 3, 1)
	swirlLoop.PlaybackSpeed = 0.9 + sv * 0.4

	-- the boost bar: cyan, magenta while boosting, red while it recharges after running empty
	local energy = player:GetAttribute("BoostEnergy") or 1
	local locked = player:GetAttribute("BoostLocked") == true
	local showBar = flying or energy < 0.995
	barBG.BackgroundTransparency += ((showBar and 0.45 or 1) - barBG.BackgroundTransparency) * math.min(dt * 8, 1)
	barFill.BackgroundTransparency = barBG.BackgroundTransparency > 0.95 and 1 or 0
	barFill.Size = UDim2.fromScale(math.clamp(energy, 0, 1), 1)
	barFill.BackgroundColor3 = locked and C3(255, 60, 70) or (boosting and MAG or CYAN)

	-- the HUD
	hudAcc += dt
	if hudAcc > 0.1 then
		hudAcc = 0
		local show = flying
		hud.BackgroundTransparency = show and 0.35 or 1
		hs.Transparency = show and 0.3 or 1
		hudText.TextTransparency = show and 0 or 1
		if show then
			hudText.Text = string.format("\u{25B2} ALT %d     \u{25B6} %d%s", math.floor(root.Position.Y + 0.5), math.floor(smoothSpeed + 0.5), boosting and "   BOOST" or (player:GetAttribute("BoostLocked") == true and "   RECHARGING" or ""))
			hs.Color = boosting and MAG or CYAN
		end
	end
	local edge = flying and math.clamp((smoothSpeed - 45) / 90, 0, 1) * 0.55 or 0
	for _, f in edges do
		f.BackgroundTransparency += ((1 - edge) - f.BackgroundTransparency) * math.min(dt * 5, 1)
		f.BackgroundColor3 = boosting and C3(40, 0, 60) or C3(0, 25, 50)
	end

	-- the camera
	fovPunch -= fovPunch * math.min(dt * 5, 1)
	shakeAmp -= shakeAmp * math.min(dt * 4.5, 1)
	if not cam then return end
	local cinematic = player:GetAttribute("InCinematic") == true or cam.CameraType ~= Enum.CameraType.Custom
	if cinematic then
		lastLook = nil
		return
	end

	local targetFov = BASE_FOV
	if flying then
		targetFov = BASE_FOV + math.clamp((smoothSpeed - 20) / 120, 0, 1) * MAX_FOV_EXTRA
	end
	if flying or t < fovRecoverUntil or math.abs(fovPunch) > 0.2 then
		local want = targetFov + fovPunch
		cam.FieldOfView += (want - cam.FieldOfView) * math.min(dt * 7, 1)
	end

	local cf = cam.CFrame
	if flying then
		-- bank into turns and lean into sideways movement
		local look = cf.LookVector
		local yawRate = 0
		if lastLook then
			yawRate = (lastLook.X * look.Z - lastLook.Z * look.X) / math.max(dt, 1e-3)
		end
		lastLook = look
		local lateral = velocity:Dot(cf.RightVector)
		local rollTarget = math.clamp(lateral * 0.0016 + yawRate * 0.035, -0.12, 0.12)
		roll += (rollTarget - roll) * math.min(dt * 4, 1)
		local off = CFrame.Angles(0, 0, roll)
		-- shake: stronger at boost, plus the decaying shake from impacts
		local amp = shakeAmp + (boosting and 0.05 or math.clamp((smoothSpeed - 90) / 400, 0, 0.03))
		if amp > 0.002 then
			off = off * CFrame.new(math.noise(t * 31, 1) * amp, math.noise(t * 29, 7) * amp, 0) * CFrame.Angles(0, 0, math.noise(t * 23, 3) * amp * 0.12)
		end
		-- a slow floaty bob when hovering
		if smoothSpeed < 10 then
			off = off * CFrame.new(0, 0.07 * math.sin(t * 1.3), 0.03 * math.sin(t * 0.9))
		end
		cam.CFrame = cf * off
	else
		lastLook = nil
		roll += (0 - roll) * math.min(dt * 6, 1)
		landDip -= landDip * math.min(dt * 5, 1)
		if shakeAmp > 0.003 or landDip > 0.01 then
			-- the landing thud: the camera drops and shakes, then settles
			cam.CFrame = cf * CFrame.new(math.noise(t * 31, 1) * shakeAmp, math.noise(t * 29, 7) * shakeAmp - landDip, 0)
		end
	end
end
RunService:BindToRenderStep("FlightFX", Enum.RenderPriority.Camera.Value + 10, step)
