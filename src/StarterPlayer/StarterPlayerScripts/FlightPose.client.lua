-- FlightPose (LocalScript)
-- Poses the body while you fly, instead of the stiff swimming animation. Everything is driven by your speed:
--   * HOVERING   : upright, arms floating slightly out and swaying, legs dangling and bobbing, gentle zero-g drift
--   * CRUISING   : a superhero pose - body flat, both arms stretched out in front, head lifted to look ahead,
--                  legs together trailing behind with a light flutter
--   * BOOSTING   : arms swept back along the sides, body streamlined, a fast tremble from the wind
--   * TURNING    : the whole body banks into turns (and when you strafe), the chest twists a little
-- The joints are moved smoothly (no snapping), and everything goes back to normal when you land or enter the rocket.
-- (R15 characters. The flight itself - speed, direction, orientation - is still done by ZeroGravityFlight.)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local PI = math.pi

local char, hum, root
local joints = {}
local animate = nil

local JOINT_NAMES = { "RootJoint", "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightHip", "LeftHip", "RightKnee", "LeftKnee" }

local function setupCharacter(character)
	char = character
	hum = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")
	joints = {}
	animate = nil
	if hum.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	character:WaitForChild("LowerTorso", 10)
	character:WaitForChild("RightUpperArm", 10)
	character:WaitForChild("RightLowerLeg", 10)
	for _, n in JOINT_NAMES do
		local m = character:FindFirstChild(n, true)
		if m and m:IsA("Motor6D") then
			joints[n] = { motor = m, base = m.C0, kind = "motor" }
		elseif m and m:IsA("AnimationConstraint") then
			joints[n] = { motor = m, kind = "anim" } -- new-style joints: posed through their Transform
		end
	end
end
player.CharacterAdded:Connect(setupCharacter)
if player.Character then
	task.spawn(setupCharacter, player.Character)
end

local function lerp(a, b, t) return a + (b - a) * t end
local function clamp01(x) return math.clamp(x, 0, 1) end

-- smoothed pose values
local S = { armAngle = 0.45, elbow = 0.2, hipSpread = 0.1, knee = 0.2, neck = 0, waist = 0, bank = 0, twist = 0, flutter = 0, tremble = 0 }
local function approach(key, target, dt, rate)
	S[key] += (target - S[key]) * (1 - math.exp(-rate * dt))
end

local wasPosed = false
local function setAnimateEnabled(on)
	animate = animate or (char and char:FindFirstChild("Animate"))
	if animate then
		animate.Enabled = on
	end
end
local function restore()
	for _, j in joints do
		if j.motor.Parent then
			if j.kind == "anim" then
				j.motor.Transform = CFrame.new()
			else
				j.motor.C0 = j.base
			end
		end
	end
	player:SetAttribute("FlightBank", 0)
	if wasPosed then
		setAnimateEnabled(true)
	end
	wasPosed = false
end

local function apply(name, offset)
	local j = joints[name]
	if j and j.motor.Parent then
		if j.kind == "anim" then
			j.motor.Transform = offset
		else
			j.motor.C0 = j.base * offset
		end
	end
end

local t = 0
local smoothSpeed = 0
local lastLook = nil
-- (after the animation step and before physics, so the animator cannot reset the pose we write)
RunService.PreSimulation:Connect(function(dt)
	t += dt
	if not (char and root and root.Parent and hum and hum.Health > 0) or next(joints) == nil then
		return
	end
	local fv = root:FindFirstChild("FlightVelocity")
	local flying = fv ~= nil and fv.Enabled and workspace.Gravity < 1
	if not flying then
		if wasPosed then
			restore()
			for k, v in { armAngle = 0.45, elbow = 0.2, hipSpread = 0.1, knee = 0.2, neck = 0, waist = 0, bank = 0, twist = 0, flutter = 0, tremble = 0 } do S[k] = v end
		end
		lastLook = nil
		return
	end

	-- while flying: no walking / swimming animations, we pose the joints ourselves
	if not wasPosed then
		wasPosed = true
		setAnimateEnabled(false)
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, tr in animator:GetPlayingAnimationTracks() do
			tr:Stop(0.1)
		end
	end

	local velocity = root.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	smoothSpeed += (speed - smoothSpeed) * (1 - math.exp(-6 * dt))
	local s = smoothSpeed
	local cam = workspace.CurrentCamera
	local boosting = player:GetAttribute("Boosting") == true

	-- how far the body is "flat" (cruising) vs upright (hovering)
	local flat = clamp01((s - 3) / 9)
	local cruise = clamp01((s - 3) / 12)
	local fast = clamp01((s - 70) / 55)
	local land = player:GetAttribute("FlightLanding") or 0

	-- arms: float out -> stretch forward -> sweep back when really fast
	local armTarget
	if s < 15 then
		armTarget = lerp(0.45, PI - 0.2, clamp01((s - 3) / 12))
	else
		armTarget = lerp(PI - 0.2, 0.14, fast)
	end
	armTarget = lerp(armTarget, 1.0, land)
	approach("armAngle", armTarget, dt, 6 + 8 * land)
	approach("elbow", lerp(0.25, 0.08, cruise) + 0.1 * fast, dt, 6)
	approach("hipSpread", lerp(0.12, 0.03, cruise), dt, 5)
	approach("knee", lerp(lerp(0.25, 0.1, cruise) + 0.1 * fast, 0.75, land), dt, 5 + 6 * land)
	approach("neck", flat * lerp(0.95, 0.55, fast) * (1 - land), dt, 5 + 6 * land)
	approach("waist", flat * lerp(0.25, 0.05, fast) * (1 - land) - 0.2 * land, dt, 5 + 6 * land)
	approach("flutter", cruise * (1 - fast * 0.6), dt, 4)
	approach("tremble", boosting and 1 or fast * 0.5, dt, 5)

	-- banking and chest twist from turning and strafing
	local bankTarget, twistTarget = 0, 0
	if cam then
		local look = cam.CFrame.LookVector
		local turnRate = 0
		if lastLook then
			turnRate = (lastLook.X * look.Z - lastLook.Z * look.X) / math.max(dt, 1e-3)
		end
		lastLook = look
		local lateral = velocity:Dot(cam.CFrame.RightVector)
		bankTarget = math.clamp(lateral * 0.011 + turnRate * 0.22, -0.65, 0.65) * flat
		twistTarget = math.clamp(turnRate * 0.12, -0.3, 0.3) * flat
	end
	approach("bank", bankTarget, dt, 5)
	approach("twist", twistTarget, dt, 6)

	-- gentle drift when hovering, a tremble when boosting
	local drift = (1 - flat)
	local sway = math.sin(t * 1.3) * 0.07 * drift
	local tr = S.tremble * 0.035
	local trem = function(k) return math.sin(t * 42 + k) * tr end

	local a = S.armAngle
	apply("RightShoulder", CFrame.Angles(0, 0, a + sway + trem(1)) * CFrame.Angles(trem(2), 0, 0))
	apply("LeftShoulder", CFrame.Angles(0, 0, -(a - sway) - trem(3)) * CFrame.Angles(trem(4), 0, 0))
	apply("RightElbow", CFrame.Angles(S.elbow + 0.05 * math.sin(t * 1.7) * drift, 0, 0))
	apply("LeftElbow", CFrame.Angles(S.elbow + 0.05 * math.sin(t * 1.9 + 1) * drift, 0, 0))

	-- legs: flutter while cruising, slow dangle while hovering
	local fl = S.flutter * 0.08
	local legR = math.sin(t * 7) * fl + math.sin(t * 1.1) * 0.08 * drift + 0.5 * land
	local legL = math.sin(t * 7 + PI) * fl + math.sin(t * 1.1 + 1.5) * 0.08 * drift + 0.5 * land
	apply("RightHip", CFrame.Angles(legR, 0, S.hipSpread * -1 + trem(5)))
	apply("LeftHip", CFrame.Angles(legL, 0, S.hipSpread + trem(6)))
	apply("RightKnee", CFrame.Angles(-(S.knee + math.max(0, math.sin(t * 7)) * fl * 0.5), 0, 0))
	apply("LeftKnee", CFrame.Angles(-(S.knee + math.max(0, math.sin(t * 7 + PI)) * fl * 0.5), 0, 0))

	-- spine, head, roll
	apply("Waist", CFrame.Angles(S.waist, S.twist, 0))
	apply("Neck", CFrame.Angles(S.neck + trem(7), -S.twist * 0.8, 0))
	player:SetAttribute("FlightBank", S.bank)
end)
