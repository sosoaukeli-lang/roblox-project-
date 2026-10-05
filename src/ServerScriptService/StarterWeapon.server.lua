-- StarterWeapon (Script)
-- Every player gets a free, very weak "Starter Blaster" every time they spawn (5 damage a shot, 0.5 s apart).
-- It is weak on purpose - an alien has 120 health - but it is enough to start killing aliens for $30 each.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local template = ServerStorage:WaitForChild("Weapons"):WaitForChild("Starter Blaster")
local notifyRemote = ReplicatedStorage:FindFirstChild("ShipNotify")
local told = {}

local function give(player)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack then
		return
	end
	local has = backpack:FindFirstChild("Starter Blaster") or (player.Character and player.Character:FindFirstChild("Starter Blaster"))
	if not has then
		template:Clone().Parent = backpack
		if notifyRemote and not told[player] then
			told[player] = true
			notifyRemote:FireClient(player, "You got a free Starter Blaster (weak) - press its number to equip it and hunt the aliens!")
		end
	end
end

local function track(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.6)
		give(player)
	end)
	if player.Character then
		task.spawn(give, player)
	end
end
Players.PlayerAdded:Connect(track)
for _, p in Players:GetPlayers() do
	track(p)
end
Players.PlayerRemoving:Connect(function(p)
	told[p] = nil
end)
