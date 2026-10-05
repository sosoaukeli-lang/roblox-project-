-- PurchaseService (Script) - every Robux purchase goes through here.
--   * the SECRET WEAPON game pass, mission SKIPS (price = 29 R$ + 30 R$ per difficulty level), bundles, money packs, energy cell
--   * receipts are processed safely: each purchase is granted ONCE, even if the player rejoins or the server crashes
--   * products whose id in ReplicatedStorage.Monetization is still 0 are "not set up": real players cannot buy them,
--     inside Roblox Studio the purchase is simulated (TEST_MODE) so you can test everything for free
-- The client asks through ProgressAction("robuxBuy", key) / ("robuxSkip", missionId); ProgressService forwards it here.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PolicyService = game:GetService("PolicyService")
local Mon = require(ReplicatedStorage:WaitForChild("Monetization"))
local Items = require(ReplicatedStorage:WaitForChild("Items"))
local notifyRemote = ReplicatedStorage:WaitForChild("ProgressNotify")
local events = ServerStorage:WaitForChild("ProgressEvents")
local grant = events:WaitForChild("Grant")
local purchaseAction = events:WaitForChild("PurchaseAction")

local receipts = DataStoreService:GetDataStore("Receipts_v1")
local pendingSkip = {} -- [userId] = { missionId, key, t }

local function ready(player)
	return grant:Invoke(player, "owns", "__ready__") ~= nil
end

----------------------------------------------------------------------
-- what each purchase gives
----------------------------------------------------------------------
local function grantProduct(player, key, entry)
	if not ready(player) then return false end
	if entry.kind == "skip" then
		local pend = pendingSkip[player.UserId]
		if not pend or pend.key ~= key or os.clock() - pend.t > 900 then
			return false
		end
		local ok = grant:Invoke(player, "skip", pend.missionId)
		if ok then pendingSkip[player.UserId] = nil end
		return ok == true
	elseif entry.kind == "chest" then
		-- the chest is added to the account and opened at once (the opening cinematic plays on the client)
		grant:Invoke(player, "chestAdd", 1)
		local res = grant:Invoke(player, "chestOpen", false)
		if typeof(res) == "table" then
			notifyRemote:FireClient(player, "chest", res, nil)
		end
		return true
	elseif entry.kind == "energy" then
		notifyRemote:FireClient(player, "robux", key)
		return grant:Invoke(player, "refill") == true
	else
		if entry.money then grant:Invoke(player, "money", entry.money) end
		if entry.iron then grant:Invoke(player, "iron", entry.iron) end
		for _, id in entry.items or {} do
			grant:Invoke(player, "item", id, true)
		end
		if entry.raygun then
			grant:Invoke(player, "item", "AetherRaygun", true)
		end
		notifyRemote:FireClient(player, "robux", key)
		return true
	end
end

local function grantPass(player, passKey)
	local pass = Mon.Passes[passKey]
	if not pass or not ready(player) then return false end
	local newly = grant:Invoke(player, "item", pass.item, true)
	if newly then
		notifyRemote:FireClient(player, "robux", passKey)
	end
	return true
end

----------------------------------------------------------------------
-- Robux receipts (developer products)
----------------------------------------------------------------------
MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = Mon.keyForProductId(info.ProductId)
	local entry = key and Mon.Products[key]
	if not entry then
		warn("[PurchaseService] unknown product id " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local rid = info.PlayerId .. "_" .. info.PurchaseId
	local okRead, done = pcall(function() return receipts:GetAsync(rid) end)
	if not okRead then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if done then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already given (the player rejoined before Roblox heard back)
	end
	if not grantProduct(player, key, entry) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	pcall(function() receipts:SetAsync(rid, true) end)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- the game pass: grant right after the purchase, and again every time the player joins
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	for key, pass in Mon.Passes do
		if pass.id ~= 0 and pass.id == passId then
			grantPass(player, key)
		end
	end
end)
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		for key, pass in Mon.Passes do
			if pass.id ~= 0 then
				local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id) end)
				if ok and owns then
					for _ = 1, 40 do
						if grantPass(player, key) then break end
						task.wait(0.5)
					end
				end
			end
		end
	end)
end)

----------------------------------------------------------------------
-- what the client can ask for
----------------------------------------------------------------------
local function startPurchase(player, key, entry, isPass)
	if entry.id == 0 then
		if Mon.TEST_MODE then
			-- Studio only: a free simulated purchase
			warn("[PurchaseService] TEST PURCHASE (no id set yet): " .. key .. " - " .. entry.price .. " R$")
			local ok
			if isPass then ok = grantPass(player, key) else ok = grantProduct(player, key, entry) end
			if ok then return true end
			return false, "Could not grant it right now."
		end
		return false, "This item is not on sale yet."
	end
	if isPass then
		MarketplaceService:PromptGamePassPurchase(player, entry.id)
	else
		MarketplaceService:PromptProductPurchase(player, entry.id)
	end
	return true
end

purchaseAction.OnInvoke = function(player, action, a)
	if typeof(a) ~= "string" then return false, "Invalid request." end
	if action == "robuxBuy" then
		local pass = Mon.Passes[a]
		if pass then
			if grant:Invoke(player, "owns", pass.item) == true then
				return false, "You already own it."
			end
			return startPurchase(player, a, pass, true)
		end
		local entry = Mon.Products[a]
		if not entry or entry.kind == "skip" then return false, "Unknown product." end
		if entry.kind == "chest" then
			-- Roblox restricts paid random items for some accounts / regions
			local okp, policy = pcall(function() return PolicyService:GetPolicyInfoForPlayerAsync(player) end)
			if okp and policy and policy.ArePaidRandomItemsRestricted then
				return false, "Paid random items are not available for your account."
			end
		end
		return startPurchase(player, a, entry, false)
	elseif action == "robuxSkip" then
		local mission = Items.Missions[a]
		if not mission then return false, "Unknown mission." end
		if grant:Invoke(player, "missionAvailable", a) ~= true then
			return false, "That mission is not available to skip."
		end
		local key = "skip_" .. math.clamp(mission.difficulty or 1, 1, Mon.MAX_DIFFICULTY)
		local entry = Mon.Products[key]
		pendingSkip[player.UserId] = { missionId = a, key = key, t = os.clock() }
		return startPurchase(player, key, entry, false)
	end
	return false, "Invalid request."
end

Players.PlayerRemoving:Connect(function(player)
	pendingSkip[player.UserId] = nil
end)
