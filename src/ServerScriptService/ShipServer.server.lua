-- ShipServer: alien ship door + cinematic trigger + SHOP / SELL aliens

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Settings
local PRICE_PER_IRON = 10        -- money you get for each iron sold to the SELL alien
local OPEN_DISTANCE = 85         -- door opens when a player is this close to it (studs)
local CLOSE_DISTANCE = 115       -- door closes again when everybody is farther than this
local CINEMATIC_DISTANCE = 420   -- the cinematic plays once for each player when they first come this close

local ship = workspace:WaitForChild("AlienShip")
local sensor = ship:WaitForChild("DoorSensor")
local aliens = ship:WaitForChild("Aliens")

local function getEvent(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = ReplicatedStorage
	end
	return e
end
local cinematicEvent = getEvent("ShipCinematic")
local notifyEvent = getEvent("ShipNotify")

ship:SetAttribute("DoorOpen", false)

-- Door + cinematic
local seen = {}
local holdFrom, holdUntil = 0, 0
Players.PlayerRemoving:Connect(function(plr)
	seen[plr] = nil
end)

task.spawn(function()
	while true do
		task.wait(0.2)
		local now = os.clock()
		local isOpen = ship:GetAttribute("DoorOpen")
		local near = false
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local d = (root.Position - sensor.Position).Magnitude
				if d <= (isOpen and CLOSE_DISTANCE or OPEN_DISTANCE) then
					near = true
				end
				if not seen[plr] and d <= CINEMATIC_DISTANCE then
					seen[plr] = true
					cinematicEvent:FireClient(plr)
					-- open the door during the cinematic so it lines up with the camera shot of the door
					holdFrom = now + 3
					holdUntil = now + 13
				end
			end
		end
		local forced = now >= holdFrom and now <= holdUntil
		ship:SetAttribute("DoorOpen", near or forced)
	end
end)

-- Aliens
local function getStat(plr, name)
	local ls = plr:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(name)
end

local sellPrompt = aliens:WaitForChild("SellerAlien"):WaitForChild("Torso"):WaitForChild("SellPrompt")
sellPrompt.Triggered:Connect(function(plr)
	local iron, money = getStat(plr, "Iron"), getStat(plr, "Money")
	if not iron or not money then
		return
	end
	local amount = iron.Value
	if amount <= 0 then
		notifyEvent:FireClient(plr, "You have no iron to sell!")
		return
	end
	local gained = amount * PRICE_PER_IRON
	iron.Value = 0
	money.Value += gained
	notifyEvent:FireClient(plr, string.format("Sold %d iron for $%d!", amount, gained))
end)

local shopPrompt = aliens:WaitForChild("ShopAlien"):WaitForChild("Torso"):WaitForChild("ShopPrompt")
-- (the client opens the shop window when this prompt is used - see StarterPlayerScripts.ProgressUI)
