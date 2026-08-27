FMTSShopData = {}


-- Rounds tab: boxes of ammunition for common calibers.
FMTSShopData.ROUNDS = {
    { cost = 100, item = "Base.Bullets38Box", rounds = 50 },
    { cost = 100, item = "Base.Bullets357Box", rounds = 50 },
    { cost = 100, item = "Base.Bullets9mmBox", rounds = 50 },
    { cost = 100, item = "Base.Bullets45Box", rounds = 50 },
    { cost = 50,  item = "Base.ShotgunShellsBox", rounds = 25 },
    { cost = 40,  item = "Base.556Box", rounds = 20 },
    { cost = 40,  item = "Base.3030Box", rounds = 20 },
    { cost = 40,  item = "Base.308Box", rounds = 20 },
    { cost = 40,  item = "Base.Bullets44Box", rounds = 20 },
}


-- Magazines tab: detachable magazines and clips for firearms.
-- `rounds` is the maximum capacity shown in the shop UI.
FMTSShopData.MAGAZINES = {
    { cost = 180, item = "Base.44Clip",    rounds = 8 },  -- D-E Magazine
    { cost = 220, item = "Base.JS14_Clip", rounds = 5 },  -- JS-2000 Magazine
    { cost = 300, item = "Base.556Clip",   rounds = 30 }, -- M16 Magazine
    { cost = 150, item = "Base.45Clip",    rounds = 7 },  -- M1911 Auto Magazine
    { cost = 320, item = "Base.M14Clip",   rounds = 20 }, -- M14 Magazine
    { cost = 150, item = "Base.9mmClip",   rounds = 15 }, -- M9 Magazine
}