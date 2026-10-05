-- RocketAmbience: the sound of being inside the rocket.
-- Inside: a low room tone + a deep drone, and a big-hall echo on every sound. Outside (in space): quiet.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local rocket = workspace:WaitForChild("Rocket")
local floor = rocket:WaitForChild("Floor") -- 232 wide, 458 long

local function loop(id, speed)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Looped = true
	s.Volume = 0
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	return s
end
local roomTone = loop(9125446543, 1) -- command-room tone / air conditioning hum
local drone = loop(9116328633, 1)    -- deep spaceship drone
local ROOM_VOLUME, DRONE_VOLUME = 0.28, 0.16

local inside = nil
local function setInside(value)
	if inside == value then
		return
	end
	inside = value
	local info = TweenInfo.new(1.2)
	TweenService:Create(roomTone, info, { Volume = value and ROOM_VOLUME or 0 }):Play()
	TweenService:Create(drone, info, { Volume = value and DRONE_VOLUME or 0.03 }):Play()
	SoundService.AmbientReverb = value and Enum.ReverbType.Hangar or Enum.ReverbType.NoReverb
end

while true do
	task.wait(0.25)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local rel = floor.CFrame:PointToObjectSpace(root.Position)
		setInside(math.abs(rel.X) < 118 and math.abs(rel.Z) < floor.Size.Z / 2 + 10 and rel.Y > -12 and rel.Y < 135)
	end
end
