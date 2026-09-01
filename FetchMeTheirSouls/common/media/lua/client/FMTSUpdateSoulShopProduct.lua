require "FMTSShopData"

FMTS = FMTS or {}
FMTS.ShopRefresh = FMTS.ShopRefresh or {}

local ShopRefresh = FMTS.ShopRefresh

ShopRefresh.PRODUCTS_PER_POOL = 2
ShopRefresh.DISCOUNT_CHANCE_PERCENT = 20

-- Relative odds of each discount tier being picked once a discount is triggered.
-- Higher weight = more common. Add/remove/edit entries to change the odds directly.
ShopRefresh.DISCOUNT_WEIGHTS = {
    { percent = 5,  weight = 700 },
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

-- Refreshes at the witching hour instead of midnight.
ShopRefresh.REFRESH_HOUR = 3

-- Day key of the last refresh, so EveryHours only refreshes once per REFRESH_HOUR.
ShopRefresh.lastRefreshDayKey = nil


local function getDayKey()
    local gameTime = getGameTime()
    return gameTime:getYear() * 372 + gameTime:getMonth() * 31 + gameTime:getDay()
end


local function pickWeightedDiscountPercent()
    local tiers = ShopRefresh.DISCOUNT_WEIGHTS
    if not tiers or #tiers == 0 then return 0 end

    local totalWeight = 0
    for i = 1, #tiers do
        totalWeight = totalWeight + tiers[i].weight
    end

    local roll = ZombRand(totalWeight) + 1
    local cumulative = 0

    for i = 1, #tiers do
        cumulative = cumulative + tiers[i].weight
        if roll <= cumulative then
            return tiers[i].percent
        end
    end

    return tiers[1].percent
end


local function pickRandomProducts(pool, count)
    if not pool or #pool == 0 then return {} end

    local indices = {}
    for i = 1, #pool do indices[i] = i end

    -- Partial Fisher-Yates shuffle.
    for i = #indices, 2, -1 do
        local j = ZombRand(i) + 1
        indices[i], indices[j] = indices[j], indices[i]
    end

    local picked = {}
    local total = math.min(count, #indices)

    for i = 1, total do
        local source = pool[indices[i]]
        local entry = { item = source.item, rounds = source.rounds, cost = source.cost, type = source.type }

        if ZombRand(100) < ShopRefresh.DISCOUNT_CHANCE_PERCENT then
            local discountPercent = pickWeightedDiscountPercent()
            local discountedCost = math.max(1, math.floor(source.cost * (100 - discountPercent) / 100))

            entry.cost = discountedCost
            entry.discountPercent = discountPercent
            entry.discountAmount = source.cost - discountedCost
        end

        picked[i] = entry
    end

    return picked
end


-- Rebuilds the on-sale table from the full catalogs and refreshes any open shop window.
function ShopRefresh.RefreshProducts()
    local picked = {}

    for _, entry in ipairs(pickRandomProducts(FMTSShopData.ALL_AMMUNITION, ShopRefresh.PRODUCTS_PER_POOL)) do
        table.insert(picked, entry)
    end

    for _, entry in ipairs(pickRandomProducts(FMTSShopData.ALL_MAGAZINES, ShopRefresh.PRODUCTS_PER_POOL)) do
        table.insert(picked, entry)
    end

    for _, entry in ipairs(pickRandomProducts(FMTSShopData.ALL_TOOLS_WEAPONS, ShopRefresh.PRODUCTS_PER_POOL)) do
        table.insert(picked, entry)
    end

    FMTSShopData.PRODUCTS = picked

    if not FMTSShopWindow then return end

    FMTSShopWindow.PRODUCTS_SORTED = false

    local instance = FMTSShopWindow.instance
    if instance then
        instance.priceLayout = {}
        instance.populatedColumn = nil
        instance:sortProductList()
        instance:populateTable()
    end
end


function ShopRefresh.GetHoursUntilNextRefresh()
    local hour = getGameTime():getHour()
    local remaining = ShopRefresh.REFRESH_HOUR - hour

    if remaining <= 0 then remaining = remaining + 24 end
    return remaining
end


local function checkForDailyRefresh()
    if getGameTime():getHour() ~= ShopRefresh.REFRESH_HOUR then return end

    local currentKey = getDayKey()
    if ShopRefresh.lastRefreshDayKey == currentKey then return end

    ShopRefresh.lastRefreshDayKey = currentKey
    ShopRefresh.RefreshProducts()
end


local function initializeShopRefresh()
    ShopRefresh.lastRefreshDayKey = getDayKey()
    ShopRefresh.RefreshProducts()
end


Events.OnGameStart.Add(initializeShopRefresh)
Events.EveryHours.Add(checkForDailyRefresh)
