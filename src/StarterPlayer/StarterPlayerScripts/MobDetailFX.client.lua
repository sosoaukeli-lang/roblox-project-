-- MobDetailFX (LocalScript)
-- Brings the MOTHERSHIP, the BOSS and their minions to life on your screen:
--   * parts on a Motor6D spin / float / flap (attributes SpinAxis, SpinSpeed, Bob, BobSpeed, FlapAxis, FlapAmp, FlapSpeed, FlapPhase)
--   * parts with the attribute Blink flicker like warning lights
--   * the boss changes colour with its phase (violet -> crimson -> white-gold)

local RunService = game:GetService("RunService")

local PHASE_COLORS = {
	Color3.fromRGB(170, 90, 255),
	Color3.fromRGB(255, 60, 90),
	Color3.fromRGB(255, 232, 170),
}
local VIOLET = Color3.fromRGB(170, 90, 255)

local tracked = {} -- [model] = { motors, blinks, tints, far }
local function near(a, b, tol)
	return math.abs(a.R - b.R) < tol and math.abs(a.G - b.G) < tol and math.abs(a.B - b.B) < tol
end

local function track(model)
	if tracked[model] then return end
	local info = { motors = {}, blinks = {}, tints = {}, big = model:GetAttribute("IsBoss") == true or model:GetAttribute("IsShip") == true }
	tracked[model] = info
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d:GetAttribute("SpinSpeed") ~= nil then
			local fa = d:GetAttribute("FlapAxis")
			info.motors[#info.motors + 1] = {
				m = d, base = d.C0, axis = (d:GetAttribute("SpinAxis") or Vector3.xAxis).Unit, speed = d:GetAttribute("SpinSpeed") or 0,
				bob = d:GetAttribute("Bob") or 0, bobSpeed = d:GetAttribute("BobSpeed") or 2, phase = math.random() * 6.28,
				flapAxis = fa and fa.Unit, flapAmp = d:GetAttribute("FlapAmp") or 0, flapSpeed = d:GetAttribute("FlapSpeed") or 1, flapPhase = d:GetAttribute("FlapPhase") or 0,
			}
		elseif d:IsA("BasePart") then
			local bl = d:GetAttribute("Blink")
			if bl then info.blinks[#info.blinks + 1] = { part = d, period = bl, phase = math.random() * 6.28 } end
			if d:GetAttribute("Tint") and near(d.Color, VIOLET, 0.02) then info.tints[#info.tints + 1] = d end
		end
	end
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then tracked[model] = nil end
	end)
end

local function scan()
	for _, name in { "MothershipShip", "MothershipForces", "LootChests" } do
		local f = workspace:FindFirstChild(name)
		if f then
			for _, m in f:GetChildren() do
				if m:IsA("Model") then track(m) end
			end
		end
	end
end

local t, acc, tintAcc = 0, 0, 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	acc += dt
	tintAcc += dt
	if acc > 0.8 then
		acc = 0
		scan()
	end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	for model, info in tracked do
		local pos = model:GetPivot().Position
		local dist = (pos - camPos).Magnitude
		if dist < (info.big and 4000 or 700) then
			for _, mo in info.motors do
				if mo.m.Parent then
					local tr = CFrame.identity
					if mo.bob > 0 then
						tr = mo.base:Inverse() * CFrame.new(0, math.sin(t * mo.bobSpeed + mo.phase) * mo.bob, 0) * mo.base
					end
					if mo.speed ~= 0 then
						tr = tr * CFrame.fromAxisAngle(mo.axis, t * mo.speed + mo.phase)
					end
					if mo.flapAxis and mo.flapAmp > 0 then
						tr = tr * CFrame.fromAxisAngle(mo.flapAxis, math.sin(t * mo.flapSpeed + mo.flapPhase) * mo.flapAmp)
					end
					mo.m.Transform = tr
				end
			end
			for _, bl in info.blinks do
				if bl.part.Parent then
					bl.part.Transparency = 0.1 + 0.7 * (0.5 + 0.5 * math.sin(t * 6.283 / bl.period + bl.phase))
				end
			end
			if tintAcc > 0.1 and #info.tints > 0 then
				local phase = math.clamp(model:GetAttribute("Phase") or 1, 1, 3)
				local target = PHASE_COLORS[phase]
				for _, p in info.tints do
					if p.Parent then p.Color = p.Color:Lerp(target, 0.12) end
				end
			end
		end
	end
	if tintAcc > 0.1 then tintAcc = 0 end
end)
