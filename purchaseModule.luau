local Core = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local BadgeService = game:GetService("BadgeService")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Indicator = ServerStorage:WaitForChild("ShopItemIndicator")
local Notify = require(Modules:WaitForChild("NotificationModule"))
local Confirmation = require(Modules:WaitForChild("Confirmation"))
local GearRarities = require(Modules:WaitForChild("GearRarities")) 
local Gradients = ReplicatedStorage:WaitForChild("Gradients")
local promptPurchase = Remotes:WaitForChild("PromptPurchase")
local promptDebounce = {}
local function CheckBadge(player, badgeId)
	if not badgeId then return true end 
	local success, hasBadge = pcall(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
	end)
	return success and hasBadge
end
local function getCurrencyValueObject(player, currencyName)
	if not player then return nil end
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild(currencyName)
end
local function Shorten(num)
	if not num then return "0" end
	if num >= 1e9 then return string.format("%.1fB", num / 1e9)
	elseif num >= 1e6 then return string.format("%.1fM", num / 1e6)
	elseif num >= 1e3 then return string.format("%.0fk", num / 1e3)
	else return tostring(num) end
end
local function AddToInventory(player, gearName, quantity)
	if not gearName then return end
	local inv = player:FindFirstChild("Inventory")
	if not inv then return end	
	local itemVal = inv:FindFirstChild(gearName)
	if itemVal then 
		itemVal.Value += (quantity or 1)
	else
		local newVal = Instance.new("NumberValue", inv)
		newVal.Name = gearName
		newVal.Value = (quantity or 1)
	end
end
local function giveGearToPlayer(player, itemName)
	local gearsFolder = ReplicatedStorage:FindFirstChild("Gears")
	local gear = nil
	for _, obj in ipairs(gearsFolder:GetDescendants()) do
		if obj:IsA("Tool") and obj.Name == itemName then
			gear = obj
			break
		end
	end
	if not gear then return false, "Gear not found in Storage" end
	AddToInventory(player, gear.Name, 1) 
	return true, "Purchased " .. gear.Name
end
local function GetItemDataFromPrompt(prompt)
	local promptType = prompt:GetAttribute("ProductType") or "Gear"
	local itemName = prompt:GetAttribute("ItemName") 
	local data = {
		Name = itemName,
		Price = 0,
		Currency = "Crystals",
		Type = promptType,
		ReqBadge = prompt:GetAttribute("ReqBadge") 
	}
	if promptType == "Gear" then
		local gearInfo = GearRarities.GetGearsData(itemName)
		if gearInfo then
			data.Price = gearInfo.BuyPrice
			data.Currency = gearInfo.Currency or "Crystals"
		end
	elseif promptType == "RandomGear" then
		local boxInfo = GearRarities.GetBoxData(itemName) 
		if boxInfo then
			data.Price = boxInfo.Price
			data.Currency = boxInfo.Currency
		else
			data.Price = prompt:GetAttribute("Price") or 999999
			data.Currency = prompt:GetAttribute("Currency") or "Crystals"
		end
	elseif promptType == "Currency" then
		data.Price = prompt:GetAttribute("Price") or 0
		data.Currency = prompt:GetAttribute("Currency") or "Crystals"
		data.Amount = prompt:GetAttribute("Amount") or 0
		data.TargetCurrency = prompt:GetAttribute("TargetCurrency") or "Coins"
	end
	return data
end
local function createIndicator(prompt,robuxPrice)
	local NewIndicator = Indicator:Clone()
	local itemData =table.clone(GetItemDataFromPrompt(prompt))
	if robuxPrice then
		itemData.Price = robuxPrice
		itemData.Currency = "R$"
	end
	NewIndicator.Parent = prompt.Parent
	NewIndicator.Price.Text = Shorten(itemData.Price) .. " " .. itemData.Currency
	prompt.HoldDuration = 1
	if itemData.Type == "Gear" then
		prompt.ActionText = "Purchase"
		NewIndicator.ItemName.Text = itemData.Name or "Unknown"
	elseif itemData.Type == "RandomGear" then
		prompt.ActionText = "Open Box"
		NewIndicator.ItemName.Text = itemData.Name or "Mystery Box"
	elseif itemData.Type == "Currency" then
		NewIndicator.DoesntSave.Visible = false
		prompt.ActionText = "Exchange"
		NewIndicator.ItemName.Text = tostring(itemData.Amount) .. " " .. itemData.TargetCurrency
	end
	if itemData.ReqBadge then
		NewIndicator.DoesntSave.Visible = true
		local success, info = pcall(function() return BadgeService:GetBadgeInfoAsync(itemData.ReqBadge) end)
		NewIndicator.DoesntSave.Text = success and ("Need Badge: " .. info.Name) or "Locked"
	end
	local currencyGradient = Gradients:FindFirstChild(itemData.Currency)
	if currencyGradient then
		currencyGradient:Clone().Parent = NewIndicator.Price
	end
	return NewIndicator
end
local function handleInGamePurchase(prompt, player)
	local itemData = GetItemDataFromPrompt(prompt)
	if itemData.Price <= 0 then return end
	if itemData.ReqBadge and not CheckBadge(player, itemData.ReqBadge) then
		Notify.Push(player, "Required badge missing!", "Warn")
		return
	end
	local wallet = getCurrencyValueObject(player, itemData.Currency)
	if not wallet or wallet.Value < itemData.Price then
		Notify.Push(player, "Not enough " .. itemData.Currency .. "!", "Error")
		return
	end
	wallet.Value -= itemData.Price
	local success = false
	local message = "Error"
	if itemData.Type == "Gear" then
		success, message = giveGearToPlayer(player, itemData.Name)
	elseif itemData.Type == "RandomGear" then
		local restriction = player:GetAttribute("PaidRandomRestricted")
		if restriction then
			success = false
			message = "Region restriction"
			Confirmation.Ask(player, "Paid random items are restricted in your region.", 2, false)
		else
			success, message = giveGearToPlayer(player, itemData.Name)
		end
	elseif itemData.Type == "Currency" then
		local targetWallet = getCurrencyValueObject(player, itemData.TargetCurrency)
		if targetWallet then
			targetWallet.Value += itemData.Amount
			success = true
			message = "Exchanged!"
		end
	end
	if success then
		Notify.Push(player, message, "Success")
	else
		wallet.Value += itemData.Price
		Notify.Push(player, message, "Error")
	end
end
local function connectPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then return end
	promptDebounce[prompt] = promptDebounce[prompt] or {}
	local IDType = prompt:GetAttribute("IDType")
	local purchaseID = prompt:GetAttribute("PurchaseID")
	local priceDisplay = prompt:GetAttribute("Price") or nil
    createIndicator(prompt,priceDisplay)
	prompt.Triggered:Connect(function(player)
		if promptDebounce[prompt][player] then return end
		promptDebounce[prompt][player] = true
		local oldState = prompt.Enabled
		prompt.Enabled = false
		if IDType and purchaseID then
			promptPurchase:FireClient(player,IDType,purchaseID)
		else	
			handleInGamePurchase(prompt, player)
		end
		prompt.Enabled = oldState
		promptDebounce[prompt][player] = false
	end)
end
function Core.PurchaseHandler()
	local folder = workspace:FindFirstChild("MAP") 
		and workspace.MAP:FindFirstChild("Lobby") 
		and workspace.MAP.Lobby:FindFirstChild("Shop") 
		and workspace.MAP.Lobby.Shop:FindFirstChild("ShopItems")
	if folder then
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				connectPrompt(d)
			end
		end
		print("Module-based Shop System Ready.")
	end
end
return Core
