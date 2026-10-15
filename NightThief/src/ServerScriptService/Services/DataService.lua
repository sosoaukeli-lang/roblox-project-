-- DataService (ModuleScript) - loads, holds and saves every player's data.
-- The data table in memory is the single source of truth; the leaderstats value is
-- just a mirror for display. All money changes go through AddCash / TrySpend.
--
-- Saved data: { Version, Cash, Items, HouseLevel, Rebirths }
--   Items is a list filled in by Phase 3 (what the player owns / has placed).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local STORE_NAME = "NightThief_PlayerData_v1"
local KEY_PREFIX = "Player_"
local DATA_VERSION = 1
local AUTOSAVE_INTERVAL = 60 -- seconds
local MAX_CASH = 2147483647 -- IntValue limit

-- In Studio a failed DataStore call usually just means "API access is off", so try once.
local MAX_ATTEMPTS = RunService:IsStudio() and 1 or 3

local DataService = {}

-- profiles[player] = { Data = table, Persist = boolean, Saving = boolean }
local profiles = {}
local pendingSaves = 0

-- GetDataStore can throw in odd Studio situations; if it does, every load/save below
-- fails inside its own pcall and goes through the normal failure handling.
local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore(STORE_NAME)
end)
if not storeOk then
	warn("[DataService] could not open the DataStore: " .. tostring(store))
	store = nil
end

local function defaultData()
	return {
		Version = DATA_VERSION,
		Cash = Config.StartCash,
		Items = {},
		HouseLevel = 1,
		Rebirths = 0,
	}
end

local function isNumber(value)
	return type(value) == "number" and value == value -- rejects NaN
end

-- Turns whatever came out of the DataStore into valid data (missing / broken fields fall
-- back to defaults), so the rest of the game can trust it.
local function sanitize(raw)
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	if isNumber(raw.Cash) then
		data.Cash = math.clamp(math.floor(raw.Cash), 0, MAX_CASH)
	end
	if isNumber(raw.HouseLevel) then
		data.HouseLevel = math.clamp(math.floor(raw.HouseLevel), 1, Config.MaxHouseLevel)
	end
	if isNumber(raw.Rebirths) then
		data.Rebirths = math.clamp(math.floor(raw.Rebirths), 0, MAX_CASH)
	end
	if type(raw.Items) == "table" then
		data.Items = raw.Items
	end
	return data
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = deepCopy(inner)
	end
	return copy
end

local function keyFor(player)
	return KEY_PREFIX .. player.UserId
end

-- Returns ok, raw. raw is nil for a brand new player.
local function fetch(player)
	local lastError
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			return true, result
		end
		lastError = result
		warn(("[DataService] load failed for %s (attempt %d): %s"):format(player.Name, attempt, tostring(result)))
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ attempt)
		end
	end
	return false, lastError
end

local function createLeaderstats(player, data)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = data.Cash
	cash.Parent = leaderstats

	leaderstats.Parent = player
end

local function setCash(player, profile, amount)
	profile.Data.Cash = amount
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	if cash then
		cash.Value = amount
	end
end

-- Writes the player's data to the DataStore (yields). Skips sessions that must not be
-- saved and never runs twice at once for the same player.
local function save(player)
	local profile = profiles[player]
	if not profile or not profile.Persist or profile.Saving then
		return
	end
	profile.Saving = true
	pendingSaves += 1

	local snapshot = deepCopy(profile.Data)
	for attempt = 1, MAX_ATTEMPTS do
		local ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function()
				return snapshot
			end)
		end)
		if ok then
			break
		end
		warn(("[DataService] save failed for %s (attempt %d): %s"):format(player.Name, attempt, tostring(err)))
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ attempt)
		end
	end

	profile.Saving = false
	pendingSaves -= 1
end

-- Loads the player's data and creates leaderstats (yields). Returns true when the player
-- may play. False means "kick them": playing on empty data would overwrite the real save.
function DataService.Load(player)
	if profiles[player] then
		return true
	end

	local ok, raw = fetch(player)
	if not player:IsDescendantOf(Players) then
		return false -- left while we were loading
	end

	local persist = true
	if not ok then
		if not RunService:IsStudio() then
			return false
		end
		warn("[DataService] Studio test without DataStore access: this session will NOT be saved. "
			.. "Publish the game and turn on Game Settings > Security > Enable Studio Access to API Services to test saving.")
		raw = nil
		persist = false
	end

	local data = sanitize(raw)
	profiles[player] = { Data = data, Persist = persist, Saving = false }
	createLeaderstats(player, data)
	return true
end

-- Saves and forgets the player. Call from PlayerRemoving.
function DataService.Unload(player)
	if not profiles[player] then
		return
	end
	save(player)
	profiles[player] = nil
end

function DataService.GetData(player)
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService.GetCash(player)
	local profile = profiles[player]
	return profile and profile.Data.Cash or 0
end

-- Adds money (amount > 0). Returns true on success.
function DataService.AddCash(player, amount)
	local profile = profiles[player]
	if not profile or not isNumber(amount) or amount <= 0 or amount == math.huge then
		return false
	end
	setCash(player, profile, math.min(profile.Data.Cash + math.floor(amount), MAX_CASH))
	return true
end

-- Takes money if the player can afford it (amount > 0). Returns true if it was taken.
function DataService.TrySpend(player, amount)
	local profile = profiles[player]
	if not profile or not isNumber(amount) or amount <= 0 or amount == math.huge then
		return false
	end
	amount = math.ceil(amount)
	if profile.Data.Cash < amount then
		return false
	end
	setCash(player, profile, profile.Data.Cash - amount)
	return true
end

-- Starts the autosave loop and the save-everything-on-shutdown hook.
function DataService.Init()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in pairs(profiles) do
				task.spawn(save, player)
			end
		end
	end)

	game:BindToClose(function()
		for player in pairs(profiles) do
			task.spawn(save, player)
		end
		while pendingSaves > 0 do
			task.wait()
		end
	end)
end

return DataService
