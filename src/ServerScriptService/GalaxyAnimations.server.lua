-- GalaxyAnimations: server-side cosmic ambience for the SpaceBackground
-- Twinkling stars, spinning galaxies/accretion disk, floating crystals, shooting stars

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local bg = workspace:FindFirstChild("SpaceBackground")
if not bg then
	bg = workspace:WaitForChild("SpaceBackground", 10)
	if not bg then return end
end

-- Collect pieces
local stars, spinners, crystals = {}, {}, {}
for _, part in bg:GetDescendants() do
	if part:IsA("BasePart") then
		if part.Name == "Star" then
			table.insert(stars, part)
		elseif part.Name:match("^Galaxy") or part.Name:match("^Accretion") or part.Name:match("^PlanetRing") then
			table.insert(spinners, {part = part, speed = part.Name:match("^Galaxy") and 0.15 or 0.5, base = part.CFrame})
		elseif part.Name:match("^Crystal") then
			table.insert(crystals, {part = part, base = part.CFrame, phase = math.random() * math.pi * 2, amp = 3 + math.random() * 4})
		end
	end
end

local rng = Random.new()

-- TWINKLE: periodically pulse a few random stars
local function twinkle()
	for _ = 1, 6 do
		local star = stars[rng:NextInteger(1, #stars)]
		if star and star.Parent then
			local goal = {Size = star.Size * 2.2}
			local t = TweenService:Create(star, TweenInfo.new(0.35, Enum.EasingStyle.Sine), goal)
			t:Play()
			t.Completed:Connect(function()
				if star.Parent then
				TweenService:Create(star, TweenInfo.new(0.5), {Size = goal.Size / 2.2}):Play()
				end
				end)
		end
	end
end

-- SHOOTING STARS: streak a glowing bolt across the sky then remove it
local shootingStars = {}
local function spawnShootingStar()
	local bolt = Instance.new("Part")
	bolt.Name = "ShootingStar"
	bolt.Material = Enum.Material.Neon
	bolt.Color = Color3.fromRGB(200, 170, 255)
	bolt.Size = Vector3.new(26, 1.2, 1.2)
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanTouch = false
	bolt.CanQuery = false
	bolt.CastShadow = false

	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(200, 900)
	local startY = rng:NextNumber(300, 600)
	local start = Vector3.new(math.cos(angle) * radius, startY, math.sin(angle) * radius)
	-- travel direction: across the map with a slight descent
	local dir = (Vector3.new(-math.cos(angle), rng:NextNumber(-0.15, 0.1), -math.sin(angle)))
	bolt.CFrame = CFrame.lookAt(start, start + dir)
	bolt.Parent = bg

	local trail = Instance.new("Trail")
	local a0 = Instance.new("Attachment", bolt)
	local a1 = Instance.new("Attachment", bolt)
	a0.Position = Vector3.new(-13, 0, 0)
	a1.Position = Vector3.new(13, 0, 0)
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.4
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(220, 190, 255), Color3.fromRGB(120, 160, 255))
	trail.Parent = bolt

	table.insert(shootingStars, {part = bolt, origin = start, dir = dir, life = 0})
end

-- MAIN LOOP
local clock = 0
RunService.Heartbeat:Connect(function(dt)
	clock += dt

	-- Spin galaxies / accretion disk / planet rings around their own disc axis
	for _, s in spinners do
		if s.part.Parent then
			s.part.CFrame = s.part.CFrame * CFrame.Angles(dt * s.speed, 0, 0)
		end
	end

	-- Bob crystals gently
	for _, c in crystals do
		if c.part.Parent then
			local offset = math.sin(clock * 0.8 + c.phase) * c.amp
			local pos = c.base.Position + Vector3.new(0, offset, 0)
			c.part.CFrame = CFrame.new(pos) * (c.base - c.base.Position)
		end
	end

	-- Move shooting stars
	for i = #shootingStars, 1, -1 do
		local s = shootingStars[i]
		s.life += dt
		if not s.part.Parent or s.life > 2 then
			if s.part.Parent then s.part:Destroy() end
			table.remove(shootingStars, i)
		else
			local pos = s.origin + s.dir * (s.life * 220)
			s.part.CFrame = CFrame.lookAt(pos, pos + s.dir)
		end
	end
end)

-- Timers: twinkle stars frequently, spawn a shooting star every few seconds
while true do
	task.wait(0.6)
	twinkle()
	if rng:NextNumber(0, 1) < 0.25 then
		spawnShootingStar()
	end
end