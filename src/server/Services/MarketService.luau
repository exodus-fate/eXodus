--[[
	MarketService — gamepasses and developer products.

	* Pass ownership is checked on the server (UserOwnsGamePassAsync) and cached.
	* Developer products are granted only in ProcessReceipt, exactly once per
	  receipt: the PurchaseId is recorded in the player's profile and saved before
	  PurchaseGranted is returned.
	* Re-entry and Team Recovery purchases are stored on the profile, then spent by
	  MissionService when eligible - a purchase that arrives after the case ended is
	  simply kept for next time, never lost.
	* Nothing here is required to finish the game.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Monetisation = require(Shared.Config.Monetisation)
local Cosmetics = require(Shared.Config.Cosmetics)

local MarketService = {}

local MAX_RECEIPTS_KEPT = 60

MarketService.passCache = {} -- [player] = { [passKey] = true }
MarketService.onGranted = {} -- callbacks(player, productKey)
MarketService.onPassChanged = {} -- callbacks(player)
MarketService.pending = {} -- [player] = { productKey = intent }

local deps

function MarketService.ownsPass(player, passKey)
	local cache = MarketService.passCache[player]
	return cache ~= nil and cache[passKey] == true
end

function MarketService.passes(player)
	return MarketService.passCache[player] or {}
end

function MarketService.refreshPasses(player)
	local cache = {}
	for key, pass in Monetisation.Passes do
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			cache[key] = ok and owns or false
		end
	end
	MarketService.passCache[player] = cache
	for _, callback in MarketService.onPassChanged do
		task.spawn(callback, player)
	end
end

function MarketService.promptPass(player, passKey)
	local pass = Monetisation.Passes[passKey]
	if not pass or pass.id == 0 then
		return false, "This pass is not available yet."
	end
	if MarketService.ownsPass(player, passKey) then
		return false, "You already own this."
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.id)
	return true
end

-- intent is remembered so the purchase can be applied right away when granted.
function MarketService.promptProduct(player, productKey, intent)
	local product = Monetisation.Products[productKey]
	if not product or product.id == 0 then
		return false, "This item is not available yet."
	end
	MarketService.pending[player] = MarketService.pending[player] or {}
	MarketService.pending[player][productKey] = intent or true
	MarketplaceService:PromptProductPurchase(player, product.id)
	return true
end

function MarketService.takeIntent(player, productKey)
	local pending = MarketService.pending[player]
	if not pending then
		return nil
	end
	local intent = pending[productKey]
	pending[productKey] = nil
	return intent
end

local function grant(profile, productKey)
	if productKey == "Revive" then
		profile.storedRevives += 1
	elseif productKey == "TeamToken" then
		profile.storedTeamTokens += 1
	elseif productKey == "EvidenceBundle" or productKey == "LobbyBundle" then
		for id, item in Cosmetics.Items do
			if item.source == "product" and item.product == productKey then
				profile.cosmetics.owned[id] = true
			end
		end
		for id, item in Cosmetics.Decor do
			if item.source == "product" and item.product == productKey then
				profile.cosmetics.owned[id] = true
			end
		end
	end
end

local function processReceipt(receipt)
	local productKey = Monetisation.productByAssetId(receipt.ProductId)
	if not productKey then
		warn("[MarketService] Receipt for unknown product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- Roblox retries when they next join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = deps.DataService.get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	profile.receipts = profile.receipts or {}
	local purchaseId = tostring(receipt.PurchaseId)
	for _, id in profile.receipts do
		if id == purchaseId then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	grant(profile, productKey)
	table.insert(profile.receipts, purchaseId)
	while #profile.receipts > MAX_RECEIPTS_KEPT do
		table.remove(profile.receipts, 1)
	end
	deps.DataService.markDirty(player)
	if not deps.DataService.saveNow(player) then
		-- The in-memory record above stops a double grant on retry this session;
		-- if the server dies before saving, neither the grant nor the record persist.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	for _, callback in MarketService.onGranted do
		task.spawn(callback, player, productKey)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MarketService.init(dependencies)
	deps = dependencies
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			local key = Monetisation.passByAssetId(passId)
			if key then
				MarketService.passCache[player] = MarketService.passCache[player] or {}
				MarketService.passCache[player][key] = true
				for _, callback in MarketService.onPassChanged do
					task.spawn(callback, player)
				end
			end
		end
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if not purchased then
			-- Cancelled or failed: forget the intent. Nothing was charged.
			local player = Players:GetPlayerByUserId(userId)
			local key = Monetisation.productByAssetId(productId)
			if player and key then
				MarketService.takeIntent(player, key)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		MarketService.refreshPasses(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(MarketService.refreshPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		MarketService.passCache[player] = nil
		MarketService.pending[player] = nil
	end)
end

-- Store listing for the client (only configured items).
function MarketService.catalogue(player)
	local passes, products = {}, {}
	for _, key in Monetisation.PassOrder do
		local pass = Monetisation.Passes[key]
		if pass.id ~= 0 then
			table.insert(passes, {
				key = key,
				name = pass.name,
				description = pass.description,
				owned = MarketService.ownsPass(player, key),
			})
		end
	end
	for _, key in Monetisation.ProductOrder do
		local product = Monetisation.Products[key]
		if product.id ~= 0 then
			table.insert(products, { key = key, name = product.name, description = product.description })
		end
	end
	return { passes = passes, products = products }
end

return MarketService
