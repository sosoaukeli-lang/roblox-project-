-- HouseService (ModuleScript) - owns which player lives in which house.
-- A player gets a free house when they join and gives it back when they leave.
-- The server decides everything here: clients only ask (ClientReady) and are told.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DOOR_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DOOR_COOLDOWN = 0.5 -- seconds between two door toggles of the same house
local READY_COOLDOWN = 1 -- seconds between two ClientReady requests of the same player

local HouseService = {}

-- houses[houseId] = { Id, Model, Owner (Player | nil), Spawn, Label, Panel, DoorOpen, LastToggle }
local houses = {}
local houseByPlayer = {}
local lastReady = {}

local function updateLabel(house)
	if house.Owner then
		house.Label.Text = "بيت " .. house.Owner.DisplayName
	else
		house.Label.Text = "بيت " .. house.Id .. " - فاضي"
	end
end

local function setDoorOpen(house, open)
	house.DoorOpen = open
	local panel = house.Panel
	local target = panel:GetAttribute(open and "OpenCFrame" or "ClosedCFrame")
	if open then
		panel.CanCollide = false
	else
		-- Solid again only once it has swung shut, so it never shoves someone in the doorway.
		task.delay(DOOR_TWEEN.Time, function()
			if not house.DoorOpen then
				panel.CanCollide = true
			end
		end)
	end
	TweenService:Create(panel, DOOR_TWEEN, { CFrame = target }):Play()
end

-- Only the owner can use the door for now (Phase 4 adds the thief rules).
local function onDoorTriggered(house, player)
	if house.Owner ~= player then
		return
	end
	local now = os.clock()
	if now - house.LastToggle < DOOR_COOLDOWN then
		return
	end
	house.LastToggle = now
	setDoorOpen(house, not house.DoorOpen)
end

local function onClientReady(player)
	local now = os.clock()
	if lastReady[player] and now - lastReady[player] < READY_COOLDOWN then
		return
	end
	lastReady[player] = now
	local house = houseByPlayer[player]
	if house then
		Remotes.Get("HouseAssigned"):FireClient(player, house.Id)
	end
end

-- houseModels: { [houseId] = Model } as returned by MapBuilder.Build()
function HouseService.Init(houseModels)
	for houseId, model in ipairs(houseModels) do
		local panel = model.Door.Panel
		local house = {
			Id = houseId,
			Model = model,
			Owner = nil,
			Spawn = model.Spawn,
			Label = model.Sign.SignGui.Label,
			Panel = panel,
			DoorOpen = false,
			LastToggle = 0,
		}
		houses[houseId] = house
		panel.DoorPrompt.Triggered:Connect(function(player)
			onDoorTriggered(house, player)
		end)
	end

	Remotes.Get("ClientReady").OnServerEvent:Connect(onClientReady)
	Players.PlayerRemoving:Connect(function(player)
		lastReady[player] = nil
	end)
end

-- Gives `player` the first free house (or their current one). Returns the house, or nil
-- when all houses are taken. Does not yield, so it is safe to call before the character spawns.
function HouseService.Assign(player)
	if houseByPlayer[player] then
		return houseByPlayer[player]
	end
	for _, house in ipairs(houses) do
		if not house.Owner then
			house.Owner = player
			houseByPlayer[player] = house
			house.Model:SetAttribute("OwnerUserId", player.UserId)
			player:SetAttribute("HouseId", house.Id)
			player.RespawnLocation = house.Spawn
			updateLabel(house)
			return house
		end
	end
	return nil
end

-- Frees the player's house: closes the door and clears the owner.
function HouseService.Release(player)
	local house = houseByPlayer[player]
	if not house then
		return
	end
	houseByPlayer[player] = nil
	house.Owner = nil
	house.Model:SetAttribute("OwnerUserId", 0)
	if house.DoorOpen then
		setDoorOpen(house, false)
	end
	updateLabel(house)
end

function HouseService.GetHouse(player)
	return houseByPlayer[player]
end

return HouseService
