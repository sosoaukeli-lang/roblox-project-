-- ProgressUI (LocalScript)
-- The whole interface of the mission / shop / loadout system:
--   * press E at Commander Vox  -> MISSION BOARD (accept, track, abandon missions)
--   * press E at the Shop alien -> SHOP (items unlock by completing missions, then you buy them)
--   * the LOADOUT tab (equip your flight trail and your passive item) is inside both windows
--   * a mission tracker on the left with a pointer to what you need (crystals, a hive, the titan)
--   * cinematic rewards: MISSION COMPLETE banner, then the unlocked item revealed on a rarity-coloured card
--   * pop-ups for Xeno Ichor / Hive Crystal pick-ups, and a subtitle with the Commander's briefing
--   * works with mouse, touch and gamepad (B closes the panel)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Items = require(ReplicatedStorage:WaitForChild("Items"))
local Mon = require(ReplicatedStorage:WaitForChild("Monetization"))
local Loot = require(ReplicatedStorage:WaitForChild("Loot"))
local WeaponStats = require(ReplicatedStorage:WaitForChild("WeaponStats"))
local actionRemote = ReplicatedStorage:WaitForChild("ProgressAction")
local stateRemote = ReplicatedStorage:WaitForChild("ProgressState")
local notifyRemote = ReplicatedStorage:WaitForChild("ProgressNotify")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local C3 = Color3.fromRGB
local rng = Random.new()

local CYAN, GOLD, RED, GREEN = C3(0, 220, 255), C3(255, 200, 90), C3(255, 70, 90), C3(110, 255, 150)
local WHITE = Color3.new(1, 1, 1)
local BG, CARD = C3(8, 12, 30), C3(16, 22, 48)

local guideTarget = nil -- set by SHOW ME THE WAY: { part = BasePart, name = string }
local state = { ichor = 0, crystal = 0, kills = 0, unlocked = {}, owned = {}, equipped = { Trail = "", Passive = "" }, done = {}, active = nil }

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
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
local function corner(o, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end
local function stroke(o, color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local function label(parent, text, size, color, font, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextColor3 = color or C3(235, 245, 255), Font = font or Enum.Font.GothamBold,
		TextSize = size, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
	if props then
		for k, v in props do l[k] = v end
	end
	return l
end
local function playOnce(id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
end
local function money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
local function stat(name)
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(name)
	return v and v.Value or 0
end

----------------------------------------------------------------------
-- the main panel
----------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "ProgressUI", ResetOnSpawn = false, DisplayOrder = 60, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)

local dim = new("TextButton", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(0, 0, 12), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false, Selectable = false }, gui)

local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.66, 0.76), BackgroundColor3 = BG, BackgroundTransparency = 0.04, Visible = false }, gui)
corner(panel, 16)
local panelStroke = stroke(panel, CYAN, 2.5)
new("UISizeConstraint", { MinSize = Vector2.new(520, 360), MaxSize = Vector2.new(1100, 720) }, panel)
local panelScale = new("UIScale", { Scale = 1 }, panel)
local pg = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(14, 20, 46), C3(6, 8, 22)) }, panel)

local header = new("Frame", { Size = UDim2.fromScale(1, 0.13), BackgroundTransparency = 1 }, panel)
local title = label(header, "MISSION CONTROL", 22, CYAN, Enum.Font.GothamBlack, { Position = UDim2.fromScale(0.03, 0), Size = UDim2.fromScale(0.34, 1), TextScaled = true })
new("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 12 }, title)

local tabs, tabButtons = {}, {}
local TAB_DEFS = { { "missions", "MISSIONS" }, { "shop", "SHOP" }, { "robux", "R$ STORE" }, { "loadout", "LOADOUT" } }
local currentTab = "missions"
local shopFilter = "ALL"
local refresh
for i, def in TAB_DEFS do
	local b = new("TextButton", {
		Name = def[1], Size = UDim2.fromScale(0.15, 0.58), Position = UDim2.fromScale(0.39 + (i - 1) * 0.16, 0.22),
		BackgroundColor3 = CARD, Text = def[2], Font = Enum.Font.GothamBlack, TextColor3 = C3(160, 190, 220), AutoButtonColor = false,
		TextScaled = true,
	}, header)
	corner(b, 8)
	new("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 8 }, b)
	tabButtons[def[1]] = b
end
local closeButton = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.985, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C3(70, 20, 34), Text = "X", Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = C3(255, 200, 210), AutoButtonColor = true }, header)
corner(closeButton, 17)

local content = new("ScrollingFrame", {
	Name = "Content", Position = UDim2.fromScale(0.02, 0.145), Size = UDim2.fromScale(0.96, 0.74), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 5, ScrollBarImageColor3 = CYAN, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.fromOffset(0, 0),
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
local list = new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, content)
new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, content)

local footer = new("Frame", { Position = UDim2.fromScale(0.02, 0.9), Size = UDim2.fromScale(0.96, 0.085), BackgroundColor3 = C3(10, 16, 36), BorderSizePixel = 0 }, panel)
corner(footer, 10)
local footLabels = {}
for i, def in { { "MONEY", GOLD }, { "IRON", C3(190, 205, 235) }, { "ICHOR", GREEN }, { "CRYSTAL", C3(210, 140, 255) } } do
	local l = label(footer, "", 16, def[2], Enum.Font.GothamBold, { Position = UDim2.fromScale((i - 1) * 0.25, 0), Size = UDim2.fromScale(0.25, 1), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true })
	new("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 8 }, l)
	footLabels[def[1]] = l
end
local function updateFooter()
	footLabels.MONEY.Text = "$ " .. money(stat("Money"))
	footLabels.IRON.Text = "IRON  " .. money(stat("Iron"))
	footLabels.ICHOR.Text = "ICHOR  " .. state.ichor
	footLabels.CRYSTAL.Text = "CRYSTAL  " .. state.crystal
end

----------------------------------------------------------------------
-- toasts and the lower subtitle
----------------------------------------------------------------------
local toastHolder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(420, 200), BackgroundTransparency = 1 }, gui)
new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)
local function toast(text, color)
	color = color or CYAN
	local f = new("Frame", { Size = UDim2.fromOffset(400, 34), BackgroundColor3 = C3(8, 12, 30), BackgroundTransparency = 0.15, BorderSizePixel = 0 }, toastHolder)
	corner(f, 17)
	stroke(f, color, 1.6)
	local l = label(f, text, 15, color:Lerp(C3(255, 255, 255), 0.4), Enum.Font.GothamBold, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true })
	new("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0), PaddingLeft = UDim.new(0.04, 0), PaddingRight = UDim.new(0.04, 0) }, l)
	f.BackgroundTransparency = 1
	l.TextTransparency = 1
	TweenService:Create(f, TweenInfo.new(0.25), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(l, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
	task.delay(3.4, function()
		TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		for _, d in f:GetChildren() do if d:IsA("UIStroke") then TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play() end end
		Debris:AddItem(f, 0.5)
	end)
end

local subBar = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(640, 70), BackgroundColor3 = C3(6, 8, 20), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, gui)
corner(subBar, 12)
local subStroke = stroke(subBar, GOLD, 1.5, 1)
local subName = label(subBar, "COMMANDER VOX", 14, GOLD, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 16) })
local subText = label(subBar, "", 15, C3(235, 242, 255), Enum.Font.Gotham, { Position = UDim2.fromOffset(14, 24), Size = UDim2.new(1, -28, 0, 40), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
local subToken = 0
local function subtitle(text)
	subToken += 1
	local my = subToken
	subBar.Visible = true
	subText.Text = text
	subBar.BackgroundTransparency = 0.2
	subStroke.Transparency = 0.3
	subName.TextTransparency = 0
	subText.TextTransparency = 0
	task.delay(math.clamp(#text / 14, 3, 9), function()
		if my ~= subToken then return end
		TweenService:Create(subBar, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(subStroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(subName, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(subText, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.delay(0.55, function() if my == subToken then subBar.Visible = false end end)
	end)
end

----------------------------------------------------------------------
-- cards
----------------------------------------------------------------------
local function actionButton(parent, text, color, onClick)
	local b = new("TextButton", {
		Size = UDim2.fromOffset(120, 36), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
		BackgroundColor3 = color, Text = text, Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = C3(8, 12, 24), AutoButtonColor = true,
	}, parent)
	corner(b, 8)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function act(...)
	local ok, success, message = pcall(function(...) return actionRemote:InvokeServer(...) end, ...)
	if ok and success then
		playOnce(9125973433, 0.25, 1.8)
		return true
	end
	playOnce(9125973984, 0.3, 0.7)
	toast((ok and message) or "Something went wrong, try again.", RED)
	return false
end

local TIER_ORDER = { Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Common = 1 }

local confirmOverlay
local function closeConfirm()
	if confirmOverlay then
		local o = confirmOverlay
		confirmOverlay = nil
		TweenService:Create(o, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		task.delay(0.16, function() o:Destroy() end)
	end
end
local function showSkipConfirm(id)
	closeConfirm()
	local m = Items.Missions[id]
	local d = m.difficulty or 1
	local price = Mon.skipPrice(d)
	local color = Items.rarityColor(m.tier)
	local overlay = new("TextButton", { Name = "SkipConfirm", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(0, 0, 10), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 40, Selectable = false }, gui)
	TweenService:Create(overlay, TweenInfo.new(0.2), { BackgroundTransparency = 0.4 }):Play()
	confirmOverlay = overlay
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(470, 372), BackgroundColor3 = C3(9, 12, 30), ZIndex = 41, Active = true }, overlay)
	corner(card, 18)
	stroke(card, C3(70, 230, 120), 3)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(14, 40, 30), C3(8, 10, 26)) }, card)
	local vp = workspace.CurrentCamera.ViewportSize
	local fit = math.min(1, (vp.Y - 30) / 372, (vp.X - 30) / 470)
	local sc = new("UIScale", { Scale = 0.4 }, card)
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	local function L(text, size, col, font, y, h, props)
		local p = { Position = UDim2.fromOffset(26, y), Size = UDim2.new(1, -52, 0, h), ZIndex = 42, TextWrapped = true }
		if props then for k, v in props do p[k] = v end end
		return label(card, text, size, col, font, p)
	end
	L("SKIP THIS MISSION?", 25, C3(120, 255, 160), Enum.Font.GothamBlack, 16, 32, { TextXAlignment = Enum.TextXAlignment.Center })
	L(m.name, 24, color, Enum.Font.GothamBlack, 56, 30, { TextXAlignment = Enum.TextXAlignment.Center })
	local stars = {}
	for i = 1, Mon.MAX_DIFFICULTY do
		stars[#stars + 1] = (i <= d) and '<font color="#ffc85a">\u{2605}</font>' or '<font color="#4a5470">\u{2605}</font>'
	end
	L("DIFFICULTY  " .. table.concat(stars, " "), 15, C3(215, 228, 245), Enum.Font.GothamBold, 90, 20, { RichText = true, TextXAlignment = Enum.TextXAlignment.Center })
	L("TARGET:  " .. m.short, 14, GOLD, Enum.Font.GothamBold, 120, 20, { TextXAlignment = Enum.TextXAlignment.Center })
	new("Frame", { Position = UDim2.fromOffset(26, 150), Size = UDim2.new(1, -52, 0, 2), BackgroundColor3 = C3(70, 230, 120), BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 42 }, card)
	L("YOU GET IT ALL, RIGHT NOW:", 12, C3(170, 190, 220), Enum.Font.GothamBold, 160, 16)
	L("$" .. money(m.reward.money or 0) .. "   +" .. (m.reward.iron or 0) .. " IRON", 18, GREEN, Enum.Font.GothamBlack, 178, 24)
	if m.unlocks then
		local it = Items.List[m.unlocks]
		L("+ UNLOCKS  " .. it.name .. "   (" .. it.rarity:upper() .. ")", 15, Items.rarityColor(it.rarity), Enum.Font.GothamBlack, 206, 22)
	end
	L("Price: 29 R$ + 30 R$ for every difficulty level  =  " .. price .. " R$.  The purchase is made through Roblox.", 12, C3(150, 168, 200), Enum.Font.Gotham, 240, 34, { TextYAlignment = Enum.TextYAlignment.Top })
	local live = Mon.Products["skip_" .. d].id ~= 0
	if not live and Mon.TEST_MODE then
		L("(Studio test mode: this purchase is simulated and free)", 11, C3(255, 200, 120), Enum.Font.GothamBold, 276, 16, { TextXAlignment = Enum.TextXAlignment.Center })
	end
	local buy = new("TextButton", { Name = "SkipBuyButton", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 26, 1, -16), Size = UDim2.new(0.6, -32, 0, 42), BackgroundColor3 = (live or Mon.TEST_MODE) and C3(70, 230, 120) or C3(70, 90, 80), Text = (live or Mon.TEST_MODE) and ("SKIP FOR  R$ " .. price) or "COMING SOON", Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = C3(6, 26, 12), ZIndex = 42 }, card)
	corner(buy, 10)
	local cancel = new("TextButton", { Name = "SkipCancelButton", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -26, 1, -16), Size = UDim2.new(0.4, -32, 0, 42), BackgroundColor3 = C3(40, 48, 80), Text = "CANCEL", Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = C3(220, 232, 255), ZIndex = 42 }, card)
	corner(cancel, 10)
	cancel.Activated:Connect(closeConfirm)
	overlay.Activated:Connect(closeConfirm)
	buy.Activated:Connect(function()
		if not live and not Mon.TEST_MODE then
			toast("Skipping is not on sale yet.", C3(255, 200, 90))
			return
		end
		closeConfirm()
		act("robuxSkip", id)
	end)
	playOnce(9125973433, 0.25, 1.5)
end
local function skipButton(card, id, m, y)
	local price = Mon.skipPrice(m.difficulty or 1)
	local b = new("TextButton", { Name = "SkipButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, y), Size = UDim2.fromOffset(132, 28), BackgroundColor3 = C3(20, 60, 44), Text = "SKIP   R$ " .. price, Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = C3(140, 255, 180), AutoButtonColor = true }, card)
	corner(b, 8)
	stroke(b, C3(70, 230, 120), 1.4, 0.2)
	b.Activated:Connect(function() showSkipConfirm(id) end)
	return b
end

local function missionCard(id, order)
	local m = Items.Missions[id]
	local color = Items.rarityColor(m.tier)
	local isActive = state.active and state.active.id == id
	local done = state.done[id] and not m.repeatable
	local locked = m.requires and not state.done[m.requires]
	local card = new("Frame", { Name = id, Size = UDim2.new(1, 0, 0, 142), BackgroundColor3 = CARD, LayoutOrder = order }, content)
	corner(card, 12)
	stroke(card, isActive and GOLD or color, isActive and 2.5 or 1.4, (done or locked) and 0.65 or 0.1)
	local bar = new("Frame", { Size = UDim2.new(0, 6, 1, -20), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = color, BorderSizePixel = 0, BackgroundTransparency = (done or locked) and 0.6 or 0 }, card)
	corner(bar, 3)
	local dimmed = (done or locked) and 0.45 or 0
	local nameL = label(card, m.name, 20, color, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(28, 8), Size = UDim2.new(1, -190, 0, 26), TextTransparency = dimmed })
	local tag = label(card, (m.repeatable and "REPEATABLE \u{2022} " or "STORY \u{2022} ") .. m.tier:upper(), 12, C3(150, 175, 205), Enum.Font.GothamBold, { Position = UDim2.fromOffset(28, 34), Size = UDim2.new(1, -190, 0, 16), TextTransparency = dimmed })
	local brief = label(card, m.brief, 14, C3(205, 220, 240), Enum.Font.Gotham, { Position = UDim2.fromOffset(28, 52), Size = UDim2.new(1, -190, 0, 50), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTransparency = dimmed })
	local rewardText = "$" .. money(m.reward.money or 0) .. "   +" .. (m.reward.iron or 0) .. " IRON"
	if m.unlocks then
		local it = Items.List[m.unlocks]
		rewardText ..= "   \u{2022}   UNLOCKS  " .. it.name .. "  (" .. it.rarity:upper() .. ")"
	end
	label(card, "TARGET: " .. m.short, 13, GOLD, Enum.Font.GothamBold, { Position = UDim2.fromOffset(28, 104), Size = UDim2.new(1, -190, 0, 16), TextTransparency = dimmed })
	label(card, "REWARD: " .. rewardText, 13, GREEN, Enum.Font.GothamBold, { Position = UDim2.fromOffset(28, 121), Size = UDim2.new(1, -190, 0, 16), TextTransparency = dimmed })
	if isActive then
		local prog = state.active.progress or 0
		local holder = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(150, 16), BackgroundColor3 = C3(8, 12, 24), BorderSizePixel = 0 }, card)
		corner(holder, 8)
		local fill = new("Frame", { Size = UDim2.fromScale(math.clamp(prog / m.target, 0, 1), 1), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, holder)
		corner(fill, 8)
		label(card, prog .. " / " .. m.target, 14, GOLD, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 34), Size = UDim2.fromOffset(150, 18), TextXAlignment = Enum.TextXAlignment.Center })
		local b = actionButton(card, "ABANDON", C3(255, 110, 120), function()
			if act("abandon") then toast("Mission abandoned.", C3(255, 150, 150)) end
		end)
		b.Position = UDim2.new(1, -14, 0, 80)
		b.AnchorPoint = Vector2.new(1, 0.5)
		skipButton(card, id, m, 106)
	elseif done then
		label(card, "\u{2713} COMPLETED", 16, GREEN, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(150, 30), TextXAlignment = Enum.TextXAlignment.Center })
	elseif locked then
		label(card, "\u{1F512} LOCKED\nFinish: " .. Items.Missions[m.requires].name, 13, C3(150, 165, 190), Enum.Font.GothamBold, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(160, 44), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
	else
		local ab = actionButton(card, "ACCEPT", color, function()
			if act("accept", id) then
				playOnce(9125973257, 0.4, 1.4)
			end
		end)
		ab.Position = UDim2.new(1, -14, 0, 50)
		skipButton(card, id, m, 106)
	end
	return card
end

local lockedOverlay
local function closeLocked()
	if lockedOverlay then
		local o = lockedOverlay
		lockedOverlay = nil
		TweenService:Create(o, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		task.delay(0.16, function() o:Destroy() end)
	end
end
local function missionChain(missionId)
	local chain, id = {}, missionId
	while id do
		table.insert(chain, 1, id)
		id = Items.Missions[id] and Items.Missions[id].requires
	end
	return chain
end
local function hex(c)
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local closePanelRef -- (set later: closes the shop window)
local function showLockedInfo(itemId)
	closeLocked()
	local it = Items.List[itemId]
	local color = Items.rarityColor(it.rarity)
	local chain = missionChain(it.mission)
	local nowId
	for _, mid in chain do
		if not state.done[mid] then nowId = mid break end
	end
	nowId = nowId or it.mission
	local m = Items.Missions[nowId]

	local overlay = new("TextButton", { Name = "LockedInfo", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(0, 0, 10), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 40, Selectable = false }, gui)
	TweenService:Create(overlay, TweenInfo.new(0.2), { BackgroundTransparency = 0.38 }):Play()
	lockedOverlay = overlay
	local H = (#chain > 1) and 480 or 436
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, H), BackgroundColor3 = C3(9, 12, 30), ZIndex = 41, Active = true }, overlay)
	corner(card, 18)
	local cs = stroke(card, RED, 3.2)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(44, 14, 26), C3(8, 10, 26)) }, card)
	local vp = workspace.CurrentCamera.ViewportSize
	local fit = math.min(1, (vp.Y - 30) / H, (vp.X - 30) / 520)
	local sc = new("UIScale", { Scale = 0.35 }, card)
	TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	TweenService:Create(cs, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 }):Play()

	local function L(text, size, col, font, y, h, props)
		local p = { Position = UDim2.fromOffset(28, y), Size = UDim2.new(1, -56, 0, h), ZIndex = 42, TextWrapped = true }
		if props then for k, v in props do p[k] = v end end
		return label(card, text, size, col, font, p)
	end
	L("\u{1F512}  ACCESS DENIED", 28, RED, Enum.Font.GothamBlack, 14, 36, { TextXAlignment = Enum.TextXAlignment.Center })
	L("This gear is not for rookies. Earn it first.", 14, C3(255, 170, 180), Enum.Font.GothamBold, 50, 20, { TextXAlignment = Enum.TextXAlignment.Center })

	-- the item
	local medal = new("Frame", { Position = UDim2.fromOffset(28, 82), Size = UDim2.fromOffset(70, 70), BackgroundColor3 = color:Lerp(C3(0, 0, 0), 0.8), BorderSizePixel = 0, ZIndex = 42 }, card)
	corner(medal, 35)
	stroke(medal, color, 3)
	label(medal, it.icon, 38, color, Enum.Font.GothamBlack, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 43 })
	L(it.name, 24, color, Enum.Font.GothamBlack, 84, 30, { Position = UDim2.fromOffset(112, 84), Size = UDim2.new(1, -140, 0, 30) })
	L(it.rarity:upper() .. "  \u{2022}  " .. it.stat, 13, GOLD, Enum.Font.GothamBold, 114, 38, { Position = UDim2.fromOffset(112, 114), Size = UDim2.new(1, -140, 0, 38), TextYAlignment = Enum.TextYAlignment.Top })

	new("Frame", { Position = UDim2.fromOffset(28, 164), Size = UDim2.new(1, -56, 0, 2), BackgroundColor3 = RED, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 42 }, card)

	-- what you must do
	L("TO UNLOCK IT YOU MUST COMPLETE THE MISSION", 12, C3(190, 205, 235), Enum.Font.GothamBold, 174, 16)
	L(m.name, 26, Items.rarityColor(m.tier), Enum.Font.GothamBlack, 192, 32)
	L("\u{25B6}  " .. m.short:upper(), 17, GOLD, Enum.Font.GothamBlack, 226, 24)
	L("\u{201C}" .. m.brief .. "\u{201D}", 13, C3(205, 218, 240), Enum.Font.Gotham, 254, 54, { TextYAlignment = Enum.TextYAlignment.Top })

	-- the chain of missions, when more than one is needed
	if #chain > 1 then
		local parts = {}
		for _, mid in chain do
			local nm = Items.Missions[mid].name
			if state.done[mid] then
				parts[#parts + 1] = '<font color="' .. hex(GREEN) .. '">\u{2713} ' .. nm .. "</font>"
			elseif mid == nowId then
				parts[#parts + 1] = '<font color="' .. hex(GOLD) .. '">\u{25B6} ' .. nm .. "</font>"
			else
				parts[#parts + 1] = '<font color="#7d8aa8">\u{1F512} ' .. nm .. "</font>"
			end
		end
		L("MISSIONS IN ORDER:", 11, C3(150, 170, 200), Enum.Font.GothamBold, 312, 14)
		L(table.concat(parts, "   \u{2192}   "), 13, C3(255, 255, 255), Enum.Font.GothamBold, 327, 34, { RichText = true, TextYAlignment = Enum.TextYAlignment.Top })
	end
	local yy = (#chain > 1) and 364 or 312
	L("REWARD:  $" .. money(m.reward.money or 0) .. "  +" .. (m.reward.iron or 0) .. " iron" .. (m.unlocks and ("   \u{2022}   unlocks  " .. Items.List[m.unlocks].name) or ""), 13, GREEN, Enum.Font.GothamBold, yy, 18)
	L("WHERE:  Commander Vox, MISSION CONTROL - the far side of the ship, behind the reactor.", 13, C3(255, 190, 90), Enum.Font.GothamBold, yy + 20, 34, { TextYAlignment = Enum.TextYAlignment.Top })

	-- buttons
	local guide = new("TextButton", { Name = "GuideButton", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 28, 1, -14), Size = UDim2.new(0.58, -34, 0, 38), BackgroundColor3 = GOLD, Text = "SHOW ME THE WAY", Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = C3(8, 12, 24), ZIndex = 42 }, card)
	corner(guide, 10)
	local gotit = new("TextButton", { Name = "GotItButton", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -14), Size = UDim2.new(0.42, -34, 0, 38), BackgroundColor3 = C3(40, 48, 80), Text = "GOT IT", Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = C3(220, 232, 255), ZIndex = 42 }, card)
	corner(gotit, 10)
	gotit.Activated:Connect(closeLocked)
	overlay.Activated:Connect(closeLocked)
	guide.Activated:Connect(function()
		local cmd = workspace:FindFirstChild("AlienShip") and workspace.AlienShip:FindFirstChild("Aliens") and workspace.AlienShip.Aliens:FindFirstChild("CommanderAlien")
		local torso = cmd and cmd:FindFirstChild("Torso")
		if torso then
			guideTarget = { part = torso, name = "Commander Vox" }
			toast("Follow the arrow on the left to Commander Vox (Mission Control).", GOLD)
		end
		playOnce(9125973257, 0.35, 1.4)
		closeLocked()
		if closePanelRef then closePanelRef() end
	end)
	playOnce(9125973984, 0.4, 0.55)
	playOnce(9065667699, 0.15, 1.8)
end

local function itemCard(id, order)
	local it = Items.List[id]
	local color = Items.rarityColor(it.rarity)
	local unlocked = state.unlocked[id]
	local owned = state.owned[id]
	local card = new("Frame", { Name = id, Size = UDim2.new(1, 0, 0, 152), BackgroundColor3 = C3(255, 255, 255), LayoutOrder = order, ClipsDescendants = true }, content)
	corner(card, 14)
	-- a background that glows in the colour of the rarity
	new("UIGradient", { Rotation = 0, Color = ColorSequence.new(color:Lerp(C3(10, 14, 32), unlocked and 0.62 or 0.82), C3(11, 15, 36)) }, card)
	local cStroke = stroke(card, color, owned and 2.8 or 1.8, unlocked and 0.05 or 0.72)
	local cScale = new("UIScale", { Scale = 1 }, card)
	card.MouseEnter:Connect(function() TweenService:Create(cScale, TweenInfo.new(0.15), { Scale = 1.012 }):Play() end)
	card.MouseLeave:Connect(function() TweenService:Create(cScale, TweenInfo.new(0.15), { Scale = 1 }):Play() end)

	-- the icon in a glowing medallion (it pulses when you can buy / use it)
	local iconBox = new("Frame", { Size = UDim2.fromOffset(92, 92), Position = UDim2.fromOffset(14, 30), BackgroundColor3 = color:Lerp(C3(0, 0, 0), 0.8), BorderSizePixel = 0 }, card)
	corner(iconBox, 46)
	local iconStroke = stroke(iconBox, color, 3, unlocked and 0.1 or 0.75)
	if unlocked then
		TweenService:Create(iconStroke, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6, Transparency = 0.5 }):Play()
	end
	label(iconBox, it.icon, 50, color, Enum.Font.GothamBlack, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = unlocked and 0 or 0.7 })

	local dimmed = unlocked and 0 or 0.5
	label(card, it.name, 21, color, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(122, 8), Size = UDim2.new(1, -290, 0, 28), TextTransparency = dimmed })
	label(card, (it.slot == "Weapon" and "WEAPON" or it.slot:upper()) .. "   \u{2022}   " .. (it.slot == "Weapon" and "goes to your backpack" or "equip in LOADOUT"), 12, C3(150, 175, 205), Enum.Font.GothamBold, { Position = UDim2.fromOffset(122, 37), Size = UDim2.new(1, -290, 0, 16), TextTransparency = dimmed })
	label(card, it.desc, 14, C3(210, 224, 244), Enum.Font.Gotham, { Position = UDim2.fromOffset(122, 56), Size = UDim2.new(1, -290, 0, 44), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTransparency = dimmed })
	label(card, "\u{2605} " .. it.stat, 13, GOLD, Enum.Font.GothamBold, { Position = UDim2.fromOffset(122, 108), Size = UDim2.new(1, -290, 0, 36), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTransparency = dimmed })

	-- the rarity tag in the top-right corner
	local tag = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(104, 22), BackgroundColor3 = color, Text = it.rarity:upper(), Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = C3(8, 12, 24), BackgroundTransparency = unlocked and 0 or 0.55, TextTransparency = unlocked and 0 or 0.3 }, card)
	corner(tag, 11)
	if unlocked and not owned then
		local badge = new("TextLabel", { Position = UDim2.fromOffset(122 + 7 * #it.name + 40, 12), Size = UDim2.fromOffset(46, 18), BackgroundColor3 = GREEN, Text = "NEW", Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C3(6, 24, 12) }, card)
		corner(badge, 9)
		TweenService:Create(badge, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.5 }):Play()
		-- a light sweeps across the card that you can buy
		local shine = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(-0.15, 0, 0.5, 0), Size = UDim2.new(0, 46, 2, 0), Rotation = 18, BackgroundColor3 = C3(255, 255, 255), BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 5 }, card)
		TweenService:Create(shine, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, false, 2.4), { Position = UDim2.new(1.15, 0, 0.5, 0) }):Play()
	end

	if owned then
		local eq = state.equipped[it.slot] == id
		if it.slot == "Weapon" then
			label(card, "\u{2713} OWNED\nin your backpack", 14, GREEN, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.55, 0), Size = UDim2.fromOffset(150, 44), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
		else
			local b = actionButton(card, eq and "EQUIPPED" or "EQUIP", eq and GREEN or color, function()
				act("equip", it.slot, eq and "" or id)
			end)
			b.Position = UDim2.new(1, -14, 0.58, 0)
			b.Size = UDim2.fromOffset(130, 40)
		end
	elseif unlocked then
		local afford = stat("Money") >= it.price
		local b = actionButton(card, "BUY   $" .. money(it.price), afford and GOLD or C3(120, 110, 80), function()
			if act("buy", id) then playOnce(9125974640, 0.35, 1.5) end
		end)
		b.Position = UDim2.new(1, -14, 0.58, 0)
		b.Size = UDim2.fromOffset(160, 42)
		if not afford then
			label(card, "not enough money", 12, C3(255, 140, 140), Enum.Font.GothamBold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0.58, 26), Size = UDim2.fromOffset(160, 16), TextXAlignment = Enum.TextXAlignment.Center })
		end
	else
		local need = Items.Missions[it.mission]
		label(card, "\u{1F512}  LOCKED", 16, C3(255, 150, 160), Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 40), Size = UDim2.fromOffset(190, 22), TextXAlignment = Enum.TextXAlignment.Center })
		label(card, "Mission:  " .. (need and need.name or "?"), 13, C3(190, 200, 225), Enum.Font.GothamBold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 64), Size = UDim2.fromOffset(190, 20), TextXAlignment = Enum.TextXAlignment.Center })
		local hintBtn = new("TextButton", { Name = "Hint_" .. id, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 92), Size = UDim2.fromOffset(190, 30), BackgroundColor3 = C3(70, 24, 40), Text = "WHAT MUST I DO?", Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = C3(255, 200, 210), AutoButtonColor = true, ZIndex = 9 }, card)
		corner(hintBtn, 8)
		stroke(hintBtn, RED, 1.5, 0.2)
		label(card, "$" .. money(it.price), 15, C3(190, 170, 110), Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 126), Size = UDim2.fromOffset(190, 20), TextXAlignment = Enum.TextXAlignment.Center })
		-- the whole card is a button, too
		local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, card)
		hit.Activated:Connect(function() showLockedInfo(id) end)
		hintBtn.Activated:Connect(function() showLockedInfo(id) end)
	end
	return card
end

local function sectionTitle(text, order, color)
	local l = label(content, text, 15, color or C3(150, 190, 230), Enum.Font.GothamBlack, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order })
	return l
end

local function robuxButton(parent, key, w, h)
	local entry = Mon.Products[key] or Mon.Passes[key]
	local live = entry.id ~= 0
	local text = live and ("R$  " .. entry.price) or (Mon.TEST_MODE and ("R$  " .. entry.price .. "  (test)") or "COMING SOON")
	local b = new("TextButton", { Name = "Buy_" .. key, Size = UDim2.fromOffset(w, h), BackgroundColor3 = (live or Mon.TEST_MODE) and C3(70, 230, 120) or C3(70, 90, 80), Text = text, Font = Enum.Font.GothamBlack, TextSize = 17, TextColor3 = C3(6, 26, 12), AutoButtonColor = true }, parent)
	corner(b, 10)
	if live or Mon.TEST_MODE then
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(130, 255, 170), C3(40, 200, 100)) }, b)
		stroke(b, C3(210, 255, 225), 1.5, 0.35)
	end
	b.Activated:Connect(function()
		if not live and not Mon.TEST_MODE then
			toast("This item is not on sale yet.", C3(255, 200, 90))
			return
		end
		act("robuxBuy", key)
	end)
	return b
end

local function contentLines(entry)
	local lines = {}
	for _, id in entry.items or {} do
		local it = Items.List[id]
		lines[#lines + 1] = { icon = it.icon, text = it.name, color = Items.rarityColor(it.rarity), owned = state.owned[id] }
	end
	if entry.raygun then
		lines[#lines + 1] = { icon = "\u{2605}", text = "SECRET WEAPON", color = Items.rarityColor("Secret"), owned = state.owned.AetherRaygun }
	end
	if entry.money then lines[#lines + 1] = { icon = "$", text = "$" .. money(entry.money), color = GOLD } end
	if entry.iron then lines[#lines + 1] = { icon = "\u{25C6}", text = money(entry.iron) .. " IRON", color = C3(190, 205, 235) } end
	return lines
end

local function secretCard(order)
	local pass = Mon.Passes.AetherRaygun
	local it = Items.List.AetherRaygun
	local owned = state.owned.AetherRaygun
	local color = Items.rarityColor("Secret")
	local card = new("Frame", { Name = "SecretCard", Size = UDim2.new(1, 0, 0, 200), BackgroundColor3 = C3(255, 255, 255), LayoutOrder = order, ClipsDescendants = true }, content)
	corner(card, 16)
	new("UIGradient", { Rotation = 20, Color = ColorSequence.new(C3(78, 10, 28), C3(16, 8, 28)) }, card)
	local st = stroke(card, color, 3.2)
	TweenService:Create(st, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5.5, Transparency = 0.45 }):Play()
	local scan = new("Frame", { Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 0, -4), BackgroundColor3 = color, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 4 }, card)
	TweenService:Create(scan, TweenInfo.new(2.6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false), { Position = UDim2.new(0, 0, 1, 0) }):Play()
	local medal = new("Frame", { Position = UDim2.fromOffset(24, 44), Size = UDim2.fromOffset(112, 112), BackgroundColor3 = C3(40, 6, 16), BorderSizePixel = 0 }, card)
	corner(medal, 56)
	local ms = stroke(medal, color, 3.5)
	TweenService:Create(ms, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 7, Transparency = 0.5 }):Play()
	label(medal, owned and it.icon or "?", owned and 60 or 78, color, Enum.Font.GothamBlack, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	label(card, "SECRET WEAPON", 13, color, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(156, 14), Size = UDim2.new(1, -330, 0, 18) })
	label(card, owned and it.name or "[ C L A S S I F I E D ]", 26, C3(255, 255, 255), Enum.Font.GothamBlack, { Position = UDim2.fromOffset(156, 34), Size = UDim2.new(1, -330, 0, 34) })
	label(card, owned and it.stat or pass.tagline, 14, C3(255, 205, 214), Enum.Font.Gotham, { Position = UDim2.fromOffset(156, 72), Size = UDim2.new(1, -330, 0, 40), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	label(card, "\u{2022} Chain lightning that jumps between aliens\n\u{2022} Goes straight to your backpack\n\u{2022} Yours forever: one purchase, no random", 13, C3(255, 230, 235), Enum.Font.GothamBold, { Position = UDim2.fromOffset(156, 116), Size = UDim2.new(1, -330, 0, 60), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	if owned then
		label(card, "\u{2713} OWNED\nin your backpack", 17, GREEN, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 0), Size = UDim2.fromOffset(170, 50), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
	else
		local b = robuxButton(card, "AetherRaygun", 170, 52)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -22, 0.5, 0)
		b.TextSize = 22
	end
	return card
end

local paidRandomRestricted -- nil = not asked yet
local function chestCard(order)
	if paidRandomRestricted == nil then
		paidRandomRestricted = false
		local ok, policy = pcall(function() return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player) end)
		if ok and policy and policy.ArePaidRandomItemsRestricted then paidRandomRestricted = true end
	end
	if paidRandomRestricted then return nil end -- hidden for accounts where Roblox restricts paid random items
	local e = Mon.Products[Mon.ChestKey]
	local card = new("Frame", { Name = "BossChestCard", Size = UDim2.new(1, 0, 0, 214), BackgroundColor3 = WHITE, LayoutOrder = order, ClipsDescendants = true }, content)
	corner(card, 16)
	new("UIGradient", { Rotation = 20, Color = ColorSequence.new(C3(70, 52, 14), C3(18, 14, 34)) }, card)
	local st = stroke(card, GOLD, 3)
	TweenService:Create(st, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5, Transparency = 0.4 }):Play()
	local medal = new("Frame", { Position = UDim2.fromOffset(20, 18), Size = UDim2.fromOffset(104, 104), BackgroundColor3 = C3(40, 30, 8), BorderSizePixel = 0 }, card)
	corner(medal, 52)
	stroke(medal, GOLD, 3)
	label(medal, "\u{1F4E6}", 58, WHITE, Enum.Font.GothamBlack, { Size = UDim2.fromScale(1, 1) })
	label(card, "BOSS CHEST", 28, GOLD, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(144, 14), Size = UDim2.new(1, -350, 0, 34), TextXAlignment = Enum.TextXAlignment.Left })
	label(card, "Opens with the full cinematic: a RANDOM weapon from the 17 boss weapons.", 13, C3(235, 225, 200), Enum.Font.Gotham, { Position = UDim2.fromOffset(144, 48), Size = UDim2.new(1, -350, 0, 34), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	label(card, "ODDS:   Rare 52%   |   Epic 30%   |   Legendary 14%   |   SECRET 4%", 13, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(144, 86), Size = UDim2.new(1, -350, 0, 18), TextXAlignment = Enum.TextXAlignment.Left })
	label(card, "Bad-luck protection: a Legendary or better is guaranteed every 12 chests, a SECRET every 60. A weapon you already own pays money instead.", 11, C3(190, 200, 225), Enum.Font.Gotham, { Position = UDim2.fromOffset(144, 106), Size = UDim2.new(1, -350, 0, 30), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	-- everything that can drop
	local rowTitle = label(card, "WHAT CAN DROP:", 11, C3(150, 165, 195), Enum.Font.GothamBold, { Position = UDim2.fromOffset(20, 138), Size = UDim2.fromOffset(120, 14), TextXAlignment = Enum.TextXAlignment.Left })
	local row = new("Frame", { Position = UDim2.fromOffset(20, 156), Size = UDim2.new(1, -40, 0, 40), BackgroundTransparency = 1 }, card)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5) }, row)
	local rc = { Rare = C3(90, 170, 255), Epic = C3(190, 100, 255), Legendary = C3(255, 200, 80), Secret = C3(255, 60, 90) }
	for _, id in Loot.Order do
		local w = Loot.Weapons[id]
		local tile = new("Frame", { Size = UDim2.fromOffset(40, 40), BackgroundColor3 = rc[w.rarity]:Lerp(C3(10, 10, 24), 0.7), BorderSizePixel = 0 }, row)
		corner(tile, 8)
		stroke(tile, rc[w.rarity], 1.6)
		label(tile, w.icon, 22, WHITE, Enum.Font.GothamBlack, { Size = UDim2.fromScale(1, 1) })
	end
	local b = robuxButton(card, Mon.ChestKey, 190, 60)
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -20, 0, 26)
	b.TextSize = 24
	label(card, "one chest, opened right away", 11, C3(190, 200, 225), Enum.Font.Gotham, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 92), Size = UDim2.fromOffset(190, 16) })
	return card
end

local function bundleCard(parent, key, owned)
	local e = Mon.Products[key]
	local color = C3(e.accent[1], e.accent[2], e.accent[3])
	local card = new("Frame", { Name = key, Size = UDim2.new(1 / 3, -7, 1, 0), BackgroundColor3 = C3(255, 255, 255), ClipsDescendants = true }, parent)
	corner(card, 14)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(C3(10, 14, 32), 0.7), C3(10, 13, 30)) }, card)
	local st = stroke(card, color, 2.4)
	if e.tag == "BEST VALUE" then
		TweenService:Create(st, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 4.5, Transparency = 0.4 }):Play()
	end
	local tag = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(104, 20), BackgroundColor3 = color, Text = e.tag, Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C3(8, 12, 24) }, card)
	corner(tag, 10)
	label(card, e.name, 20, color, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 26) })
	label(card, e.tagline, 12, C3(200, 215, 240), Enum.Font.Gotham, { Position = UDim2.fromOffset(14, 60), Size = UDim2.new(1, -28, 0, 32), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	label(card, "WHAT YOU GET", 11, C3(150, 170, 200), Enum.Font.GothamBold, { Position = UDim2.fromOffset(14, 96), Size = UDim2.new(1, -28, 0, 14) })
	local list = new("Frame", { Position = UDim2.fromOffset(14, 112), Size = UDim2.new(1, -28, 1, -176), BackgroundTransparency = 1 }, card)
	new("UIListLayout", { Padding = UDim.new(0, 2) }, list)
	for _, ln in contentLines(e) do
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 19), BackgroundTransparency = 1 }, list)
		label(row, ln.icon, 15, ln.color, Enum.Font.GothamBlack, { Size = UDim2.fromOffset(22, 19), TextXAlignment = Enum.TextXAlignment.Center })
		label(row, ln.text .. (ln.owned and "   (owned)" or ""), 13, ln.owned and C3(130, 145, 170) or C3(235, 242, 255), Enum.Font.GothamBold, { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -28, 1, 0) })
	end
	local b = robuxButton(card, key, 170, 44)
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -14)
	return card
end

local function renderStore()
	title.Text = "R$ STORE"
	local order = 0
	order += 1
	label(content, "Every offer shows exactly what you get. The BOSS CHEST is the only random one: its odds are on the card. Purchases are handled by Roblox.", 13, C3(150, 185, 225), Enum.Font.Gotham, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order })
	order += 1
	sectionTitle("\u{2605}  SECRET WEAPON", order, Items.rarityColor("Secret"))
	order += 1
	secretCard(order)
	order += 1
	if chestCard(order) then
		order += 1
		sectionTitle("BUNDLES", order, GOLD)
	else
		sectionTitle("BUNDLES", order, GOLD)
	end
	order += 1
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 392), BackgroundTransparency = 1, LayoutOrder = order }, content)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i, key in Mon.Bundles do
		bundleCard(row, key).LayoutOrder = i
	end
	order += 1
	sectionTitle("PACKS & BOOSTS", order, C3(120, 255, 160))
	order += 1
	local packRow = new("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundTransparency = 1, LayoutOrder = order }, content)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, packRow)
	for packIndex, key in Mon.Packs do
		local e = Mon.Products[key]
		local color = C3(e.accent[1], e.accent[2], e.accent[3])
		local c = new("Frame", { Name = key, Size = UDim2.new(0.25, -6, 1, 0), BackgroundColor3 = C3(14, 20, 44), LayoutOrder = packIndex }, packRow)
		corner(c, 12)
		stroke(c, color, 1.8, 0.2)
		label(c, e.name, 15, color, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 20) })
		label(c, e.tagline, 11, C3(190, 205, 230), Enum.Font.Gotham, { Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 0, 30), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		label(c, e.money and ("$" .. money(e.money)) or "BOOST BAR  100%", 16, e.money and GOLD or CYAN, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 64), Size = UDim2.new(1, -20, 0, 22) })
		local b = robuxButton(c, key, 130, 34)
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -10)
		b.TextSize = 15
	end
	order += 1
	sectionTitle("SKIP A MISSION  (from the mission board)", order, C3(150, 190, 230))
	order += 1
	label(content, "Stuck on a mission? Open Commander Vox's board and press SKIP: you get ALL the rewards at once. Price: 29 R$ + 30 R$ for every difficulty level.", 13, C3(190, 205, 230), Enum.Font.Gotham, { Size = UDim2.new(1, 0, 0, 36), LayoutOrder = order, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
end

-- WEAPON LOADOUT (a section of the LOADOUT tab): choose up to 4 weapons for the hotbar; the others wait in the armory
local WEAPON_META = {
	["Starter Blaster"] = { rarity = "Common", icon = "\u{25CF}", stat = "Free. 5 damage a shot" },
	["Laser Pistol"] = { rarity = "Rare", icon = "\u{1F539}", stat = "15 damage, precise cyan beam" },
	["Plasma Rifle"] = { rarity = "Epic", icon = "\u{1F7E2}", stat = "Automatic plasma fire" },
	["Void Cannon"] = { rarity = "Legendary", icon = "\u{1F52E}", stat = "Charged 60 damage blast" },
	["Xeno Fang"] = { rarity = "Epic", icon = "\u{1F5E1}", stat = "Bleed damage" },
	["Hive Piercer"] = { rarity = "Legendary", icon = "\u{26A1}", stat = "Pierces up to 7 aliens" },
	["Aether Raygun"] = { rarity = "Secret", icon = "\u{2605}", stat = "Chain lightning" },
}
local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Secret = 5 }
local RARITY_COL = { Common = C3(170, 180, 200), Rare = C3(90, 170, 255), Epic = C3(190, 100, 255), Legendary = C3(255, 200, 80), Secret = C3(255, 60, 90) }
local function weaponInfo(tool)
	local id = Loot.ByTool[tool]
	if id then
		local w = Loot.Weapons[id]
		return { rarity = w.rarity, icon = w.icon, name = w.name, stat = w.stat }
	end
	local m = WEAPON_META[tool]
	return { rarity = m and m.rarity or "Common", icon = m and m.icon or "\u{25CF}", name = tool:upper(), stat = m and m.stat or "" }
end

-- 3D weapon previews (real models, built from the tool the player owns) --------------------------------------------
local previewTemplates = {}
local function findWeaponTool(name)
	local bp = player:FindFirstChild("Backpack")
	local stash = player:FindFirstChild("WeaponStash")
	return (bp and bp:FindFirstChild(name)) or (player.Character and player.Character:FindFirstChild(name)) or (stash and stash:FindFirstChild(name))
end
local function previewTemplate(name)
	local t = previewTemplates[name]
	if t then return t end
	local tool = findWeaponTool(name)
	local handle = tool and tool:FindFirstChild("Handle")
	if not handle then return nil end
	local model = Instance.new("Model")
	local h0 = handle.CFrame
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d:Clone()
			for _, ch in c:GetChildren() do
				if not ch:IsA("SpecialMesh") then ch:Destroy() end
			end
			c.Anchored = true
			c.CFrame = h0:ToObjectSpace(d.CFrame)
			if c.Material ~= Enum.Material.Neon and c.Material ~= Enum.Material.Glass and c.Material ~= Enum.Material.ForceField then
				c.Material = Enum.Material.SmoothPlastic -- flat shading: the weapon looks bright and clear in the preview
				c.Reflectance = 0
			end
			c.Parent = model
		end
	end
	previewTemplates[name] = model
	return model
end

-- the bounds of the weapon WITHOUT the few far-away decorations (floating shards, halos): so the weapon itself fills the frame
local function trimmedBounds(copy)
	local parts, wsum, centroid = {}, 0, Vector3.zero
	for _, p in copy:GetChildren() do
		if p:IsA("BasePart") then
			local v = math.max(p.Size.X * p.Size.Y * p.Size.Z, 1e-4)
			parts[#parts + 1] = p
			wsum += v
			centroid += p.Position * v
		end
	end
	centroid /= math.max(wsum, 1e-4)
	table.sort(parts, function(a, b) return (a.Position - centroid).Magnitude > (b.Position - centroid).Magnitude end)
	local skip = math.floor(#parts * 0.08)
	local mn, mx = Vector3.one * math.huge, Vector3.one * -math.huge
	for i = skip + 1, #parts do
		local p = parts[i]
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local q = p.CFrame:PointToWorldSpace(Vector3.new(sx, sy, sz) * p.Size / 2)
					mn = Vector3.new(math.min(mn.X, q.X), math.min(mn.Y, q.Y), math.min(mn.Z, q.Z))
					mx = Vector3.new(math.max(mx.X, q.X), math.max(mx.Y, q.Y), math.max(mx.Z, q.Z))
				end
			end
		end
	end
	return CFrame.new((mn + mx) / 2), mx - mn
end

-- AUTO-FIT: finds the camera distance at which EVERY corner of the weapon's bounding box stays inside the frame, at every angle the weapon will swing to
local function fitCamera(copy, aspect, fov)
	local bbCF, bbSize = trimmedBounds(copy)
	local center = bbCF.Position
	local corners = {}
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				corners[#corners + 1] = bbCF:PointToWorldSpace(Vector3.new(sx, sy, sz) * bbSize / 2)
			end
		end
	end
	local tanH = math.tan(math.rad(fov / 2))
	local function fits(angle, dist)
		local pos = center + Vector3.new(math.cos(angle) * dist, bbSize.Y * 0.1, math.sin(angle) * dist)
		local look = (center - pos).Unit
		local right = look:Cross(Vector3.yAxis).Unit
		local up = right:Cross(look)
		for _, q in corners do
			local v = q - pos
			local depth = v:Dot(look)
			if depth < 0.05 then return false end
			if math.abs(v:Dot(right) / depth / (tanH * aspect)) > 0.92 or math.abs(v:Dot(up) / depth / tanH) > 0.86 then return false end
		end
		return true
	end
	local function minDist(angle)
		local lo, hi = 0.5, math.max(bbSize.X, bbSize.Y, bbSize.Z) * 40
		for _ = 1, 28 do
			local mid = (lo + hi) / 2
			if fits(angle, mid) then hi = mid else lo = mid end
		end
		return hi
	end
	local dist = 0
	for _, ang in { -0.5, 0, 0.5 } do dist = math.max(dist, minDist(ang)) end
	return center, dist, bbSize
end

-- returns the ViewportFrame and a function that swings the camera round the weapon (a = radians, 0 = side view, the barrel points right)
local function weaponViewport(parent, name, position, size, z, aspect)
	local template = previewTemplate(name)
	if not template then return nil end
	local vp = new("ViewportFrame", { Position = position, Size = size, BackgroundTransparency = 1, ZIndex = z or 4, Ambient = C3(190, 190, 215), LightColor = C3(255, 255, 255), LightDirection = Vector3.new(-0.7, -0.6, -0.9) }, parent)
	local wm = new("WorldModel", {}, vp)
	local copy = template:Clone()
	copy.Parent = wm
	local fov = 28
	local cam = new("Camera", { FieldOfView = fov }, vp)
	vp.CurrentCamera = cam
	local center, dist, bbSize = fitCamera(copy, aspect or 1.8, fov)
	local function setAngle(a)
		cam.CFrame = CFrame.lookAt(center + Vector3.new(math.cos(a) * dist, bbSize.Y * 0.1, math.sin(a) * dist), center)
	end
	setAngle(0)
	return vp, setAngle
end

local function powerBar(parent, power, color, x, y, w)
	local frac = math.clamp(power / WeaponStats.MaxPower, 0.03, 1)
	local bg = new("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 8), BackgroundColor3 = C3(8, 10, 24), BorderSizePixel = 0, ZIndex = 6 }, parent)
	corner(bg, 4)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 7 }, bg)
	corner(fill, 4)
	new("UIGradient", { Color = ColorSequence.new(color:Lerp(WHITE, 0.45), color) }, fill)
	TweenService:Create(fill, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.fromScale(frac, 1) }):Play() -- the bar fills up
	return bg
end

-- the cinematic touches: an aura behind the weapon, a light sweep, twinkling sparks and a pulsing outline (stronger the rarer the weapon)
local function cardFx(card, rarity, outline, cx, cy)
	local col = RARITY_COL[rarity] or WHITE
	local rank = RARITY_RANK[rarity] or 1
	-- the aura
	local aura = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(150, 80), BackgroundColor3 = col, BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = 3 }, card)
	corner(aura, 40)
	if rank >= 3 then
		TweenService:Create(aura, TweenInfo.new(rank >= 5 and 0.8 or 1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.62, Size = UDim2.fromOffset(176, 96) }):Play()
	end
	if rank < 3 then return end
	-- the light sweep
	local sheen = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.3, 0.5), Size = UDim2.new(0.2, 0, 1.6, 0), Rotation = 18, BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 9 }, card)
	local delay = math.random() * 2
	task.spawn(function()
		task.wait(delay)
		while sheen.Parent do
			sheen.Position = UDim2.fromScale(-0.3, 0.5)
			TweenService:Create(sheen, TweenInfo.new(1.1, Enum.EasingStyle.Sine), { Position = UDim2.fromScale(1.3, 0.5) }):Play()
			task.wait(rank >= 5 and 1.8 or 3.5)
		end
	end)
	if outline and rank >= 4 then
		TweenService:Create(outline, TweenInfo.new(rank >= 5 and 0.6 or 1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = outline.Thickness + 2.4, Transparency = 0.3 }):Play()
	end
	-- twinkling sparks rising round the weapon (Legendary and Secret)
	if rank >= 4 then
		for i = 1, (rank >= 5) and 9 or 5 do
			local sp = new("Frame", { Size = UDim2.fromOffset(4, 4), Rotation = 45, BackgroundColor3 = (i % 2 == 0) and WHITE or col, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8 }, card)
			task.spawn(function()
				task.wait(math.random() * 2.5)
				while sp.Parent do
					local x = cx - 70 + math.random() * 140
					sp.Position = UDim2.fromOffset(x, cy + 30)
					sp.BackgroundTransparency = 0.1
					TweenService:Create(sp, TweenInfo.new(1.4 + math.random(), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(x + (math.random() - 0.5) * 24, cy - 46), BackgroundTransparency = 1 }):Play()
					task.wait(1.4 + math.random() * 1.2)
				end
			end)
		end
	end
end

local function hoverSpin(card, setAngle)
	if not setAngle then return end
	local conn
	card.MouseEnter:Connect(function()
		if conn then conn:Disconnect() end
		local t0 = os.clock()
		conn = RunService.RenderStepped:Connect(function()
			if not card.Parent then conn:Disconnect() return end
			setAngle(math.sin((os.clock() - t0) * 1.6) * 0.5)
		end)
	end)
	card.MouseLeave:Connect(function()
		if conn then conn:Disconnect() conn = nil end
		setAngle(0)
	end)
end

local function renderWeaponLoadout(order)
	local armory = state.armory or {}
	local current = {}
	if state.loadout then for _, n in state.loadout do current[#current + 1] = n end end
	local slotOf = {}
	for i, n in current do slotOf[n] = i end
	local function save(list)
		playOnce(9125973433, 0.25, 1.6)
		act("loadoutSave", list)
	end
	local sorted = table.clone(armory)
	table.sort(sorted, function(a, b)
		local ra, rb = RARITY_RANK[weaponInfo(a).rarity], RARITY_RANK[weaponInfo(b).rarity]
		if ra ~= rb then return ra > rb end
		local pa, pb = WeaponStats.get(a).power, WeaponStats.get(b).power
		if pa ~= pb then return pa > pb end
		return a < b
	end)

	order += 1
	sectionTitle("WEAPON LOADOUT   -   up to 4 weapons in your hotbar", order, GOLD)
	order += 1
	label(content, state.loadout and "These are the weapons in your hotbar. All the others wait in your ARMORY until you equip them." or "No loadout yet: ALL your weapons are in the hotbar. Pick up to 4 to keep it clean and fast.", 13, C3(170, 190, 220), Enum.Font.Gotham, { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
	order += 1
	local btnRow = new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = order }, content)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }, btnRow)
	local auto = new("TextButton", { Name = "AutoPick", Size = UDim2.fromOffset(210, 36), BackgroundColor3 = C3(40, 110, 70), Text = "AUTO-PICK MY BEST 4", Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = WHITE, LayoutOrder = 1 }, btnRow)
	corner(auto, 10)
	auto.Activated:Connect(function()
		local list = {}
		for i = 1, math.min(4, #sorted) do list[i] = sorted[i] end
		save(list)
	end)
	local clear = new("TextButton", { Name = "UseAll", Size = UDim2.fromOffset(230, 36), BackgroundColor3 = C3(50, 58, 96), Text = "USE ALL (NO LOADOUT)", Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = WHITE, LayoutOrder = 2 }, btnRow)
	corner(clear, 10)
	clear.Activated:Connect(function() save({}) end)

	-- the four hotbar slots, with the real weapon in them
	order += 1
	local slotRow = new("Frame", { Name = "Slots", Size = UDim2.new(1, 0, 0, 196), BackgroundTransparency = 1, LayoutOrder = order }, content)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, slotRow)
	for i = 1, 4 do
		local name = current[i]
		local info = name and weaponInfo(name)
		local col = info and RARITY_COL[info.rarity] or C3(70, 80, 120)
		local b = new("TextButton", { Name = "Slot" .. i, Size = UDim2.new(0.25, -6, 1, 0), BackgroundColor3 = info and col:Lerp(C3(8, 10, 24), 0.8) or C3(12, 16, 36), Text = "", AutoButtonColor = false, LayoutOrder = i, ClipsDescendants = true }, slotRow)
		corner(b, 14)
		local sk = stroke(b, col, info and 2.6 or 1.4, info and 0 or 0.5)
		label(b, "SLOT " .. i, 12, col, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(60, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
		if info then
			local stats = WeaponStats.get(name)
			cardFx(b, info.rarity, sk, 95, 70)
			local vp, setAngle = weaponViewport(b, name, UDim2.fromOffset(6, 20), UDim2.new(1, -12, 0, 104), 5, 1.75)
			if not vp then label(b, info.icon, 44, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 56), ZIndex = 5 }) end
			label(b, info.rarity:upper(), 12, col, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 128), Size = UDim2.new(1, -20, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
			label(b, info.name, 14, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 142), Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
			label(b, "POWER " .. stats.power, 13, col, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 162), Size = UDim2.new(1, -20, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
			powerBar(b, stats.power, col, 10, 180, 150)
			hoverSpin(b, setAngle)
			b.Activated:Connect(function()
				local list = {}
				for _, n in current do if n ~= name then list[#list + 1] = n end end
				save(list)
			end)
		else
			label(b, "EMPTY", 18, C3(90, 100, 140), Enum.Font.GothamBlack, { Position = UDim2.fromScale(0, 0.34), Size = UDim2.fromScale(1, 0.2), ZIndex = 8 })
			label(b, "pick a weapon below", 11, C3(110, 120, 160), Enum.Font.Gotham, { Position = UDim2.fromScale(0, 0.56), Size = UDim2.fromScale(1, 0.15), ZIndex = 8 })
		end
	end

	-- the armory: every weapon you own, with its real model, rarity and power
	order += 1
	sectionTitle("ARMORY   -   " .. #armory .. " weapons   (tap one to equip / unequip it; hover to turn it)", order, C3(150, 190, 230))
	order += 1
	local grid = new("Frame", { Name = "Armory", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, content)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(180, 216), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, name in sorted do
		local info = weaponInfo(name)
		local stats = WeaponStats.get(name)
		local col = RARITY_COL[info.rarity] or WHITE
		local slot = slotOf[name]
		local card = new("TextButton", { Name = "W_" .. name, BackgroundColor3 = col:Lerp(C3(8, 10, 24), 0.8), Text = "", AutoButtonColor = false, LayoutOrder = i, ClipsDescendants = true }, grid)
		corner(card, 14)
		local sk = stroke(card, slot and GREEN or col, slot and 3.2 or 1.8, slot and 0 or 0.2)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(col:Lerp(C3(14, 16, 36), 0.55), C3(8, 10, 24)) }, card)
		cardFx(card, info.rarity, sk, 90, 62)
		local vp, setAngle = weaponViewport(card, name, UDim2.fromOffset(4, 8), UDim2.new(1, -8, 0, 106), 5, 1.65)
		if not vp then label(card, info.icon, 48, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 60), ZIndex = 5 }) end
		local badge = slot and ("SLOT " .. slot) or (state.loadout and "ARMORY" or "HOTBAR")
		local pill = new("TextLabel", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(58, 18), BackgroundColor3 = slot and GREEN or C3(40, 48, 84), Text = badge, Font = Enum.Font.GothamBlack, TextSize = 10, TextColor3 = slot and C3(6, 20, 12) or C3(190, 200, 230), ZIndex = 8 }, card)
		corner(pill, 9)
		label(card, info.rarity:upper(), 12, col, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 118), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
		label(card, info.name, 14, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 134), Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
		label(card, "POWER", 10, C3(150, 165, 195), Enum.Font.GothamBold, { Position = UDim2.fromOffset(10, 156), Size = UDim2.fromOffset(46, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
		label(card, tostring(stats.power), 16, col, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(52, 153), Size = UDim2.fromOffset(60, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8 })
		label(card, string.format("%.1f shots/s", stats.shotsPerSecond), 10, C3(150, 165, 195), Enum.Font.Gotham, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 158), Size = UDim2.fromOffset(80, 12), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 8 })
		powerBar(card, stats.power, col, 10, 174, 160)
		label(card, stats.special, 10, C3(190, 205, 230), Enum.Font.Gotham, { Position = UDim2.fromOffset(10, 186), Size = UDim2.new(1, -20, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 8 })
		hoverSpin(card, setAngle)
		card.Activated:Connect(function()
			local list = {}
			for _, n in current do list[#list + 1] = n end
			if slot then
				table.remove(list, slot)
			elseif #list < 4 then
				list[#list + 1] = name
			else
				toast("Your hotbar is full (4). Tap an equipped weapon first to remove it.", C3(255, 200, 90))
				return
			end
			save(list)
		end)
	end
	return order
end

local hudMode = false -- true: the window was opened from the LOADOUT button on the left of the screen (only the loadout is shown, no shop)
local lastTabShown
refresh = function()
	updateFooter()
	if lastTabShown ~= currentTab then
		lastTabShown = currentTab
		content.CanvasPosition = Vector2.new(0, 0)
	end
	for _, c in content:GetChildren() do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local shopWindow = currentTab ~= "missions" -- the mission board is its own window, the shop window has SHOP + LOADOUT
	for name, b in tabButtons do
		if name == "missions" then
			b.Visible = false
		else
			b.Visible = shopWindow and (not hudMode or name == "loadout")
		end
		local on = name == currentTab
		b.BackgroundColor3 = on and CYAN or CARD
		b.TextColor3 = on and C3(6, 10, 24) or C3(160, 190, 220)
	end
	tabButtons.shop.Position = UDim2.fromScale(0.34, 0.22)
	tabButtons.robux.Position = UDim2.fromScale(0.51, 0.22)
	tabButtons.loadout.Position = hudMode and UDim2.fromScale(0.34, 0.22) or UDim2.fromScale(0.68, 0.22)
	if currentTab == "missions" then
		title.Text = "MISSION CONTROL"
		local order = 0
		local function add(cond, header2)
			local first = true
			for _, id in Items.MissionOrder do
				local m = Items.Missions[id]
				if cond(id, m) then
					if first and header2 then
						order += 1
						sectionTitle(header2, order)
						first = false
					end
					order += 1
					missionCard(id, order)
				end
			end
		end
		add(function(id) return state.active and state.active.id == id end, "\u{25B6} ACTIVE MISSION")
		add(function(id, m) return not (state.active and state.active.id == id) and not m.repeatable and not state.done[id] and (not m.requires or state.done[m.requires]) end, "AVAILABLE")
		add(function(id, m) return not (state.active and state.active.id == id) and m.repeatable and (not m.requires or state.done[m.requires]) end, "BOUNTIES  (repeat as often as you like)")
		add(function(id, m) return not state.done[id] and m.requires and not state.done[m.requires] and not m.repeatable end, "LOCKED")
		add(function(id, m) return state.done[id] and not m.repeatable end, "COMPLETED")
	elseif currentTab == "shop" then
		title.Text = "ALIEN SHOP"
		local order = 0
		-- intro + filter chips
		order += 1
		label(content, "Rare gear from beyond the stars. Finish missions to unlock it, then buy it with your money.", 13, C3(150, 185, 225), Enum.Font.Gotham, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order })
		order += 1
		local chips = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order }, content)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center }, chips)
		for _, def in { { "ALL", "ALL" }, { "Trail", "TRAILS" }, { "Passive", "PASSIVE" }, { "Weapon", "WEAPONS" } } do
			local on = shopFilter == def[1]
			local chip = new("TextButton", { Size = UDim2.fromOffset(92, 30), BackgroundColor3 = on and CYAN or CARD, Text = def[2], Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = on and C3(6, 10, 24) or C3(170, 195, 225), AutoButtonColor = false }, chips)
			corner(chip, 15)
			stroke(chip, CYAN, 1.4, on and 1 or 0.55)
			chip.Activated:Connect(function()
				shopFilter = def[1]
				playOnce(9125973433, 0.2, 1.8)
				refresh()
			end)
		end
		local ids = {}
		for _, id in Items.Order do
			if shopFilter == "ALL" or Items.List[id].slot == shopFilter then ids[#ids + 1] = id end
		end
		table.sort(ids, function(a, b)
			local A, B = Items.List[a], Items.List[b]
			local sa = state.owned[a] and 2 or (state.unlocked[a] and 0 or 1)
			local sb = state.owned[b] and 2 or (state.unlocked[b] and 0 or 1)
			if sa ~= sb then return sa < sb end
			return (TIER_ORDER[A.rarity] or 0) < (TIER_ORDER[B.rarity] or 0)
		end)
		for _, id in ids do
			order += 1
			itemCard(id, order)
		end
	elseif currentTab == "robux" then
		renderStore()
	else
		title.Text = "LOADOUT"
		local order = renderWeaponLoadout(0)
		for _, slot in { "Trail", "Passive" } do
			order += 1
			sectionTitle((slot == "Trail" and "FLIGHT TRAIL" or "PASSIVE ITEM") .. "   -   equipped: " .. ((state.equipped[slot] or "") ~= "" and Items.List[state.equipped[slot]].name or "none"), order, GOLD)
			local any = false
			for _, id in Items.Order do
				if Items.List[id].slot == slot and state.owned[id] then
					any = true
					order += 1
					itemCard(id, order)
				end
			end
			if not any then
				order += 1
				label(content, "You do not own any yet. Complete missions to unlock them, then buy them in the shop.", 14, C3(150, 165, 190), Enum.Font.Gotham, { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, TextWrapped = true })
			end
		end
	end
end

----------------------------------------------------------------------
-- opening / closing
----------------------------------------------------------------------
local isOpen = false
local sourcePart = nil
local function closePanel()
	if not isOpen then return end
	isOpen = false
	ContextActionService:UnbindAction("ProgressClose")
	TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }):Play()
	TweenService:Create(panel, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(dim, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
	task.delay(0.2, function()
		if not isOpen then
			panel.Visible = false
			dim.Visible = false
		end
	end)
end
local function openPanel(tab, source)
	currentTab = tab or currentTab
	hudMode = (source == "hud")
	sourcePart = (typeof(source) == "Instance") and source or nil
	refresh()
	if not isOpen then
		isOpen = true
		dim.Visible = true
		panel.Visible = true
		panelScale.Scale = 0.9
		panel.BackgroundTransparency = 1
		dim.BackgroundTransparency = 1
		TweenService:Create(panelScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(panel, TweenInfo.new(0.25), { BackgroundTransparency = 0.04 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.5 }):Play()
		playOnce(9125973433, 0.3, 1.5)
		ContextActionService:BindActionAtPriority("ProgressClose", function(_, state2)
			if state2 == Enum.UserInputState.Begin then closePanel() end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	end
	if UserInputService:GetLastInputType().Name:find("Gamepad") then
		GuiService.SelectedObject = tabButtons[currentTab]
	end
end
for name, b in tabButtons do
	b.Activated:Connect(function()
		currentTab = name
		playOnce(9125973433, 0.2, 1.7)
		refresh()
	end)
end
closePanelRef = closePanel
closeButton.Activated:Connect(closePanel)

-- the LOADOUT button on the left of the screen: open it from anywhere, no need to visit the shop
local loadoutButton = new("TextButton", { Name = "LoadoutButton", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(78, 78), BackgroundColor3 = C3(14, 20, 46), BackgroundTransparency = 0.12, Text = "", AutoButtonColor = true, ZIndex = 5 }, gui)
corner(loadoutButton, 16)
local lbStroke = stroke(loadoutButton, CYAN, 2.2, 0.15)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C3(34, 48, 96), C3(12, 16, 38)) }, loadoutButton)
label(loadoutButton, "\u{1F392}", 32, WHITE, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 38), ZIndex = 6 })
label(loadoutButton, "LOADOUT", 12, CYAN, Enum.Font.GothamBlack, { Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 16), ZIndex = 6 })
loadoutButton.MouseEnter:Connect(function() TweenService:Create(lbStroke, TweenInfo.new(0.15), { Thickness = 3.6, Transparency = 0 }):Play() end)
loadoutButton.MouseLeave:Connect(function() TweenService:Create(lbStroke, TweenInfo.new(0.15), { Thickness = 2.2, Transparency = 0.15 }):Play() end)
loadoutButton.Activated:Connect(function()
	if isOpen and hudMode then
		closePanel()
	else
		openPanel("loadout", "hud")
	end
end)
dim.Activated:Connect(closePanel)

ProximityPromptService.PromptTriggered:Connect(function(prompt, plr)
	if plr ~= player then return end
	if prompt.Name == "MissionPrompt" then
		openPanel("missions", prompt.Parent)
	elseif prompt.Name == "ShopPrompt" then
		openPanel("shop", prompt.Parent)
	end
end)
----------------------------------------------------------------------
-- the mission tracker (left side) with a pointer to what you need
----------------------------------------------------------------------
local tracker = new("Frame", { Name = "Tracker", Position = UDim2.new(0, 14, 0, 96), Size = UDim2.fromOffset(290, 158), BackgroundColor3 = C3(8, 12, 30), BackgroundTransparency = 0.2, Visible = false }, gui)
corner(tracker, 12)
local trackerStroke = stroke(tracker, GOLD, 1.8, 0.2)
label(tracker, "\u{25B6} MISSION", 12, C3(160, 185, 215), Enum.Font.GothamBold, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 14) })
local trName = label(tracker, "", 18, GOLD, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(12, 20), Size = UDim2.new(1, -24, 0, 24) })
local trShort = label(tracker, "", 13, C3(215, 228, 245), Enum.Font.Gotham, { Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -24, 0, 18) })
local trBarBG = new("Frame", { Position = UDim2.fromOffset(12, 68), Size = UDim2.new(1, -90, 0, 12), BackgroundColor3 = C3(14, 18, 36), BorderSizePixel = 0 }, tracker)
corner(trBarBG, 6)
local trFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, trBarBG)
corner(trFill, 6)
local trCount = label(tracker, "", 15, GOLD, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 62), Size = UDim2.fromOffset(70, 22), TextXAlignment = Enum.TextXAlignment.Right })
local trDial = new("Frame", { Position = UDim2.fromOffset(12, 86), Size = UDim2.fromOffset(60, 60), BackgroundColor3 = C3(14, 16, 36), BorderSizePixel = 0 }, tracker)
corner(trDial, 30)
local trDialStroke = stroke(trDial, CYAN, 2.4)
local trArrowHolder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, trDial)
local trArrow = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 80, Text = "\u{25B2}", TextColor3 = CYAN }, trArrowHolder)
new("UIStroke", { Color = C3(0, 0, 0), Thickness = 2.4 }, trArrow)
local trTail = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromOffset(5, 14), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, trArrowHolder)
new("UIStroke", { Color = C3(0, 0, 0), Thickness = 1.8 }, trTail)
local trTarget = label(tracker, "", 15, CYAN, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(84, 94), Size = UDim2.new(1, -96, 0, 24) })
local trDist = label(tracker, "", 13, C3(190, 205, 230), Enum.Font.GothamBold, { Position = UDim2.fromOffset(84, 120), Size = UDim2.new(1, -96, 0, 20) })

local function targetPosition(m)
	-- where should the pointer point?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local f = m.filter or {}
	if m.type == "collect" and f.resource == "Crystal" then
		local pts = ReplicatedStorage:FindFirstChild("CrystalPoints")
		local best, bd
		if pts then
			for _, v in pts:GetChildren() do
				if v:IsA("Vector3Value") and v:GetAttribute("Active") ~= false then
					local d = (v.Value - root.Position).Magnitude
					if not bd or d < bd then best, bd = v.Value, d end
				end
			end
		end
		return best, "nearest Hive Crystal"
	elseif m.type == "collect" then
		local drops = workspace:FindFirstChild("IchorDrops")
		local best, bd
		if drops then
			for _, d in drops:GetChildren() do
				local dist = (d.Position - root.Position).Magnitude
				if not bd or dist < bd then best, bd = d.Position, dist end
			end
		end
		if best then return best, "Xeno Ichor on the ground" end
		return nil, "kill aliens - their Ichor drops"
	elseif f.hive then
		return workspace:GetAttribute("HivePos" .. f.hive), "Hive " .. f.hive
	elseif m.type == "titan" then
		for _, h in workspace:FindFirstChild("AlienHives") and workspace.AlienHives:GetChildren() or {} do
			if h:GetAttribute("TitanAlive") then return h:GetAttribute("Center"), "the Xeno Titan  (Hive " .. tostring(h:GetAttribute("Index")) .. ")" end
		end
		return nil, "the Titan is rising..."
	else
		-- nearest hive
		local best, bd, bi
		for i = 1, 12 do
			local hp = workspace:GetAttribute("HivePos" .. i)
			if hp then
				local d = (hp - root.Position).Magnitude
				if not bd or d < bd then best, bd, bi = hp, d, i end
			end
		end
		return best, bi and ("nearest Hive " .. bi) or nil
	end
end

local function updateTracker()
	local a = state.active
	local m = a and Items.Missions[a.id]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	-- the "show me the way" guide ends when you arrive, or when you take a mission
	if guideTarget then
		if not guideTarget.part.Parent or m ~= nil or (root and (guideTarget.part.Position - root.Position).Magnitude < 28) then
			guideTarget = nil
		end
	end
	tracker.Visible = (m ~= nil or guideTarget ~= nil) and not isOpen
	if not m and not guideTarget then return end
	local pos, text
	if m then
		trName.Text = m.name
		trShort.Text = m.short
		local prog = a.progress or 0
		trFill.Size = UDim2.fromScale(math.clamp(prog / m.target, 0, 1), 1)
		trCount.Text = prog .. "/" .. m.target
		pos, text = targetPosition(m)
	else
		trName.Text = guideTarget.title or "MISSION CONTROL"
		trShort.Text = guideTarget.sub or "Go to Commander Vox to start a mission"
		trFill.Size = UDim2.fromScale(0, 1)
		trCount.Text = ""
		pos, text = guideTarget.part.Position, guideTarget.where or "Commander Vox - far side of the ship"
	end
	local cam = workspace.CurrentCamera
	if pos and cam and root then
		local flat = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
		local lp = cam.CFrame:VectorToObjectSpace(flat.Magnitude > 0 and flat.Unit or Vector3.zero)
		trArrowHolder.Rotation = math.deg(math.atan2(lp.X, -lp.Z))
		trArrow.TextTransparency = 0
		trTail.BackgroundTransparency = 0
		trDialStroke.Transparency = 0
		trTarget.Text = text or ""
		local d = math.floor((pos - root.Position).Magnitude + 0.5)
		trDist.Text = (tostring(d):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) .. " studs away"
	else
		trArrow.TextTransparency = 1
		trTail.BackgroundTransparency = 1
		trDialStroke.Transparency = 0.6
		trTarget.Text = text or ""
		trDist.Text = ""
	end
end
local trAcc = 0
RunService.Heartbeat:Connect(function(dt)
	trAcc += dt
	if trAcc > 0.1 then
		trAcc = 0
		updateTracker()
		if isOpen then
			updateFooter()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and sourcePart and sourcePart.Parent and (sourcePart.Position - root.Position).Magnitude > 45 then
				closePanel() -- you walked away from the NPC
			end
		end
	end
	panelStroke.Color = CYAN:Lerp(C3(190, 90, 255), 0.5 + 0.5 * math.sin(os.clock() * 1.4))
end)

----------------------------------------------------------------------
-- cinematic reveals
----------------------------------------------------------------------
local reveal = new("Frame", { Name = "Reveal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C3(0, 0, 8), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, gui)
local revealBusy = false
local revealQueue = {}
local function runReveal(spec)
	revealBusy = true
	for _, c in reveal:GetChildren() do c:Destroy() end
	reveal.Visible = true
	reveal.BackgroundTransparency = 1
	TweenService:Create(reveal, TweenInfo.new(0.35), { BackgroundTransparency = 0.35 }):Play()
	local color = spec.color

	-- spinning light rays
	local rays = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.6, 1.6), BackgroundColor3 = color, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 21 }, reveal)
	local rg = new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.4), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(0.75, 0.4), NumberSequenceKeypoint.new(1, 1) }) }, rays)
	local rayAspect = new("UIAspectRatioConstraint", { AspectRatio = 1 }, rays)

	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(380, 470), BackgroundColor3 = C3(8, 12, 30), BorderSizePixel = 0, ZIndex = 22 }, reveal)
	corner(card, 18)
	stroke(card, color, 3.5)
	local cg = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(C3(0, 0, 0), 0.55), C3(6, 8, 22)) }, card)
	local cScale = new("UIScale", { Scale = 0.2 }, card)
	label(card, spec.header, 15, color, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	local iconHolder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(150, 150), BackgroundColor3 = color:Lerp(C3(0, 0, 0), 0.7), BorderSizePixel = 0, ZIndex = 23 }, card)
	corner(iconHolder, 75)
	stroke(iconHolder, color, 3)
	label(iconHolder, spec.icon, 80, color, Enum.Font.GothamBlack, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
	label(card, spec.name, 26, C3(255, 255, 255), Enum.Font.GothamBlack, { Position = UDim2.fromOffset(10, 214), Size = UDim2.new(1, -20, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, ZIndex = 23 })
	label(card, spec.rarity, 15, color, Enum.Font.GothamBlack, { Position = UDim2.fromOffset(0, 250), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	label(card, spec.text, 15, C3(215, 228, 245), Enum.Font.Gotham, { Position = UDim2.fromOffset(24, 278), Size = UDim2.new(1, -48, 0, 90), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	label(card, spec.footer or "", 14, GOLD, Enum.Font.GothamBold, { Position = UDim2.fromOffset(24, 372), Size = UDim2.new(1, -48, 0, 50), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	local cont = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(150, 34), BackgroundColor3 = color, Text = "CONTINUE", Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = C3(8, 12, 24), ZIndex = 24 }, card)
	corner(cont, 10)

	TweenService:Create(cScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	playOnce(9125974640, 0.5, 1.1)
	playOnce(9125973984, 0.4, 1.3)

	-- sparks flying out of the card
	for i = 1, 34 do
		local sp = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(rng:NextInteger(4, 9), rng:NextInteger(4, 9)), BackgroundColor3 = (i % 3 == 0) and C3(255, 255, 255) or color, BorderSizePixel = 0, ZIndex = 25, Rotation = rng:NextInteger(0, 90) }, reveal)
		local ang = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0.25, 0.7)
		TweenService:Create(sp, TweenInfo.new(rng:NextNumber(0.7, 1.4), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5 + math.cos(ang) * r * 0.9, 0.5 + math.sin(ang) * r), BackgroundTransparency = 1,
		}):Play()
		Debris:AddItem(sp, 1.6)
	end

	local closed = false
	local conn
	local function finish()
		if closed then return end
		closed = true
		if conn then conn:Disconnect() end
		TweenService:Create(cScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.1 }):Play()
		TweenService:Create(reveal, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.delay(0.32, function()
			for _, c in reveal:GetChildren() do c:Destroy() end
			reveal.Visible = false
			revealBusy = false
			local nxt = table.remove(revealQueue, 1)
			if nxt then runReveal(nxt) end
		end)
	end
	cont.Activated:Connect(finish)
	conn = RunService.RenderStepped:Connect(function(dt)
		rays.Rotation += dt * 22
		iconHolder.Rotation = 4 * math.sin(os.clock() * 2)
	end)
	task.delay(spec.duration or 9, finish)
end
local function queueReveal(spec)
	if revealBusy then
		table.insert(revealQueue, spec)
	else
		runReveal(spec)
	end
end

----------------------------------------------------------------------
-- messages from the server
----------------------------------------------------------------------
stateRemote.OnClientEvent:Connect(function(data)
	state = data
	state.unlocked = state.unlocked or {}
	state.owned = state.owned or {}
	state.done = state.done or {}
	state.equipped = state.equipped or { Trail = "", Passive = "" }
	if isOpen then refresh() end
	updateTracker()
end)

local pickupLabel = label(gui, "", 20, GREEN, Enum.Font.GothamBlack, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(360, 30), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 })
local pickupStroke = new("UIStroke", { Color = C3(0, 20, 6), Thickness = 2, Transparency = 1 }, pickupLabel)
local pickupToken = 0
local function pickup(kind, total)
	pickupToken += 1
	local my = pickupToken
	local isCrystal = kind == "Crystal"
	pickupLabel.Text = (isCrystal and "\u{25C6} +1 HIVE CRYSTAL  (" or "\u{25CF} +1 XENO ICHOR  (") .. total .. ")"
	pickupLabel.TextColor3 = isCrystal and C3(215, 150, 255) or GREEN
	pickupLabel.TextTransparency = 0
	pickupStroke.Transparency = 0.2
	pickupLabel.Position = UDim2.fromScale(0.5, 0.62)
	TweenService:Create(pickupLabel, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.57) }):Play()
	playOnce(isCrystal and 9125973984 or 9125973433, 0.3, isCrystal and 1.5 or 2.0)
	task.delay(1.1, function()
		if my ~= pickupToken then return end
		TweenService:Create(pickupLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(pickupStroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	end)
end

notifyRemote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "toast" then
		toast(a, b)
	elseif kind == "pickup" then
		pickup(a, b)
	elseif kind == "accepted" then
		local m = Items.Missions[a]
		if m then
			toast("MISSION ACCEPTED: " .. m.name, GOLD)
			subtitle(m.brief)
		end
	elseif kind == "complete" then
		local m = Items.Missions[a]
		if not m then return end
		local tierColor = Items.rarityColor(m.tier)
		queueReveal({
			color = tierColor, header = "MISSION COMPLETE", icon = "\u{2713}", name = m.name, rarity = m.tier:upper() .. " MISSION",
			text = m.short .. "\n\nReward:  $" .. money(m.reward.money or 0) .. "   +" .. (m.reward.iron or 0) .. " iron",
			footer = (c and "SKIPPED WITH ROBUX  -  " or "") .. (b and ("NEW ITEM UNLOCKED IN THE SHOP:  " .. Items.List[b].name) or "Come back for the next one."), duration = 7,
		})
		if b and Items.List[b] then
			local it = Items.List[b]
			queueReveal({
				color = Items.rarityColor(it.rarity), header = "NEW ITEM UNLOCKED", icon = it.icon, name = it.name, rarity = it.rarity:upper() .. "  \u{2022}  " .. (it.slot == "Weapon" and "WEAPON" or it.slot:upper()),
				text = it.desc .. "\n\n" .. it.stat, footer = "Buy it at the alien shop for $" .. money(it.price) .. ".", duration = 10,
			})
		end
	elseif kind == "guide" then
		if typeof(a) == "Instance" and a:IsA("BasePart") then
			guideTarget = { part = a, name = b or "TARGET", title = b or "TARGET", sub = "Fly to the glowing beacon and hold E", where = "Follow the arrow - the beacon is visible from far away" }
		end
	elseif kind == "robux" then
		-- thank-you reveals for Robux purchases
		if Mon.Passes[a] then
			local it = Items.List[Mon.Passes[a].item]
			queueReveal({
				color = Items.rarityColor("Secret"), header = "SECRET WEAPON UNLOCKED", icon = it.icon, name = it.name, rarity = "SECRET  \u{2022}  WEAPON",
				text = it.desc .. "\n\n" .. it.stat, footer = "It is in your backpack. Thank you for supporting the game!", duration = 11,
			})
		elseif Mon.Products[a] then
			local e = Mon.Products[a]
			if e.kind == "energy" then
				toast("ENERGY CELL: your BOOST bar is full!", CYAN)
				playOnce(9125974640, 0.4, 1.6)
			else
				local color = e.accent and C3(e.accent[1], e.accent[2], e.accent[3]) or GOLD
				local names = {}
				for _, ln in contentLines(e) do names[#names + 1] = ln.icon .. "  " .. ln.text end
				queueReveal({
					color = color, header = "THANK YOU!", icon = "\u{2605}", name = e.name, rarity = e.kind == "bundle" and "BUNDLE" or "PACK",
					text = table.concat(names, "\n"), footer = "Everything is already in your account.", duration = 9,
				})
			end
		end
	elseif kind == "purchased" then
		local it = Items.List[a]
		if it then
			queueReveal({
				color = Items.rarityColor(it.rarity), header = "ACQUIRED", icon = it.icon, name = it.name, rarity = it.rarity:upper(),
				text = it.desc, footer = it.slot == "Weapon" and "It is in your backpack." or "Equip it in LOADOUT (at the alien shop).", duration = 6,
			})
		end
	end
end)

updateFooter()
local ok, st = pcall(function() return actionRemote:InvokeServer("state") end)
