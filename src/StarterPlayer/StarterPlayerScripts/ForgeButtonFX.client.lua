-- ForgeButtonFX (LocalScript)
-- The weapon-forge buttons breathe: the glowing core and the ring around each glass dome pulse softly
-- (only on your own screen). Parts arrive and leave with instance streaming, so they register themselves.

local RunService = game:GetService("RunService")
local rng = Random.new()

local rocket = workspace:WaitForChild("Rocket")
local stations = rocket:WaitForChild("IronStations")

local cores, rings = {}, {}
local function register(d)
	if d:IsA("BasePart") then
		if d.Name:find("^BtnCore") then
			table.insert(cores, { part = d, light = d:FindFirstChildOfClass("PointLight"), phase = rng:NextNumber(0, 6.28) })
		elseif d.Name:find("^BtnRing") then
			table.insert(rings, { part = d, phase = rng:NextNumber(0, 6.28) })
		end
	end
end
for _, d in stations:GetDescendants() do register(d) end
stations.DescendantAdded:Connect(register)

local t, acc, pruneAt = 0, 0, 5
RunService.Heartbeat:Connect(function(dt)
	t += dt
	acc += dt
	if acc < 1 / 20 then
		return
	end
	acc = 0
	for _, c in cores do
		local k = 0.5 + 0.5 * math.sin(t * 2.2 + c.phase)
		c.part.Transparency = 0.02 + 0.16 * k
		if c.light and c.light.Brightness < 2 then
			c.light.Brightness = 0.8 + 0.6 * k
		end
	end
	for _, r in rings do
		r.part.Transparency = 0.08 + 0.3 * (0.5 + 0.5 * math.sin(t * 3 + r.phase))
	end
	if t >= pruneAt then
		pruneAt = t + 5
		for _, list in { cores, rings } do
			for i = #list, 1, -1 do
				if not list[i].part.Parent then
					table.remove(list, i)
				end
			end
		end
	end
end)
