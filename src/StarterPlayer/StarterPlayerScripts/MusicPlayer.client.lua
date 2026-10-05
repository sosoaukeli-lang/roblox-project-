-- MusicPlayer (LocalScript)
-- Background music that fits the place, kept well below the sound effects:
--   * three moods, picked by where you are, with a smooth cross-fade between them:
--       inside the ROCKET  : retro-synth tracks (energetic but calm)
--       outside in SPACE   : deep ambient tracks
--       inside the ALIEN SHIP: dark synthwave
--   * tracks play one after another (shuffled) and cross-fade into each other
--   * the music ducks (gets quieter) during cinematics and the weapon / machine reveals, so effects stay clear
--   * press M to turn the music off / on
-- All tracks are free music by DistrokidOfficial from the Creator Store.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local rng = Random.new()

-- how loud each mood plays (1.0 = the track's full volume). Effects are louder than this on purpose.
local PLAYLISTS = {
	rocket = {
		level = 0.26,
		tracks = { 126815257129625, 95892812028438, 112608727509905 }, -- Retro Space Station, Neon Android Dreams, Retro Sci-Fi Skyline
	},
	space = {
		level = 0.34,
		tracks = { 140533822783920, 136827064604146, 102039057339088, 140041908508788 }, -- Space Ambient, Deep Space Ocean, Zero Gravity, Slow Breathing Aurora
	},
	ship = {
		level = 0.28,
		tracks = { 133934204383081, 102039057339088 }, -- Deep Night Synthwave, Zero Gravity
	},
}
local FADE = 3.5 -- seconds for every cross-fade

-- wait until the loading screen is gone
while playerGui:FindFirstChild("AlienLoading") do
	task.wait(0.5)
end
task.wait(0.5)

local group = Instance.new("SoundGroup")
group.Name = "Music"
group.Volume = 0
group.Parent = SoundService
-- a gentle EQ keeps the music out of the way of machine hums and effects
local eq = Instance.new("EqualizerSoundEffect")
eq.LowGain = -4
eq.MidGain = -2
eq.HighGain = -1
eq.Parent = group

local rocket = workspace:WaitForChild("Rocket")
local ship = workspace:WaitForChild("AlienShip")

local function zoneOf(pos)
	local rel = rocket:GetPivot():PointToObjectSpace(pos)
	local dy = rel.Y - 19.5
	if rel.Z > -112 and rel.Z < 348 and math.sqrt(rel.X * rel.X + dy * dy) < 118 then
		return "rocket"
	end
	local sp = ship:GetPivot():PointToObjectSpace(pos)
	if Vector3.new(sp.X, 0, sp.Z).Magnitude < 205 and sp.Y > -10 and sp.Y < 80 then
		return "ship"
	end
	return "space"
end

-- shuffled order per mood, never repeating the same track twice in a row
local queues = {}
local lastPlayed = {}
local function nextTrack(zone)
	local list = PLAYLISTS[zone].tracks
	local q = queues[zone]
	if not q or #q == 0 then
		q = table.clone(list)
		for i = #q, 2, -1 do
			local j = rng:NextInteger(1, i)
			q[i], q[j] = q[j], q[i]
		end
		if #q > 1 and q[#q] == lastPlayed[zone] then
			q[#q], q[1] = q[1], q[#q]
		end
		queues[zone] = q
	end
	local id = table.remove(q)
	lastPlayed[zone] = id
	return id
end

local current = nil -- { sound = Sound, zone = string, level = number }
local function fadeTo(sound, volume, time, thenDestroy)
	local tw = TweenService:Create(sound, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Volume = volume })
	tw:Play()
	if thenDestroy then
		tw.Completed:Once(function()
			sound:Stop()
			sound:Destroy()
		end)
	end
end

local function startTrack(zone)
	local level = PLAYLISTS[zone].level
	local s = Instance.new("Sound")
	s.Name = "MusicTrack"
	s.SoundId = "rbxassetid://" .. nextTrack(zone)
	s.Volume = 0
	s.Looped = false
	s.SoundGroup = group
	s.Parent = SoundService
	s:Play()
	fadeTo(s, level, FADE)
	local old = current
	current = { sound = s, zone = zone, level = level }
	if old and old.sound.Parent then
		fadeTo(old.sound, 0, FADE, true)
	end
end

-- ducking + mute
local muted = false
local duckUntil = 0
local function duck(seconds)
	duckUntil = math.max(duckUntil, os.clock() + seconds)
end
local fxRemote = ReplicatedStorage:FindFirstChild("WeaponFX") or ReplicatedStorage:WaitForChild("WeaponFX", 10)
if fxRemote then
	fxRemote.OnClientEvent:Connect(function(kind)
		if kind == "evolve" then
			duck(6)
		elseif kind == "forgeStart" then
			duck(5)
		elseif kind == "forgeReveal" or kind == "weaponShow" then
			duck(7)
		end
	end)
end
player:GetAttributeChangedSignal("MusicToggle"):Connect(function()
	muted = not muted
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Music", Text = muted and "Music OFF" or "Music ON", Duration = 2.5 })
	end)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		muted = not muted
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Music",
				Text = muted and "Music OFF  (press M to turn it on)" or "Music ON",
				Duration = 2.5,
			})
		end)
	end
end)

-- the first track of the starting mood
local activeZone = zoneOf((player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position) or Vector3.zero)
startTrack(activeZone)

local pendingZone, pendingSince = nil, 0
local accum = 0
RunService.Heartbeat:Connect(function(dt)
	-- smooth master volume (mute / duck)
	local ducking = (os.clock() < duckUntil) or player:GetAttribute("InCinematic") == true or player:GetAttribute("BossMusic") == true
	local target = muted and 0 or (ducking and 0.42 or 1)
	group.Volume += (target - group.Volume) * math.min(dt * 3, 1)

	accum += dt
	if accum < 0.25 then
		return
	end
	accum = 0

	-- which mood fits where I am (a new mood must hold for 1.5 s, so walking through a door does not flicker)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local z = zoneOf(root.Position)
		if z ~= activeZone then
			if pendingZone ~= z then
				pendingZone, pendingSince = z, os.clock()
			elseif os.clock() - pendingSince >= 1.5 then
				activeZone = z
				pendingZone = nil
				startTrack(z)
				return
			end
		else
			pendingZone = nil
		end
	end

	-- when the track is about to end, cross-fade into the next one of the same mood
	if current and current.sound.Parent and current.sound.IsLoaded and current.sound.TimeLength > 0 then
		if current.sound.TimePosition >= current.sound.TimeLength - FADE - 0.5 then
			startTrack(activeZone)
		end
	elseif current and not current.sound.Parent then
		startTrack(activeZone)
	end
end)
