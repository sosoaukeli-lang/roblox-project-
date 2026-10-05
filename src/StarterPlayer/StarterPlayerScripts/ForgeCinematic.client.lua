-- ForgeCinematic: movie-style camera work for the weapon forge, for the player who is crafting.
--   forgeStart  : the camera swoops in and orbits the forge while it fires up (title card: FORGING ...)
--   forgeReveal : when the weapon is finished, a low hero shot looks up at it floating, slow orbit + push-in
-- Both use letterbox bars, depth of field (blurred background), colour grading in the weapon's colour,
-- a FOV zoom and a title card. Nothing here changes the game for other players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local fxRemote = ReplicatedStorage:WaitForChild("WeaponFX")

local BASE_FOV = 70
local PI = math.pi

----------------------------------------------------------------------
-- UI: letterbox bars, title card, flash
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "ForgeFX"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 46
gui.Parent = player:WaitForChild("PlayerGui")

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
	local size = UDim2.fromScale(1, show and 0.11 or 0)
	TweenService:Create(topBar, info, { Size = size }):Play()
	TweenService:Create(bottomBar, info, { Size = size }):Play()
end

local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.ZIndex = 2
flashFrame.Parent = gui
local function flash(color, alpha, time)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = alpha
	TweenService:Create(flashFrame, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

local function makeText(y, size, font)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, y)
	l.Size = UDim2.fromScale(0.8, size)
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = font
	l.TextTransparency = 1
	l.TextStrokeTransparency = 1
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.ZIndex = 6
	l.Parent = gui
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = font == Enum.Font.GothamBlack and 72 or 26
	c.Parent = l
	return l
end
local titleLabel = makeText(0.42, 0.1, Enum.Font.GothamBlack)
local subLabel = makeText(0.52, 0.04, Enum.Font.GothamMedium)
local function showTitle(title, sub, color)
	titleLabel.Text = title
	titleLabel.TextColor3 = color
	subLabel.Text = sub
	subLabel.TextColor3 = Color3.new(1, 1, 1)
	TweenService:Create(titleLabel, TweenInfo.new(0.6), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
	TweenService:Create(subLabel, TweenInfo.new(0.6), { TextTransparency = 0.1, TextStrokeTransparency = 0.6 }):Play()
end
local function hideTitle(time)
	local info = TweenInfo.new(time)
	TweenService:Create(titleLabel, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(subLabel, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end

----------------------------------------------------------------------
-- cinematic helpers
----------------------------------------------------------------------
local busy = false

local function lerp(a, b, t)
	return a + (b - a) * t
end
local function smooth(t)
	return t * t * (3 - 2 * t)
end

-- starts a cinematic: freezes the character, bars in, depth of field + colour grading on
local function begin(tint)
	local cam = workspace.CurrentCamera
	local state = { cam = cam }

	player:SetAttribute("InCinematic", true)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		state.hum = hum
		state.walk, state.jumpPower, state.jumpHeight = hum.WalkSpeed, hum.JumpPower, hum.JumpHeight
		hum.WalkSpeed, hum.JumpPower, hum.JumpHeight = 0, 0, 0
	end

	letterbox(true, 0.35)
	cam.CameraType = Enum.CameraType.Scriptable

	local cc = Lighting:FindFirstChild("ColorCorrection")
	if cc then
		state.cc = cc
		state.ccOld = { Brightness = cc.Brightness, Contrast = cc.Contrast, Saturation = cc.Saturation, TintColor = cc.TintColor }
		TweenService:Create(cc, TweenInfo.new(0.6), {
			Brightness = -0.05,
			Contrast = cc.Contrast + 0.08,
			Saturation = cc.Saturation + 0.15,
			TintColor = Color3.new(1, 1, 1):Lerp(tint, 0.25),
		}):Play()
	end
	local dof = Lighting:FindFirstChild("DepthOfField")
	if dof then
		state.dof = dof
		state.dofOld = { Enabled = dof.Enabled, FarIntensity = dof.FarIntensity, NearIntensity = dof.NearIntensity, InFocusRadius = dof.InFocusRadius }
		dof.FarIntensity = 0.55
		dof.NearIntensity = 0.25
		dof.InFocusRadius = 12
		dof.Enabled = true
	end
	return state
end

-- glide the camera back behind the player, then give everything back
local function finish(state, lookAtPos)
	local cam = state.cam
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	pcall(function()
		if root then
			local from = cam.CFrame
			local look = lookAtPos - root.Position
			look = (look.Magnitude > 1) and look.Unit or Vector3.new(0, 0, -1)
			local target = CFrame.lookAt(root.Position - look * 14 + Vector3.new(0, 6, 0), root.Position + look * 30)
			local t1 = os.clock()
			while true do
				local b = (os.clock() - t1) / 0.55
				if b >= 1 then
					break
				end
				cam.CFrame = from:Lerp(target, smooth(b))
				cam.FieldOfView = cam.FieldOfView + (BASE_FOV - cam.FieldOfView) * 0.2
				if state.dof then
					state.dof.FarIntensity = lerp(0.55, state.dofOld.FarIntensity, b)
				end
				RunService.RenderStepped:Wait()
			end
		end
	end)

	cam.FieldOfView = BASE_FOV
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	letterbox(false, 0.5)
	hideTitle(0.3)
	if state.cc then
		TweenService:Create(state.cc, TweenInfo.new(0.6), state.ccOld):Play()
	end
	if state.dof then
		state.dof.Enabled = state.dofOld.Enabled
		state.dof.FarIntensity = state.dofOld.FarIntensity
		state.dof.NearIntensity = state.dofOld.NearIntensity
		state.dof.InFocusRadius = state.dofOld.InFocusRadius
	end
	if state.hum and state.hum.Parent then
		state.hum.WalkSpeed, state.hum.JumpPower, state.hum.JumpHeight = state.walk, state.jumpPower, state.jumpHeight
	end
	player:SetAttribute("InCinematic", false)
	busy = false
end

-- runs `update(a)` every frame for `duration` seconds (a goes 0 -> 1)
local function shot(duration, update)
	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / duration
		if a >= 1 then
			update(1)
			break
		end
		update(a)
		RunService.RenderStepped:Wait()
	end
end

local function orbitCFrame(center, angle, radius, height)
	local pos = center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
	return pos
end

----------------------------------------------------------------------
-- 1) FORGE STARTS: swoop in, orbit, title card
----------------------------------------------------------------------
local function playStart(center, name, color)
	if busy or player:GetAttribute("InCinematic") or typeof(center) ~= "Vector3" then
		return
	end
	busy = true
	local state = begin(color)
	local cam = state.cam
	local ok, err = pcall(function()
		local startCF = cam.CFrame
		local dof = state.dof
		local function focus()
			if dof then
				dof.FocusDistance = (cam.CFrame.Position - center).Magnitude
			end
		end
		-- shot 1: swoop from where you stand to a wide front-left view of the forge
		local wideAngle = PI / 2 - 0.65
		local widePos = orbitCFrame(center, wideAngle, 24, 8)
		local wideCF = CFrame.lookAt(widePos, center + Vector3.new(0, 1, 0))
		shot(1.0, function(a)
			cam.CFrame = startCF:Lerp(wideCF, smooth(a))
			cam.FieldOfView = lerp(BASE_FOV, 62, smooth(a))
			focus()
		end)
		showTitle("FORGING", name, color)
		-- shot 2: slow orbit around the forge with a push-in
		shot(2.6, function(a)
			local e = smooth(a)
			local angle = wideAngle + e * 1.9
			local pos = orbitCFrame(center, angle, lerp(24, 13, e), lerp(8, 4, e))
			cam.CFrame = CFrame.lookAt(pos, center + Vector3.new(0, 1 + 1.5 * e, 0))
			cam.FieldOfView = lerp(62, 48, e)
			focus()
			if a > 0.78 then
				hideTitle(0.5)
			end
		end)
	end)
	if not ok then
		warn("ForgeCinematic error: " .. tostring(err))
	end
	finish(state, center)
end

----------------------------------------------------------------------
-- 2) WEAPON READY: hero shot of the finished weapon
----------------------------------------------------------------------
local function playReveal(pos, name, color)
	if busy or typeof(pos) ~= "Vector3" then
		return
	end
	-- if another cinematic is still running, wait a moment for it
	local waited = 0
	while busy and waited < 3 do
		task.wait(0.1)
		waited += 0.1
	end
	if busy then
		return
	end
	busy = true
	local state = begin(color)
	local cam = state.cam
	local ok, err = pcall(function()
		local dof = state.dof
		-- aim at the REAL floating hologram (it hovers with the rocket) instead of a guessed spot
		local holoModel
		do
			local best = 14
			for _, d in workspace:GetChildren() do
				if d.Name == "Hologram" and d:IsA("Model") then
					local dd = (d:GetPivot().Position - pos).Magnitude
					if dd < best then
						best, holoModel = dd, d
					end
				end
			end
		end
		local function refresh()
			if holoModel and holoModel.Parent then
				pos = holoModel:GetPivot().Position
			end
		end
		local function focus()
			if dof then
				dof.FocusDistance = (cam.CFrame.Position - pos).Magnitude
			end
		end
		flash(Color3.new(1, 1, 1):Lerp(color, 0.5), 0.8, 0.7)
		showTitle(name, "FORGED", color)
		-- shot 1: low hero angle looking up at the floating weapon
		local baseAngle = PI / 2 - 0.5
		shot(1.0, function(a)
			refresh()
			local e = smooth(a)
			local p = orbitCFrame(pos, baseAngle, 16, -1.5 + e * 0.5)
			cam.CFrame = CFrame.lookAt(p, pos)
			cam.FieldOfView = lerp(52, 50, e)
			focus()
		end)
		-- shot 2: slow orbit and push-in
		shot(4.5, function(a)
			refresh()
			local e = smooth(a)
			local angle = baseAngle + e * 2.0
			local p = orbitCFrame(pos, angle, lerp(16, 9, e), lerp(-1, 2.5, e))
			cam.CFrame = CFrame.lookAt(p, pos)
			cam.FieldOfView = lerp(50, 40, e)
			focus()
			if a > 0.8 then
				hideTitle(0.5)
			end
		end)
	end)
	if not ok then
		warn("ForgeCinematic error: " .. tostring(err))
	end
	finish(state, pos)
end

fxRemote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "forgeStart" then
		task.spawn(playStart, a, b, c)
	elseif kind == "forgeReveal" then
		task.spawn(playReveal, a, b, c)
	end
end)
