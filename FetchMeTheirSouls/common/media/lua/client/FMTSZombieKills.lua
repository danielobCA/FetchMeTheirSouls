require "FMTSShared"

FMTS.LastAttacker = FMTS.LastAttacker or {}

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

    if killer and instanceof(killer, "IsoPlayer") then
        FMTS.AddSouls(killer, 1)
    end

    FMTS.LastAttacker[zombie] = nil
end

Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
Events.OnZombieDead.Add(onZombieDead)