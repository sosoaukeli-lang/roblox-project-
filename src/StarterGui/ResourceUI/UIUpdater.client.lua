-- UIUpdater: the resource HUD (Iron + Money).
-- Two glass cards with glowing animated borders, icon badges, numbers that count up/down smoothly,
-- floating "+5" / "-$100" popups with sparkles, a pulse + colour flash on every change,
-- an income-per-minute readout, and a tag with your station number.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local gui = script.Parent

gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
for _, c in gui:GetChildren() do
	if c ~= script then
		c:Destroy()
	end
end

local rng = Random.new()
local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(110, 255, 160)
local RED = Color3.fromRGB(255, 100, 110)

local CARDS = {
	{ key = "Iron", title = "IRON", icon = "\u{1F529}", accent = Color3.fromRGB(120, 205, 255), prefix = "", gainSound = 6603571443, gainSpeed = 2.6 },
	{ key = "Money", title = "MONEY", icon = "\u{1F4B0}", accent = Color3.fromRGB(255, 205, 80), prefix = "$", gainSound = 9116277954, gainSpeed = 2.4 },
}

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
local function round(parent, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

-- 1234567 -> "1.23M", 52000 -> "52,000"
local function formatNumber(n)
	local a = math.abs(n)
	if a >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif a >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	end
	local s = tostring(math.floor(a))
	local r = s:reverse()
	r = r:gsub("(%d%d%d)", "%1,")
	r = r:reverse()
	r = r:gsub("^,", "")
	return (n < 0 and "-" or "") .. r
end

----------------------------------------------------------------------
-- layout
----------------------------------------------------------------------
local hud = new("Frame", {
	Name = "Hud",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 22, 1, -22),
	Size = UDim2.fromOffset(300, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
}, gui)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Bottom }, hud)
local hudScale = new("UIScale", { Scale = 1 }, hud)
local popLayer = new("Frame", { Name = "Popups", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 50 }, gui)

-- station tag
local tag = new("Frame", {
	Name = "StationTag",
	LayoutOrder = 0,
	Size = UDim2.fromOffset(150, 26),
	BackgroundColor3 = Color3.fromRGB(10, 12, 28),
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
}, hud)
round(tag, 13)
new("UIStroke", { Color = Color3.fromRGB(130, 245, 255), Thickness = 1.5, Transparency = 0.3 }, tag)
local tagLabel = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(130, 245, 255),
	Text = "",
}, tag)
local function refreshTag()
	local n = player:GetAttribute("StationNumber")
	if n and n > 0 then
		tagLabel.Text = "\u{25C6}  STATION " .. n
	else
		tagLabel.Text = "\u{25C6}  VISITOR"
	end
end
refreshTag()
player:GetAttributeChangedSignal("StationNumber"):Connect(refreshTag)

----------------------------------------------------------------------
-- cards
----------------------------------------------------------------------
local states = {}

local function makeCard(def, order)
	local accent = def.accent
	local dark = Color3.new(accent.R * 0.25, accent.G * 0.25, accent.B * 0.25)

	local card = new("CanvasGroup", {
		Name = def.key,
		LayoutOrder = order,
		Size = UDim2.fromOffset(300, 78),
		BackgroundColor3 = Color3.fromRGB(9, 11, 26),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, hud)
	round(card, 16)
	local scale = new("UIScale", { Scale = 0.8 }, card)
	local stroke = new("UIStroke", { Color = WHITE, Thickness = 2.5, Transparency = 0.1 }, card)
	local strokeGrad = new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, accent),
			ColorSequenceKeypoint.new(0.5, WHITE),
			ColorSequenceKeypoint.new(1, accent),
		}),
	}, stroke)

	-- soft coloured glow behind the content
	local glow = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 1 }, card)
	new("UIGradient", {
		Color = ColorSequence.new(accent, dark),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.97) }),
	}, glow)

	-- icon badge
	local badge = new("Frame", {
		Position = UDim2.fromOffset(13, 13),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = dark,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, card)
	round(badge, 26)
	new("UIStroke", { Color = accent, Thickness = 2, Transparency = 0.2 }, badge)
	local icon = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 1,
		Text = def.icon,
		TextScaled = true,
		ZIndex = 4,
	}, badge)

	local title = new("TextLabel", {
		Position = UDim2.fromOffset(78, 9),
		Size = UDim2.fromOffset(120, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextSize = 14,
		TextColor3 = accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = def.title,
		ZIndex = 3,
	}, card)

	local value = new("TextLabel", {
		Position = UDim2.fromOffset(76, 22),
		Size = UDim2.fromOffset(212, 38),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = WHITE,
		TextStrokeColor3 = dark,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = def.prefix .. "0",
		ZIndex = 3,
	}, card)
	new("UITextSizeConstraint", { MaxTextSize = 36 }, value)

	local rate = new("TextLabel", {
		Position = UDim2.fromOffset(78, 59),
		Size = UDim2.fromOffset(200, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(160, 170, 200),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "\u{2014}",
		ZIndex = 3,
	}, card)

	-- light sweep
	local shimmer = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(-0.2, 0, 0.5, 0),
		Size = UDim2.fromOffset(26, 160),
		Rotation = 20,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, card)

	-- intro: fade + grow in, one after the other
	task.delay(0.15 * order, function()
		TweenService:Create(card, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
		TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)

	return { card = card, scale = scale, stroke = stroke, grad = strokeGrad, glow = glow, icon = icon, value = value, rate = rate, shimmer = shimmer, badge = badge }
end

local function makeSound(id, volume)
	return new("Sound", { SoundId = "rbxassetid://" .. id, Volume = volume }, gui)
end

local leaderstats = player:WaitForChild("leaderstats", 30)
for i, def in CARDS do
	local ui = makeCard(def, i)
	local valueObj = leaderstats and leaderstats:WaitForChild(def.key, 15)
	local start = valueObj and valueObj.Value or 0
	states[i] = {
		def = def, ui = ui, obj = valueObj,
		target = start, display = 0, last = start,
		bump = 0, flash = 0, flashColor = WHITE,
		history = {}, rateText = "",
		phase = rng:NextNumber(0, 6),
		gainSnd = makeSound(def.gainSound, 0.12),
	}
end
local startClock = os.clock()

----------------------------------------------------------------------
-- popups
----------------------------------------------------------------------
local function popup(state, delta)
	local ui, def = state.ui, state.def
	local gain = delta > 0
	local color = gain and GREEN or RED
	local pos = ui.card.AbsolutePosition
	local size = ui.card.AbsoluteSize
	local origin = Vector2.new(pos.X + size.X + 14, pos.Y + size.Y * 0.5)
	origin += Vector2.new(0, rng:NextNumber(-10, 10))

	local p = new("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(origin.X, origin.Y),
		Size = UDim2.fromOffset(180, 36),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 28,
		TextColor3 = color,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.35,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = (gain and "+" or "-") .. def.prefix .. formatNumber(math.abs(delta)),
		ZIndex = 60,
	}, popLayer)
	local ps = new("UIScale", { Scale = 0.5 }, p)
	TweenService:Create(ps, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.1 }):Play()
	task.delay(0.25, function()
		TweenService:Create(ps, TweenInfo.new(0.2), { Scale = 1 }):Play()
	end)
	TweenService:Create(p, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(origin.X + 8, origin.Y - 52),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(p, 1.4)

	-- sparkles bursting out of the card edge
	for _ = 1, 7 do
		local s = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X - 10, origin.Y),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = gain and def.accent or RED,
			BorderSizePixel = 0,
			Rotation = rng:NextNumber(0, 90),
			ZIndex = 55,
		}, popLayer)
		local ang = rng:NextNumber(-1.4, 1.4)
		local dist = rng:NextNumber(24, 58)
		TweenService:Create(s, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(origin.X - 10 + math.cos(ang) * dist, origin.Y + math.sin(ang) * dist),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
		}):Play()
		Debris:AddItem(s, 0.8)
	end
end

local function onChange(state, newValue)
	local delta = newValue - state.last
	state.last = newValue
	state.target = newValue
	if delta == 0 then
		return
	end
	state.bump = 1
	state.flash = 1
	state.flashColor = delta > 0 and GREEN or RED
	popup(state, delta)
	if delta > 0 then
		table.insert(state.history, { t = os.clock(), v = delta })
		state.gainSnd.PlaybackSpeed = state.def.gainSpeed * rng:NextNumber(0.95, 1.05)
		state.gainSnd:Play()
	else
		state.gainSnd.PlaybackSpeed = 0.6
		state.gainSnd:Play()
	end
end
for _, state in states do
	if state.obj then
		state.obj.Changed:Connect(function(v)
			onChange(state, v)
		end)
	end
end

----------------------------------------------------------------------
-- animation loop
----------------------------------------------------------------------
local t, rateTimer = 0, 0
RunService.RenderStepped:Connect(function(dt)
	t += dt

	-- scale the HUD with the screen size (phones, small windows)
	local cam = workspace.CurrentCamera
	if cam then
		hudScale.Scale = math.clamp(cam.ViewportSize.Y / 900, 0.7, 1.25)
	end

	-- income per minute
	rateTimer += dt
	local updateRate = rateTimer >= 0.5
	if updateRate then
		rateTimer = 0
	end

	for i, st in states do
		local ui = st.ui

		-- numbers glide to their new value
		st.display += (st.target - st.display) * math.min(dt * 7, 1)
		local shown = math.floor(st.display + 0.5)
		if math.abs(st.target - st.display) < 0.5 then
			shown = st.target
		end
		ui.value.Text = st.def.prefix .. formatNumber(shown)

		-- pulse + flash after a change
		st.bump = math.max(0, st.bump - dt * 3.2)
		st.flash = math.max(0, st.flash - dt * 2.2)
		ui.scale.Scale = 1 + 0.07 * math.sin(st.bump * math.pi)
		ui.value.TextColor3 = st.flashColor:Lerp(WHITE, 1 - st.flash)
		ui.glow.BackgroundColor3 = WHITE:Lerp(st.flashColor, st.flash * 0.6)

		-- living border: rotating gradient + gentle breathing
		ui.grad.Rotation = (t * 70 + i * 90) % 360
		ui.stroke.Transparency = 0.12 + 0.12 * math.sin(t * 2 + st.phase) - 0.1 * st.flash

		-- the icon bobs
		ui.icon.Rotation = 8 * math.sin(t * 1.8 + st.phase)
		ui.icon.Position = UDim2.new(0.5, 0, 0.5, 2 * math.sin(t * 2.4 + st.phase))

		-- a light sweep every few seconds
		local sweep = ((t + i * 1.7) % 5) / 1.1
		ui.shimmer.Position = UDim2.new(-0.15 + 1.4 * math.clamp(sweep, 0, 1), 0, 0.5, 0)
		ui.shimmer.Visible = sweep < 1

		if updateRate then
			local now = os.clock()
			local sum = 0
			for k = #st.history, 1, -1 do
				local e = st.history[k]
				if now - e.t > 60 then
					table.remove(st.history, k)
				else
					sum += e.v
				end
			end
			local window = math.clamp(now - startClock, 15, 60)
			local perMin = sum * 60 / window
			local text = (sum > 0) and ("\u{25B2} " .. st.def.prefix .. formatNumber(math.floor(perMin + 0.5)) .. " / min") or "\u{2014}"
			if text ~= st.rateText then
				st.rateText = text
				ui.rate.Text = text
				ui.rate.TextColor3 = (sum > 0) and GREEN or Color3.fromRGB(160, 170, 200)
			end
		end
	end
end)
