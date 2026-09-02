require "ISUI/ISPanel"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "FMTSShopData"
require "FMTSUpdateSoulShopProduct"


FMTSShopWindow = ISCollapsableWindow:derive("FMTSShopWindow")
FMTSShopWindow.instance = nil


FMTSShopWindow.SOUL_REFRESH_INTERVAL = 30
FMTSShopWindow.FEEDBACK_DURATION = 8
FMTSShopWindow.MIN_WIDTH = 630
FMTSShopWindow.MIN_HEIGHT = 575
FMTSShopWindow.ROW_HEIGHT = 70
FMTSShopWindow.HEADER_HEIGHT = 28
FMTSShopWindow.ICON_SIZE = 32
FMTSShopWindow.FOOTER_HEIGHT = 56
FMTSShopWindow.FOOTER_BOTTOM_PADDING = 20
FMTSShopWindow.CONTROL_HEIGHT = 28
FMTSShopWindow.PRICE_ICON_SIZE = 18
FMTSShopWindow.BUY_COLUMN_WIDTH = 100
FMTSShopWindow.COST_COLUMN_WIDTH = 80
FMTSShopWindow.TYPE_COLUMN_WIDTH = 100
FMTSShopWindow.BYPASS_SOUL_REQUIREMENT = false
FMTSShopWindow.MANUAL_REFRESH_COST = 50
FMTSShopWindow.PURCHASE_SOUND = "FMTS_SoulPurchase"
FMTSShopWindow.REFRESH_SOUND = "FMTS_SoulRefresh"


FMTSShopWindow.CONTENT_MARGIN = 10
FMTSShopWindow.TOP_ROW_Y = 28
FMTSShopWindow.HEADER_Y = 68
FMTSShopWindow.TABLE_Y = 96
FMTSShopWindow.DIVIDER_COLOR = { r = 1, g = 1, b = 0.2, a = .1 }


-- Fine-tune offsets (in pixels) for visual alignment.
-- Negative values shift left, positive values shift right.
FMTSShopWindow.ICON_X_OFFSET = -4
FMTSShopWindow.BUY_X_OFFSET = -10


-- Sort indicator glyphs appended to whichever header is active.
-- Kept ASCII-safe (^ / v) since symbol glyphs like arrows aren't
-- guaranteed to exist in Zomboid's UI fonts and render as "?".
FMTSShopWindow.SORT_ASC_GLYPH = " ^"
FMTSShopWindow.SORT_DESC_GLYPH = " v"


-- Info popup copy, shown via the vanilla ISCollapsableWindow info
-- icon/button (same icon + title-bar position as the Health panel).
FMTSShopWindow.INFO_TEXT =
    "Welcome to Soul Offerings.\n" ..
    "\n" ..
    "Trade the Souls you have collected for ammunition and magazines. " ..
    "The Type column shows whether an offering is Ammunition or a Magazine.\n" ..
    "\n" ..
    "Select a column header to sort the offerings by item, type, or cost. " ..
    "Choose Buy to claim an offering. The required Souls will be " ..
    "deducted immediately, provided you have enough to pay for it."


-- Sort state. Shop catalog data itself lives in FMTSShopData.lua; this
-- file only tracks whether the list has been sorted under the CURRENT
-- column+direction.
FMTSShopWindow.PRODUCTS_SORTED = false


-- Sort preference. Kept at class level (not per-instance) so it
-- persists across window close/reopen within the same session.
FMTSShopWindow.sortColumn = "cost"
FMTSShopWindow.sortAscending = true


function FMTSShopWindow:new(x, y, width, height, player, statue)
    local window = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(window, self)
    self.__index = self

    window.player = player
    window.title = "Soul Offerings"
    window.resizable = false
    window.minimumWidth = FMTSShopWindow.MIN_WIDTH
    window.minimumHeight = FMTSShopWindow.MIN_HEIGHT

    window.lastSoulCount = -1
    window.refreshCounter = 0
    window.feedback = {}
    window.pendingAction = nil

    window.itemTextures = {}
    window.itemInfo = {}
    window.itemNames = {}
    window.priceLayout = {}
    window.columns = nil

    window.populatedColumn = nil
    window.populatedAscending = nil

    return window
end


function FMTSShopWindow:initialise()
    ISCollapsableWindow.initialise(self)
end


function FMTSShopWindow:createLabel(x, y, width, height, text, font)
    local label = ISLabel:new(x, y, height, text, 1, 1, 1, 1, font or UIFont.Small, true)
    label:initialise()
    label:setWidth(width)
    self:addChild(label)
    return label
end


function FMTSShopWindow:getItemScript(fullType)
    return getScriptManager():FindItem(fullType)
end


function FMTSShopWindow:getItemTexture(fullType)
    if self.itemTextures[fullType] ~= nil then return self.itemTextures[fullType] or nil end

    local scriptItem = self:getItemScript(fullType)
    if not scriptItem then
        self.itemTextures[fullType] = false
        return nil
    end

    local normalTexture = scriptItem:getNormalTexture()
    if not normalTexture then
        self.itemTextures[fullType] = false
        return nil
    end

    local textureName = normalTexture:getName()
    local texture = textureName and getTexture(textureName) or nil

    self.itemTextures[fullType] = texture or false
    return texture
end


-- Resolves and caches display names from item scripts instead of
-- requiring hand-written names in FMTSShopData.lua.
function FMTSShopWindow:getItemName(fullType)
    local cached = self.itemNames[fullType]
    if cached then return cached end

    local scriptItem = self:getItemScript(fullType)
    local name = fullType

    if scriptItem and scriptItem.getDisplayName then
        local displayName = scriptItem:getDisplayName()
        if displayName and displayName ~= "" then name = displayName end
    end

    self.itemNames[fullType] = name
    return name
end


-- Ammo boxes use entry.rounds from FMTSShopData.
-- Magazine capacities are read from safe ItemScript getters.
-- No temporary InventoryItem is created here.
function FMTSShopWindow:getItemInfo(entry)
    local cached = self.itemInfo[entry.item]
    if cached then return cached end

    local scriptItem = self:getItemScript(entry.item)
    local info = {
        rounds = entry.rounds,
        capacity = nil,
        encumbrance = 0,
        ammoName = nil,
    }

    if scriptItem then
        if scriptItem.getCapacity then
            local capacity = tonumber(scriptItem:getCapacity())
            if capacity and capacity > 0 then
                info.capacity = capacity
            end
        end

        if not info.capacity and scriptItem.getMaxAmmo then
            local maxAmmo = tonumber(scriptItem:getMaxAmmo())
            if maxAmmo and maxAmmo > 0 then
                info.capacity = maxAmmo
            end
        end

        if scriptItem.getActualWeight then
            info.encumbrance = tonumber(scriptItem:getActualWeight()) or 0
        elseif scriptItem.getWeight then
            info.encumbrance = tonumber(scriptItem:getWeight()) or 0
        end
    end

    if entry.ammo then
        info.ammoName = self:getItemName(entry.ammo)
    end

    self.itemInfo[entry.item] = info
    return info
end


function FMTSShopWindow:formatNumber(value)
    if value == math.floor(value) then return tostring(math.floor(value)) end
    return string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
end


function FMTSShopWindow:getColumns()
    if self.columns then return self.columns end

    local left = FMTSShopWindow.CONTENT_MARGIN
    local right = self.width - FMTSShopWindow.CONTENT_MARGIN
    local iconCellWidth = 45
    local buyDivider = right - FMTSShopWindow.BUY_COLUMN_WIDTH
    local costDivider = buyDivider - FMTSShopWindow.COST_COLUMN_WIDTH
    local typeDivider = costDivider - FMTSShopWindow.TYPE_COLUMN_WIDTH

    self.columns = {
        left = left,
        right = right,
        iconDivider = left + iconCellWidth,
        typeDivider = typeDivider,
        costDivider = costDivider,
        buyDivider = buyDivider,
        itemX = left + iconCellWidth + 10,
        typeX = typeDivider + 10,
        costX = costDivider + math.floor((FMTSShopWindow.COST_COLUMN_WIDTH - FMTSShopWindow.PRICE_ICON_SIZE - 25) / 2),
        buyX = buyDivider + math.floor((FMTSShopWindow.BUY_COLUMN_WIDTH - 28) / 2) + FMTSShopWindow.BUY_X_OFFSET,
        iconX = left + math.floor((iconCellWidth - FMTSShopWindow.ICON_SIZE) / 2) + FMTSShopWindow.ICON_X_OFFSET,
    }

    return self.columns
end


function FMTSShopWindow:invalidateColumns()
    self.columns = nil
    self.priceLayout = {}
end


function FMTSShopWindow:getPriceLayout(entry)
    local cached = self.priceLayout[entry.item]
    if cached then return cached end

    local columns = self:getColumns()
    local priceIconSize = FMTSShopWindow.PRICE_ICON_SIZE
    local priceWidth = priceIconSize + 5 + getTextManager():MeasureStringX(UIFont.Small, tostring(entry.cost))
    local priceX = columns.costDivider + math.floor((FMTSShopWindow.COST_COLUMN_WIDTH - priceWidth) / 2)

    local layout = { priceX = priceX }
    self.priceLayout[entry.item] = layout
    return layout
end


function FMTSShopWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setInfo(FMTSShopWindow.INFO_TEXT)

    self:createNextUpdateLabel()
    self:createTableHeader()
    self:createTable()
    self:createFooter()

    self:sortProductList()
    self:populateTable()
    self:refreshSoulCount()
end


function FMTSShopWindow:createNextUpdateLabel()
    self.nextUpdateLabel = ISLabel:new(FMTSShopWindow.CONTENT_MARGIN, 0, 20, "", 0.85, 0.85, 0.85, 1, UIFont.Small, true)
    self.nextUpdateLabel:initialise()
    self.nextUpdateLabel:setAnchorLeft(true)
    self.nextUpdateLabel:setAnchorRight(false)
    self.nextUpdateLabel:setAnchorTop(false)
    self.nextUpdateLabel:setAnchorBottom(true)
    self:addChild(self.nextUpdateLabel)
    self:updateNextUpdateLabel()
end


function FMTSShopWindow:updateNextUpdateLabel()
    if not self.nextUpdateLabel or not FMTS.ShopRefresh then return end

    local hours = math.ceil(FMTS.ShopRefresh.GetHoursUntilNextRefresh())
    local suffix = hours == 1 and " hour" or " hours"

    self.nextUpdateLabel.name = "New offerings in " .. tostring(hours) .. suffix
    self.nextUpdateLabel:setWidthToName(1)
end


function FMTSShopWindow:createTableHeader()
    self.headerPanel = ISPanel:new(FMTSShopWindow.CONTENT_MARGIN, FMTSShopWindow.HEADER_Y, self.width - (FMTSShopWindow.CONTENT_MARGIN * 2), FMTSShopWindow.HEADER_HEIGHT)
    self.headerPanel:initialise()
    self.headerPanel:setAnchorRight(true)
    self.headerPanel.backgroundColor = { r = 0.10, g = 0.10, b = 0.10, a = 1.0 }
    self.headerPanel.borderColor = { r = 0.55, g = 0.55, b = 0.55, a = 1.0 }
    self.headerPanel.drawBorder = true
    self:addChild(self.headerPanel)

    self.headerItem = self:createLabel(70, FMTSShopWindow.HEADER_Y + 5, 300, 20, "Item")
    self.headerType = self:createLabel(380, FMTSShopWindow.HEADER_Y + 5, 90, 20, "Type")
    self.headerCost = self:createLabel(500, FMTSShopWindow.HEADER_Y + 5, 105, 20, "Cost")
    self.headerBuy = self:createLabel(605, FMTSShopWindow.HEADER_Y + 5, 90, 20, "")

    self.costHeaderButton = ISButton:new(0, 0, 1, 1, "", self, FMTSShopWindow.onCostHeaderClick)
    self.costHeaderButton:initialise()
    self.costHeaderButton.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.costHeaderButton.backgroundColorMouseOver = { r = 0.35, g = 0.35, b = 0.35, a = 0.25 }
    self.costHeaderButton.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(self.costHeaderButton)

    self.typeHeaderButton = ISButton:new(0, 0, 1, 1, "", self, FMTSShopWindow.onTypeHeaderClick)
    self.typeHeaderButton:initialise()
    self.typeHeaderButton.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.typeHeaderButton.backgroundColorMouseOver = { r = 0.35, g = 0.35, b = 0.35, a = 0.25 }
    self.typeHeaderButton.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(self.typeHeaderButton)

    self.itemHeaderButton = ISButton:new(0, 0, 1, 1, "", self, FMTSShopWindow.onItemHeaderClick)
    self.itemHeaderButton:initialise()
    self.itemHeaderButton.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.itemHeaderButton.backgroundColorMouseOver = { r = 0.35, g = 0.35, b = 0.35, a = 0.25 }
    self.itemHeaderButton.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(self.itemHeaderButton)

    self:layoutColumns()
    self:updateSortHeaders()
end


function FMTSShopWindow:layoutColumns()
    self:invalidateColumns()
    local columns = self:getColumns()

    if self.headerBuy then self.headerBuy:setX(columns.buyX) end

    if self.costHeaderButton then
        self.costHeaderButton:setX(columns.costDivider)
        self.costHeaderButton:setY(FMTSShopWindow.HEADER_Y)
        self.costHeaderButton:setWidth(columns.buyDivider - columns.costDivider)
        self.costHeaderButton:setHeight(FMTSShopWindow.HEADER_HEIGHT)
    end

    if self.typeHeaderButton then
        self.typeHeaderButton:setX(columns.typeDivider)
        self.typeHeaderButton:setY(FMTSShopWindow.HEADER_Y)
        self.typeHeaderButton:setWidth(columns.costDivider - columns.typeDivider)
        self.typeHeaderButton:setHeight(FMTSShopWindow.HEADER_HEIGHT)
    end

    if self.itemHeaderButton then
        self.itemHeaderButton:setX(columns.iconDivider)
        self.itemHeaderButton:setY(FMTSShopWindow.HEADER_Y)
        self.itemHeaderButton:setWidth(columns.typeDivider - columns.iconDivider)
        self.itemHeaderButton:setHeight(FMTSShopWindow.HEADER_HEIGHT)
    end

    self:updateSortHeaders()
end


function FMTSShopWindow:updateSortHeaders()
    if not self.headerItem or not self.headerType or not self.headerCost then return end

    local glyph = FMTSShopWindow.sortAscending and FMTSShopWindow.SORT_ASC_GLYPH or FMTSShopWindow.SORT_DESC_GLYPH
    local itemText = "Item"
    local typeText = "Type"
    local costText = "Cost"

    if FMTSShopWindow.sortColumn == "name" then
        itemText = itemText .. glyph
    elseif FMTSShopWindow.sortColumn == "type" then
        typeText = typeText .. glyph
    else
        costText = costText .. glyph
    end

    self.headerItem.name = itemText
    self.headerType.name = typeText
    self.headerCost.name = costText
    self.headerItem:setWidthToName(1)
    self.headerType:setWidthToName(1)
    self.headerCost:setWidthToName(1)

    local columns = self:getColumns()
    local itemColWidth = columns.typeDivider - columns.iconDivider
    local typeColWidth = columns.costDivider - columns.typeDivider
    local costColWidth = columns.buyDivider - columns.costDivider

    self.headerItem:setX(columns.iconDivider + math.floor((itemColWidth - self.headerItem.width) / 2))
    self.headerType:setX(columns.typeDivider + math.floor((typeColWidth - self.headerType.width) / 2))
    self.headerCost:setX(columns.costDivider + math.floor((costColWidth - self.headerCost.width) / 2))
end


function FMTSShopWindow:createTable()
    self.table = ISScrollingListBox:new(FMTSShopWindow.CONTENT_MARGIN, FMTSShopWindow.TABLE_Y, self.width - (FMTSShopWindow.CONTENT_MARGIN * 2), self.height - FMTSShopWindow.TABLE_Y - FMTSShopWindow.FOOTER_HEIGHT)
    self.table:initialise()
    self.table:setAnchorRight(true)
    self.table:setAnchorBottom(true)
    self.table:setAnchorLeft(true)
    self.table:setAnchorTop(true)
    self.table.backgroundColor = { r = 0.02, g = 0.02, b = 0.02, a = 0.88 }
    self.table.borderColor = { r = 0.55, g = 0.55, b = 0.55, a = 1.0 }
    self.table.drawBorder = true
    self.table.drawSelection = false
    self.table.itemheight = FMTSShopWindow.ROW_HEIGHT
    self.table.doDrawItem = FMTSShopWindow.drawTableRow
    self.table.onMouseDown = FMTSShopWindow.onTableMouseDown
    self.table.target = self
    self:addChild(self.table)
end


function FMTSShopWindow:layoutFooter()
    local footerY = self.height - FMTSShopWindow.FOOTER_HEIGHT
    local controlsY = self.height - FMTSShopWindow.FOOTER_BOTTOM_PADDING - FMTSShopWindow.CONTROL_HEIGHT

    if self.nextUpdateLabel then
        self.nextUpdateLabel:setX(FMTSShopWindow.CONTENT_MARGIN)
        self.nextUpdateLabel:setY(controlsY)
    end

    if self.closeButton then
        self.closeButton:setX(self.width - FMTSShopWindow.CONTENT_MARGIN - self.closeButton.width)
        self.closeButton:setY(controlsY)
    end

    if self.refreshShopButton then
        self.refreshShopButton:setX(self.width - (FMTSShopWindow.CONTENT_MARGIN * 2) - self.closeButton.width - self.refreshShopButton.width)
        self.refreshShopButton:setY(controlsY)
    end
end


function FMTSShopWindow:createFooter()
    local height = FMTSShopWindow.CONTROL_HEIGHT
    local iconSize = 20
    local padding = 10
    local gap = 8

    self.soulPanel = ISPanel:new(0, FMTSShopWindow.TOP_ROW_Y, 150, height)
    self.soulPanel:initialise()
    self.soulPanel:setAnchorLeft(false)
    self.soulPanel:setAnchorRight(true)
    self.soulPanel:setAnchorTop(true)
    self.soulPanel:setAnchorBottom(false)
    self.soulPanel.backgroundColor = { r = 0.02, g = 0.02, b = 0.02, a = 0.92 }
    self.soulPanel.borderColor = { r = 0.35, g = 0.35, b = 0.35, a = 1.0 }
    self.soulPanel.drawBorder = true
    self.soulPanel.height = height
    self.soulPanel.iconSize = iconSize
    self.soulPanel.padding = padding
    self.soulPanel.gap = gap
    self.soulPanel.soulTexture = self:getItemTexture(FMTS.SOUL_ITEM)
    self.soulPanel.soulCount = 0
    self.soulPanel.render = FMTSShopWindow.drawSoulPanel
    self:addChild(self.soulPanel)

    self.closeButton = ISButton:new(0, 0, 90, 28, "Close", self, FMTSShopWindow.onCloseButton)
    self.closeButton:initialise()
    self.closeButton:setAnchorLeft(false)
    self.closeButton:setAnchorRight(true)
    self.closeButton:setAnchorTop(false)
    self.closeButton:setAnchorBottom(true)
    self.closeButton.backgroundColor = { r = 0.45, g = 0.05, b = 0.05, a = 1.0 }
    self.closeButton.backgroundColorMouseOver = { r = 0.70, g = 0.08, b = 0.08, a = 1.0 }
    self.closeButton.borderColor = { r = 0.75, g = 0.20, b = 0.20, a = 1.0 }
    self:addChild(self.closeButton)

    local refreshButtonLabel = "Refresh (" .. tostring(FMTSShopWindow.MANUAL_REFRESH_COST) .. " Souls)"
    local refreshButtonWidth = getTextManager():MeasureStringX(UIFont.Small, refreshButtonLabel) + 20

    self.refreshShopButton = ISButton:new(0, 0, refreshButtonWidth, 28, refreshButtonLabel, self, FMTSShopWindow.onRefreshShopButton)
    self.refreshShopButton:initialise()
    self.refreshShopButton:setAnchorLeft(false)
    self.refreshShopButton:setAnchorRight(true)
    self.refreshShopButton:setAnchorTop(false)
    self.refreshShopButton:setAnchorBottom(true)
    self:addChild(self.refreshShopButton)

    self:updateSoulPanel()
    self:layoutFooter()
end


function FMTSShopWindow:drawSoulPanel()
    ISPanel.render(self)

    local text = "Souls: " .. tostring(self.soulCount)
    local textWidth = getTextManager():MeasureStringX(UIFont.Small, text)
    local textHeight = getTextManager():MeasureStringY(UIFont.Small, text)
    local contentWidth = self.iconSize + self.gap + textWidth
    local startX = math.floor((self.width - contentWidth) / 2)
    local iconY = math.floor((self.height - self.iconSize) / 2)
    local textY = math.floor((self.height - textHeight) / 2)

    if self.soulTexture then
        self:drawTextureScaled(self.soulTexture, startX, iconY, self.iconSize, self.iconSize, 1.0)
    end

    self:drawText(text, startX + self.iconSize + self.gap, textY, 1, 1, 1, 1, UIFont.Small)
end


function FMTSShopWindow:updateSoulPanel()
    if not self.soulPanel then return end

    local souls = self:getSoulCount()
    self.soulPanel.soulCount = souls

    local text = "Souls: " .. tostring(souls)
    local textWidth = getTextManager():MeasureStringX(UIFont.Small, text)
    local contentWidth = self.soulPanel.padding * 2 + self.soulPanel.iconSize + self.soulPanel.gap + textWidth
    local width = math.max(150, contentWidth)

    self.soulPanel:setWidth(width)
    self.soulPanel:setX(self.width - FMTSShopWindow.CONTENT_MARGIN - width)
end


function FMTSShopWindow:sortProductList()
    if FMTSShopWindow.PRODUCTS_SORTED then return end

    local list = FMTSShopData.PRODUCTS
    local ascending = FMTSShopWindow.sortAscending
    local target = self

    if FMTSShopWindow.sortColumn == "name" then
        table.sort(list, function(a, b)
            local nameA = target:getItemName(a.item)
            local nameB = target:getItemName(b.item)

            if nameA == nameB then return a.cost < b.cost end
            if ascending then return nameA < nameB end
            return nameA > nameB
        end)
    elseif FMTSShopWindow.sortColumn == "type" then
        table.sort(list, function(a, b)
            if a.type == b.type then
                return target:getItemName(a.item) < target:getItemName(b.item)
            end

            if ascending then return a.type < b.type end
            return a.type > b.type
        end)
    else
        table.sort(list, function(a, b)
            if a.cost == b.cost then
                return target:getItemName(a.item) < target:getItemName(b.item)
            end

            if ascending then return a.cost < b.cost end
            return a.cost > b.cost
        end)
    end

    FMTSShopWindow.PRODUCTS_SORTED = true
end


function FMTSShopWindow:setSortColumn(column)
    if FMTSShopWindow.sortColumn == column then
        FMTSShopWindow.sortAscending = not FMTSShopWindow.sortAscending
    else
        FMTSShopWindow.sortColumn = column
        FMTSShopWindow.sortAscending = true
    end

    FMTSShopWindow.PRODUCTS_SORTED = false

    self:updateSortHeaders()
    self:sortProductList()
    self:populateTable()
end


function FMTSShopWindow:onCostHeaderClick()
    self:setSortColumn("cost")
end


function FMTSShopWindow:onItemHeaderClick()
    self:setSortColumn("name")
end


function FMTSShopWindow:onTypeHeaderClick()
    self:setSortColumn("type")
end


function FMTSShopWindow:populateTable()
    if not self.table then return end

    if self.populatedColumn == FMTSShopWindow.sortColumn
        and self.populatedAscending == FMTSShopWindow.sortAscending then
        return
    end

    self.table:clear()

    for _, entry in ipairs(FMTSShopData.PRODUCTS) do
        local row = self.table:addItem(self:getItemName(entry.item), entry)
        row.height = FMTSShopWindow.ROW_HEIGHT
    end

    self.populatedColumn = FMTSShopWindow.sortColumn
    self.populatedAscending = FMTSShopWindow.sortAscending
end


function FMTSShopWindow:isBuyHovered(rowY, mouseX, mouseY, columns)
    return mouseX >= columns.buyDivider
        and mouseX <= self.table.width
        and mouseY >= rowY
        and mouseY <= rowY + FMTSShopWindow.ROW_HEIGHT
end


function FMTSShopWindow:getBuyColor(entry, hovering)
    local feedback = self.feedback[entry.item]

    if feedback and feedback.frames > 0 then return 0.20, 1.00, 0.20 end
    if not FMTSShopWindow.BYPASS_SOUL_REQUIREMENT and self.lastSoulCount < entry.cost then
        return 0.85, 0.20, 0.20
    end
    if hovering then return 0.72, 0.72, 0.72 end

    return 1.00, 1.00, 1.00
end


-- Each row has:
-- Item name
-- X Rounds (ammo-box quantity or magazine capacity)
-- Encumbrance
function FMTSShopWindow:drawTableRow(y, item, alt)
    local row = item.item
    local list = self
    local target = list.target
    local rowHeight = FMTSShopWindow.ROW_HEIGHT
    local width = list.width
    local iconSize = FMTSShopWindow.ICON_SIZE
    local priceIconSize = FMTSShopWindow.PRICE_ICON_SIZE
    local info = target:getItemInfo(row)
    local columns = target:getColumns()
    local priceLayout = target:getPriceLayout(row)
    local mouseX = list:getMouseX()
    local mouseY = list:getMouseY()
    local displayName = target:getItemName(row.item)

    if row.discountPercent and row.discountPercent > 0 then
        -- Uniform subtle gold highlight for all discounted offerings (alpha, r, g, b)
        list:drawRect(0, y, width, rowHeight, 0.08, 0.85, 0.70, 0.20)
    elseif alt then
        list:drawRect(0, y, width, rowHeight, 0.20, 0.12, 0.12, 0.12)
    end

    if mouseY >= y and mouseY <= y + rowHeight then
        -- Subtle brightness boost on hover (alpha, r, g, b)
        list:drawRect(0, y, width, rowHeight, 0.08, 1.0, 1.0, 1.0)
    end

    list:drawRect(0, y + rowHeight - 1, width, 1, FMTSShopWindow.DIVIDER_COLOR.a, FMTSShopWindow.DIVIDER_COLOR.r, FMTSShopWindow.DIVIDER_COLOR.g, FMTSShopWindow.DIVIDER_COLOR.b)
    list:drawRect(columns.iconDivider, y, 1, rowHeight, FMTSShopWindow.DIVIDER_COLOR.a, FMTSShopWindow.DIVIDER_COLOR.r, FMTSShopWindow.DIVIDER_COLOR.g, FMTSShopWindow.DIVIDER_COLOR.b)
    list:drawRect(columns.typeDivider, y, 1, rowHeight, FMTSShopWindow.DIVIDER_COLOR.a, FMTSShopWindow.DIVIDER_COLOR.r, FMTSShopWindow.DIVIDER_COLOR.g, FMTSShopWindow.DIVIDER_COLOR.b)
    list:drawRect(columns.costDivider, y, 1, rowHeight, FMTSShopWindow.DIVIDER_COLOR.a, FMTSShopWindow.DIVIDER_COLOR.r, FMTSShopWindow.DIVIDER_COLOR.g, FMTSShopWindow.DIVIDER_COLOR.b)
    list:drawRect(columns.buyDivider, y, 1, rowHeight, FMTSShopWindow.DIVIDER_COLOR.a, FMTSShopWindow.DIVIDER_COLOR.r, FMTSShopWindow.DIVIDER_COLOR.g, FMTSShopWindow.DIVIDER_COLOR.b)

    local texture = target:getItemTexture(row.item)

    if texture then
        local texW = texture:getWidth()
        local texH = texture:getHeight()
        local drawW = iconSize
        local drawH = iconSize

        if texW and texH and texW > 0 and texH > 0 then
            local scale = math.min(iconSize / texW, iconSize / texH)
            drawW = texW * scale
            drawH = texH * scale
        end

        local drawX = columns.iconX + math.floor((iconSize - drawW) / 2)
        local drawY = y + math.floor((rowHeight - drawH) / 2)

        list:drawTextureScaled(texture, drawX, drawY, drawW, drawH, 1.0)
    end

    list:drawText(displayName, columns.itemX, y + 5, 1, 1, 1, 1, UIFont.Small)

    local encumbranceY = y + 23

    if info.rounds ~= nil then
        list:drawText(target:formatNumber(info.rounds) .. " Rounds", columns.itemX, y + 23, 0.72, 0.72, 0.72, 1, UIFont.Small)
        encumbranceY = y + 41
    elseif info.capacity ~= nil then
        list:drawText(target:formatNumber(info.capacity) .. " Rounds", columns.itemX, y + 23, 0.72, 0.72, 0.72, 1, UIFont.Small)
        encumbranceY = y + 41
    end

    list:drawText("Encumbrance: " .. target:formatNumber(info.encumbrance), columns.itemX, encumbranceY, 0.72, 0.72, 0.72, 1, UIFont.Small)

    list:drawText(row.type or "", columns.typeX, y + 29, 0.85, 0.85, 0.85, 1, UIFont.Small)

    local soulTexture = target:getItemTexture(FMTS.SOUL_ITEM)
    local priceX = priceLayout.priceX

    if soulTexture then
        list:drawTextureScaled(soulTexture, priceX, y + math.floor((rowHeight - priceIconSize) / 2), priceIconSize, priceIconSize, 1.0)
    end

    list:drawText(tostring(row.cost), priceX + priceIconSize + 5, y + 29, 1, 1, 1, 1, UIFont.Small)

    if row.discountPercent and row.discountPercent > 0 then
        local discountLabel
        if row.discountAmount and row.discountAmount > 0 then
            discountLabel = tostring(row.discountPercent) .. "% (-" .. tostring(row.discountAmount) .. ")"
        else
            discountLabel = tostring(row.discountPercent) .. "%"
        end
        list:drawText(discountLabel, priceX, y + 45, 1.0, 0.85, 0.10, 1, UIFont.Small)
    end

    local hovering = target:isBuyHovered(y, mouseX, mouseY, columns)
    local red, green, blue = target:getBuyColor(row, hovering)

    list:drawText("Exchange", columns.buyX - 10, y + 29, red, green, blue, 1, UIFont.Small)

    return y + rowHeight
end


function FMTSShopWindow:onTableMouseDown(x, y)
    local rowIndex = self:rowAt(x, y)
    local row = self.items[rowIndex]

    if not row or not row.item then return true end

    if x >= self.target:getColumns().buyDivider then
        self.target:onBuyRow(row.item)
    end

    return true
end


function FMTSShopWindow:setSuccessFeedback(entry)
    self.feedback[entry.item] = { frames = FMTSShopWindow.FEEDBACK_DURATION }
end

function FMTSShopWindow:playShopSound()
    local soundName = self.closeButton and self.closeButton.sounds.activate

    if soundName then
        getSoundManager():playUISound(soundName)
    end
end

function FMTSShopWindow:playPurchaseSound()
    if FMTSShopWindow.PURCHASE_SOUND then
        getSoundManager():playUISound(FMTSShopWindow.PURCHASE_SOUND)
    end
end

function FMTSShopWindow:playRefreshSound()
    if FMTSShopWindow.REFRESH_SOUND then
        getSoundManager():playUISound(FMTSShopWindow.REFRESH_SOUND)
    end
end


function FMTSShopWindow:onBuyRow(entry)
    if not entry or not self.player then return end
    if self.pendingAction then return end

    self.pendingAction = "buy"
    sendClientCommand("FMTS", "BuyItem", {
        offeringId = entry.id,
    })
end


function FMTSShopWindow:onCloseButton()
    self:close()
end


function FMTSShopWindow:onRefreshShopButton()
    if self.pendingAction then return end

    self.pendingAction = "refresh"
    sendClientCommand("FMTS", "RefreshShop", {})
end


function FMTSShopWindow:handleServerCommand(module, command, args)
    if module ~= "FMTS" then
        return
    end

    if command == "BuyItemResult" then
        self.pendingAction = nil

        if args and args.ok and args.item then
            if args.spent then
                FMTS.RemoveSouls(self.player, args.spent)
            end
            self.player:getInventory():AddItem(args.item)
            self:setSuccessFeedback({ item = args.item })
            self:playPurchaseSound()
        end

        self:refreshSoulCount()
        return
    end

    if command == "RefreshShopResult" then
        self.pendingAction = nil

        if args and args.ok then
            if args.spent then
                FMTS.RemoveSouls(self.player, args.spent)
            end
            self:playRefreshSound()
        end

        self:refreshSoulCount()
        self:updateNextUpdateLabel()
        return
    end

    if command == "ShopCatalog" then
        if FMTS.ShopRefresh and args and args.products then
            FMTS.ShopRefresh.ApplyProducts(args.products, args.hoursUntilRefresh)
        end

        self:refreshSoulCount()
    end
end


function FMTSShopWindow:getSoulCount()
    return FMTS.GetSoulCount(self.player)
end


function FMTSShopWindow:refreshSoulCount()
    self:setSoulCount(self:getSoulCount())
end


function FMTSShopWindow:setSoulCount(souls)
    if souls == nil then return end
    if souls == self.lastSoulCount then return end

    self.lastSoulCount = souls
    self:updateSoulPanel()
    self:updateRefreshButtonColor()
    self:layoutFooter()
end


function FMTSShopWindow:updateRefreshButtonColor()
    if not self.refreshShopButton then return end

    if not FMTSShopWindow.BYPASS_SOUL_REQUIREMENT and self.lastSoulCount < FMTSShopWindow.MANUAL_REFRESH_COST then
        self.refreshShopButton.textColor = { r = 0.85, g = 0.20, b = 0.20, a = 1.0 }
        self.refreshShopButton.borderColor = { r = 0.75, g = 0.20, b = 0.20, a = 1.0 }
    else
        self.refreshShopButton.textColor = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
        self.refreshShopButton.borderColor = { r = 0.70, g = 0.70, b = 0.70, a = 0.70 }
    end
end


function FMTSShopWindow:update()
    ISCollapsableWindow.update(self)

    for itemType, feedback in pairs(self.feedback) do
        feedback.frames = feedback.frames - 1

        if feedback.frames <= 0 then
            self.feedback[itemType] = nil
        end
    end

    self.refreshCounter = self.refreshCounter + 1

    if self.refreshCounter >= FMTSShopWindow.SOUL_REFRESH_INTERVAL then
        self.refreshCounter = 0
        self:refreshSoulCount()
        self:updateNextUpdateLabel()
    end
end


function FMTSShopWindow:close()
    self:playShopSound()
    self:setVisible(false)
    self:removeFromUIManager()

    if FMTSShopWindow.instance == self then
        FMTSShopWindow.instance = nil
    end
end


function FMTSShopWindow.Open(player)
    if not player then return nil end

    if FMTSShopWindow.instance then
        local existing = FMTSShopWindow.instance

        if existing:getIsVisible() then
            existing:bringToTop()
            existing:refreshSoulCount()
            return existing
        end

        existing:close()
    end

    local width = FMTSShopWindow.MIN_WIDTH
    local height = FMTSShopWindow.MIN_HEIGHT
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local x = math.floor((screenWidth - width) / 2)
    local y = math.floor((screenHeight - height) / 2)

    local window = FMTSShopWindow:new(x, y, width, height, player)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)

    FMTSShopWindow.instance = window
    window:playShopSound()
    sendClientCommand("FMTS", "RequestShopCatalog", {})
    return window
end


Events.OnServerCommand.Add(function(module, command, args)
    local instance = FMTSShopWindow.instance

    if not instance or not module or not command then
        return
    end

    instance:handleServerCommand(module, command, args)
end)
