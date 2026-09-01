FMTSShopData = {}

-- Sampled separately by FMTSUpdateSoulShopProduct.lua so each refresh
-- draws a fixed number of items from every pool below.
FMTSShopData.ALL_AMMUNITION = {
    { cost = 100, item = "Base.Bullets38Box", rounds = 50, type = "Ammunition" },
    { cost = 100, item = "Base.Bullets357Box", rounds = 50, type = "Ammunition" },
    { cost = 100, item = "Base.Bullets9mmBox", rounds = 50, type = "Ammunition" },
    { cost = 100, item = "Base.Bullets45Box", rounds = 50, type = "Ammunition" },
    { cost = 50,  item = "Base.ShotgunShellsBox", rounds = 25, type = "Ammunition" },
    { cost = 40,  item = "Base.556Box", rounds = 20, type = "Ammunition" },
    { cost = 40,  item = "Base.3030Box", rounds = 20, type = "Ammunition" },
    { cost = 40,  item = "Base.308Box", rounds = 20, type = "Ammunition" },
    { cost = 40,  item = "Base.Bullets44Box", rounds = 20, type = "Ammunition" },
}

FMTSShopData.ALL_MAGAZINES = {
    { cost = 180, item = "Base.44Clip",    rounds = 8,  type = "Magazine" }, --B-F
    { cost = 220, item = "Base.JS14_Clip", rounds = 20,  type = "Magazine" }, --JS14
    { cost = 300, item = "Base.556Clip",   rounds = 30, type = "Magazine" }, --M16
    { cost = 150, item = "Base.45Clip",    rounds = 7,  type = "Magazine" }, --1911
    { cost = 320, item = "Base.M14Clip",   rounds = 20, type = "Magazine" }, --M1A
    { cost = 150, item = "Base.9mmClip",   rounds = 15, type = "Magazine" }, -- M9
}

-- Tools and Weapons share one pool but keep their own Type value.
FMTSShopData.ALL_TOOLS_WEAPONS = {
    { cost = 500, item = "Base.SledgehammerForged", type = "Tool" },
    { cost = 200, item = "Base.CrowbarForged", type = "Tool" },
    
    { cost = 200, item = "Base.MacheteForged", type = "Weapon" },
    { cost = 200, item = "Base.BaseballBat_Crafted", type = "Weapon" },


}

FMTSShopData.PRODUCTS = {}