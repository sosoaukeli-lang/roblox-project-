-- TestGiveWeapons (Script) - FOR TESTING ONLY: gives every player all 17 boss-chest weapons each time they spawn.
-- Set GIVE_ALL to false (or delete this script) before publishing, otherwise nobody needs the chest!
local GIVE_ALL = true

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Loot = require(game:GetService("ReplicatedStorage"):WaitForChild("Loot"))
local weapons = ServerStorage:WaitForChild("Weapons")

local function give(player)
	local backpack = player:WaitForChild("Backpack", 15)
	if not backpack then return end
	task.wait(2.5) -- after the saved weapons were restored
	for _, id in Loot.Order do
		local name = Loot.Weapons[id].tool
		local tpl = weapons:FindFirstChild(name)
		if tpl and not backpack:FindFirstChild(name) and not (player.Character and player.Character:FindFirstChild(name)) then
			tpl:Clone().Parent = backpack
		end
	end
end

if GIVE_ALL then
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function() task.spawn(give, player) end)
	end)
	for _, p in Players:GetPlayers() do
		p.CharacterAdded:Connect(function() task.spawn(give, p) end)
		task.spawn(give, p)
	end
end
