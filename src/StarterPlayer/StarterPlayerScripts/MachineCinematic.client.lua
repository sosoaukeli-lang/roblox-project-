-- MachineCinematic: when you upgrade your iron machine, the camera swings around it while it charges up
-- and transforms (letterbox bars, slow orbit, dolly zoom, flash). Triggered by the server ("evolve" event).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local fxRemote = ReplicatedStorage:WaitForChild("WeaponFX")

local BASE_FOV = 70

-- UI: letterbox bars + flash
local gui = Instance.new("ScreenGui")
gui.Name = "EvolveFX"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 45
gui.Parent = player:WaitForChild("PlayerGui")

local function makeBar(anchorY)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0, anchorY)
	f.Position = UDim2.fromScale(0, anchorY)
	f.Size = UDim2.fromScale(1, 0)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Parent = gui
	return f
end
local topBar, bottomBar = makeBar(0), makeBar(1)
local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.ZIndex = 2
flashFrame.Parent = gui

local function letterbox(show, time)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local size = UDim2.fromScale(1, show and 0.1 or 0)
	TweenService:Create(topBar, info, { Size = size }):Play()
	TweenService:Create(bottomBar, info, { Size = size }):Play()
end
local function flash(color, alpha, time)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = alpha
	TweenService:Create(flashFrame, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

local busy = false
local TIER_FLASH = {
	Color3.fromRGB(255, 170, 40), Color3.fromRGB(255, 220, 80), Color3.fromRGB(190, 235, 255), Color3.fromRGB(190, 120, 255),
}

local function playEvolve(center, level)
	if busy or typeof(center) ~= "Vector3" then
		return
	end
	busy = true
	local cam = workspace.CurrentCamera
	local isMax = level >= 4
	local duration = isMax and 3.6 or 2.6
	local radius = isMax and 40 or 30
	local sweep = isMax and 4.4 or 2.7 -- radians the camera travels around the machine

	player:SetAttribute("InCinematic", true) -- the flight script ignores steering while this is set

	-- freeze the character in place (setting speeds instead of switching the whole control system off,
	-- which could leave the controls in a strange state afterwards)
	local hum0 = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local savedWalk, savedJumpPower, savedJumpHeight
	if hum0 then
		savedWalk, savedJumpPower, savedJumpHeight = hum0.WalkSpeed, hum0.JumpPower, hum0.JumpHeight
		hum0.WalkSpeed = 0
		hum0.JumpPower = 0
		hum0.JumpHeight = 0
	end

	letterbox(true, 0.35)
	local ok, err = pcall(function()
		cam.CameraType = Enum.CameraType.Scriptable
		local startRel = cam.CFrame.Position - center
		local startAngle = math.atan2(startRel.Z, startRel.X)
		local t0 = os.clock()
		local flashed = false
		while true do
			local a = (os.clock() - t0) / duration
			if a >= 1 then
				break
			end
			local ease = a * a * (3 - 2 * a)
			local angle = startAngle + ease * sweep
			local r = radius * (1 - 0.3 * math.sin(a * math.pi))
			local h = 4 + 12 * ease
			local pos = center + Vector3.new(math.cos(angle) * r, h, math.sin(angle) * r)
			cam.CFrame = CFrame.lookAt(pos, center + Vector3.new(0, 3 + 5 * ease, 0))
			cam.FieldOfView = BASE_FOV - 16 * math.sin(a * math.pi) -- dolly zoom
			if not flashed and a > (isMax and 0.42 or 0.38) then
				flashed = true
				flash(TIER_FLASH[math.clamp(level, 1, 4)], 0.35, isMax and 0.9 or 0.6)
			end
			RunService.RenderStepped:Wait()
		end

		-- glide back behind the player
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local from = cam.CFrame
			local look = (center - root.Position)
			look = (look.Magnitude > 1) and look.Unit or Vector3.new(0, 0, -1)
			local target = CFrame.lookAt(root.Position - look * 14 + Vector3.new(0, 6, 0), root.Position + look * 30)
			local t1 = os.clock()
			while true do
				local b = (os.clock() - t1) / 0.5
				if b >= 1 then
					break
				end
				cam.CFrame = from:Lerp(target, b * b * (3 - 2 * b))
				cam.FieldOfView = cam.FieldOfView + (BASE_FOV - cam.FieldOfView) * 0.2
				RunService.RenderStepped:Wait()
			end
		end
	end)
	if not ok then
		warn("MachineCinematic error: " .. tostring(err))
	end

	cam.FieldOfView = BASE_FOV
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	letterbox(false, 0.5)
	if hum0 and hum0.Parent then
		hum0.WalkSpeed = savedWalk
		hum0.JumpPower = savedJumpPower
		hum0.JumpHeight = savedJumpHeight
	end
	player:SetAttribute("InCinematic", false)
	busy = false
end

fxRemote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "evolve" then
		task.spawn(playEvolve, a, b)
	end
end)
