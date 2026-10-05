-- WeaponDetailFX (LocalScript)
-- Brings the weapon models to life (all on your own screen):
--   * parts on a Motor6D spin / float: gyro rings, floating prisms, plasma coils, halos (attributes SpinAxis, SpinSpeed, Bob, BobSpeed)
--   * parts tagged Glow flash white for a moment every time YOU shoot (WeaponClient raises the ShotPulse attribute)
--   * vents puff steam, the little display on the weapon shows READY / HOT and a heat bar
-- It animates the weapons of every character close to the camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local RANGE = 140

local tracked = {} -- [tool] = { motors = {}, glows = {}, vents = {}, screens = {}, heat = 0 }
local function track(tool)
	if tracked[tool] or tool:GetAttribute("WeaponId") == nil then return end
	local info = { motors = {}, glows = {}, vents = {}, screens = {}, heat = 0, flash = 0 }
	tracked[tool] = info
	for _, d in tool:GetDescendants() do
		if d:IsA("Motor6D") and d:GetAttribute("SpinSpeed") ~= nil then
			info.motors[#info.motors + 1] = {
				m = d, base = d.C0, axis = (d:GetAttribute("SpinAxis") or Vector3.xAxis).Unit, speed = d:GetAttribute("SpinSpeed") or 0,
				bob = d:GetAttribute("Bob") or 0, bobSpeed = d:GetAttribute("BobSpeed") or 2, phase = math.random() * 6.28,
			}
		elseif d:IsA("BasePart") and d:GetAttribute("Rainbow") ~= nil then
			info.rainbow = info.rainbow or {}
			info.rainbow[#info.rainbow + 1] = { part = d, hue = d:GetAttribute("Rainbow") }
		elseif d:IsA("BasePart") and d:GetAttribute("Glow") then
			info.glows[#info.glows + 1] = { part = d, color = d.Color }
		elseif d:IsA("ParticleEmitter") and d:GetAttribute("Vent") then
			info.vents[#info.vents + 1] = d
		elseif d:IsA("SurfaceGui") and d.Name == "Screen" then
			local state = d:FindFirstChild("State", true)
			local heat = d:FindFirstChild("Heat", true)
			if state and heat then
				info.screens[#info.screens + 1] = { state = state, heat = heat, color = heat.BackgroundColor3 }
			end
		end
	end
	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(game) then tracked[tool] = nil end
	end)
	tool:GetAttributeChangedSignal("ShotPulse"):Connect(function()
		info.heat = math.min(1, info.heat + 0.13)
		info.flash = 1
		for _, v in info.vents do v:Emit(5) end
	end)
end

local function scan()
	local cam = workspace.CurrentCamera
	if not cam then return end
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - cam.CFrame.Position).Magnitude < RANGE then
			for _, c in char:GetChildren() do
				if c:IsA("Tool") then track(c) end
			end
		end
	end
	-- a tool you hold can also sit in the backpack
	local bp = player:FindFirstChild("Backpack")
	if bp then
		for _, c in bp:GetChildren() do
			if c:IsA("Tool") then track(c) end
		end
	end
end

local t, acc = 0, 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	acc += dt
	if acc > 0.7 then
		acc = 0
		scan()
	end
	local cam = workspace.CurrentCamera
	for tool, info in tracked do
		local handle = tool:FindFirstChild("Handle")
		local equipped = tool.Parent and tool.Parent:IsA("Model")
		if handle and equipped and cam and (handle.Position - cam.CFrame.Position).Magnitude < RANGE then
			for _, mo in info.motors do
				if mo.m.Parent then
					local spin = CFrame.fromAxisAngle(mo.axis, t * mo.speed + mo.phase)
					local off = (mo.bob > 0) and (math.sin(t * mo.bobSpeed + mo.phase) * mo.bob) or 0
					-- float up and down in the weapon's own frame, then turn around the part's own axis
					local bobT = mo.base:Inverse() * CFrame.new(0, off, 0) * mo.base
					mo.m.Transform = bobT * spin
				end
			end
			-- rainbow parts (Genesis Cannon) cycle through every colour
			if info.rainbow then
				for _, rb in info.rainbow do
					if rb.part.Parent then rb.part.Color = Color3.fromHSV((t * 0.35 + rb.hue) % 1, 0.8, 1) end
				end
			end
			-- the glow flash and the heat bar
			info.flash = math.max(0, info.flash - dt * 7)
			info.heat = math.max(0, info.heat - dt * 0.3)
			if info.flash > 0.01 or info.lastFlash ~= 0 then
				for _, g in info.glows do
					if g.part.Parent then g.part.Color = g.color:Lerp(Color3.new(1, 1, 1), info.flash * 0.85) end
				end
				info.lastFlash = info.flash > 0.01 and 1 or 0
			end
			for _, s in info.screens do
				s.heat.Size = UDim2.fromScale(info.heat, 1)
				s.heat.BackgroundColor3 = s.color:Lerp(Color3.fromRGB(255, 70, 60), math.clamp((info.heat - 0.5) * 2, 0, 1))
				s.state.Text = info.heat > 0.8 and "HOT" or (info.heat > 0.05 and "FIRING" or "READY")
			end
		end
	end
end)
