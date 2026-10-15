-- MapBuilder (ModuleScript) - builds the village from code: ground, market, 8 house lots.
-- Call MapBuilder.Build() once at server start (Main.server.lua does it).
--
-- Workspace.Village
--   Ground, Paths (Parts)
--   Market      Plaza + Shop (Shop.Counter is where the shop prompt goes in Phase 3)
--   Houses      House1 .. House8, each a Model with:
--                 attributes HouseId, OwnerUserId (0 = free), Level
--                 Floor, Walls, Roof, Lamp, Spawn (SpawnLocation), Sign (name board)
--                 Door.Panel (+ DoorPrompt)   Slots.Slot1 .. SlotN (item spots)
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

-- Village layout (studs)
local GROUND_SIZE = 420
local PLAZA_SIZE = 64
local PLAZA_HEIGHT = 0.3
local HOUSE_RING_RADIUS = 110
local PATH_WIDTH = 6

-- House geometry (studs)
local WALL_THICKNESS = 1
local WALL_HEIGHT = 10
local FLOOR_HEIGHT = 0.4
local DOOR_WIDTH = 5
local DOOR_HEIGHT = 7.5
local DOOR_OPEN_ANGLE = 100 -- degrees, swings outward
local SLOT_SIZE = 4
local SLOT_PITCH = 5.5 -- distance between slot centres in a row
local SLOT_ROW_PITCH = 6
local SLOTS_PER_ROW = 4

local COLORS = {
	Grass = Color3.fromRGB(86, 140, 70),
	Stone = Color3.fromRGB(150, 150, 155),
	Path = Color3.fromRGB(176, 152, 120),
	Wall = Color3.fromRGB(222, 198, 160),
	Floor = Color3.fromRGB(150, 105, 70),
	Door = Color3.fromRGB(110, 70, 40),
	Wood = Color3.fromRGB(120, 85, 55),
	Slot = Color3.fromRGB(255, 200, 80),
	Lamp = Color3.fromRGB(255, 214, 140),
	ShopRoof = Color3.fromRGB(180, 60, 50),
}

local function newPart(className, name, size, cframe, props, parent)
	local part = Instance.new(className)
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for key, value in pairs(props) do
			part[key] = value
		end
	end
	part.Parent = parent
	return part
end

-- A text board floating above `adornee`. Returns the TextLabel.
local function addBillboard(adornee, text, width, offset, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SignGui"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(width, 50)
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.AlwaysOnTop = false

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.SourceSansBold
	label.TextScaled = true
	label.Text = text
	label.Parent = gui

	gui.Parent = adornee
	return label
end

local function buildMarket(parent)
	local market = Instance.new("Model")
	market.Name = "Market"

	newPart("Part", "Plaza", Vector3.new(PLAZA_SIZE, PLAZA_HEIGHT, PLAZA_SIZE),
		CFrame.new(0, PLAZA_HEIGHT / 2, 0),
		{ Material = Enum.Material.Cobblestone, Color = COLORS.Stone }, market)

	-- The shop stall sits on the north edge of the plaza and faces the centre,
	-- which stays free for the leaderboard (Phase 8).
	local shop = Instance.new("Model")
	shop.Name = "Shop"
	local baseY = PLAZA_HEIGHT
	local stallZ = -20
	local woodProps = { Material = Enum.Material.Wood, Color = COLORS.Wood }

	newPart("Part", "Counter", Vector3.new(14, 3.5, 2.5), CFrame.new(0, baseY + 1.75, stallZ + 4), woodProps, shop)
	for _, x in ipairs({ -7, 7 }) do
		for _, z in ipairs({ stallZ - 4, stallZ + 4 }) do
			newPart("Part", "Pillar", Vector3.new(1, 10, 1), CFrame.new(x, baseY + 5, z), woodProps, shop)
		end
	end
	local roof = newPart("Part", "Roof", Vector3.new(17, 1, 11), CFrame.new(0, baseY + 10.5, stallZ),
		{ Material = Enum.Material.Wood, Color = COLORS.ShopRoof }, shop)
	addBillboard(roof, "المتجر", 160, Vector3.new(0, 3, 0), 150)

	shop.Parent = market
	market.Parent = parent
end

-- A dirt path from a house's door to the plaza.
local function buildPath(houseOrigin, depth, parent)
	local startPos = houseOrigin.Position + houseOrigin.LookVector * (depth / 2 + 1)
	local endPos = houseOrigin.LookVector * -(PLAZA_SIZE / 2 - 2) -- point inside the plaza, same direction
	startPos = Vector3.new(startPos.X, 0.1, startPos.Z)
	endPos = Vector3.new(endPos.X, 0.1, endPos.Z)
	local length = (endPos - startPos).Magnitude
	local middle = (startPos + endPos) / 2
	newPart("Part", "Path", Vector3.new(PATH_WIDTH, 0.2, length), CFrame.lookAt(middle, endPos),
		{ Material = Enum.Material.Ground, Color = COLORS.Path }, parent)
end

-- Builds one house in the local space of `origin`: the front (door side) is -Z and
-- faces the village centre. Level data comes from Config.HouseLevels.
local function buildHouse(houseId, origin, levelDef, roofColor, parent)
	local width, depth = levelDef.Width, levelDef.Depth
	local halfW, halfD = width / 2, depth / 2
	local wallY = FLOOR_HEIGHT + WALL_HEIGHT / 2

	local model = Instance.new("Model")
	model.Name = "House" .. houseId
	model:SetAttribute("HouseId", houseId)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("Level", 1)

	local function add(className, name, size, localPos, props, container)
		return newPart(className, name, size, origin * CFrame.new(localPos), props, container or model)
	end
	local wallProps = { Material = Enum.Material.Brick, Color = COLORS.Wall }

	local floor = add("Part", "Floor", Vector3.new(width, FLOOR_HEIGHT, depth), Vector3.new(0, FLOOR_HEIGHT / 2, 0),
		{ Material = Enum.Material.WoodPlanks, Color = COLORS.Floor })
	model.PrimaryPart = floor

	-- Walls: back, left, right, and the front split around the doorway.
	add("Part", "BackWall", Vector3.new(width, WALL_HEIGHT, WALL_THICKNESS),
		Vector3.new(0, wallY, halfD - WALL_THICKNESS / 2), wallProps)
	add("Part", "LeftWall", Vector3.new(WALL_THICKNESS, WALL_HEIGHT, depth - 2 * WALL_THICKNESS),
		Vector3.new(-(halfW - WALL_THICKNESS / 2), wallY, 0), wallProps)
	add("Part", "RightWall", Vector3.new(WALL_THICKNESS, WALL_HEIGHT, depth - 2 * WALL_THICKNESS),
		Vector3.new(halfW - WALL_THICKNESS / 2, wallY, 0), wallProps)

	local frontZ = -(halfD - WALL_THICKNESS / 2)
	local frontSide = (width - DOOR_WIDTH) / 2
	local frontSideX = DOOR_WIDTH / 2 + frontSide / 2
	add("Part", "FrontWallLeft", Vector3.new(frontSide, WALL_HEIGHT, WALL_THICKNESS),
		Vector3.new(-frontSideX, wallY, frontZ), wallProps)
	add("Part", "FrontWallRight", Vector3.new(frontSide, WALL_HEIGHT, WALL_THICKNESS),
		Vector3.new(frontSideX, wallY, frontZ), wallProps)
	local lintelHeight = WALL_HEIGHT - DOOR_HEIGHT
	add("Part", "DoorLintel", Vector3.new(DOOR_WIDTH, lintelHeight, WALL_THICKNESS),
		Vector3.new(0, FLOOR_HEIGHT + DOOR_HEIGHT + lintelHeight / 2, frontZ), wallProps)

	add("Part", "Roof", Vector3.new(width + 3, 1, depth + 3), Vector3.new(0, FLOOR_HEIGHT + WALL_HEIGHT + 0.5, 0),
		{ Material = Enum.Material.Slate, Color = roofColor })

	-- Door: a panel hinged on its left edge that swings outward. HouseService tweens
	-- the panel between the two CFrames stored as attributes.
	local doorModel = Instance.new("Model")
	doorModel.Name = "Door"
	local panelLocal = Vector3.new(0, FLOOR_HEIGHT + DOOR_HEIGHT / 2, frontZ)
	local panel = add("Part", "Panel", Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, 0.6), panelLocal,
		{ Material = Enum.Material.Wood, Color = COLORS.Door }, doorModel)
	local hinge = origin * CFrame.new(panelLocal + Vector3.new(-DOOR_WIDTH / 2, 0, 0))
	panel:SetAttribute("ClosedCFrame", panel.CFrame)
	panel:SetAttribute("OpenCFrame", hinge * CFrame.Angles(0, math.rad(DOOR_OPEN_ANGLE), 0) * CFrame.new(DOOR_WIDTH / 2, 0, 0))

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DoorPrompt"
	prompt.ObjectText = "الباب"
	prompt.ActionText = "فتح / قفل"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = panel
	doorModel.Parent = model

	-- Interior lamp (keeps the inside readable once the village goes dark in Phase 2).
	local lamp = add("Part", "Lamp", Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, FLOOR_HEIGHT + WALL_HEIGHT - 1.5, 0),
		{ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = COLORS.Lamp, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Range = 28
	light.Brightness = 1.2
	light.Color = COLORS.Lamp
	light.Parent = lamp

	-- Spawn point just inside the door. The owner's Player.RespawnLocation points here.
	add("SpawnLocation", "Spawn", Vector3.new(4, 0.2, 4), Vector3.new(0, FLOOR_HEIGHT + 0.1, -halfD + 5),
		{ Transparency = 1, CanCollide = false, Neutral = true, Duration = 0 })

	-- Item slots, rows of SLOTS_PER_ROW along the back wall.
	local slots = Instance.new("Folder")
	slots.Name = "Slots"
	for index = 1, levelDef.Slots do
		local row = math.ceil(index / SLOTS_PER_ROW)
		local column = (index - 1) % SLOTS_PER_ROW + 1
		local inRow = math.min(SLOTS_PER_ROW, levelDef.Slots - (row - 1) * SLOTS_PER_ROW)
		local x = (column - (inRow + 1) / 2) * SLOT_PITCH
		local z = halfD - WALL_THICKNESS - 3 - (row - 1) * SLOT_ROW_PITCH
		local slot = add("Part", "Slot" .. index, Vector3.new(SLOT_SIZE, 0.2, SLOT_SIZE),
			Vector3.new(x, FLOOR_HEIGHT + 0.1, z),
			{ Material = Enum.Material.Neon, Color = COLORS.Slot, Transparency = 0.5, CanCollide = false }, slots)
		slot:SetAttribute("SlotIndex", index)
	end
	slots.Parent = model

	-- Name board above the door, updated by HouseService.
	local sign = add("Part", "Sign", Vector3.new(1, 1, 1), Vector3.new(0, FLOOR_HEIGHT + WALL_HEIGHT + 5, -halfD - 1),
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	addBillboard(sign, "بيت " .. houseId .. " - فاضي", 260, Vector3.new(0, 0, 0), 140)

	model.Parent = parent
	return model
end

-- Removes the default Studio template pieces that would overlap the village.
local function clearTemplate()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
	local spawn = Workspace:FindFirstChild("SpawnLocation")
	if spawn and spawn:IsA("SpawnLocation") then
		spawn:Destroy()
	end
end

-- Builds the whole village (replacing an old one) and returns
-- { Village = Folder, Houses = { [houseId] = Model } }.
function MapBuilder.Build()
	local old = Workspace:FindFirstChild("Village")
	if old then
		old:Destroy()
	end
	clearTemplate()

	local village = Instance.new("Folder")
	village.Name = "Village"

	newPart("Part", "Ground", Vector3.new(GROUND_SIZE, 2, GROUND_SIZE), CFrame.new(0, -1, 0),
		{ Material = Enum.Material.Grass, Color = COLORS.Grass }, village)
	buildMarket(village)

	local housesFolder = Instance.new("Folder")
	housesFolder.Name = "Houses"
	local houses = {}
	local levelDef = Config.HouseLevels[1]
	for houseId = 1, Config.MaxHouses do
		local angle = (houseId - 1) * (2 * math.pi / Config.MaxHouses)
		local position = Vector3.new(math.cos(angle) * HOUSE_RING_RADIUS, 0, math.sin(angle) * HOUSE_RING_RADIUS)
		local origin = CFrame.lookAt(position, Vector3.new(0, 0, 0)) -- front (-Z) faces the plaza
		houses[houseId] = buildHouse(houseId, origin, levelDef, Config.HouseColors[houseId].Color, housesFolder)
		buildPath(origin, levelDef.Depth, village)
	end
	housesFolder.Parent = village

	village.Parent = Workspace
	return { Village = village, Houses = houses }
end

return MapBuilder
