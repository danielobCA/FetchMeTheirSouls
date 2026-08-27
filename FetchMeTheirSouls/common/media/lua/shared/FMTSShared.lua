FMTS = FMTS or {}

FMTS.SOUL_ITEM = "FMTS.Soul"

local function getWornSoulPendant(player)
    local wornItems = player:getWornItems()

    for index = 0, wornItems:size() - 1 do
        local wornItem = wornItems:get(index):getItem()

        if wornItem and wornItem:getFullType() == "FMTS.SoulPendant" then
            return wornItem
        end
    end

    return nil
end

local function getWornSoulPendantContainer(player)
    local pendant = getWornSoulPendant(player)
    return pendant and pendant:getItemContainer() or nil
end

function FMTS.RefreshSoulPendantName(player)
    if not player then
        return
    end

    local pendant = getWornSoulPendant(player)
    local container = pendant and pendant:getItemContainer()

    if not pendant or not container then
        return
    end

    local count = container:getItemCount(FMTS.SOUL_ITEM)
    local suffix = count == 1 and " Soul" or " Souls"
    local name = "Soul Pendant (" .. tostring(count) .. suffix .. ")"

    if pendant:getName() ~= name then
        pendant:setName(name)
    end
end

function FMTS.GetSoulCount(player)
    if not player then
        return 0
    end

    local count = player:getInventory():getItemCount(FMTS.SOUL_ITEM)
    local pendantContainer = getWornSoulPendantContainer(player)

    if pendantContainer then
        count = count + pendantContainer:getItemCount(FMTS.SOUL_ITEM)
    end

    return count
end

function FMTS.AddSouls(player, amount)
    if not player or amount <= 0 then
        return
    end

    local container = getWornSoulPendantContainer(player)

    if not container then
        return
    end

    for i = 1, amount do
        container:AddItem(FMTS.SOUL_ITEM)
    end

    FMTS.RefreshSoulPendantName(player)
end

function FMTS.RemoveSouls(player, amount)
    if not player or amount <= 0 then
        return false
    end

    local inventory = player:getInventory()
    local pendantContainer = getWornSoulPendantContainer(player)
    local total = inventory:getItemCount(FMTS.SOUL_ITEM)

    if pendantContainer then
        total = total + pendantContainer:getItemCount(FMTS.SOUL_ITEM)
    end

    if total < amount then
        return false
    end

    local removed = 0

    while removed < amount and inventory:getItemCount(FMTS.SOUL_ITEM) > 0 do
        local soul = inventory:FindAndReturn(
            FMTS.SOUL_ITEM
        )

        if not soul then
            return false
        end

        inventory:Remove(soul)
        removed = removed + 1
    end

    while removed < amount and pendantContainer do
        local soul = pendantContainer:FindAndReturn(FMTS.SOUL_ITEM)

        if not soul then
            break
        end

        pendantContainer:Remove(soul)
        removed = removed + 1
    end

    if removed == amount then
        FMTS.RefreshSoulPendantName(player)
        return true
    end

    return false
end