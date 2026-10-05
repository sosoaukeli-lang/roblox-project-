local model = script.Parent
local collector = model:WaitForChild("Collector")
local dropper = model:WaitForChild("Dropper")
local upgradeBtn = model:WaitForChild("UpgradeButton")
local prompt = upgradeBtn:WaitForChild("ProximityPrompt")
local colLabel = collector:WaitForChild("BillboardGui"):WaitForChild("TextLabel")
local levelLabel = dropper:WaitForChild("BillboardGui"):WaitForChild("LevelLabel")

local level = 0
local maxLevel = 4
local pendingIron = 0

-- Costs and Drop Timers matching exactly what was requested
local costs = {100, 1000, 5000, 10000}
local times = {50, 40, 30, 20, 10}

-- 1) Collection Logic (Touch the green square)
local debounce = false
collector.Touched:Connect(function(hit)
    if debounce then return end
    local char = hit.Parent
    local player = game.Players:GetPlayerFromCharacter(char)
    if player and pendingIron > 0 then
        debounce = true
        local stats = player:FindFirstChild("leaderstats")
        if stats then
            local ironStat = stats:FindFirstChild("Iron")
            if ironStat then
                ironStat.Value = ironStat.Value + pendingIron
                pendingIron = 0
                colLabel.Text = pendingIron .. " Iron"
            end
        end
        task.wait(0.2)
        debounce = false
    end
end)

-- 2) Upgrade Logic (Interact with the blue button)
prompt.Triggered:Connect(function(player)
    if level >= maxLevel then return end

    local cost = costs[level + 1]
    local stats = player:FindFirstChild("leaderstats")
    if stats then
        local moneyStat = stats:FindFirstChild("Money")
        if moneyStat and moneyStat.Value >= cost then
            moneyStat.Value = moneyStat.Value - cost
            level = level + 1

            if level >= maxLevel then
                prompt.ObjectText = "MAX LEVEL"
                prompt.Enabled = false
                levelLabel.Text = "Iron Machine (MAX)\n" .. times[level + 1] .. "s / drop"
            else
                prompt.ObjectText = "Cost: " .. costs[level + 1] .. " Money"
                levelLabel.Text = "Iron Machine (Lv. " .. level .. ")\n" .. times[level + 1] .. "s / drop"
            end
        end
    end
end)

-- 3) Dropping Logic (Spawns a piece of iron that tweens to the collector)
task.spawn(function()
    while true do
        local waitTime = times[level + 1]
        task.wait(waitTime)

        -- Create a visual drop
        local drop = Instance.new("Part")
        drop.Size = Vector3.new(1.2, 1.2, 1.2)
        drop.Position = dropper.Position + Vector3.new(0, 1, 0)
        drop.BrickColor = BrickColor.new("Medium stone grey")
        drop.Material = Enum.Material.Metal
        drop.CanCollide = false
        drop.Anchored = true
        drop.Parent = model
        
        -- Tween the drop onto the collector pad
        local ts = game:GetService("TweenService")
        local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        local tween = ts:Create(drop, tweenInfo, {Position = collector.Position + Vector3.new(0, 1, 0)})
        tween:Play()
        tween.Completed:Wait()
        
        drop:Destroy()

        pendingIron = pendingIron + 1
        colLabel.Text = pendingIron .. " Iron"
    end
end)
