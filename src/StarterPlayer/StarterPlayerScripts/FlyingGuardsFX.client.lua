-- FlyingGuardsFX (LocalScript)
-- The flying soldiers that guard the two masters (workspace.FlyingGuards). They are animated on your own
-- screen every frame, relative to the rocket (which hovers), so they move smoothly:
--   * two ROYAL GUARDS hover beside the masters and turn to watch you
--   * four PATROL soldiers fly elliptical patrols around the balcony, banking into the turns
--   * every 25-45 seconds two of the patrol soldiers swoop down the hall on a scouting flight and come back
-- Their jet-pack and boot thrusters flare up with speed.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local rocket = workspace:WaitForChild("Rocket")
local folder = workspace:WaitForChild("FlyingGuards")
local rng = Random.new()
local PI = math.pi
local BAL_TOP = 14.3 + 44

local guards = {}
local function register(m)
	if not (m:IsA("Model") and m:GetAttribute("Mode")) then
		return
	end
	for _, g in guards do
		if g.model == m then
			return
		end
	end
	local g = {
		model = m,
		mode = m:GetAttribute("Mode"),
		phase = m:GetAttribute("phase") or 0,
		cx = m:GetAttribute("cx"), cy = m:GetAttribute("cy"), cz = m:GetAttribute("cz"),
		rx = m:GetAttribute("rx"), rz = m:GetAttribute("rz"), ry = m:GetAttribute("ry") or 0,
		dir = m:GetAttribute("dir") or 1,
		speed = m:GetAttribute("speed") or 0.3,
		gx = m:GetAttribute("gx"), gy = m:GetAttribute("gy"), gz = m:GetAttribute("gz"),
		scout = m:GetAttribute("scout") == true,
		flames = {},
		fwd = Vector3.new(0, 0, -1),
		yaw = nil,
		lastPos = nil,
		lastFwd = Vector3.new(0, 0, -1),
		scoutAt = 15 + rng:NextNumber(0, 25),
		scouting = nil,
	}
	for _, d in m:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "Flame" then
			table.insert(g.flames, d)
		end
	end
	table.insert(guards, g)
end
for _, m in folder:GetChildren() do register(m) end
folder.ChildAdded:Connect(function(m) task.defer(register, m) end)

local function orbitPos(g, tt)
	local a = g.phase + g.dir * tt * g.speed
	return Vector3.new(g.cx + math.cos(a) * g.rx, g.cy + math.sin(a * 2 + g.phase) * g.ry, g.cz + math.sin(a) * g.rz)
end

local function catmull(p0, p1, p2, p3, s)
	return 0.5 * ((2 * p1) + (p2 - p0) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s + (-p0 + 3 * p1 - 3 * p2 + p3) * s * s * s)
end

local SCOUT_TIME = 9
local function startScout(g, t)
	local p0 = orbitPos(g, t)
	local p4 = orbitPos(g, t + SCOUT_TIME)
	local side = (p0.X >= 0) and 1 or -1
	local w1 = Vector3.new(p0.X * 0.6, BAL_TOP + 10, 298)
	local w2 = Vector3.new(side * 18, BAL_TOP - 2, 245)
	local w3 = Vector3.new(-side * 12, BAL_TOP + 4, 280)
	g.scouting = { start = t, pts = { p0, p0, w1, w2, w3, p4, p4 } }
end

local function scoutPos(sc, t)
	local u = math.clamp((t - sc.start) / SCOUT_TIME, 0, 1)
	local segs = #sc.pts - 3
	local f = u * segs
	local i = math.min(math.floor(f), segs - 1)
	local s = f - i
	local p = sc.pts
	return catmull(p[i + 1], p[i + 2], p[i + 3], p[i + 4], s), u >= 1
end

local t, flameAcc = 0, 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local pivot = rocket:GetPivot()
	local rootPos
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		rootPos = pivot:PointToObjectSpace(char.HumanoidRootPart.Position)
	end
	flameAcc += dt
	local updateFlames = flameAcc >= 0.1
	if updateFlames then flameAcc = 0 end

	for _, g in guards do
		if g.model.Parent then
			local pos, speed = nil, 0
			if g.mode == "Guard" then
				pos = Vector3.new(g.gx, g.gy + 0.7 * math.sin(t * 1.3 + g.phase), g.gz)
				-- turn to watch you (or face the hall when you are far away)
				local want = Vector3.new(0, 0, -1)
				if rootPos then
					local d = rootPos - pos
					if d.Magnitude < 170 then
						want = Vector3.new(d.X, d.Y * 0.4, d.Z).Unit
					end
				end
				g.fwd = g.fwd:Lerp(want, math.min(dt * 2.5, 1))
				if g.fwd.Magnitude < 0.1 then g.fwd = want end
				local cf = CFrame.lookAt(pos, pos + g.fwd.Unit)
				g.model:PivotTo(pivot * cf * CFrame.Angles(0, 0, 0.04 * math.sin(t * 1.1 + g.phase)))
			else
				if g.scouting then
					local done
					pos, done = scoutPos(g.scouting, t)
					if done then
						g.scouting = nil
						g.scoutAt = t + rng:NextNumber(25, 45)
					end
				else
					pos = orbitPos(g, t)
					if g.scout and t >= g.scoutAt then
						startScout(g, t)
					end
				end
				if g.lastPos then
					local vel = (pos - g.lastPos) / math.max(dt, 1e-3)
					speed = vel.Magnitude
					if speed > 0.5 then
						g.fwd = g.fwd:Lerp(vel.Unit, math.min(dt * 6, 1))
						if g.fwd.Magnitude < 0.1 then g.fwd = vel.Unit end
					end
				end
				local fwd = g.fwd.Unit
				-- bank into the turns
				local turn = g.lastFwd:Cross(fwd).Y / math.max(dt, 1e-3)
				local bank = math.clamp(turn * 0.25, -0.55, 0.55)
				g.bank = (g.bank or 0) + (bank - (g.bank or 0)) * math.min(dt * 5, 1)
				g.lastFwd = fwd
				local up = CFrame.fromAxisAngle(fwd, g.bank):VectorToWorldSpace(Vector3.yAxis)
				local cf = CFrame.lookAt(pos, pos + fwd, up) * CFrame.Angles(-0.3, 0, 0)
				g.model:PivotTo(pivot * cf)
				g.lastPos = pos
			end
			if updateFlames then
				local rate = (g.mode == "Guard") and 55 or (45 + math.min(speed, 40) * 2.2)
				for _, e in g.flames do
					e.Rate = rate
				end
			end
		end
	end
end)
