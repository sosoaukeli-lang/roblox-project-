-- ProgressService (Script)
-- Everything that persists and everything the missions / shop / loadout need:
--   * saves each player's money, iron, resources, unlocked + bought items, equipped items, mission progress and weapons
--     (DataStore; in Studio turn on "Enable Studio Access to API Services" or the game runs without saving)
--   * the mission system (accept / progress / complete / abandon) + the six story missions and the repeatable hive bounties
--   * the shop (buy) and the loadout (equip a trail and a passive)
--   * Xeno Ichor drops, Hive Crystals, the item effects that need the server (burn trail, slow trail, crown bonus)
-- The client UI (ProgressUI) talks to this script through the remotes ProgressAction / ProgressState / ProgressNotify.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Items = require(ReplicatedStorage:WaitForChild("Items"))
local actionRemote = ReplicatedStorage:WaitForChild("ProgressAction")
local stateRemote = ReplicatedStorage:WaitForChild("ProgressState")
local notifyRemote = ReplicatedStorage:WaitForChild("ProgressNotify")
local events = ServerStorage:WaitForChild("ProgressEvents")
local weaponsFolder = ServerStorage:WaitForChild("Weapons")
local Loot = require(ReplicatedStorage:WaitForChild("Loot"))
local rng = Random.new()

local store = DataStoreService:GetDataStore("SpaceGameProgress_v1")
local profiles = {}

local CROWN_BONUS = 10
local ICHOR_PER_KILL = 1
local CRYSTAL_RESPAWN = 600
local SOLAR_DPS = 12
local VOID_RANGE = 45
local C3 = Color3.fromRGB

----------------------------------------------------------------------
-- profiles
----------------------------------------------------------------------
local function newProfile()
	return { ichor = 0, crystal = 0, kills = 0, unlocked = {}, owned = {}, equipped = { Trail = "", Passive = "" }, done = {}, active = nil, weapons = {}, loadout = nil, chests = 0, pity = { sinceLegendary = 0, sinceSecret = 0 }, canSave = true, loaded = false }
end

local function stat(player, name)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(name)
end

local function loadProfile(player)
	local p = newProfile()
	profiles[player] = p
	local ls = player:WaitForChild("leaderstats", 15)
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	for _, n in { "Money", "Iron" } do
		if not ls:FindFirstChild(n) then
			local v = Instance.new("IntValue")
			v.Name = n
			v.Parent = ls
		end
	end
	for _, n in { "Ichor", "Crystal" } do
		if not ls:FindFirstChild(n) then
			local v = Instance.new("IntValue")
			v.Name = n
			v.Parent = ls
		end
	end
	local ok, data = pcall(function()
		return store:GetAsync("p_" .. player.UserId)
	end)
	if ok then
		p.loaded = true
		if typeof(data) == "table" then
			if data.money then ls.Money.Value = data.money end
			if data.iron then ls.Iron.Value = data.iron end
			p.ichor, p.crystal, p.kills = data.ichor or 0, data.crystal or 0, data.kills or 0
			p.unlocked, p.owned, p.done = data.unlocked or {}, data.owned or {}, data.done or {}
			p.equipped = data.equipped or p.equipped
			p.active = data.active
			p.weapons = data.weapons or {}
			p.chests = data.chests or 0
			p.loadout = (typeof(data.loadout) == "table" and #data.loadout > 0) and data.loadout or nil
			p.pity = data.pity or p.pity
		end
	else
		p.canSave = false -- never overwrite a save we could not read
		warn("[ProgressService] could not load the save of " .. player.Name .. " (" .. tostring(data) .. "). Playing without saving.")
	end
	ls.Ichor.Value = p.ichor
	ls.Crystal.Value = p.crystal
	player:SetAttribute("TrailId", p.equipped.Trail or "")
	player:SetAttribute("PassiveId", p.equipped.Passive or "")
	return p
end

local function collectWeapons(player, p)
	for _, container in { player:FindFirstChild("Backpack"), player.Character } do
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t.Name ~= "Starter Blaster" and weaponsFolder:FindFirstChild(t.Name) then
					p.weapons[t.Name] = true
				end
			end
		end
	end
end

local function saveProfile(player)
	local p = profiles[player]
	if not p or not p.canSave then
		return
	end
	collectWeapons(player, p)
	local data = {
		money = stat(player, "Money") and stat(player, "Money").Value or 0,
		iron = stat(player, "Iron") and stat(player, "Iron").Value or 0,
		ichor = p.ichor, crystal = p.crystal, kills = p.kills,
		unlocked = p.unlocked, owned = p.owned, equipped = p.equipped, done = p.done, active = p.active, weapons = p.weapons,
		chests = p.chests, pity = p.pity, loadout = p.loadout,
	}
	local ok, err = pcall(function()
		store:SetAsync("p_" .. player.UserId, data)
	end)
	if not ok then
		warn("[ProgressService] save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

-- a save right after an important event (mission done, purchase), but never more often than every 8 seconds
local lastSave, saveQueued = {}, {}
local function requestSave(player)
	if saveQueued[player] then return end
	local wait_ = 8 - (os.clock() - (lastSave[player] or -100))
	if wait_ <= 0 then
		lastSave[player] = os.clock()
		saveProfile(player)
	else
		saveQueued[player] = true
		task.delay(wait_, function()
			saveQueued[player] = nil
			if player.Parent then
				lastSave[player] = os.clock()
				saveProfile(player)
			end
		end)
	end
end

----------------------------------------------------------------------
-- state sync + notifications
----------------------------------------------------------------------
local armoryNames -- (defined below, next to the loadout code)
local function sendState(player)
	local p = profiles[player]
	if not p then return end
	stateRemote:FireClient(player, {
		armory = armoryNames and armoryNames(player, p) or {}, loadout = p.loadout,
		ichor = p.ichor, crystal = p.crystal, kills = p.kills,
		unlocked = p.unlocked, owned = p.owned, equipped = p.equipped, done = p.done, active = p.active, chests = p.chests,
	})
end
local function notify(player, kind, a, b, c)
	notifyRemote:FireClient(player, kind, a, b, c)
end

local function setResource(player, p, key, value)
	p[key] = value
	local v = stat(player, key == "ichor" and "Ichor" or "Crystal")
	if v then v.Value = value end
end

local function giveWeapon(player, toolName)
	local tpl = weaponsFolder:FindFirstChild(toolName)
	if not tpl then return end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	local stash = player:FindFirstChild("WeaponStash")
	if backpack:FindFirstChild(toolName) or (player.Character and player.Character:FindFirstChild(toolName)) or (stash and stash:FindFirstChild(toolName)) then return end
	tpl:Clone().Parent = backpack
end

local applyLoadout, queueLoadout -- (defined below, in the loadout section)
local LOADOUT_SLOTS = 4
local function restoreWeapons(player)
	local p = profiles[player]
	if not p then return end
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack then return end
	for name in p.weapons do giveWeapon(player, name) end
	for id in p.owned do
		local it = Items.List[id]
		if it and it.tool then giveWeapon(player, it.tool) end
	end
	-- remember every weapon that reaches the backpack from now on (crafted ones too)
	backpack.ChildAdded:Connect(function(t)
		if t:IsA("Tool") and t.Name ~= "Starter Blaster" and weaponsFolder:FindFirstChild(t.Name) then
			local isNew = not p.weapons[t.Name]
			p.weapons[t.Name] = true
			-- a brand new weapon takes a free hotbar slot if you use a loadout
			if isNew and p.loadout and #p.loadout < LOADOUT_SLOTS and not table.find(p.loadout, t.Name) then
				table.insert(p.loadout, t.Name)
			end
		end
		queueLoadout(player)
	end)
	applyLoadout(player)
end

----------------------------------------------------------------------
-- WEAPON LOADOUT: up to 4 weapons in the hotbar, the rest wait in the armory (a stash folder on the player)
----------------------------------------------------------------------
local function stashOf(player)
	local f = player:FindFirstChild("WeaponStash")
	if not f then
		f = Instance.new("Folder")
		f.Name = "WeaponStash"
		f.Parent = player
	end
	return f
end
local function isWeaponTool(t)
	return t:IsA("Tool") and weaponsFolder:FindFirstChild(t.Name) ~= nil
end
armoryNames = function(player, p)
	local set = { ["Starter Blaster"] = true }
	for name in p.weapons do set[name] = true end
	for id in p.owned do
		local it = Items.List[id]
		if it and it.tool then set[it.tool] = true end
	end
	local stash = player:FindFirstChild("WeaponStash")
	for _, container in { player:FindFirstChild("Backpack"), player.Character, stash } do
		if container then
			for _, t in container:GetChildren() do
				if isWeaponTool(t) then set[t.Name] = true end
			end
		end
	end
	local list = {}
	for name in set do
		if weaponsFolder:FindFirstChild(name) then list[#list + 1] = name end
	end
	table.sort(list)
	return list
end
applyLoadout = function(player)
	local p = profiles[player]
	local backpack = player:FindFirstChild("Backpack")
	if not p or not backpack then return end
	local stash = stashOf(player)
	local char = player.Character
	-- one copy of each weapon only (a respawn hands out a fresh copy of what sits in the stash)
	local seen = {}
	local function claim(t)
		if seen[t.Name] then t:Destroy() else seen[t.Name] = true end
	end
	if char then for _, t in char:GetChildren() do if isWeaponTool(t) then claim(t) end end end
	for _, t in backpack:GetChildren() do if isWeaponTool(t) then claim(t) end end
	for _, t in stash:GetChildren() do if isWeaponTool(t) then claim(t) end end
	local allowed
	if p.loadout and #p.loadout > 0 then
		allowed = {}
		for _, n in p.loadout do allowed[n] = true end
	end
	if allowed then
		if char then for _, t in char:GetChildren() do if isWeaponTool(t) and not allowed[t.Name] then t.Parent = stash end end end
		for _, t in backpack:GetChildren() do if isWeaponTool(t) and not allowed[t.Name] then t.Parent = stash end end
		for _, t in stash:GetChildren() do if allowed[t.Name] then t.Parent = backpack end end
	else
		for _, t in stash:GetChildren() do t.Parent = backpack end -- no loadout chosen: everything is in the hotbar
	end
end
local loadoutQueued = {}
queueLoadout = function(player)
	if loadoutQueued[player] then return end
	loadoutQueued[player] = true
	task.delay(0.35, function()
		loadoutQueued[player] = nil
		if player.Parent then
			applyLoadout(player)
			sendState(player) -- the armory list changes when a weapon arrives
		end
	end)
end

----------------------------------------------------------------------
-- missions
----------------------------------------------------------------------
local function available(p, id)
	local m = Items.Missions[id]
	if not m then return false end
	if m.requires and not p.done[m.requires] then return false end
	if p.done[id] and not m.repeatable then return false end
	return true
end

local function completeMission(player, p, skipped)
	local a = p.active
	local m = a and Items.Missions[a.id]
	if not m then return end
	local money, iron = stat(player, "Money"), stat(player, "Iron")
	if money and m.reward.money then money.Value += m.reward.money end
	if iron and m.reward.iron then iron.Value += m.reward.iron end
	if not m.repeatable then p.done[a.id] = true end
	local unlocked
	if m.unlocks and not p.unlocked[m.unlocks] then
		p.unlocked[m.unlocks] = true
		unlocked = m.unlocks
	end
	p.active = nil
	notify(player, "complete", a.id, unlocked, skipped == true)
	sendState(player)
	requestSave(player)
end

local function addProgress(player, kind, info)
	local p = profiles[player]
	local a = p and p.active
	local m = a and Items.Missions[a.id]
	if not m or m.type ~= kind then return end
	local f = m.filter or {}
	if kind == "kill" then
		if f.hive and info.hive ~= f.hive then return end
		if f.weapon and info.weapon ~= f.weapon then return end
	elseif kind == "collect" then
		if f.resource ~= info.resource then return end
	end
	a.progress = (a.progress or 0) + (info.amount or 1)
	if a.progress >= m.target then
		a.progress = m.target
		completeMission(player, p)
	else
		sendState(player)
	end
end

local function startTitan(player)
	-- the Titan rises from the hive nearest to the player
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local best, bd
	for _, h in workspace:WaitForChild("AlienHives"):GetChildren() do
		local c = h:GetAttribute("Center")
		if c and not h:GetAttribute("TitanAlive") then
			local d = root and (c - root.Position).Magnitude or 0
			if not bd or d < bd then best, bd = h, d end
		end
	end
	if best then
		best:SetAttribute("SpawnTitan", true)
		notify(player, "toast", "The Xeno Titan is rising from HIVE " .. tostring(best:GetAttribute("Index")) .. "!", C3(255, 70, 90))
	else
		notify(player, "toast", "A Titan is already alive. Find it and kill it!", C3(255, 200, 90))
	end
end

actionRemote.OnServerInvoke = function(player, action, a, b)
	local p = profiles[player]
	if not p then return false, "loading" end
	if action == "state" then
		return true, p.chests or 0
	elseif action == "accept" then
		if typeof(a) ~= "string" or not available(p, a) then return false, "That mission is not available." end
		if p.active then return false, "Finish or abandon your current mission first." end
		p.active = { id = a, progress = 0 }
		notify(player, "accepted", a)
		sendState(player)
		if Items.Missions[a].type == "titan" then startTitan(player) end
		return true
	elseif action == "abandon" then
		if p.active then
			p.active = nil
			sendState(player)
		end
		return true
	elseif action == "buy" then
		local it = typeof(a) == "string" and Items.List[a]
		if not it then return false, "Unknown item." end
		if it.secret then return false, "This one is not for sale with money." end
		if p.owned[a] then return false, "You already own it." end
		if not p.unlocked[a] then return false, "Locked: complete the mission first." end
		local money = stat(player, "Money")
		if not money or money.Value < it.price then return false, "Not enough money." end
		money.Value -= it.price
		p.owned[a] = true
		if it.tool then
			giveWeapon(player, it.tool)
		elseif (p.equipped[it.slot] or "") == "" then
			p.equipped[it.slot] = a
			player:SetAttribute(it.slot .. "Id", a)
		end
		notify(player, "purchased", a)
		sendState(player)
		requestSave(player)
		return true
	elseif action == "loadoutSave" then
		-- a = array of up to 4 weapon names (empty = no loadout: every weapon in the hotbar)
		if typeof(a) ~= "table" then return false end
		local owned = {}
		for _, n in armoryNames(player, p) do owned[n] = true end
		local list, seen = {}, {}
		for _, n in a do
			if typeof(n) == "string" and owned[n] and not seen[n] and #list < LOADOUT_SLOTS then
				seen[n] = true
				list[#list + 1] = n
			end
		end
		p.loadout = (#list > 0) and list or nil
		applyLoadout(player)
		sendState(player)
		requestSave(player)
		return true
	elseif action == "openChest" then
		local res = events.Grant:Invoke(player, "chestOpen", false)
		if typeof(res) == "table" then
			notify(player, "chest", res)
			return true, res
		end
		return false, "You have no chest to open."
	elseif action == "robuxBuy" or action == "robuxSkip" then
		return events.PurchaseAction:Invoke(player, action, a)
	elseif action == "equip" then
		-- a = slot ("Trail" / "Passive"), b = item id or "" to unequip
		if a ~= "Trail" and a ~= "Passive" then return false end
		if b == "" or b == nil then
			p.equipped[a] = ""
		else
			local it = typeof(b) == "string" and Items.List[b]
			if not it or it.slot ~= a or not p.owned[b] then return false, "You do not own that." end
			p.equipped[a] = b
		end
		player:SetAttribute(a .. "Id", p.equipped[a])
		sendState(player)
		return true
	end
	return false
end

----------------------------------------------------------------------
-- Xeno Ichor drops (they drift toward you when you are close)
----------------------------------------------------------------------
local drops = {}
local function dropIchor(pos, count)
	for i = 1, count do
		local orb = Instance.new("Part")
		orb.Name = "XenoIchor"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(2.2, 2.2, 2.2)
		orb.Material = Enum.Material.Neon
		orb.Color = C3(130, 255, 100)
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CanTouch = false
		orb.CastShadow = false
		orb.Position = pos + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(1, 5), rng:NextNumber(-6, 6))
		local l = Instance.new("PointLight")
		l.Color = orb.Color; l.Range = 14; l.Brightness = 0.8; l.Shadows = false
		l.Parent = orb
		local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 1, 0); a0.Parent = orb
		local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -1, 0); a1.Parent = orb
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime = 0.6; tr.LightEmission = 1; tr.Color = ColorSequence.new(orb.Color); tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		tr.Parent = orb
		orb.Parent = workspace.IchorDrops
		table.insert(drops, { part = orb, born = os.clock(), base = orb.Position })
	end
end

local function sparkBurst(pos, color, count)
	local fx = Instance.new("Part")
	fx.Anchored = true; fx.CanCollide = false; fx.CanQuery = false; fx.Transparency = 1; fx.Size = Vector3.new(1, 1, 1); fx.Position = pos
	fx.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1; e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.4, 0.9); e.Speed = NumberRange.new(10, 28); e.SpreadAngle = Vector2.new(180, 180); e.Rate = 0
	e.Parent = fx
	e:Emit(count)
	Debris:AddItem(fx, 1.5)
end

task.spawn(function()
	while true do
		task.wait(0.05)
		local now = os.clock()
		for i = #drops, 1, -1 do
			local d = drops[i]
			local orb = d.part
			if not orb.Parent or now - d.born > 120 then
				if orb.Parent then orb:Destroy() end
				table.remove(drops, i)
			else
				orb.Position = d.base + Vector3.new(0, math.sin(now * 2 + d.born) * 0.6, 0)
				for _, player in Players:GetPlayers() do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					local p = profiles[player]
					if root and p then
						local dist = (root.Position - orb.Position).Magnitude
						if dist < 7 then
							setResource(player, p, "ichor", p.ichor + 1)
							sparkBurst(orb.Position, orb.Color, 14)
							notify(player, "pickup", "Ichor", p.ichor)
							addProgress(player, "collect", { resource = "Ichor" })
							sendState(player)
							orb:Destroy()
							table.remove(drops, i)
							break
						elseif dist < 40 then
							d.base = d.base:Lerp(root.Position, 0.18) -- drift toward the player
						end
					end
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- Hive Crystals on the towers
----------------------------------------------------------------------
local crystalPoints = ReplicatedStorage:FindFirstChild("CrystalPoints")
if not crystalPoints then
	crystalPoints = Instance.new("Folder")
	crystalPoints.Name = "CrystalPoints"
	crystalPoints.Parent = ReplicatedStorage
end
local function setupCrystals()
	local folder = workspace:WaitForChild("HiveCrystals", 20)
	if not folder then return end
	for _, crystal in folder:GetChildren() do
		local prompt = crystal:FindFirstChildOfClass("ProximityPrompt")
		local marker = crystalPoints:FindFirstChild(crystal.Name)
		if not marker then
			marker = Instance.new("Vector3Value")
			marker.Name = crystal.Name
			marker.Value = crystal.Position
			marker.Parent = crystalPoints
		end
		marker:SetAttribute("Active", true)
		if prompt then
			prompt.Triggered:Connect(function(player)
				local p = profiles[player]
				if not p or crystal:GetAttribute("Taken") then return end
				crystal:SetAttribute("Taken", true)
				marker:SetAttribute("Active", false)
				setResource(player, p, "crystal", p.crystal + 1)
				sparkBurst(crystal.Position, C3(200, 120, 255), 40)
				notify(player, "pickup", "Crystal", p.crystal)
				addProgress(player, "collect", { resource = "Crystal" })
				sendState(player)
				for _, d in crystal:GetDescendants() do
					if d:IsA("BasePart") then d.Transparency = 1 end
					if d:IsA("Light") or d:IsA("Beam") then d.Enabled = false end
				end
				prompt.Enabled = false
				task.delay(CRYSTAL_RESPAWN, function()
					for _, d in crystal:GetDescendants() do
						if d:IsA("BasePart") and d.Name ~= "CrystalHitbox" then d.Transparency = d:GetAttribute("BaseTransparency") or 0 end
						if d:IsA("Light") or d:IsA("Beam") then d.Enabled = true end
					end
					prompt.Enabled = true
					crystal:SetAttribute("Taken", nil)
					marker:SetAttribute("Active", true)
				end)
			end)
		end
	end
end
task.spawn(setupCrystals)

----------------------------------------------------------------------
-- kills (sent by AlienHive)
----------------------------------------------------------------------
events.AlienDied.Event:Connect(function(pos, killerId, hiveIndex, weaponId, isTitan)
	dropIchor(pos, isTitan and 8 or ICHOR_PER_KILL)
	local killer = killerId and Players:GetPlayerByUserId(killerId)
	local p = killer and profiles[killer]
	if not p then return end
	p.kills += 1
	if p.equipped.Passive == "ArchonCrown" then
		local money = stat(killer, "Money")
		if money then money.Value += CROWN_BONUS end
		notify(killer, "toast", "ARCHON'S CROWN  +$" .. CROWN_BONUS, Items.rarityColor("Legendary"))
	end
	addProgress(killer, "kill", { hive = hiveIndex, weapon = weaponId })
	if isTitan then
		addProgress(killer, "titan", {})
		local money = stat(killer, "Money")
		if money then money.Value += 400 end
		notify(killer, "toast", "XENO TITAN SLAIN  +$400", Items.rarityColor("Mythic"))
	end
end)
events.WaveCleared.Event:Connect(function(hiveIndex, killerIds)
	for _, id in killerIds or {} do
		local pl = Players:GetPlayerByUserId(id)
		if pl and profiles[pl] then addProgress(pl, "wave", {}) end
	end
end)

----------------------------------------------------------------------
-- item effects that need the server
----------------------------------------------------------------------
-- every hostile: the hive aliens AND the mothership forces (the contrails burn / slow all of them)
local function allForces()
	local list = {}
	for _, name in { "XenoAliens", "MothershipForces" } do
		local f = workspace:FindFirstChild(name)
		if f then
			for _, c in f:GetChildren() do list[#list + 1] = c end
		end
	end
	return list
end
local trails = {} -- [player] = { {pos, t}, ... } recent positions while moving fast
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		local aliens = { GetChildren = function() return allForces() end }
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local trail = player:GetAttribute("TrailId")
			if root and aliens and (trail == "SolarContrail" or trail == "VoidContrail") then
				if trail == "VoidContrail" then
					for _, a in aliens:GetChildren() do
						local ar = a.PrimaryPart
						local h = a:FindFirstChildOfClass("Humanoid")
						if ar and h and h.Health > 0 and (ar.Position - root.Position).Magnitude < VOID_RANGE then
							a:SetAttribute("SlowUntil", now + 0.6)
						end
					end
				else
					local list = trails[player] or {}
					trails[player] = list
					if root.AssemblyLinearVelocity.Magnitude > 20 then
						table.insert(list, { pos = root.Position, t = now })
					end
					while #list > 0 and now - list[1].t > 2.5 do table.remove(list, 1) end
					for _, a in aliens:GetChildren() do
						local ar = a.PrimaryPart
						local h = a:FindFirstChildOfClass("Humanoid")
						if ar and h and h.Health > 0 then
							for _, pt in list do
								if now - pt.t > 0.3 and (ar.Position - pt.pos).Magnitude < 9 then
									h:SetAttribute("LastAttacker", player.UserId)
									h:SetAttribute("LastAttackTime", now)
									h:SetAttribute("LastWeapon", "SolarContrail")
									h:TakeDamage(SOLAR_DPS * 0.25)
									if rng:NextNumber() < 0.5 then sparkBurst(ar.Position, C3(255, 140, 40), 6) end
									break
								end
							end
						end
					end
				end
			else
				trails[player] = nil
			end
		end
	end
end)

----------------------------------------------------------------------
-- grants (used by PurchaseService when a Robux purchase succeeds). Returns nil = profile not ready, false = nothing new, true = granted
----------------------------------------------------------------------
events.Grant.OnInvoke = function(player, action, a, silent)
	local p = profiles[player]
	if not p then return nil end
	if action == "money" then
		local v = stat(player, "Money")
		if v and typeof(a) == "number" then v.Value += a return true end
		return false
	elseif action == "iron" then
		local v = stat(player, "Iron")
		if v and typeof(a) == "number" then v.Value += a return true end
		return false
	elseif action == "item" then
		local it = Items.List[a]
		if not it then return false end
		if p.owned[a] then return false end
		p.unlocked[a] = true
		p.owned[a] = true
		if it.tool then
			giveWeapon(player, it.tool)
		elseif (p.equipped[it.slot] or "") == "" then
			p.equipped[it.slot] = a
			player:SetAttribute(it.slot .. "Id", a)
		end
		if not silent then notify(player, "purchased", a) end
		sendState(player)
		return true
	elseif action == "owns" then
		return p.owned[a] == true
	elseif action == "skip" then
		-- complete a mission right away: all its rewards and its unlock. The player's current mission is kept.
		if typeof(a) ~= "string" or not available(p, a) then return false end
		local prev = p.active
		p.active = { id = a, progress = Items.Missions[a].target }
		completeMission(player, p, true)
		if prev and prev.id ~= a then
			p.active = prev
			sendState(player)
		end
		return true
	elseif action == "missionAvailable" then
		return typeof(a) == "string" and available(p, a)
	elseif action == "chestAdd" then
		-- a boss chest the player did not open in the world is kept for later (opened from the HUD button)
		p.chests = (p.chests or 0) + (typeof(a) == "number" and a or 1)
		sendState(player)
		requestSave(player)
		return true
	elseif action == "chestOpen" then
		-- roll one chest. a = true: it is a chest that was opened in the world (does not use a saved chest)
		local fromWorld = a == true
		if not fromWorld then
			if (p.chests or 0) <= 0 then return false end
			p.chests -= 1
		end
		local owned = {}
		for id, w in Loot.Weapons do
			if p.weapons[w.tool] or (player.Backpack:FindFirstChild(w.tool)) or (player.Character and player.Character:FindFirstChild(w.tool)) then owned[id] = true end
		end
		local id, rarity, pity = Loot.roll({ sinceLegendary = p.pity.sinceLegendary, sinceSecret = p.pity.sinceSecret, owned = owned }, rng)
		p.pity.sinceSecret = (rarity == "Secret") and 0 or (p.pity.sinceSecret + 1)
		p.pity.sinceLegendary = (rarity == "Secret" or rarity == "Legendary") and 0 or (p.pity.sinceLegendary + 1)
		local w = Loot.Weapons[id]
		local duplicate = owned[id] == true
		local moneyGained = 0
		if duplicate then
			moneyGained = Loot.DuplicateMoney[rarity]
			local v = stat(player, "Money")
			if v then v.Value += moneyGained end
		else
			p.weapons[w.tool] = true
			if p.loadout and #p.loadout < LOADOUT_SLOTS and not table.find(p.loadout, w.tool) then table.insert(p.loadout, w.tool) end
			giveWeapon(player, w.tool)
		end
		applyLoadout(player)
		local stashed = (not duplicate) and p.loadout ~= nil and not table.find(p.loadout, w.tool)
		sendState(player)
		requestSave(player)
		return { id = id, rarity = rarity, duplicate = duplicate, money = moneyGained, pity = pity, stashed = stashed }
	elseif action == "refill" then
		player:SetAttribute("BoostRefill", (player:GetAttribute("BoostRefill") or 0) + 1)
		return true
	end
	return false
end

----------------------------------------------------------------------
-- players
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	local p = loadProfile(player)
	sendState(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.8)
		restoreWeapons(player)
		sendState(player)
	end)
	if player.Character then
		task.spawn(function()
			task.wait(0.8)
			restoreWeapons(player)
		end)
	end
	task.spawn(function()
		while player.Parent do
			task.wait(60)
			saveProfile(player)
		end
	end)
end)
Players.PlayerRemoving:Connect(function(player)
	saveProfile(player)
	profiles[player] = nil
	trails[player] = nil
end)
-- developer hook (server scripts only, no client can reach it): wipe a player's saved progress and stop saving it for this session
local resetFn = Instance.new("BindableFunction")
resetFn.Name = "ResetProfile"
resetFn.Parent = events
resetFn.OnInvoke = function(player)
	local p = profiles[player]
	if p then p.canSave = false end
	local ok, err = pcall(function()
		store:RemoveAsync("p_" .. player.UserId)
	end)
	return ok, err
end

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveProfile(player)
	end
end)
for _, player in Players:GetPlayers() do
	task.spawn(function()
		loadProfile(player)
		sendState(player)
	end)
end
