-- LoadingScreen v2 (LocalScript in ReplicatedFirst)
-- Space loading screen: parallax stars + nebulae that react to your mouse, rotating HUD rings, shooting stars,
-- a UFO with a blinking alien and a sparkling beam, a glitchy RGB-split title, a segmented loading bar,
-- sci-fi HUD readouts, and a HYPERSPACE JUMP when you press START THE GAME.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")

local TITLE = "WELCOME TO ALIEN SPACE"
local SUBTITLE = "YOUR ADVENTURE AMONG THE STARS BEGINS HERE"
local TIP = "TIP: JUMP TO START FLYING THROUGH SPACE!"
local MIN_TIME = 5      -- the loading bar never finishes faster than this (seconds)
local WARP_TIME = 1.5   -- length of the hyperspace jump after pressing START

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local rng = Random.new()
local PI = math.pi

local CYAN = Color3.fromRGB(80, 240, 255)
local MAGENTA = Color3.fromRGB(255, 90, 230)
local WHITE = Color3.new(1, 1, 1)

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local function round(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(1, 0) }, parent)
end
local function gradient(parent, c0, c1, rotation)
	return new("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = rotation or 0 }, parent)
end

----------------------------------------------------------------------
-- GUI root
----------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "AlienLoading",
	DisplayOrder = 1000,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- keep the player from moving behind the loading screen
local controls
task.spawn(function()
	local ok, mod = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 15))
	end)
	if ok and mod then
		local ok2, c = pcall(function()
			return mod:GetControls()
		end)
		if ok2 and c then
			controls = c
			pcall(function()
				c:Disable()
			end)
		end
	end
end)

local root = new("CanvasGroup", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
}, gui)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(5, 2, 22)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(26, 8, 62)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 4, 36)),
	}),
}, root)

-- white flash used by the hyperspace jump (sits above everything)
local flash = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 100,
}, gui)

----------------------------------------------------------------------
-- Nebulae (soft glowing clouds made of stacked circles)
----------------------------------------------------------------------
local nebulae = {}
local function makeNebula(pos, h, color)
	local n = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromScale(0, h),
		BackgroundTransparency = 1,
		ZIndex = 0,
	}, root)
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, n)
	for i = 1, 7 do
		local sz = 1 - (i - 1) * 0.13
		local c = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(sz, sz),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.955,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, n)
		round(c)
	end
	table.insert(nebulae, { f = n, base = pos, phase = rng:NextNumber(0, 6.28) })
end
makeNebula(UDim2.fromScale(0.2, 0.3), 0.9, Color3.fromRGB(150, 60, 255))
makeNebula(UDim2.fromScale(0.82, 0.62), 0.8, Color3.fromRGB(255, 70, 190))
makeNebula(UDim2.fromScale(0.55, 0.95), 0.7, Color3.fromRGB(40, 190, 255))

----------------------------------------------------------------------
-- Stars (3 depth layers for parallax)
----------------------------------------------------------------------
local starColors = { WHITE, Color3.fromRGB(150, 230, 255), Color3.fromRGB(255, 170, 240) }
local stars = {}
for i = 1, 120 do
	local size = rng:NextInteger(2, 5)
	local base = rng:NextNumber(0.1, 0.65)
	local x, y = rng:NextNumber(), rng:NextNumber()
	local f = new("Frame", {
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromScale(x, y),
		BackgroundColor3 = starColors[rng:NextInteger(1, #starColors)],
		BackgroundTransparency = base,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, root)
	round(f)
	stars[i] = {
		f = f, x = x, y = y, size = size, base = base,
		speed = 0.004 + size * 0.004,
		depth = size - 1,
		phase = rng:NextNumber(0, 6.28),
		rate = rng:NextNumber(1, 3.5),
		vx = 0, vy = 0,
	}
end

----------------------------------------------------------------------
-- Rotating HUD rings (dotted) behind the title
----------------------------------------------------------------------
local function makeRing(heightScale, dots, dotSize, alpha, color)
	local ring = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0, heightScale),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, root)
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, ring)
	for i = 1, dots do
		local a = 2 * PI * i / dots
		local d = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)),
			Size = UDim2.fromOffset(dotSize, dotSize),
			BackgroundColor3 = color,
			BackgroundTransparency = alpha,
			BorderSizePixel = 0,
		}, ring)
		round(d)
	end
	return { f = ring, h = heightScale }
end
local ringOuter = makeRing(0.95, 60, 4, 0.55, CYAN)
local ringInner = makeRing(0.64, 36, 5, 0.6, MAGENTA)

----------------------------------------------------------------------
-- Planets
----------------------------------------------------------------------
local function makePlanet(pos, heightScale, c0, c1, hasRing)
	local p = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromScale(0, heightScale),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, p)
	round(p)
	local g = gradient(p, c0, c1, 40)
	new("UIStroke", { Color = c0:Lerp(WHITE, 0.5), Transparency = 0.5, Thickness = 2 }, p)
	if hasRing then
		local r = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.9, 0.35),
			BackgroundTransparency = 1,
			Rotation = -22,
			ZIndex = 4,
		}, p)
		round(r)
		new("UIStroke", { Color = Color3.fromRGB(210, 240, 255), Thickness = 4, Transparency = 0.25 }, r)
	end
	return { f = p, grad = g, base = pos, phase = rng:NextNumber(0, 6.28) }
end
local planets = {
	makePlanet(UDim2.fromScale(0.13, 0.78), 0.3, Color3.fromRGB(190, 100, 255), Color3.fromRGB(60, 20, 140), false),
	makePlanet(UDim2.fromScale(0.88, 0.2), 0.2, Color3.fromRGB(100, 230, 255), Color3.fromRGB(30, 70, 170), true),
	makePlanet(UDim2.fromScale(0.86, 0.82), 0.1, Color3.fromRGB(255, 150, 90), Color3.fromRGB(150, 40, 80), false),
}

----------------------------------------------------------------------
-- UFO with a blinking alien, antennae and a sparkling beam
----------------------------------------------------------------------
local ufo = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.2),
	Size = UDim2.fromScale(0, 0.17),
	BackgroundTransparency = 1,
	ZIndex = 6,
}, root)
new("UIAspectRatioConstraint", { AspectRatio = 2.2, DominantAxis = Enum.DominantAxis.Height }, ufo)

local beam = new("Frame", {
	Position = UDim2.fromScale(0.28, 0.72),
	Size = UDim2.fromScale(0.44, 1.7),
	BackgroundColor3 = Color3.fromRGB(150, 255, 200),
	BorderSizePixel = 0,
	ZIndex = 5,
}, ufo)
new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
}, beam)
local beamDots = {}
for i = 1, 9 do
	local d = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, beam)
	round(d)
	beamDots[i] = { f = d, x = rng:NextNumber(0.1, 0.9), speed = rng:NextNumber(0.25, 0.6), phase = rng:NextNumber() }
end

local dome = new("Frame", {
	Position = UDim2.fromScale(0.33, 0.02),
	Size = UDim2.fromScale(0.34, 0.62),
	BackgroundColor3 = Color3.fromRGB(160, 240, 255),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	ZIndex = 6,
}, ufo)
round(dome)
new("UIStroke", { Color = WHITE, Transparency = 0.5, Thickness = 2 }, dome)
local antennaTips = {}
for _, s in { -1, 1 } do
	new("Frame", {
		Position = UDim2.fromScale(0.5 + s * 0.12 - 0.025, 0.06),
		Size = UDim2.fromScale(0.05, 0.3),
		BackgroundColor3 = Color3.fromRGB(120, 230, 110),
		BorderSizePixel = 0,
		Rotation = s * 14,
		ZIndex = 7,
	}, dome)
	local tip = new("Frame", {
		Position = UDim2.fromScale(0.5 + s * 0.17 - 0.06, 0.0),
		Size = UDim2.fromScale(0.12, 0.12),
		BackgroundColor3 = MAGENTA,
		BorderSizePixel = 0,
		ZIndex = 8,
	}, dome)
	round(tip)
	table.insert(antennaTips, tip)
end
local head = new("Frame", {
	Position = UDim2.fromScale(0.3, 0.3),
	Size = UDim2.fromScale(0.4, 0.6),
	BackgroundColor3 = Color3.fromRGB(120, 230, 110),
	BorderSizePixel = 0,
	ZIndex = 7,
}, dome)
round(head)
local eyes = {}
for _, ex in { 0.1, 0.62 } do
	local eye = new("Frame", {
		Position = UDim2.fromScale(ex, 0.3),
		Size = UDim2.fromScale(0.28, 0.36),
		BackgroundColor3 = Color3.fromRGB(10, 10, 20),
		BorderSizePixel = 0,
		ZIndex = 8,
	}, head)
	round(eye)
	table.insert(eyes, eye)
end

local body = new("Frame", {
	Position = UDim2.fromScale(0, 0.42),
	Size = UDim2.fromScale(1, 0.42),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	ZIndex = 7,
}, ufo)
round(body)
gradient(body, Color3.fromRGB(210, 220, 245), Color3.fromRGB(90, 100, 150), 90)
new("UIStroke", { Color = WHITE, Transparency = 0.6, Thickness = 2 }, body)
local ufoLights = {}
local lightColors = { CYAN, MAGENTA, Color3.fromRGB(255, 230, 90), CYAN, MAGENTA }
for i = 1, 5 do
	local l = new("Frame", {
		Position = UDim2.fromScale(0.1 + (i - 1) * 0.18, 0.52),
		Size = UDim2.fromScale(0.08, 0.15),
		BackgroundColor3 = lightColors[i],
		BorderSizePixel = 0,
		ZIndex = 8,
	}, ufo)
	round(l)
	ufoLights[i] = l
end

----------------------------------------------------------------------
-- Title (RGB-split ghosts + glitch), subtitle
----------------------------------------------------------------------
local function makeTitle(color, z, trans)
	local l = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromScale(0.92, 0.14),
		BackgroundTransparency = 1,
		Text = TITLE,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = color,
		TextTransparency = trans,
		MaxVisibleGraphemes = 0,
		ZIndex = z,
	}, root)
	new("UITextSizeConstraint", { MaxTextSize = 96 }, l)
	return l
end
local ghostC = makeTitle(CYAN, 8, 0.55)
local ghostM = makeTitle(MAGENTA, 8, 0.55)
local title = makeTitle(WHITE, 10, 0)
local titleGrad = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CYAN),
		ColorSequenceKeypoint.new(0.5, MAGENTA),
		ColorSequenceKeypoint.new(1, CYAN),
	}),
}, title)
local titleStroke = new("UIStroke", { Color = Color3.fromRGB(90, 30, 170), Thickness = 3 }, title)

local subtitle = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.57),
	Size = UDim2.fromScale(0.7, 0.04),
	BackgroundTransparency = 1,
	Text = SUBTITLE,
	TextScaled = true,
	Font = Enum.Font.GothamMedium,
	TextColor3 = Color3.fromRGB(215, 205, 255),
	TextTransparency = 1,
	ZIndex = 10,
}, root)
new("UITextSizeConstraint", { MaxTextSize = 28 }, subtitle)

----------------------------------------------------------------------
-- Loading bar (segmented), big percentage, decoding status text
----------------------------------------------------------------------
local barGroup = new("CanvasGroup", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.72),
	Size = UDim2.fromScale(0.5, 0.17),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, root)
local pct = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(0.3, 0.34),
	BackgroundTransparency = 1,
	Text = "0%",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = WHITE,
	ZIndex = 10,
}, barGroup)
new("UITextSizeConstraint", { MaxTextSize = 40 }, pct)
gradient(pct, CYAN, MAGENTA, 0)

local SEG = 40
local barBack = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.58),
	Size = UDim2.new(0.92, 0, 0, 20),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, barGroup)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, barBack)
local segs = {}
for i = 1, SEG do
	local sgm = new("Frame", {
		LayoutOrder = i,
		Size = UDim2.new(1 / SEG, -3 + 3 / SEG, 1, 0),
		BackgroundColor3 = Color3.fromHSV(0.5 + 0.38 * (i / SEG), 0.8, 1),
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 11,
	}, barBack)
	round(sgm, UDim.new(0.25, 0))
	segs[i] = sgm
end
local rocketIcon = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromOffset(36, 36),
	BackgroundTransparency = 1,
	Text = "\u{1F680}",
	TextSize = 30,
	Rotation = 45,
	ZIndex = 13,
}, barBack)
local status = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.74),
	Size = UDim2.fromScale(0.9, 0.24),
	BackgroundTransparency = 1,
	Text = "",
	TextScaled = true,
	Font = Enum.Font.Code,
	TextColor3 = Color3.fromRGB(190, 255, 245),
	ZIndex = 10,
}, barGroup)
new("UITextSizeConstraint", { MaxTextSize = 20 }, status)

----------------------------------------------------------------------
-- START button (rounded group with a light sweep)
----------------------------------------------------------------------
local btnGroup = new("CanvasGroup", {
	Name = "StartGroup",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.85),
	Size = UDim2.fromScale(0.36, 0.1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 40,
}, root)
round(btnGroup, UDim.new(0.3, 0))
local btnStroke = new("UIStroke", { Color = CYAN, Thickness = 3 }, btnGroup)
local btnScale = new("UIScale", { Scale = 0 }, btnGroup)
local button = new("TextButton", {
	Name = "StartButton",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "START GAME",
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = WHITE,
	ZIndex = 22,
}, btnGroup)
new("UITextSizeConstraint", { MaxTextSize = 42 }, button)
new("UIPadding", { PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0), PaddingLeft = UDim.new(0.06, 0), PaddingRight = UDim.new(0.06, 0) }, button)
-- the gradient lives on its own background (a gradient on the button itself would also tint the text and hide it)
local btnBg = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	ZIndex = 20,
}, btnGroup)
gradient(btnBg, Color3.fromRGB(120, 60, 230), Color3.fromRGB(40, 150, 230), 0)
new("UIStroke", { Color = Color3.fromRGB(30, 10, 80), Thickness = 2 }, button) -- outlines the text
local shimmer = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(-0.3, 0.5),
	Size = UDim2.fromScale(0.12, 2),
	Rotation = 20,
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.75,
	BorderSizePixel = 0,
	ZIndex = 21,
}, btnGroup)

local tip = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.975),
	Size = UDim2.fromScale(0.6, 0.035),
	BackgroundTransparency = 1,
	Text = TIP,
	TextScaled = true,
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(190, 180, 235),
	TextTransparency = 0.2,
	ZIndex = 10,
}, root)
new("UITextSizeConstraint", { MaxTextSize = 20 }, tip)

----------------------------------------------------------------------
-- HUD: corner brackets, readouts, vignette, scan line
----------------------------------------------------------------------
local function bracket(ax, ay)
	local ox = (ax == 0) and 14 or -14
	local oy = (ay == 0) and 14 or -14
	for _, horizontal in { true, false } do
		new("Frame", {
			AnchorPoint = Vector2.new(ax, ay),
			Position = UDim2.new(ax, ox, ay, oy),
			Size = horizontal and UDim2.fromOffset(46, 3) or UDim2.fromOffset(3, 46),
			BackgroundColor3 = CYAN,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 15,
		}, root)
	end
end
bracket(0, 0)
bracket(1, 0)
bracket(0, 1)
bracket(1, 1)

local function hud(text, anchor, pos, align)
	return new("TextLabel", {
		AnchorPoint = anchor,
		Position = pos,
		Size = UDim2.fromOffset(380, 20),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Code,
		TextSize = 15,
		TextColor3 = CYAN,
		TextTransparency = 0.25,
		TextXAlignment = align,
		ZIndex = 15,
	}, root)
end
hud("ALIEN SPACE  //  BOOT SEQUENCE", Vector2.new(0, 0), UDim2.new(0, 30, 0, 26), Enum.TextXAlignment.Left)
local hudClock = hud("T+00:00.0", Vector2.new(1, 0), UDim2.new(1, -30, 0, 26), Enum.TextXAlignment.Right)
hud("PILOT: " .. string.upper(player.DisplayName), Vector2.new(0, 1), UDim2.new(0, 30, 1, -26), Enum.TextXAlignment.Left)
local hudCoord = hud("SECTOR 7G  //  000.00 / 000.00", Vector2.new(1, 1), UDim2.new(1, -30, 1, -26), Enum.TextXAlignment.Right)

local function edge(anchor, pos, size, rot)
	local f = new("Frame", {
		AnchorPoint = anchor,
		Position = pos,
		Size = size,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 30,
	}, root)
	new("UIGradient", {
		Rotation = rot,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	}, f)
end
edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90)
edge(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.22), 270)
edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.14, 1), 0)
edge(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.14, 1), 180)

local scan = new("Frame", {
	Size = UDim2.new(1, 0, 0, 3),
	BackgroundColor3 = CYAN,
	BackgroundTransparency = 0.85,
	BorderSizePixel = 0,
	ZIndex = 31,
}, root)

----------------------------------------------------------------------
-- Loading progress
----------------------------------------------------------------------
local startClock = os.clock()
local assetsDone = false
task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local list = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("Decal") or d:IsA("Texture") or d:IsA("MeshPart") or d:IsA("Sound") or d:IsA("ParticleEmitter") then
			table.insert(list, d)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	assetsDone = true
end)

local MESSAGES = {
	"SCANNING THE GALAXY",
	"CHARGING THE ENGINES",
	"WAKING UP THE ALIENS",
	"POLISHING THE STARS",
	"ALMOST THERE",
}
local GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#@%&*+="
local function scramble(target, p)
	local n = math.floor(#target * p)
	local out = {}
	for i = 1, #target do
		local ch = target:sub(i, i)
		if i <= n or ch == " " then
			out[i] = ch
		else
			local g = rng:NextInteger(1, #GLYPHS)
			out[i] = GLYPHS:sub(g, g)
		end
	end
	return table.concat(out)
end

----------------------------------------------------------------------
-- State, START / hyperspace jump
----------------------------------------------------------------------
local t, shown = 0, 0
local ready, started, finished = false, false, false
local warpStart = nil
local ufoWarpFrom = nil
local msgIdx, msgStart = 0, 0
local conn

local function showStart()
	ready = true
	TweenService:Create(barGroup, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
	btnGroup.Visible = true
	TweenService:Create(btnScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function start()
	if started or not ready then
		return
	end
	started = true
	button.Active = false
	TweenService:Create(btnScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
	for _, s in stars do
		s.vx, s.vy = s.x - 0.5, s.y - 0.5
		if math.abs(s.vx) + math.abs(s.vy) < 0.04 then
			local a = rng:NextNumber(0, 2 * PI)
			s.vx, s.vy = math.cos(a) * 0.1, math.sin(a) * 0.1
		end
		s.f.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	ufoWarpFrom = ufo.Position
	warpStart = t
end
button.Activated:Connect(start)
button.MouseEnter:Connect(function()
	if ready and not started then
		TweenService:Create(btnScale, TweenInfo.new(0.15), { Scale = 1.08 }):Play()
	end
end)
button.MouseLeave:Connect(function()
	if ready and not started then
		TweenService:Create(btnScale, TweenInfo.new(0.15), { Scale = 1 }):Play()
	end
end)

local function finish()
	if finished then
		return
	end
	finished = true
	if conn then
		conn:Disconnect()
	end
	root.Visible = false
	if controls then
		pcall(function()
			controls:Enable()
		end)
	end
	-- coming out of hyperspace: the camera zooms back from a wide-angle burst
	local cam = workspace.CurrentCamera
	if cam then
		cam.FieldOfView = 105
		TweenService:Create(cam, TweenInfo.new(1.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { FieldOfView = 70 }):Play()
	end
	TweenService:Create(flash, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	task.delay(1, function()
		gui:Destroy()
	end)
end

-- shooting stars now and then
task.spawn(function()
	while gui.Parent and not started do
		task.wait(rng:NextNumber(1.2, 2.8))
		if not gui.Parent or started then
			break
		end
		local y0 = rng:NextNumber(0.02, 0.45)
		local streak = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(rng:NextInteger(140, 240), 3),
			Position = UDim2.fromScale(-0.1, y0),
			Rotation = 15,
			BackgroundColor3 = starColors[rng:NextInteger(1, #starColors)],
			BorderSizePixel = 0,
			ZIndex = 4,
		}, root)
		new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		}, streak)
		TweenService:Create(streak, TweenInfo.new(1, Enum.EasingStyle.Linear), { Position = UDim2.fromScale(0.95, y0 + 0.3) }):Play()
		task.delay(1.1, function()
			streak:Destroy()
		end)
	end
end)

----------------------------------------------------------------------
-- Animation loop
----------------------------------------------------------------------
local pmx, pmy = 0, 0 -- smoothed mouse offset for parallax
local glitchUntil, nextGlitch = 0, 2.5
local hudTimer = 0

conn = RunService.RenderStepped:Connect(function(dt)
	t += dt
	local abs = gui.AbsoluteSize

	-- mouse parallax
	local mouse = UserInputService:GetMouseLocation()
	local mx = math.clamp(mouse.X / math.max(abs.X, 1) - 0.5, -0.5, 0.5)
	local my = math.clamp(mouse.Y / math.max(abs.Y, 1) - 0.5, -0.5, 0.5)
	pmx += (mx - pmx) * math.min(dt * 4, 1)
	pmy += (my - pmy) * math.min(dt * 4, 1)

	-- stars
	if not warpStart then
		for _, s in stars do
			s.x -= s.speed * dt
			if s.x < -0.02 then
				s.x = 1.02
			end
			s.f.Position = UDim2.new(s.x, -pmx * s.depth * 6, s.y, -pmy * s.depth * 6)
			s.f.BackgroundTransparency = math.clamp(s.base + 0.3 * math.sin(t * s.rate + s.phase), 0, 1)
		end
	end

	-- nebulae, planets
	for _, n in nebulae do
		n.f.Position = n.base + UDim2.fromOffset(math.sin(t * 0.15 + n.phase) * 30 - pmx * 14, math.cos(t * 0.12 + n.phase) * 20 - pmy * 14)
	end
	for _, p in planets do
		p.f.Position = p.base + UDim2.fromOffset(-pmx * 40, math.sin(t * 0.6 + p.phase) * 10 - pmy * 40)
		p.grad.Rotation = 40 + t * 6
	end

	-- HUD rings (counter-rotating)
	ringOuter.f.Rotation = t * 6
	ringInner.f.Rotation = -t * 10

	-- UFO floats in a lazy figure-eight
	ufo.Position = UDim2.fromScale(0.5 + 0.16 * math.sin(t * 0.5), 0.2 + 0.025 * math.sin(t * 1.3)) + UDim2.fromOffset(-pmx * 24, -pmy * 24)
	ufo.Rotation = 5 * math.sin(t * 0.8)
	beam.BackgroundTransparency = 0.15 * (0.5 + 0.5 * math.sin(t * 6))
	for i, l in ufoLights do
		l.BackgroundTransparency = 0.5 - 0.5 * math.sin(t * 6 - i * 1.1)
	end
	for _, d in beamDots do
		local y = 1 - ((t * d.speed + d.phase) % 1)
		d.f.Position = UDim2.fromScale(d.x, y)
		d.f.BackgroundTransparency = 0.1 + 0.8 * (1 - y) * 0.6
	end
	local blink = (t % 3.6) < 0.12
	for _, e in eyes do
		e.Size = blink and UDim2.fromScale(0.28, 0.05) or UDim2.fromScale(0.28, 0.36)
		e.Position = UDim2.fromScale(e.Position.X.Scale, blink and 0.46 or 0.3)
	end
	for i, tipFrame in antennaTips do
		tipFrame.BackgroundTransparency = 0.5 - 0.5 * math.sin(t * 5 + i * 1.5)
	end

	-- title: types itself in, shimmers, glitches now and then
	local typed = math.floor(math.min(t / 1.4, 1) * #TITLE)
	ghostC.MaxVisibleGraphemes = typed
	ghostM.MaxVisibleGraphemes = typed
	title.MaxVisibleGraphemes = typed
	local dx = 3 + 2 * math.sin(t * 3)
	local jx, jy = 0, 0
	if t >= nextGlitch then
		glitchUntil = t + 0.18
		nextGlitch = t + rng:NextNumber(2.5, 5)
	end
	if t < glitchUntil then
		dx = rng:NextNumber(-14, 14)
		jx, jy = rng:NextNumber(-6, 6), rng:NextNumber(-3, 3)
	end
	ghostC.Position = UDim2.new(0.5, -dx + jx, 0.47, jy)
	ghostM.Position = UDim2.new(0.5, dx + jx, 0.47, -jy)
	title.Position = UDim2.new(0.5, jx, 0.47, jy)
	titleGrad.Offset = Vector2.new(math.sin(t * 0.8) * 0.5, 0)
	titleStroke.Transparency = 0.15 + 0.2 * math.sin(t * 2)
	subtitle.TextTransparency = 1 - math.clamp((t - 1.2) / 0.8, 0, 1)

	-- scan line + HUD readouts
	scan.Position = UDim2.fromScale(0, (t * 0.22) % 1)
	hudTimer += dt
	if hudTimer >= 0.2 then
		hudTimer = 0
		hudClock.Text = string.format("T+00:%04.1f", t % 60)
		hudCoord.Text = string.format("SECTOR 7G  //  %06.2f / %06.2f", rng:NextNumber(0, 999), rng:NextNumber(0, 999))
	end

	-- progress
	local timeP = math.clamp((os.clock() - startClock) / MIN_TIME, 0, 1)
	local target = assetsDone and timeP or math.min(timeP, 0.9)
	shown += (target - shown) * math.min(dt * 3, 1)
	local sp = math.clamp(shown, 0, 1)
	for i, sgm in segs do
		local lit = (i / SEG) <= sp + 0.001
		local head = math.abs(i / SEG - sp) < 1.2 / SEG
		sgm.BackgroundTransparency = lit and (head and 0.1 * (1 + math.sin(t * 14)) or 0) or 0.88
	end
	rocketIcon.Position = UDim2.fromScale(sp, 0.5 + 0.1 * math.sin(t * 12))
	if not ready then
		pct.Text = math.floor(sp * 100 + 0.5) .. "%"
		local idx = math.clamp(math.floor(sp * #MESSAGES) + 1, 1, #MESSAGES)
		if idx ~= msgIdx then
			msgIdx, msgStart = idx, t
		end
		status.Text = "> " .. scramble(MESSAGES[idx], (t - msgStart) / 0.7) .. " ..."
		if assetsDone and timeP >= 1 and shown > 0.99 then
			showStart()
		end
	else
		btnStroke.Thickness = 3 + 1.5 * math.sin(t * 4)
		shimmer.Position = UDim2.fromScale(-0.3 + 1.6 * ((t * 0.5) % 1), 0.5)
	end

	-- HYPERSPACE JUMP
	if warpStart then
		local w = t - warpStart
		local k = 1 + (math.exp(w * 3.4) - 1) * 0.5
		for _, s in stars do
			local px, py = s.vx * k, s.vy * k
			s.f.Position = UDim2.fromScale(0.5 + px, 0.5 + py)
			s.f.Size = UDim2.fromOffset(math.min(s.size + (k - 1) * 4, 520), math.max(2, s.size * 0.8))
			s.f.Rotation = math.deg(math.atan2(py * abs.Y, px * abs.X))
			s.f.BackgroundTransparency = math.max(s.base - 0.4, 0)
		end
		local k2 = 1 + w * w * 8
		for _, p in planets do
			p.f.Position = UDim2.fromScale(0.5 + (p.base.X.Scale - 0.5) * k2, 0.5 + (p.base.Y.Scale - 0.5) * k2)
		end
		ringOuter.f.Size = UDim2.fromScale(0, ringOuter.h * (1 + w * 3))
		ringInner.f.Size = UDim2.fromScale(0, ringInner.h * (1 + w * 4))
		local ua = math.clamp(w / 1.0, 0, 1)
		local from = ufoWarpFrom
		ufo.Position = UDim2.fromScale(from.X.Scale + (0.5 - from.X.Scale) * ua, from.Y.Scale + (0.48 - from.Y.Scale) * ua)
		ufo.Size = UDim2.fromScale(0, 0.17 * (1 - ua * 0.93))
		local ta = math.clamp(w / 0.7, 0, 1)
		local grow = 1 + w * 1.5
		for _, l in { ghostC, ghostM, title } do
			l.Size = UDim2.fromScale(0.92 * grow, 0.14 * grow)
			l.TextTransparency = ta
		end
		titleStroke.Transparency = ta
		subtitle.TextTransparency = ta
		tip.TextTransparency = ta
		flash.BackgroundTransparency = 1 - math.clamp((w - (WARP_TIME - 0.35)) / 0.35, 0, 1)
		if w >= WARP_TIME then
			finish()
		end
	end
end)
