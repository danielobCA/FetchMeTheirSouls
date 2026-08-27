require "FMTSShared"
require "FMTSShopTest"

local function refreshPendantName(player)
    FMTS.RefreshSoulPendantName(player)
end

Events.OnPlayerUpdate.Add(refreshPendantName)