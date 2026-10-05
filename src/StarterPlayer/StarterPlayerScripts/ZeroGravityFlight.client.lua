-- ZeroGravityFlight (LocalScript)
-- The map has no gravity; the rocket interior has normal gravity.
--   * Inside the rocket: normal gravity, normal walking and jumping.
--   * Outside: you swim through the air. Leaving the rocket, JUMPING, or stepping off a ledge starts flying.
--   * Touch the ground while flying and you go back to walking normally. Jump again to fly again.
--
-- Controls while flying:
--   W / S            swim forward / backward (toward where the camera looks, including up and down)
--   A / D            move left / right
--   Space            move up          (gamepad: A)
--   Ctrl or C        move down        (gamepad: B)
--   Left Shift       boost

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Settings
local WALK_GRAVITY = 196.2        -- normal Roblox gravity (inside the rocket, and when walking on the ground)
local SPACE_GRAVITY = 0           -- gravity while flying
local FLY_SPEED = 55              -- studs per second
local BOOST_MULTIPLIER = 2.5      -- speed multiplier while holding Left Shift
local BOOST_MAX = 100             -- boost energy
local BOOST_DRAIN = 25            -- energy used per second while boosting  (100 / 25 = 4 seconds of boost)
local BOOST_RECHARGE = 14         -- energy gained per second while not boosting (about 7 seconds from empty to full)
local BOOST_RECHARGE_DELAY = 1.2  -- seconds after boosting before it starts to recharge
local BOOST_UNLOCK = 0.3          -- after running empty, boost needs this fraction of the bar before it works again
local ACCELERATION = 1.8          -- higher = snappier speed changes, lower = floatier
local IDLE_DRAG = 1.2             -- higher = you stop faster when no key is pressed
local TURN_RESPONSIVENESS = 12    -- higher = character turns faster
local MAX_ACCEL = 300             -- physics limit (studs/s^2) so speed changes never jolt
local EXIT_MARGIN = 10            -- studs past the rocket edge before it counts as outside (avoids flicker at the door)
local TAKEOFF_LIFT = 30           -- upward speed you get when you jump into flight
local MIN_FLIGHT_TIME = 0.5       -- seconds after takeoff before landing is allowed
local FALL_TO_FLY_DELAY = 0.35    -- seconds in the air while walking outside before you fly instead of falling
local LAND_EXTRA_DISTANCE = 0.75  -- how close to the ground counts as touching it

-- Roblox's default swimming animations, played while flying
local SWIM_MOVE_ID = "rbxassetid://913402848"
local SWIM_IDLE_ID = "rbxassetid://913384386"
local PROCEDURAL_POSE = true      -- true: the FlightPose script poses the body while flying (no swim animation)
local SWIM_ANIM_MIN_SPEED = 0.7   -- slowest swim-stroke playback
local SWIM_ANIM_MAX_SPEED = 1.8   -- fastest swim-stroke playback

-- Rocket interior shape: a cylinder lying along Z, sized from the Rocket.Floor part
local AXIS_HEIGHT_ABOVE_FLOOR_CENTER = 7.5 -- cylinder axis sits this far above the middle of the Floor part

local rocket = workspace:WaitForChild("Rocket")

-- Optional: use Roblox's default controls (thumbstick, gamepad) when the PlayerModule exists.
-- WASD works either way, so a missing PlayerModule never blocks the script.
local controls = nil
task.spawn(function()
	local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
	if playerModule then
		local ok, result = pcall(require, playerModule)
		if ok then
			controls = result:GetControls()
		end
	end
end)

local function isInsideRocket(position, wasInside)
	local floor = rocket:FindFirstChild("Floor")
	if not floor then
		return false
	end

	-- Uses the floor's live CFrame so it keeps working while the rocket hovers
	local rel = floor.CFrame:PointToObjectSpace(position)
	local margin = wasInside and EXIT_MARGIN or 0

	local radius = floor.Size.X / 2 + margin
	local halfLength = floor.Size.Z / 2 + margin
	local dy = rel.Y - AXIS_HEIGHT_ABOVE_FLOOR_CENTER

	return math.abs(rel.Z) <= halfLength and (rel.X * rel.X + dy * dy) <= radius * radius
end

-- Alien ship interior: a big round room (radius ~198) that is ~72 studs tall, with normal gravity inside
local function isInsideShip(position, wasInside)
	local ship = workspace:FindFirstChild("AlienShip")
	local zone = ship and ship:FindFirstChild("InteriorZone")
	if not zone then
		return false
	end

	local rel = zone.CFrame:PointToObjectSpace(position)
	local margin = wasInside and EXIT_MARGIN or 0
	local radius = zone.Size.X / 2 + margin

	return (rel.X * rel.X + rel.Z * rel.Z) <= radius * radius and math.abs(rel.Y) <= zone.Size.Y / 2 + margin
end

local humanoid, root, attachment, align, linear, moveTrack, idleTrack
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local smoothVelocity = Vector3.zero
local inside = nil          -- nil until the first check after spawning
local flying = false
local flightStart = 0
local airTime = 0
local lastFacing = Vector3.new(0, 0, -1)
local boostEnergy = BOOST_MAX
local boostLocked = false
local lastDrainT = 0
player:GetAttributeChangedSignal("BoostRefill"):Connect(function()
	boostEnergy = BOOST_MAX -- ENERGY CELL (bought with Robux): full bar, no lock
	boostLocked = false
end)

-- the boost bar recharges by itself (also while walking / inside the rocket)
RunService.Heartbeat:Connect(function(dt)
	if os.clock() - lastDrainT > BOOST_RECHARGE_DELAY and boostEnergy < BOOST_MAX then
		boostEnergy = math.min(BOOST_MAX, boostEnergy + BOOST_RECHARGE * dt)
		if boostLocked and boostEnergy >= BOOST_MAX * BOOST_UNLOCK then
			boostLocked = false
		end
	end
	player:SetAttribute("BoostEnergy", boostEnergy / BOOST_MAX)
	player:SetAttribute("BoostLocked", boostLocked)
end)

local function startFlying(lift)
	if flying then
		return
	end
	flying = true
	flightStart = os.clock()
	airTime = 0

	workspace.Gravity = SPACE_GRAVITY
	local v = root.AssemblyLinearVelocity
	smoothVelocity = Vector3.new(v.X, math.max(v.Y, lift or 0), v.Z) -- keep momentum, add lift on takeoff
	linear.VectorVelocity = smoothVelocity
	linear.Enabled = true
	align.Enabled = true
	humanoid.PlatformStand = true
end

local function stopFlying(land)
	workspace.Gravity = WALK_GRAVITY
	if not flying then
		return
	end
	flying = false
	linear.Enabled = false
	align.Enabled = false
	player:SetAttribute("FlightLanding", 0)
	moveTrack:Stop(0.2)
	idleTrack:Stop(0.2)
	humanoid.PlatformStand = false
	if land then
		-- TOUCHDOWN: the body was flying flat, so just letting go made it hit the ground lying down and bounce up.
		-- Stand it up with the feet exactly on the floor, and take most of the dive speed away.
		local pos = root.Position
		local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), rayParams)
		if hit then
			pos = hit.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
		end
		root.CFrame = CFrame.lookAt(pos, pos + lastFacing)
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X * 0.35, 0, v.Z * 0.35)
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid:ChangeState(Enum.HumanoidStateType.Landed)
	else
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function nearGround()
	local reach = humanoid.HipHeight + root.Size.Y / 2 + LAND_EXTRA_DISTANCE
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams) ~= nil
end

local function setupCharacter(character)
	humanoid = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")
	rayParams.FilterDescendantsInstances = { character }

	attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = root

	align = Instance.new("AlignOrientation")
	align.Name = "FlightOrientation"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.Responsiveness = TURN_RESPONSIVENESS
	align.MaxTorque = math.huge
	align.Enabled = false
	align.Parent = root

	-- Physics-driven movement: the engine moves the character toward our smoothed target speed
	linear = Instance.new("LinearVelocity")
	linear.Name = "FlightVelocity"
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	linear.MaxForce = 0
	linear.Enabled = false
	linear.Parent = root

	-- Swimming animations for use while flying
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local function loadTrack(id, name)
		local animation = Instance.new("Animation")
		animation.Name = name
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		return track
	end
	moveTrack = loadTrack(SWIM_MOVE_ID, "FlySwim")
	idleTrack = loadTrack(SWIM_IDLE_ID, "FlySwimIdle")

	flying = false
	inside = nil
	airTime = 0
	boostEnergy = BOOST_MAX -- a new life starts with a full boost bar
	boostLocked = false
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then
	setupCharacter(player.Character)
end

-- Jumping outside the rocket launches you into flight
UserInputService.JumpRequest:Connect(function()
	if humanoid and root and humanoid.Health > 0 and not flying and inside == false then
		startFlying(TAKEOFF_LIFT)
	end
end)

local function isDown(key)
	return UserInputService:IsKeyDown(key)
end

-- A cinematic (ship arrival / machine upgrade) freezes steering while it plays.
-- Failsafe: if that flag ever gets stuck, steering comes back by itself after 15 seconds.
local cinematicSince = nil
local function cinematicActive()
	if player:GetAttribute("InCinematic") then
		cinematicSince = cinematicSince or os.clock()
		return os.clock() - cinematicSince < 15
	end
	cinematicSince = nil
	return false
end

RunService.RenderStepped:Connect(function(dt)
	if not (humanoid and root and root.Parent and humanoid.Health > 0) then
		return
	end

	-- Inside the rocket you always walk; leaving it starts flying
	local nowInside = isInsideRocket(root.Position, inside == true) or isInsideShip(root.Position, inside == true)
	if nowInside ~= inside then
		inside = nowInside
		if inside then
			stopFlying()
		else
			startFlying(0)
		end
	end

	if inside then
		return -- normal walking, Roblox handles it
	end

	if not flying then
		-- Walking on the ground outside: if you drop off an edge, fly instead of falling
		if humanoid.FloorMaterial == Enum.Material.Air then
			airTime += dt
			if airTime >= FALL_TO_FLY_DELAY then
				startFlying(0)
			end
		else
			airTime = 0
		end
		return
	end

	-- Free flight
	local cam = workspace.CurrentCamera
	local move = Vector3.zero -- x = right, z = back
	if controls then
		move = controls:GetMoveVector()
	end
	if move.Magnitude < 0.01 and UserInputService:GetFocusedTextBox() == nil then
		move = Vector3.new(
			(isDown(Enum.KeyCode.D) and 1 or 0) - (isDown(Enum.KeyCode.A) and 1 or 0),
			0,
			(isDown(Enum.KeyCode.S) and 1 or 0) - (isDown(Enum.KeyCode.W) and 1 or 0)
		)
	end
	local cinematic = cinematicActive()
	if cinematic then
		move = Vector3.zero -- no steering while a cinematic is playing
	end
	local dir = cam.CFrame.RightVector * move.X + cam.CFrame.LookVector * -move.Z

	local boosting = false
	if UserInputService:GetFocusedTextBox() == nil and not cinematic then
		local vertical = 0
		if isDown(Enum.KeyCode.Space) or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA) or player:GetAttribute("VirtUp") == true then
			vertical += 1
		end
		if isDown(Enum.KeyCode.LeftControl) or isDown(Enum.KeyCode.C) or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonB) or player:GetAttribute("VirtDown") == true then
			vertical -= 1
		end
		dir += Vector3.yAxis * vertical
		boosting = isDown(Enum.KeyCode.LeftShift) or player:GetAttribute("VirtBoost") == true
	end

	-- the boost has a LIMIT: it drains the bar while you boost; when the bar is empty the boost shuts off until it recharges
	if boosting and not boostLocked and boostEnergy > 0 and dir.Magnitude > 0.01 then
		boostEnergy = math.max(0, boostEnergy - BOOST_DRAIN * dt)
		lastDrainT = os.clock()
		if boostEnergy <= 0 then
			boostLocked = true
		end
	else
		boosting = false
	end
	player:SetAttribute("Boosting", boosting)

	if dir.Magnitude > 0.01 then
		local target = dir.Unit * FLY_SPEED * (boosting and BOOST_MULTIPLIER or 1)
		smoothVelocity = smoothVelocity:Lerp(target, 1 - math.exp(-ACCELERATION * dt))
	else
		smoothVelocity = smoothVelocity:Lerp(Vector3.zero, 1 - math.exp(-IDLE_DRAG * dt))
	end
	-- weapon recoil in zero gravity: each shot pushes you back a little (set by WeaponClient)
	local kickV = player:GetAttribute("FlightKick")
	if kickV and (kickV.X ~= kickV.X or kickV.Y ~= kickV.Y or kickV.Z ~= kickV.Z or kickV.Magnitude > 400) then
		player:SetAttribute("FlightKick", nil)
		kickV = nil
	end
	if kickV then
		smoothVelocity += kickV
		player:SetAttribute("FlightKick", nil)
	end

	-- LANDING FLARE: when you dive toward the ground the body straightens up and the descent slows,
	-- so you arrive feet-first at a speed the ground can take (instead of hitting it flat at full speed)
	local landing = 0
	if smoothVelocity.Y < -6 then
		local flareDist = 16 + (-smoothVelocity.Y) * 0.22
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -(flareDist + 4), 0), rayParams)
		if hit then
			local dist = hit.Distance
			local reach = humanoid.HipHeight + root.Size.Y / 2 + LAND_EXTRA_DISTANCE
			if dist < flareDist then
				landing = 1 - dist / flareDist
				local maxDown = -(7 + math.max(0, dist - reach) * 2.4)
				if smoothVelocity.Y < maxDown then
					smoothVelocity = Vector3.new(smoothVelocity.X, maxDown, smoothVelocity.Z)
				end
				local keep = math.exp(-landing * 5 * dt)
				smoothVelocity = Vector3.new(smoothVelocity.X * keep, smoothVelocity.Y, smoothVelocity.Z * keep)
			end
		end
	end
	player:SetAttribute("FlightLanding", landing)
	align.Responsiveness = landing > 0 and 26 or TURN_RESPONSIVENESS

	linear.VectorVelocity = smoothVelocity
	linear.MaxForce = root.AssemblyMass * MAX_ACCEL

	-- Touching the ground (and not rising) ends flight and lets you walk normally
	if os.clock() - flightStart > MIN_FLIGHT_TIME and smoothVelocity.Y <= 5 and nearGround() then
		stopFlying(true)
		return
	end

	-- Swim animation: strokes while moving, treading water while hovering
	local speed = smoothVelocity.Magnitude
	if PROCEDURAL_POSE then
		if moveTrack.IsPlaying then moveTrack:Stop(0.15) end
		if idleTrack.IsPlaying then idleTrack:Stop(0.15) end
	elseif speed > 3 then
		if idleTrack.IsPlaying then
			idleTrack:Stop(0.25)
		end
		if not moveTrack.IsPlaying then
			moveTrack:Play(0.25)
		end
		moveTrack:AdjustSpeed(math.clamp(speed / 25, SWIM_ANIM_MIN_SPEED, SWIM_ANIM_MAX_SPEED))
	else
		if moveTrack.IsPlaying then
			moveTrack:Stop(0.25)
		end
		if not idleTrack.IsPlaying then
			idleTrack:Play(0.25)
		end
	end

	-- Orientation: lie flat like a swimmer while moving (head toward travel direction, face down);
	-- stand upright facing the camera when hovering
	local look = cam.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.05 then
		lastFacing = flat.Unit
	end

	if speed > 3 then
		local forward = smoothVelocity.Unit
		local down = Vector3.new(0, -1, 0)
		local perpendicularDown = down - forward * down:Dot(forward)
		local front = perpendicularDown.Magnitude > 0.2 and perpendicularDown.Unit or lastFacing
		local back = -front
		align.CFrame = CFrame.fromMatrix(Vector3.zero, forward:Cross(back), forward, back) * CFrame.Angles(0, player:GetAttribute("FlightBank") or 0, 0)
	else
		align.CFrame = CFrame.lookAt(Vector3.zero, lastFacing)
	end
	if landing > 0 then
		align.CFrame = align.CFrame:Lerp(CFrame.lookAt(Vector3.zero, lastFacing), math.clamp(landing * 1.8, 0, 1))
	end
end)
