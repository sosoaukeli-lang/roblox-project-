-- DeviceAdapt (LocalScript)
-- Makes the game playable (and smooth) on phones / tablets and on consoles (PlayStation / Xbox), not just on a PC:
--
-- CONTROLS
--   * PHONE / TABLET : while you fly, three touch buttons appear on the right side: UP, DOWN and BOOST
--                      (the thumbstick moves you, dragging the screen turns the camera, tapping the screen shoots)
--   * GAMEPAD        : left stick moves, A = up, B = down, L3 (press the left stick) or L2 = BOOST, R2 = shoot
--                      (shots go to the centre of the screen, with a small reticle), Back/Select = music on/off
--   * ZeroGravityFlight / FlightFX read these buttons through the player attributes VirtUp / VirtDown / VirtBoost
--
-- PERFORMANCE ("low spec" mode on phones, "console" mode on consoles)
--   * point lights that are far from you are switched off (the map has hundreds of them)
--   * far-away particle emitters are switched off, effects like speed lines run at half strength on phones

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled
local consoleOnly = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled

-- quality settings the other scripts read
player:SetAttribute("LowSpec", touchOnly)
player:SetAttribute("FXScale", touchOnly and 0.5 or 1)
player:SetAttribute("Device", touchOnly and "phone" or (consoleOnly and "console" or "pc"))

----------------------------------------------------------------------
-- gamepad: boost + music buttons (always available when a gamepad is connected)
----------------------------------------------------------------------
local function holdAttribute(attr)
	return function(_, state)
		if state == Enum.UserInputState.Begin then
			player:SetAttribute(attr, true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			player:SetAttribute(attr, false)
		end
		return Enum.ContextActionResult.Pass
	end
end
ContextActionService:BindAction("FlyBoostPad", holdAttribute("VirtBoost"), false, Enum.KeyCode.ButtonL3, Enum.KeyCode.ButtonL2)
ContextActionService:BindAction("MusicTogglePad", function(_, state)
	if state == Enum.UserInputState.Begin then
		player:SetAttribute("MusicToggle", (player:GetAttribute("MusicToggle") or 0) + 1)
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.ButtonSelect)

----------------------------------------------------------------------
-- phone: UP / DOWN / BOOST touch buttons, only while you are flying
----------------------------------------------------------------------
local buttonsBound = false
local function touchHandler(attr)
	return function(_, state)
		if state == Enum.UserInputState.Begin then
			player:SetAttribute(attr, true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			player:SetAttribute(attr, false)
		end
		return Enum.ContextActionResult.Sink
	end
end
local function bindTouchButtons()
	if buttonsBound then return end
	buttonsBound = true
	ContextActionService:BindAction("FlyUp", touchHandler("VirtUp"), true)
	ContextActionService:BindAction("FlyDown", touchHandler("VirtDown"), true)
	ContextActionService:BindAction("FlyBoost", touchHandler("VirtBoost"), true)
	ContextActionService:SetTitle("FlyUp", "\u{25B2} UP")
	ContextActionService:SetTitle("FlyDown", "\u{25BC} DOWN")
	ContextActionService:SetTitle("FlyBoost", "BOOST")
	ContextActionService:SetPosition("FlyUp", UDim2.new(1, -95, 0.38, 0))
	ContextActionService:SetPosition("FlyDown", UDim2.new(1, -95, 0.62, 0))
	ContextActionService:SetPosition("FlyBoost", UDim2.new(1, -185, 0.5, 0))
end
local function unbindTouchButtons()
	if not buttonsBound then return end
	buttonsBound = false
	for _, n in { "FlyUp", "FlyDown", "FlyBoost" } do
		ContextActionService:UnbindAction(n)
	end
	for _, a in { "VirtUp", "VirtDown", "VirtBoost" } do
		player:SetAttribute(a, false)
	end
end

----------------------------------------------------------------------
-- gamepad aiming reticle (only while a weapon is equipped and you play with a gamepad)
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "DeviceUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 45
gui.IgnoreGuiInset = true
gui.Parent = playerGui
local reticle = Instance.new("Frame")
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.5)
reticle.Size = UDim2.fromOffset(26, 26)
reticle.BackgroundTransparency = 1
reticle.Visible = false
reticle.Parent = gui
local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(0, 230, 255); rs.Thickness = 2; rs.Parent = reticle
local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0.5, 0); rc.Parent = reticle
local dot = Instance.new("Frame")
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(4, 4)
dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
dot.BorderSizePixel = 0
dot.Parent = reticle
local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0.5, 0); dc.Parent = dot

----------------------------------------------------------------------
-- light / particle level of detail (phones and consoles only)
----------------------------------------------------------------------
local lodRange = touchOnly and 220 or (consoleOnly and 400 or nil)
local lights = {}
local function trackLight(d)
	if (d:IsA("PointLight") or d:IsA("SpotLight")) and d.Enabled then
		lights[d] = true -- only lights that are ON by design are managed (a muzzle flash light that is off stays off)
	end
end
if lodRange then
	for _, d in workspace:GetDescendants() do trackLight(d) end
	workspace.DescendantAdded:Connect(trackLight)
	workspace.DescendantRemoving:Connect(function(d) lights[d] = nil end)
end

local acc, lodAcc = 0, 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then return end
	acc = 0

	-- flight buttons on phones
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local fv = root and root:FindFirstChild("FlightVelocity")
	local flying = fv ~= nil and fv.Enabled
	if touchOnly then
		if flying then bindTouchButtons() else unbindTouchButtons() end
	end

	-- reticle for the gamepad
	local pad = UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
	reticle.Visible = pad and char ~= nil and char:FindFirstChildOfClass("Tool") ~= nil

	-- LOD
	if lodRange then
		lodAcc += 1
		if lodAcc % 2 == 0 then
			local cam = workspace.CurrentCamera
			local cp = cam and cam.CFrame.Position
			if cp then
				for l in lights do
					local parent = l.Parent
					if not parent then
						lights[l] = nil
					elseif parent:IsA("BasePart") then
						l.Enabled = (parent.Position - cp).Magnitude < lodRange
					end
				end
			end
		end
	end
end)
