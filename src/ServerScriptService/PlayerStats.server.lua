-- TEST MODE: extra starting resources so you can try the weapon forge right away.
-- When you are done testing, set these back to 150 and 0.
local START_MONEY = 100000
local START_IRON = 500

game.Players.PlayerAdded:Connect(function(player)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then
        leaderstats = Instance.new("Folder")
        leaderstats.Name = "leaderstats"
        leaderstats.Parent = player
    end

    if not leaderstats:FindFirstChild("Money") then
        local money = Instance.new("IntValue")
        money.Name = "Money"
        money.Value = START_MONEY
        money.Parent = leaderstats
    end

    if not leaderstats:FindFirstChild("Iron") then
        local iron = Instance.new("IntValue")
        iron.Name = "Iron"
        iron.Value = START_IRON
        iron.Parent = leaderstats
    end
end)
