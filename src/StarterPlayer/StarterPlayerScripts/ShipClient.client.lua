-- ShipClient (LocalScript)
-- Runs the alien ship visuals on your screen: floating/bobbing, orbiting lights, the sliding door,
-- the arrival cinematic, and the small messages from the SHOP / SELL aliens.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local ship = workspace:WaitForChild("AlienShip")
local basePivot = ship:WaitForChild("ShipPivot").CFrame
local baseRot = basePivot - basePivot.Position

local BOB_HEIGHT = 2.5   -- studs up/down
local BOB_PERIOD = 11    -- seconds for one float cycle
local DOOR_SPEED = 0.5   -- seconds (roughly) the door takes to open

local function polar(R, a, y)
	return CFrame.new(R * math.sin(a), y, -R * math.cos(a)) * CFrame.Angles(0, -a, 0)
end

-- Collect animated parts
local spinners, panels, glows = {}, {}, {}
local function track(inst)
	if not inst:IsDescendantOf(ship) then
		return
	end
	if CollectionService:HasTag(inst, "ShipSpin") then
		table.insert(spinners, { part = inst, rel = basePivot:ToObjectSpace(inst.CFrame), speed = inst:GetAttribute("Spin") or 0, angle = 0 })
	elseif CollectionService:HasTag(inst, "ShipDoorPanel") then
		table.insert(panels, { part = inst, R = inst:GetAttribute("Radius"), Y = inst:GetAttribute("Height"), closed = inst:GetAttribute("ClosedAngle"), open = inst:GetAttribute("OpenAngle") })
	elseif CollectionService:HasTag(inst, "ShipDoorGlow") then
		table.insert(glows, inst)
	end
end
for _, tag in { "ShipSpin", "ShipDoorPanel", "ShipDoorGlow" } do
	for _, inst in CollectionService:GetTagged(tag) do
		track(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(track)
end

-- UI (messages, letterbox bars, title)
local gui = Instance.new("ScreenGui")
gui.Name = "ShipUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.fromScale(0.5, 0.12)
toast.Size = UDim2.fromOffset(560, 50)
toast.BackgroundColor3 = Color3.fromRGB(15, 20, 35)
toast.BackgroundTransparency = 0.15
toast.TextColor3 = Color3.new(1, 1, 1)
toast.Font = Enum.Font.GothamBold
toast.TextSize = 22
toast.TextWrapped = true
toast.Visible = false
toast.Parent = gui
local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 12)
toastCorner.Parent = toast
local toastStroke = Instance.new("UIStroke")
toastStroke.Color = Color3.fromRGB(0, 230, 255)
toastStroke.Thickness = 2
toastStroke.Parent = toast

local toastId = 0
ReplicatedStorage:WaitForChild("ShipNotify").OnClientEvent:Connect(function(msg)
	toastId += 1
	local id = toastId
	toast.Text = msg
	toast.Visible = true
	task.delay(3.5, function()
		if toastId == id then
			toast.Visible = false
		end
	end)
end)

local function makeBar(anchorY)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0, anchorY)
	f.Position = UDim2.fromScale(0, anchorY)
	f.Size = UDim2.fromScale(1, 0)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.ZIndex = 10
	f.Parent = gui
	return f
end
local topBar, bottomBar = makeBar(0), makeBar(1)

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.42)
title.Size = UDim2.fromScale(0.7, 0.12)
title.BackgroundTransparency = 1
title.Text = "THE MOTHERSHIP"
title.TextScaled = true
title.Font = Enum.Font.GothamBlack
title.TextColor3 = Color3.fromRGB(120, 255, 240)
title.TextStrokeColor3 = Color3.fromRGB(0, 40, 60)
title.TextTransparency = 1
title.TextStrokeTransparency = 1
title.ZIndex = 11
title.Parent = gui

local subtitle = Instance.new("TextLabel")
subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
subtitle.Position = UDim2.fromScale(0.5, 0.52)
subtitle.Size = UDim2.fromScale(0.4, 0.04)
subtitle.BackgroundTransparency = 1
subtitle.Text = "ALIEN TRADING VESSEL"
subtitle.TextScaled = true
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
subtitle.TextTransparency = 1
subtitle.ZIndex = 11
subtitle.Parent = gui

local function fadeTitle(toVisible, time)
	local info = TweenInfo.new(time)
	TweenService:Create(title, info, { TextTransparency = toVisible and 0 or 1, TextStrokeTransparency = toVisible and 0.3 or 1 }):Play()
	TweenService:Create(subtitle, info, { TextTransparency = toVisible and 0.1 or 1 }):Play()
end

-- Cinematic
local playing = false
local spinBoost = 1

local function playCinematic()
	if playing then
		return
	end
	playing = true
	player:SetAttribute("InCinematic", true)
	spinBoost = 4

	local cam = workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")

	TweenService:Create(topBar, TweenInfo.new(0.6), { Size = UDim2.fromScale(1, 0.12) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.6), { Size = UDim2.fromScale(1, 0.12) }):Play()

	local ok, err = pcall(function()
		cam.CameraType = Enum.CameraType.Scriptable
		local P = ship:GetPivot()
		local function at(pos, look)
			return CFrame.lookAt(P:PointToWorldSpace(pos), P:PointToWorldSpace(look))
		end
		local function shot(a, b, dur, fovA, fovB)
			local t0 = os.clock()
			repeat
				local alpha = math.clamp((os.clock() - t0) / dur, 0, 1)
				cam.CFrame = a:Lerp(b, alpha)
				cam.FieldOfView = fovA + (fovB - fovA) * alpha
				RunService.RenderStepped:Wait()
			until alpha >= 1
		end

		-- Shot 1: sweeping reveal of the whole ship
		fadeTitle(true, 0.8)
		task.delay(2.4, function()
			fadeTitle(false, 0.8)
		end)
		shot(at(Vector3.new(-420, 230, -560), Vector3.new(0, 70, -40)), at(Vector3.new(-300, 150, -470), Vector3.new(0, 60, -80)), 3.2, 65, 60)

		-- Shot 2: the door slides open
		shot(at(Vector3.new(-120, 14, -330), Vector3.new(0, 30, -200)), at(Vector3.new(-55, 26, -285), Vector3.new(0, 34, -200)), 3.0, 55, 50)

		-- Shot 3: fly through the doorway toward the aliens
		shot(at(Vector3.new(0, 40, -300), Vector3.new(0, 22, -95)), at(Vector3.new(0, 36, -175), Vector3.new(0, 18, -90)), 2.8, 70, 75)

		-- Shot 4: back behind the player
		if root and root.Parent then
			local doorPos = P:PointToWorldSpace(Vector3.new(0, 35, -200))
			local dir = doorPos - root.Position
			dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, -1)
			local endCF = CFrame.lookAt(root.Position - dir * 16 + Vector3.new(0, 5, 0), root.Position + dir * 40)
			shot(cam.CFrame, endCF, 1.4, 75, 70)
		end
	end)
	if not ok then
		warn("ShipClient cinematic error: " .. tostring(err))
	end

	cam.FieldOfView = 70
	cam.CameraType = Enum.CameraType.Custom
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid") or hum
	if h then
		cam.CameraSubject = h
	end
	fadeTitle(false, 0.3)
	TweenService:Create(topBar, TweenInfo.new(0.5), { Size = UDim2.fromScale(1, 0) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.5), { Size = UDim2.fromScale(1, 0) }):Play()
	player:SetAttribute("InCinematic", false)
	playing = false
end

ReplicatedStorage:WaitForChild("ShipCinematic").OnClientEvent:Connect(function()
	task.spawn(playCinematic)
end)

-- Main animation loop (Stepped = before physics, so the floor moves smoothly under your feet)
local t = 0
local openAmount = 0
RunService.Stepped:Connect(function(_, dt)
	t += dt
	local bob = Vector3.new(0, math.sin(t * 2 * math.pi / BOB_PERIOD) * BOB_HEIGHT, 0)
	local tilt = CFrame.Angles(math.sin(t * 0.37) * 0.004, math.sin(t * 0.23) * 0.006, math.sin(t * 0.31) * 0.004)
	local pivot = CFrame.new(basePivot.Position + bob) * baseRot * tilt
	ship:PivotTo(pivot)

	if not playing then
		spinBoost += (1 - spinBoost) * math.min(dt / 1.5, 1)
	end

	-- Door
	local target = ship:GetAttribute("DoorOpen") and 1 or 0
	openAmount += (target - openAmount) * math.min(dt / DOOR_SPEED, 1)
	local e = openAmount * openAmount * (3 - 2 * openAmount)
	for _, pn in panels do
		local a = pn.closed + (pn.open - pn.closed) * e
		pn.part.CFrame = pivot * polar(pn.R, a, pn.Y)
	end
	for _, g in glows do
		g.Transparency = 1 - 0.18 * e * (0.85 + 0.15 * math.sin(t * 4))
	end

	-- Orbiting rim lights and hologram rings
	for _, s in spinners do
		s.angle += s.speed * spinBoost * dt
		s.part.CFrame = pivot * CFrame.Angles(0, s.angle, 0) * s.rel
	end
end)
