-- WeaponPreviews (Script)
-- Copies the LOOK of every weapon (its parts only - no scripts, no values) into ReplicatedStorage.WeaponPreviews,
-- so the client can show the real weapon models in the boss chest reel and reveal.
-- The real Tools stay in ServerStorage, where no client can reach them.
-- Each preview is a Model whose parts are placed relative to the weapon's Handle (the Handle sits at the origin).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local weapons = ServerStorage:WaitForChild("Weapons")

local folder = Instance.new("Folder")
folder.Name = "WeaponPreviews"

-- the only things a preview part keeps: what changes how it looks
local function isVisual(inst)
	return inst:IsA("SpecialMesh") or inst:IsA("Decal") or inst:IsA("SurfaceAppearance")
end

local function addPreview(tool)
	if not tool:IsA("Tool") or folder:FindFirstChild(tool.Name) then return end
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then return end
	local model = Instance.new("Model")
	model.Name = tool.Name
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d:Clone()
			if c then
				for _, ch in c:GetChildren() do
					if not isVisual(ch) then ch:Destroy() end
				end
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.CastShadow = false
				c.CFrame = handle.CFrame:ToObjectSpace(d.CFrame)
				c.Parent = model
			end
		end
	end
	model.Parent = folder
end

for _, tool in weapons:GetChildren() do
	addPreview(tool)
end
weapons.ChildAdded:Connect(addPreview)
folder.Parent = ReplicatedStorage
