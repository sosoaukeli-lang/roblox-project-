-- Main (Script) - server entry point. Builds the village, starts the services and
-- wires player join / leave. Every other piece of server logic lives in Services/.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

require(ReplicatedStorage.Shared.Remotes) -- creates the RemoteEvents before any client asks for them

local Services = ServerScriptService.Services
local MapBuilder = require(Services.MapBuilder)
local HouseService = require(Services.HouseService)
local DataService = require(Services.DataService)

local map = MapBuilder.Build()
HouseService.Init(map.Houses)
DataService.Init()

local function onPlayerAdded(player)
	-- The house comes first and without yielding, so RespawnLocation is set before
	-- the character spawns.
	if not HouseService.Assign(player) then
		player:Kick("السيرفر ممتلي، جرّب سيرفر ثاني.")
		return
	end

	-- Never let someone play without their real data: a later save would overwrite it.
	if not DataService.Load(player) and player.Parent then
		player:Kick("تعذر تحميل بياناتك، حاول مرة ثانية.")
	end
end

local function onPlayerRemoving(player)
	HouseService.Release(player)
	DataService.Unload(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
-- Players who joined before this script finished starting (Studio Play, slow loads).
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
