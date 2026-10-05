-- WeaponKit (ModuleScript, ServerStorage) - helpers used to BUILD the weapon models (not used at runtime).
-- Coordinates are "design units"; everything is multiplied by K (the weapons are a bit smaller than before).
-- Convention: the grip is at the origin, the barrel points to -Z, up is +Y.
local Kit = {}
Kit.__index = Kit

local C3 = Color3.fromRGB
local PI = math.pi
local K = 0.8

function Kit.new(name, attrs)
	local self = setmetatable({}, Kit)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = CFrame.new()
	for k, v in attrs do tool:SetAttribute(k, v) end
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.42, 1.2, 0.66) * K
	handle.Color = C3(34, 36, 44)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool
	self.tool = tool
	self.handle = handle
	self.K = K
	return self
end

local function style(p, o)
	if o.shape then p.Shape = o.shape end
	if o.trans then p.Transparency = o.trans end
	if o.refl then p.Reflectance = o.refl end
	if o.glow then p:SetAttribute("Glow", true) end
	if o.rainbow then p:SetAttribute("Rainbow", o.hue or 0) end
	if o.ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
end

-- a part welded to the handle
function Kit:part(name, size, cf, color, mat, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * K
	p.Color = color
	p.Material = mat or Enum.Material.Metal
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	local rel = CFrame.new(cf.Position * K) * (cf - cf.Position)
	p.CFrame = self.handle.CFrame * rel
	style(p, o)
	local w = Instance.new("WeldConstraint")
	w.Part0 = o.weldTo or self.handle
	w.Part1 = p
	w.Parent = p
	p.Parent = self.tool
	return p
end
function Kit:neon(name, size, cf, color, o)
	o = o or {}
	if o.glow == nil then o.glow = true end
	return self:part(name, size, cf, color, Enum.Material.Neon, o)
end
-- a cylinder along the barrel (Z axis): length, diameter
function Kit:cyl(name, length, diameter, pos, color, mat, o)
	o = o or {}
	o.shape = Enum.PartType.Cylinder
	return self:part(name, Vector3.new(length, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, PI / 2, 0), color, mat, o)
end
-- a cylinder standing up (Y axis)
function Kit:post(name, height, diameter, pos, color, mat, o)
	o = o or {}
	o.shape = Enum.PartType.Cylinder
	return self:part(name, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, PI / 2), color, mat, o)
end
-- a cylinder lying across the weapon (X axis)
function Kit:rod(name, length, diameter, pos, color, mat, o)
	o = o or {}
	o.shape = Enum.PartType.Cylinder
	return self:part(name, Vector3.new(length, diameter, diameter), CFrame.new(pos), color, mat, o)
end
function Kit:ball(name, diameter, pos, color, mat, o)
	o = o or {}
	o.shape = Enum.PartType.Ball
	return self:part(name, Vector3.new(diameter, diameter, diameter), CFrame.new(pos), color, mat, o)
end
function Kit:ellipsoid(name, size, pos, color, mat, o)
	o = o or {}
	o.ellipsoid = true
	return self:part(name, size, CFrame.new(pos), color, mat, o)
end
-- a bar from p0 to p1
function Kit:limb(name, p0, p1, thick, color, mat, o)
	o = o or {}
	local len = (p1 - p0).Magnitude
	return self:part(name, Vector3.new(thick, thick, len), CFrame.lookAt((p0 + p1) / 2, p1), color, mat, o)
end
-- a ring (flat disc seen as a ring) around the Z axis
function Kit:ring(name, diameter, thickness, pos, color, mat, o)
	o = o or {}
	o.shape = Enum.PartType.Cylinder
	return self:part(name, Vector3.new(thickness, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, PI / 2, 0), color, mat or Enum.Material.Neon, o)
end

-- a part on a Motor6D, animated by the client (WeaponDetailFX): spins or floats
-- axis = rotation axis in the part's own frame (default X = the ring axis of cylinders), speed = radians / second
function Kit:motor(name, size, cf, color, mat, o)
	o = o or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * K
	p.Color = color
	p.Material = mat or Enum.Material.Neon
	p.CanCollide = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local rel = CFrame.new(cf.Position * K) * (cf - cf.Position)
	p.CFrame = self.handle.CFrame * rel
	style(p, o)
	local mo = Instance.new("Motor6D")
	mo.Name = "Joint_" .. name
	mo.Part0 = self.handle
	mo.Part1 = p
	mo.C0 = rel
	mo:SetAttribute("SpinAxis", o.axis or Vector3.new(1, 0, 0))
	mo:SetAttribute("SpinSpeed", o.speed or 0)
	mo:SetAttribute("Bob", (o.bob or 0) * K)
	mo:SetAttribute("BobSpeed", o.bobSpeed or 2)
	mo.Parent = p
	p.Parent = self.tool
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

-- the muzzle: the point the shots start from (the server flashes MuzzleLight / MuzzleFlash)
function Kit:muzzle(parent, pos, color)
	local a = Instance.new("Attachment")
	a.Name = "Muzzle"
	a.Position = pos * K
	a.Parent = parent
	local l = Instance.new("PointLight")
	l.Name = "MuzzleLight"
	l.Color = color
	l.Brightness = 4
	l.Range = 14
	l.Enabled = false
	l.Shadows = false
	l.Parent = a
	local e = Instance.new("ParticleEmitter")
	e.Name = "MuzzleFlash"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.1, 0.22)
	e.Speed = NumberRange.new(4, 14)
	e.SpreadAngle = Vector2.new(22, 22)
	e.EmissionDirection = Enum.NormalId.Front
	e.Rate = 0
	e.Parent = a
	return a
end

-- steam / heat vents: the client emits from them when you shoot
function Kit:vent(parent, pos, color, dir)
	local a = Instance.new("Attachment")
	a.Name = "Vent"
	a.Position = pos * K
	a.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Name = "VentSteam"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.6), color)
	e.LightEmission = 0.5
	e.LightInfluence = 0.2
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1.1) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(15, 15)
	e.EmissionDirection = dir or Enum.NormalId.Top
	e.Rate = 0
	e.Enabled = true
	e.Parent = a
	e:SetAttribute("Vent", true)
	return a
end

-- a tiny display on a face of a part: name + a heat bar (the client keeps it alive)
function Kit:screen(parent, face, title, color)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Screen"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(180, 90)
	sg.LightInfluence = 0
	sg.Brightness = 2
	sg.Parent = parent
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(4, 8, 14)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.Position = UDim2.fromScale(0.06, 0.06)
	t.Size = UDim2.fromScale(0.88, 0.38)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Code
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = color
	t.Text = title
	t.Parent = bg
	local st = Instance.new("TextLabel")
	st.Name = "State"
	st.Position = UDim2.fromScale(0.06, 0.46)
	st.Size = UDim2.fromScale(0.88, 0.24)
	st.BackgroundTransparency = 1
	st.Font = Enum.Font.Code
	st.TextScaled = true
	st.TextXAlignment = Enum.TextXAlignment.Left
	st.TextColor3 = Color3.fromRGB(235, 245, 255)
	st.Text = "READY"
	st.Parent = bg
	local barBG = Instance.new("Frame")
	barBG.Position = UDim2.fromScale(0.06, 0.78)
	barBG.Size = UDim2.fromScale(0.88, 0.14)
	barBG.BackgroundColor3 = Color3.fromRGB(20, 28, 40)
	barBG.BorderSizePixel = 0
	barBG.Parent = bg
	local fill = Instance.new("Frame")
	fill.Name = "Heat"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = barBG
	return sg
end

function Kit:finish(parentFolder)
	for _, c in self.tool:GetChildren() do
		if c:IsA("BasePart") then
			c.Anchored = false
		end
	end
	self.tool.Parent = parentFolder
	return self.tool
end

return Kit
