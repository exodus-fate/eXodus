--[[
	Gamepasses and developer products.

	IDs are 0 until you create the passes/products in the Creator Dashboard
	(Monetization > Passes / Developer Products) and paste their IDs here.
	Anything with id = 0 is hidden in the store and can never be prompted.

	Prices are the brief's starting hypotheses (Robux) for you to test; the price
	actually charged is whatever you set on the dashboard.

	Rules enforced in code (MarketService):
	  * The game is completable without spending anything.
	  * No paid invulnerability, unlimited edits, guaranteed escape, ending skip
	    or exclusive story clues.
	  * Re-entry is at most once per player per case, at a safe checkpoint, with
	    a short delay; it never restores spent edit charges.
	  * Purchases are granted server-side from ProcessReceipt, once per receipt.
]]

local Monetisation = {}

Monetisation.Passes = {
	Locker = {
		id = 0,
		name = "Investigator's Locker",
		priceHint = "79-129 Robux",
		description = "Two extra loadout preset slots and the Locker Reserve uniform. No gameplay advantage.",
	},
	ClassicPack = {
		id = 0,
		name = "Classic Broadcast Pack",
		priceHint = "99-149 Robux",
		description = "Extra CRT menu themes, the Classic camcorder shell and the Classic REC overlay. All information stays equally readable.",
	},
	Quarters = {
		id = 0,
		name = "Personal Quarters",
		priceHint = "79-149 Robux",
		description = "Decorate your desk in the field office with a poster, lamp and tape display shelf.",
	},
	Supporter = {
		id = 0,
		name = "Supporter Pass",
		priceHint = "149-249 Robux",
		description = "Supporter nameplate and jacket. No story clues or survival tools.",
	},
	ExtraPresets = {
		id = 0,
		name = "Extra Loadout Presets",
		priceHint = "49-79 Robux",
		description = "Three more loadout preset slots.",
	},
}
Monetisation.PassOrder = { "Locker", "ClassicPack", "Quarters", "Supporter", "ExtraPresets" }

Monetisation.Products = {
	Revive = {
		id = 0,
		name = "Emergency Re-entry",
		priceHint = "15-29 Robux",
		description = "Return once this case at a safe checkpoint after a short delay. Does not restore spent edit charges or skip objectives. If the case has ended, it is kept for your next case.",
	},
	TeamToken = {
		id = 0,
		name = "Team Recovery",
		priceHint = "39-59 Robux",
		description = "Brings back every eliminated teammate at a checkpoint. Needs the team to agree. After a team recovery, no more re-entries can be bought this case.",
	},
	EvidenceBundle = {
		id = 0,
		name = "Evidence Label Bundle",
		priceHint = "19-49 Robux",
		description = "Red and blue tape label skins for your Evidence Archive. No lore.",
	},
	LobbyBundle = {
		id = 0,
		name = "Office Decoration Bundle",
		priceHint = "29-79 Robux",
		description = "A plant, an old radio and a portable TV for your field office desk.",
	},
}
Monetisation.ProductOrder = { "Revive", "TeamToken", "EvidenceBundle", "LobbyBundle" }

function Monetisation.productByAssetId(assetId: number)
	for key, product in Monetisation.Products do
		if product.id ~= 0 and product.id == assetId then
			return key, product
		end
	end
	return nil
end

function Monetisation.passByAssetId(assetId: number)
	for key, pass in Monetisation.Passes do
		if pass.id ~= 0 and pass.id == assetId then
			return key, pass
		end
	end
	return nil
end

return Monetisation
