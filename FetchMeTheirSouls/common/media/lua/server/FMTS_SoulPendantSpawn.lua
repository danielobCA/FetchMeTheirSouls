local function addSoulPendantToCultist(zombie)
    if not zombie or zombie:getOutfitName() ~= "Cultist" then
        return
    end

    if ZombRand(100) >= 100 then
        return
    end

    local inventory = zombie:getInventory()

    if inventory and not inventory:contains("FMTS.SoulPendant") then
        inventory:AddItem("FMTS.SoulPendant")
    end
end

Events.OnZombieDead.Add(addSoulPendantToCultist)

local function addSoulPendantToCultistBedroom(roomType, containerType, container)
    if roomType ~= "cultistbedroom" or containerType ~= "locker" or not container then
        return
    end

    container:AddItem("FMTS.SoulPendant")
    container:AddItem("Base.BookFancy_Occult")
    container:AddItem("Base.BookFancy_Occult")

    if ZombRand(100) < 40 then
        container:AddItem("FMTS.SoulPendant")
    end

    if ZombRand(100) < 25 then
        container:AddItem("Base.HuntingKnife")
    end
end

Events.OnFillContainer.Add(addSoulPendantToCultistBedroom)