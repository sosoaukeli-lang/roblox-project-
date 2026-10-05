-- MobKit (ModuleScript, ServerStorage) - helpers used to BUILD the mothership, the minions and the boss (not used at runtime).
-- Every part is welded to the root (HumanoidRootPart). Positions are relative to the root: -Z is the front, +Y is up.
local Kit = {}
Kit.__index = Kit
local PI = math.pi

function Kit.new(name, rootSize, anchoredRoot)
	local self = setmetatable({}, Kit)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = rootSize
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.Massless = false
	root.Anchored = anchoredRoot or false
	root.CFrame = CFrame.new(0, 1000, 0)
	root.Parent = model
	model.PrimaryPart = root
	self.model = model
	self.root = root
	return self
end

local function style(p, o)
	if o.shape then p.Shape = o.shape end
	if o.trans then p.Transparency = o.trans end
	if o.refl then p.Reflectance = o.refl end
	if o.glow then p:SetAttribute("Tint", true) end
	if o.blink then p:SetAttribute("Blink", o.blink) end
	if o.noQuery then p.CanQuery = false end
	if o.ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
end

function Kit:part(name, size, cf, color, mat, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.Metal
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = self.root.CFrame * cf
	style(p, o)
	local w = Instance.new("WeldConstraint")
	w.Part0 = o.weldTo or self.root
	w.Part1 = p
	w.Parent = p
	p.Parent = o.parent or self.model
	return p
end
function Kit:neon(name, size, cf, color, o)
	o = o or {}
	if o.glow == nil then o.glow = true end
	return self:part(name, size, cf, color, Enum.Material.Neon, o)
end
function Kit:ball(name, d, pos, color, mat, o)
	o = o or {}
	o.shape = Enum.PartType.Ball
	return self:part(name, Vector3.new(d, d, d), CFrame.new(pos), color, mat, o)
end
function Kit:ellipsoid(name, size, pos, color, mat, o)
	o = o or {}
	o.ellipsoid = true
	return self:part(name, size, CFrame.new(pos), color, mat, o)
end
-- a cylinder along Z (length, diameter)
function Kit:cyl(name, length, d, pos, color, mat, o)
	o = o or {}
	o.shape = Enum.PartType.Cylinder
	return self:part(name, Vector3.new(length, d, d), CFrame.new(pos) * CFrame.Angles(0, PI / 2, 0), color, mat, o)
end
-- a cylinder along Y
function Kit:post(name, height, d, pos, color, mat, o)
	o = o or {}
	o.shape = Enum.PartType.Cylinder
	return self:part(name, Vector3.new(height, d, d), CFrame.new(pos) * CFrame.Angles(0, 0, PI / 2), color, mat, o)
end
function Kit:limb(name, p0, p1, thick, color, mat, o)
	o = o or {}
	return self:part(name, Vector3.new(thick, thick, (p1 - p0).Magnitude), CFrame.lookAt((p0 + p1) / 2, p1), color, mat, o)
end
-- a part on a Motor6D that the CLIENT animates (MobDetailFX): spin (axis/speed), bob, flap
-- o.axis / o.speed: spin   o.bob / o.bobSpeed: float up and down   o.flapAxis / o.flapAmp / o.flapSpeed: swing back and forth
function Kit:motor(name, size, cf, color, mat, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.Neon
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = self.root.CFrame * cf
	style(p, o)
	local mo = Instance.new("Motor6D")
	mo.Name = "Joint_" .. name
	mo.Part0 = o.part0 or self.root
	mo.Part1 = p
	mo.C0 = (o.part0 and o.part0.CFrame:ToObjectSpace(p.CFrame)) or cf
	mo:SetAttribute("SpinAxis", o.axis or Vector3.new(1, 0, 0))
	mo:SetAttribute("SpinSpeed", o.speed or 0)
	mo:SetAttribute("Bob", o.bob or 0)
	mo:SetAttribute("BobSpeed", o.bobSpeed or 2)
	if o.flapAmp then
		mo:SetAttribute("FlapAxis", o.flapAxis or Vector3.new(0, 0, 1))
		mo:SetAttribute("FlapAmp", o.flapAmp)
		mo:SetAttribute("FlapSpeed", o.flapSpeed or 1.5)
		mo:SetAttribute("FlapPhase", o.flapPhase or 0)
	end
	mo.Parent = p
	p.Parent = o.parent or self.model
	return p
end
function Kit:light(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
	return l
end
function Kit:attach(parent, name, pos)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = pos
	a.Parent = parent
	return a
end
function Kit:humanoid(health)
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = health
	hum.Health = health
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = self.model
	return hum
end

return Kit
