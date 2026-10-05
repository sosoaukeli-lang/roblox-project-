-- ItemFX (LocalScript)
-- The client side of the passive items:
--   * ORACLE HORNS: every alien glows through walls (an x-ray outline) and its health bar shows from far away
-- (the trails are drawn by FlightFX; the burn / slow / crown effects are done by the server)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local C3 = Color3.fromRGB

local highlights = {} -- [alien model] = Highlight
local function hasHorns()
	return player:GetAttribute("PassiveId") == "OracleHorns"
end

local function applyTo(alien)
	if not alien:IsA("Model") then return end
	if hasHorns() then
		if not highlights[alien] then
			local h = Instance.new("Highlight")
			h.Name = "OracleSight"
			h.Adornee = alien
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.FillColor = C3(255, 60, 90)
			h.FillTransparency = 0.72
			h.OutlineColor = C3(255, 230, 120)
			h.OutlineTransparency = 0.1
			h.Parent = alien
			highlights[alien] = h
		end
		local root = alien.PrimaryPart or alien:FindFirstChild("HumanoidRootPart")
		local hp = root and root:FindFirstChild("HP")
		if hp then
			hp.AlwaysOnTop = true
			hp.MaxDistance = 600
		end
	else
		local h = highlights[alien]
		if h then
			h:Destroy()
			highlights[alien] = nil
		end
		local root = alien.PrimaryPart or alien:FindFirstChild("HumanoidRootPart")
		local hp = root and root:FindFirstChild("HP")
		if hp and not alien:GetAttribute("Titan") then
			hp.AlwaysOnTop = false
		end
	end
end

local function watch(folder)
	for _, a in folder:GetChildren() do applyTo(a) end
	folder.ChildAdded:Connect(function(a)
		task.wait(0.2)
		applyTo(a)
	end)
end
task.spawn(function()
	watch(workspace:WaitForChild("XenoAliens"))
end)
player:GetAttributeChangedSignal("PassiveId"):Connect(function()
	local folder = workspace:FindFirstChild("XenoAliens")
	if folder then
		for _, a in folder:GetChildren() do applyTo(a) end
	end
end)

-- clean up highlights of aliens that are gone, and keep applying the sight (health bars stream in a little later)
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	for alien, h in highlights do
		if not alien.Parent then
			highlights[alien] = nil
		end
	end
	acc += dt
	if acc > 1.5 then
		acc = 0
		local folder = workspace:FindFirstChild("XenoAliens")
		if folder and hasHorns() then
			for _, a in folder:GetChildren() do applyTo(a) end
		end
	end
end)

----------------------------------------------------------------------
-- the ship's display pieces: item holograms circling the shop alien, and the spinning hive map in Mission Control
----------------------------------------------------------------------
task.spawn(function()
	local ship = workspace:WaitForChild("AlienShip")
	local holos = ship:WaitForChild("ShopHolos", 20)
	local mapModel = ship:WaitForChild("MissionHolo", 20)
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		local pivot = ship:GetPivot()
		local cam = workspace.CurrentCamera
		if holos and cam and (cam.CFrame.Position - pivot.Position).Magnitude < 260 then
			local center = holos:GetAttribute("LocalCenter") or Vector3.new(-16, 9.5, -85)
			local radius = holos:GetAttribute("Radius") or 10.5
			for _, m in holos:GetChildren() do
				local core = m.PrimaryPart
				if core then
					local phase = m:GetAttribute("Phase") or 0
					local a = phase + t * 0.5
					local lp = center + Vector3.new(math.cos(a) * radius, math.sin(t * 1.3 + phase) * 0.7, math.sin(a) * radius)
					local cf = pivot * CFrame.new(lp)
					core.CFrame = cf * CFrame.Angles(0, -a, 0) * CFrame.Angles(t * 1.2, 0, 0)
					local glow = m:FindFirstChild("Glow")
					if glow then glow.CFrame = cf end
				end
			end
		end
		if mapModel and mapModel.PrimaryPart then
			local c = mapModel:GetAttribute("SpinLocal") or Vector3.new(0, 7.4, 70)
			mapModel:PivotTo(pivot * CFrame.new(c) * CFrame.Angles(0, t * 0.35, 0))
		end
	end)
end)
