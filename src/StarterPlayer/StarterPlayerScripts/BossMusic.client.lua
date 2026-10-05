-- BossMusic (LocalScript) - the boss theme: "See You In Hell" plays for the WHOLE fight. It gets louder and a little faster with each
-- phase (II, III) and fades out after the victory or when the ship retreats. The normal background music is turned down meanwhile.
--
-- TO USE ANOTHER SONG: replace SONG_ID (Creator Store > Audio; the audio must be public or yours).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local SONG_ID = 1837853076 -- See You In Hell (APM Music, Creator Store)
local VOLUME = { 1.0, 1.15, 1.3 }
local SPEED = { 1.0, 1.04, 1.09 }

local player = Players.LocalPlayer
local ev = RS:WaitForChild("MothershipEvent")
local sound, playing = nil, false

local group = Instance.new("SoundGroup")
group.Name = "BossMusic"
group.Volume = 1
group.Parent = SoundService
local eq = Instance.new("EqualizerSoundEffect") -- extra punch: more bass, more crunch
eq.LowGain = 4
eq.MidGain = 1
eq.HighGain = 2
eq.Parent = group
local comp = Instance.new("CompressorSoundEffect") -- louder, denser
comp.Threshold = -18
comp.Ratio = 4
comp.Parent = group

local function stopMusic(fade)
	playing = false
	player:SetAttribute("BossMusic", nil)
	local s = sound
	sound = nil
	if s then
		TweenService:Create(s, TweenInfo.new(fade or 3), { Volume = 0 }):Play()
		Debris:AddItem(s, (fade or 3) + 0.2)
	end
end

ev.OnClientEvent:Connect(function(kind, a)
	if kind == "bossIntro" then
		playing = true
		player:SetAttribute("BossMusic", true) -- the normal music ducks
		task.delay(2.2, function()
			if playing and not sound then
				local s = Instance.new("Sound")
				s.Name = "BossTrack"
				s.SoundId = "rbxassetid://" .. SONG_ID
				s.Volume = 0
				s.PlaybackSpeed = SPEED[1]
				s.Looped = true
				s.SoundGroup = group
				s.Parent = SoundService
				s:Play()
				TweenService:Create(s, TweenInfo.new(2.5), { Volume = VOLUME[1] }):Play()
				sound = s
			end
		end)
	elseif kind == "phase" and playing and sound then
		local ph = math.clamp(a or 2, 1, 3)
		TweenService:Create(sound, TweenInfo.new(1.0), { Volume = VOLUME[ph], PlaybackSpeed = SPEED[ph] }):Play()
	elseif kind == "bossDeath" then
		stopMusic(2.5)
	elseif kind == "retreat" then
		stopMusic(3)
	end
end)
