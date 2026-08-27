require "TimedActions/ISInventoryTransferAction"

local originalIsValid = ISInventoryTransferAction.isValid

function ISInventoryTransferAction:isValid()
    if self.item and self.item.getFullType
        and self.item:getFullType() == FMTS.SOUL_ITEM then
        return false
    end

    return originalIsValid(self)
end
