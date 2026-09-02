require "FMTSShared"
require "FMTSShopData"

FMTS.LastAttacker = FMTS.LastAttacker or {}

local SHOP_DATA_KEY_PREFIX = "FetchMeTheirSouls_ShopCatalog_"
local SHOP_REFRESH_HOUR = 3
local PRODUCTS_PER_POOL = 2
local MANUAL_REFRESH_COST = 50
local DISCOUNT_CHANCE_PERCENT = 20
local DISCOUNT_WEIGHTS = {
    { percent = 5, weight = 700 },
    { percent = 10, weight = 400 },
    { percent = 15, weight = 200 },
    { percent = 20, weight = 100 },
    { percent = 25, weight = 50 },
    { percent = 30, weight = 25 },
    { percent = 35, weight = 12 },
    { percent = 40, weight = 6 },
    { percent = 45, weight = 3 },
    { percent = 50, weight = 1 },
}

local function hasSoulPendantEquipped(player)
    if not player then
        return false
    end

    local wornItems = player:getWornItems()
    if not wornItems then
        return false
    end

    for index = 0, wornItems:size() - 1 do
        local wornItem = wornItems:get(index)
        if wornItem then
            local item = wornItem:getItem()
            if item and item:getFullType() == "FMTS.SoulPendant" then
                return true
            end
        end
    end

    return false
end

local function getDayKey()
    local gameTime = getGameTime()
    return gameTime:getYear() * 372 + gameTime:getMonth() * 31 + gameTime:getDay()
end

local function getHoursUntilNextRefresh()
    local remaining = SHOP_REFRESH_HOUR - getGameTime():getHour()
    if remaining <= 0 then remaining = remaining + 24 end
    return remaining
end

local function pickDiscountPercent()
    local totalWeight = 0
    for _, tier in ipairs(DISCOUNT_WEIGHTS) do
        totalWeight = totalWeight + tier.weight
    end

    local roll = ZombRand(totalWeight) + 1
    local cumulative = 0
    for _, tier in ipairs(DISCOUNT_WEIGHTS) do
        cumulative = cumulative + tier.weight
        if roll <= cumulative then return tier.percent end
    end

    return DISCOUNT_WEIGHTS[1].percent
end

local function pickProducts(pool)
    local indices = {}
    for index = 1, #pool do indices[index] = index end

    for index = #indices, 2, -1 do
        local swapIndex = ZombRand(index) + 1
        indices[index], indices[swapIndex] = indices[swapIndex], indices[index]
    end

    local products = {}
    for index = 1, math.min(PRODUCTS_PER_POOL, #indices) do
        local source = pool[indices[index]]
        local product = { item = source.item, rounds = source.rounds, cost = source.cost, type = source.type }

        if ZombRand(100) < DISCOUNT_CHANCE_PERCENT then
            product.discountPercent = pickDiscountPercent()
            product.cost = math.max(1, math.floor(source.cost * (100 - product.discountPercent) / 100))
            product.discountAmount = source.cost - product.cost
        end

        table.insert(products, product)
    end

    return products
end

local function getShopDataKey(player)
    if not player then return nil end

    local onlineId = player:getOnlineID()
    if onlineId and onlineId >= 0 then
        return SHOP_DATA_KEY_PREFIX .. tostring(onlineId)
    end

    local username = player:getUsername()
    return username and SHOP_DATA_KEY_PREFIX .. username or nil
end

local function refreshShopCatalog(player)
    local products = {}
    for _, pool in ipairs({ FMTSShopData.ALL_AMMUNITION, FMTSShopData.ALL_MAGAZINES, FMTSShopData.ALL_TOOLS_WEAPONS }) do
        for _, product in ipairs(pickProducts(pool)) do
            product.id = #products + 1
            table.insert(products, product)
        end
    end

    local shopDataKey = getShopDataKey(player)
    if not shopDataKey then return nil end

    local shopData = ModData.getOrCreate(shopDataKey)
    shopData.products = products
    shopData.lastRefreshDayKey = getDayKey()
    ModData.transmit(shopDataKey)
    return shopData
end

local function getShopCatalog(player)
    local shopDataKey = getShopDataKey(player)
    if not shopDataKey then return nil end

    local shopData = ModData.getOrCreate(shopDataKey)
    if not shopData.products or #shopData.products == 0 then
        shopData = refreshShopCatalog(player)
    end
    return shopData
end

local function sendShopCatalog(player)
    local shopData = getShopCatalog(player)
    if not shopData then return end

    sendServerCommand(player, "FMTS", "ShopCatalog", {
        products = shopData.products,
        hoursUntilRefresh = getHoursUntilNextRefresh(),
        soulCount = FMTS.GetSoulCount(player),
    })
end

local function findProduct(player, productId)
    local shopData = getShopCatalog(player)
    if not shopData then return nil end

    for _, product in ipairs(shopData.products) do
        if product.id == productId then return product end
    end
    return nil
end

local function onWeaponHitCharacter(attacker, target, weapon, damage)
    if not attacker or not target then
        return
    end

    if instanceof(attacker, "IsoPlayer")
        and instanceof(target, "IsoZombie") then

        FMTS.LastAttacker[target] = attacker
    end
end

local function onZombieDead(zombie)
    if not zombie then
        return
    end

    local killer = FMTS.LastAttacker[zombie]

    if killer and instanceof(killer, "IsoPlayer") and hasSoulPendantEquipped(killer) then
        FMTS.AddSouls(killer, 1)
    end

    FMTS.LastAttacker[zombie] = nil
end

local function handleBuyItem(player, args)
    if not player then
        return
    end

    local product = findProduct(player, tonumber(args and args.offeringId))
    if not product then
        sendServerCommand(player, "FMTS", "BuyItemResult", {
            ok = false,
            item = nil,
            soulCount = FMTS.GetSoulCount(player),
        })
        return
    end

    if not hasSoulPendantEquipped(player) then
        sendServerCommand(player, "FMTS", "BuyItemResult", {
            ok = false,
            item = product.item,
            soulCount = FMTS.GetSoulCount(player),
        })
        return
    end

    if FMTS.GetSoulCount(player) < product.cost then
        sendServerCommand(player, "FMTS", "BuyItemResult", {
            ok = false,
            item = product.item,
            soulCount = FMTS.GetSoulCount(player),
        })
        return
    end

    if not FMTS.RemoveSouls(player, product.cost) then
        sendServerCommand(player, "FMTS", "BuyItemResult", {
            ok = false,
            item = product.item,
            soulCount = FMTS.GetSoulCount(player),
        })
        return
    end

    player:getInventory():AddItem(product.item)
    sendServerCommand(player, "FMTS", "BuyItemResult", {
        ok = true,
        item = product.item,
        spent = product.cost,
        soulCount = FMTS.GetSoulCount(player),
    })
end

local function handleRefreshShop(player, args)
    if not player then
        return
    end

    if not hasSoulPendantEquipped(player) then
        sendServerCommand(player, "FMTS", "RefreshShopResult", {
            ok = false,
            soulCount = FMTS.GetSoulCount(player),
        })
        return
    end

    if FMTS.GetSoulCount(player) < MANUAL_REFRESH_COST then
        sendServerCommand(player, "FMTS", "RefreshShopResult", {
            ok = false,
            soulCount = FMTS.GetSoulCount(player),
        })
        return
    end

    if not FMTS.RemoveSouls(player, MANUAL_REFRESH_COST) then
        sendServerCommand(player, "FMTS", "RefreshShopResult", {
            ok = false,
            soulCount = FMTS.GetSoulCount(player),
        })
        return
    end

    refreshShopCatalog(player)
    sendServerCommand(player, "FMTS", "RefreshShopResult", {
        ok = true,
        spent = MANUAL_REFRESH_COST,
        soulCount = FMTS.GetSoulCount(player),
    })
    sendShopCatalog(player)
end

local function checkForDailyRefresh()
    if getGameTime():getHour() < SHOP_REFRESH_HOUR then return end

    local players = getOnlinePlayers()
    if not players then return end

    for index = 0, players:size() - 1 do
        local player = players:get(index)
        local shopData = getShopCatalog(player)
        if shopData and shopData.lastRefreshDayKey ~= getDayKey() then
            refreshShopCatalog(player)
            sendShopCatalog(player)
        end
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= "FMTS" then
        return
    end

    if command == "BuyItem" then
        handleBuyItem(player, args)
        return
    end

    if command == "RefreshShop" then
        handleRefreshShop(player, args)
        return
    end

    if command == "RequestShopCatalog" then
        sendShopCatalog(player)
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
Events.OnZombieDead.Add(onZombieDead)
Events.EveryHours.Add(checkForDailyRefresh)
