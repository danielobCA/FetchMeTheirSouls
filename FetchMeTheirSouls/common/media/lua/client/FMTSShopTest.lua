require "FMTSShopWindow"

local function openTestShop(player)
    FMTSShopWindow.Open(player)
end

local function hasSoulPendantEquipped(player)
    local wornItems = player:getWornItems()

    for index = 0, wornItems:size() - 1 do
        local item = wornItems:get(index):getItem()

        if item and item:getFullType() == "FMTS.SoulPendant" then
            return true
        end
    end

    return false
end

local SHOP_TILE_SCRIPT_PREFIX = "Moveables.location_community_cemetary_01_"
local SHOP_TILE_SPRITE_PREFIX = "location_community_cemetary_01_"

local function isShopScript(worldObject)
    local itemName = worldObject.getItemName and worldObject:getItemName()

    if itemName and string.sub(itemName, 1, #SHOP_TILE_SCRIPT_PREFIX) == SHOP_TILE_SCRIPT_PREFIX then
        return true
    end

    local spriteName = worldObject.getSpriteName and worldObject:getSpriteName()

    if not spriteName then
        local sprite = worldObject:getSprite()
        spriteName = sprite and sprite:getName()
    end

    return spriteName
        and string.sub(spriteName, 1, #SHOP_TILE_SPRITE_PREFIX) == SHOP_TILE_SPRITE_PREFIX
end

local function isShopObject(worldObject)
    return isShopScript(worldObject)
end

local function isShopTile(worldObjects)
    for _, worldObject in ipairs(worldObjects) do
        if isShopObject(worldObject) then
                return true
        end

        local square = worldObject:getSquare()
        local squareObjects = square and square:getObjects()

        if squareObjects then
            for index = 0, squareObjects:size() - 1 do
                if isShopObject(squareObjects:get(index)) then
                    return true
                end
            end
        end
    end

    return false
end

local function addShopTestOption(playerNum, context, worldObjects)
    local player = getSpecificPlayer(playerNum)

    if not player then
        return
    end

    if not isShopTile(worldObjects) then
        return
    end

    local option = context:addOption(
        "Open Soul Shop",
        player,
        openTestShop
    )

    if not hasSoulPendantEquipped(player) then
        option.notAvailable = true

        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = "You must be wearing a Soul Pendant."
        option.toolTip = tooltip
    end
end

Events.OnFillWorldObjectContextMenu.Add(addShopTestOption)