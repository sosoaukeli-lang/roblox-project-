-- PlanetFX (LocalScript)
-- Makes the planets move (only on your own screen):
--   * the surface and the cloud layer turn slowly, at different speeds, around each planet's tilted axis
--   * the rings of the ringed planet drift
--   * moons orbit their planets
-- Planets live in workspace.Planets as persistent models, so they are always loaded.

local RunService = game:GetService("RunService")

local folder = workspace:WaitForChild("Planets")
local rigs = {}

local function buildRig(model)
	local surface = model:WaitForChild("Surface", 90)
	if not surface then
		return
	end
	-- the planets are big models that arrive piece by piece: wait until this one has finished arriving
	local last, stable = -1, 0
	repeat
		task.wait(0.5)
		local n = #model:GetDescendants()
		if n == last then
			stable += 1
		else
			stable = 0
		end
		last = n
	until stable >= 3
	if not surface.PrimaryPart then
		return
	end
	local rig = {
		model = model,
		center = model:GetAttribute("Center"),
		spinS = model:GetAttribute("SpinSurface") or 0.02,
		spinC = model:GetAttribute("SpinClouds") or 0.04,
		surface = surface, surfaceBase = surface.PrimaryPart.CFrame,
		moons = {},
	}
	local clouds = model:FindFirstChild("Clouds")
	if clouds and clouds.PrimaryPart then
		rig.clouds, rig.cloudsBase = clouds, clouds.PrimaryPart.CFrame
	end
	local rings = model:FindFirstChild("Rings")
	if rings and rings.PrimaryPart then
		rig.rings, rig.ringsBase = rings, rings.PrimaryPart.CFrame
	end
	for _, m in model:GetChildren() do
		if m:IsA("Model") and m.Name:find("^Moon") and m.PrimaryPart then
			table.insert(rig.moons, {
				model = m, r = m:GetAttribute("OrbitR"), speed = m:GetAttribute("OrbitSpeed"),
				tilt = m:GetAttribute("OrbitTilt"), phase = m:GetAttribute("Phase"),
			})
		end
	end
	table.insert(rigs, rig)
end
for _, m in folder:GetChildren() do
	task.spawn(buildRig, m)
end
folder.ChildAdded:Connect(function(m)
	task.spawn(buildRig, m)
end)

local t, slowAcc, moonAcc = 0, 0, 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	slowAcc += dt
	moonAcc += dt
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero

	-- moons: 20 times a second (a moon is only ~15 parts)
	if moonAcc >= 1 / 20 then
		moonAcc = 0
		for _, rig in rigs do
			if rig.center and (rig.center - camPos).Magnitude < 4000 then
				for _, m in rig.moons do
					local a = m.phase + t * m.speed
					local off = CFrame.Angles(m.tilt, 0, 0):VectorToWorldSpace(Vector3.new(math.cos(a) * m.r, 0, math.sin(a) * m.r))
					m.model:PivotTo(CFrame.new(rig.center + off) * CFrame.Angles(0, t * 0.2, 0))
				end
			end
		end
	end

	-- surface, clouds and rings turn very slowly, so 4 updates a second are plenty (these models have hundreds of parts)
	if slowAcc >= 0.25 then
		slowAcc = 0
		for _, rig in rigs do
			if rig.center and (rig.center - camPos).Magnitude < 4000 then
				rig.surface:PivotTo(rig.surfaceBase * CFrame.Angles(0, t * rig.spinS, 0))
				if rig.clouds then
					rig.clouds:PivotTo(rig.cloudsBase * CFrame.Angles(0, t * rig.spinC, 0))
				end
				if rig.rings then
					rig.rings:PivotTo(rig.ringsBase * CFrame.Angles(0, t * 0.008, 0))
				end
			end
		end
	end
end)
