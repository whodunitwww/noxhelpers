-- AutoSellConfigEditor.lua
-- Standalone config editor for AutoSell thresholds, with pretty UI + live ore icons.
-- UPDATED:
--    • Fixed Rune Traits tab (was empty due to a parenting error).
--    • Fixed sorting (Exotic/Divine/Relic/Mythic now sort correctly).
--    • Standardized "Mythic" vs "Mythical".
--    • Ores are zoomed in 50%+ larger.

-- CONFIG PATH
local BASE_DIR            = "Cerberus/The Forge"   -- <== make sure this matches References.gameDir in your main script
local AutoSellConfigFile = BASE_DIR .. "/AutoSellConfig.json"

local Players             = game:GetService("Players")
local HttpService         = game:GetService("HttpService")
local CoreGui             = game:GetService("CoreGui")
local UserInputService    = game:GetService("UserInputService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Shared              = ReplicatedStorage:WaitForChild("Shared")

local LocalPlayer         = Players.LocalPlayer

----------------------------------------------------------------
-- DATA (mirrors main script)
----------------------------------------------------------------
local EssenceRarityMap    = {
    ["Tiny Essence"]      = "Common",
    ["Small Essence"]     = "Common",
    ["Medium Essence"]    = "Uncommon",
    ["Large Essence"]     = "Uncommon",
    ["Greater Essence"]   = "Rare",
    ["Superior Essence"]  = "Epic",
    ["Epic Essence"]      = "Epic",
    ["Legendary Essence"] = "Legendary",
    ["Mythical Essence"]  = "Mythical",
}

local OreRarityMap = {
    ["Aether Lotus"] = "Rare",
    ["Aetherit"] = "Rare",
    ["Aite"] = "Epic",
    ["Amethyst"] = "Rare",
    ["Aqujade"] = "Epic",
    ["Arcane Crystal"] = "Mythic",
    ["Aurelia-no-Ki"] = "Rare",
    ["Azuryxite"] = "Legendary",
    ["Bamboo"] = "Uncommon",
    ["Bananite"] = "Uncommon",
    ["Blue Crystal"] = "Epic",
    ["Blue Gem Quill"] = "Epic",
    ["Boneite"] = "Rare",
    ["Cardboardite"] = "Common",
    ["Ceyite"] = "Exotic",
    ["Cobalt"] = "Uncommon",
    ["Coinite"] = "Legendary",
    ["Copper"] = "Common",
    ["Crimson Crystal"] = "Epic",
    ["Crimsonite"] = "Epic",
    ["Cryptex"] = "Epic",
    ["Cuprite"] = "Epic",
    ["Cyanite Jade"] = "Epic",
    ["Dark Boneite"] = "Rare",
    ["Darkryte"] = "Mythic",
    ["Demonite"] = "Mythic",
    ["Diamond"] = "Rare",
    ["Duquack"] = "Legendary",
    ["Duranite"] = "Mythic",
    ["Earthite"] = "Rare",
    ["Emerald"] = "Epic",
    ["Etherealite"] = "Mythic",
    ["Evil Eye"] = "Mythic",
    ["Eye Ore"] = "Legendary",
    ["Fichillium"] = "Relic",
    ["Fichilliumorite"] = "Unobtainable",
    ["Fierce Jade"] = "Unobtainable",
    ["Fireite"] = "Legendary",
    ["Frogite"] = "Epic",
    ["Frost Fossil"] = "Epic",
    ["Fruite"] = "Rare",
    ["Galaxite"] = "Divine",
    ["Galestor"] = "Epic",
    ["Gargantuan"] = "Divine",
    ["Gold"] = "Uncommon",
    ["Golem Heart"] = "Divine",
    ["Graphite"] = "Rare",
    ["Grass"] = "Common",
    ["Green Crystal"] = "Epic",
    ["Gulabite"] = "Legendary",
    ["Heart Of The Island"] = "Relic",
    ["Heat Steel"] = "Epic",
    ["Heavenite"] = "Divine",
    ["Heavenly Orb"] = "Mythic",
    ["Iceite"] = "Mythic",
    ["Iron"] = "Common",
    ["Kitsunite"] = "Unobtainable",
    ["Kokorite"] = "Unobtainable",
    ["Kyomutite"] = "Unobtainable",
    ["Kyubite"] = "Divine",
    ["Lapis Lazuli"] = "Uncommon",
    ["Larimar"] = "Epic",
    ["Lgarite"] = "Rare",
    ["Lightite"] = "Legendary",
    ["Lucky Cat"] = "Epic",
    ["Magenta Crystal"] = "Epic",
    ["Magit"] = "Epic",
    ["Magmaite"] = "Legendary",
    ["Malachite"] = "Epic",
    ["Marblite"] = "Exotic",
    ["Melonite"] = "Rare",
    ["Meteorite"] = "Mythic",
    ["Mistvein"] = "Rare",
    ["Moltenfrost"] = "Epic",
    ["Moon Stone"] = "Legendary",
    ["Mosasaursit"] = "Exotic",
    ["Mushroomite"] = "Rare",
    ["Mythril"] = "Legendary",
    ["Neurotite"] = "Epic",
    ["North Star"] = "Unobtainable",
    ["Obsidian"] = "Epic",
    ["Onite"] = "Legendary",
    ["Onyx"] = "Legendary",
    ["Orange Crystal"] = "Epic",
    ["Platinum"] = "Rare",
    ["Poopite"] = "Epic",
    ["Prismatic Heart"] = "Legendary",
    ["Pumice"] = "Rare",
    ["Quartz"] = "Rare",
    ["Rainbow Crystal"] = "Legendary",
    ["Rivalite"] = "Epic",
    ["Rock Seed"] = "Rare",
    ["Roosite"] = "Legendary",
    ["Root Spire"] = "Uncommon",
    ["Ruby"] = "Epic",
    ["Ryuseki"] = "Unobtainable",
    ["Sakuranite"] = "Rare",
    ["Sakurite"] = "Unobtainable",
    ["Sanctis"] = "Legendary",
    ["Sand Stone"] = "Common",
    ["Sapphire"] = "Rare",
    ["Scheelite"] = "Rare",
    ["Sealed Curse"] = "Epic",
    ["Shikanite"] = "Epic",
    ["Silver"] = "Uncommon",
    ["Slimite"] = "Epic",
    ["Snowite"] = "Legendary",
    ["Starite"] = "Mythic",
    ["Stolen Heart"] = "Divine",
    ["Stone"] = "Common",
    ["Sulfur"] = "Uncommon",
    ["Sun Stone"] = "Legendary",
    ["Suryafal"] = "Relic",
    ["Takenokoishi"] = "Unobtainable",
    ["Takiseki"] = "Unobtainable",
    ["Tide Carve"] = "Epic",
    ["Tiger's Eye"] = "Epic",
    ["Tin"] = "Uncommon",
    ["Titanium"] = "Uncommon",
    ["Topaz"] = "Rare",
    ["Tungsten"] = "Common",
    ["Uranium"] = "Legendary",
    ["Vanegos"] = "Rare",
    ["Velchire"] = "Legendary",
    ["Voidfractal"] = "Rare",
    ["Voidstar"] = "Legendary",
    ["Volcanic Rock"] = "Rare",
    ["Vooite"] = "Exotic",
    ["Water Stone"] = "Rare",
    ["Wolfarite"] = "Unobtainable",
    ["Wraith"] = "Epic",
    ["Yang"] = "Unobtainable",
    ["Yeti Heart"] = "Mythic",
    ["Yin"] = "Unobtainable",
    ["Yin-Yang"] = "Unobtainable",
    ["Zenstone"] = "Legendary",
    ["Zephyte"] = "Rare",
}

-- UPDATED: Added Exotic, Divine, Relic colors
local RarityColors        = {
    Common       = Color3.fromRGB(140, 140, 140),
    Uncommon     = Color3.fromRGB(80, 190, 120),
    Rare         = Color3.fromRGB(90, 140, 240),
    Epic         = Color3.fromRGB(200, 90, 240),
    Legendary    = Color3.fromRGB(255, 200, 80),
    Mythical     = Color3.fromRGB(255, 80, 110),
    Exotic       = Color3.fromRGB(255, 105, 180), -- Hot Pink
    Divine       = Color3.fromRGB(255, 255, 200), -- Pale Gold/White
    Relic        = Color3.fromRGB(0, 255, 255),   -- Cyan/Aqua
}

local EssenceNamesList    = {
    "Tiny Essence",
    "Small Essence",
    "Medium Essence",
    "Large Essence",
    "Greater Essence",
    "Superior Essence",
    "Epic Essence",
    "Legendary Essence",
    "Mythical Essence",
}

local OreNamesList        = {}
for oreName in pairs(OreRarityMap) do
    table.insert(OreNamesList, oreName)
end

-- UPDATED: Added sorting logic for higher tiers
local rarityOrder = {
    Relic        = 1,
    Divine       = 2,
    Exotic       = 3,
    Mythical     = 4,
    Legendary    = 5,
    Epic         = 6,
    Rare         = 7,
    Uncommon     = 8,
    Common       = 9,
}

table.sort(OreNamesList, function(a, b)
    local ra = rarityOrder[OreRarityMap[a]] or 99
    local rb = rarityOrder[OreRarityMap[b]] or 99
    if ra == rb then
        return a < b
    end
    return ra < rb
end)

-- UPDATED: Added buttons for the new rarities in the filter tab
local OreRarityList        = { "Relic", "Divine", "Exotic", "Mythical", "Legendary", "Epic", "Rare", "Uncommon", "Common" }
local EssenceRarityList    = { "Mythical", "Legendary", "Epic", "Rare", "Uncommon", "Common" }

-- existing rune *items* (shards etc)
local RuneValues            = {
    "Miner Shard",
    "Blast Chip",
    "Frost Speck",
    "Flame Spark",
    "Briar Notch",
    "Rage Mark",
    "Drain Edge",
    "Chill Dust",
    "Ward Patch",
    "Venom Crumb",
    "Flame Spark II",
    "Rage Mark II",
    "Frost Speck II",
    "Miner Shard II",
    "Chill Dust II",
}

local RuneImageIds          = {
    ["Ward Patch"] = "136618198347198",
    ["Briar Notch"] = "130375351000261",
    ["Rage Mark"] = "74377849245058",
    ["Rot Stitch"] = "137770213250456",
    ["Chill Dust"] = "114452465252568",
    ["Miner Shard"] = "110898589664978",
    ["Flame Spark"] = "73865699740150",
    ["Frost Speck"] = "70953025556952",
    ["Blast Chip"] = "85050444076173",
    ["Drain Edge"] = "89173473574831",
    ["Venom Crumb"] = "77052262266995",
    ["Flame Spark II"] = "73865699740150",
    ["Rage Mark II"] = "74377849245058",
    ["Frost Speck II"] = "70953025556952",
    ["Miner Shard II"] = "110898589664978",
    ["Chill Dust II"] = "114452465252568",
    ["Frost Speck II"] = "70953025556952",
}

local EssenceImageIds       = {
    ["Tiny Essence"]      = "72025528879375",
    ["Small Essence"]     = "117483889562292",
    ["Medium Essence"]    = "92874766076839",
    ["Large Essence"]     = "122449926928886",
    ["Greater Essence"]   = "75420167695755",
    ["Superior Essence"]  = "120798786019612",
    ["Epic Essence"]      = "71038820643974",
    ["Legendary Essence"] = "126658024565240",
    ["Mythical Essence"]  = "97191650147139",
}

----------------------------------------------------------------
-- RUNE TRAIT DEFINITIONS
----------------------------------------------------------------
local RuneTraitDefinitions = {
    { id = "Radioactive", name = "Radioactive", description = "Deal nil% of max health as damage as AoE while in-combat.", iconImageId = "126391228181883" },
    { id = "Berserker", name = "Berserker", description = "Boosts physical damage and movement speed by nil% for nil seconds. Has nil seconds cooldown. Activates when health is below 35%.", iconImageId = "99579458536104" },
    { id = "Poison", name = "Poison", description = "Deals nil% of weapon damage as poison per second for nil seconds. nil% chance on hit.", iconImageId = "77726317529525" },
    { id = "FlatHealthRegen", name = "Flat Regen", description = "Regen nil health per second.", iconImageId = "92712417449524" },
    { id = "Thorn", name = "Thorn", description = "Reflect nil% physical damage taken. Maximum damage given limits at 5% max health of user. 0.05 seconds cooldown.", iconImageId = "126391228181883" },
    { id = "UndeadSecondChance", name = "Second Chance", description = "Refills 50% of max hp when hp is under 10% every 5 minutes", iconImageId = "94132270840631" },
    { id = "DemonDevilsFinger", name = "Devil's Finger", description = "When you dash, teleport with hellfire particles and 35% chance to create a hellfire circle deal AOE to the enemies inside dealing 45% damage of your weapon per second for 3 sec.", iconImageId = "126391228181883" },
    { id = "AttackSpeedBoost", name = "Attack Speed", description = "Increase attack speed by nil%.", iconImageId = "74403354215536" },
    { id = "JumpBoost", name = "Jump Boost", description = "nil% longer jump.", iconImageId = "99963424031166" },
    { id = "ShadowPhantomStep", name = "Phantom Step", description = "nil% to be immortal and gain movement speed for a brief duration.", iconImageId = "94132270840631" },
    { id = "ToxicVeins", name = "Toxic Veins", description = "Deals nil% poison damage around the character for nil seconds. Has nil seconds cooldown. Activates when health is below 35%.", iconImageId = "131438262369264" },
    { id = "MoveSpeed", name = "Swiftness", description = "nil% extra movement speed.", iconImageId = "92712417449524" },
    { id = "Explosion", name = "Explosion", description = "Cause an explosion at location of victim, dealing nil% of weapon damage as AOE damage. nil% chance on hit.", iconImageId = "110063824255919" },
    { id = "MinePower", name = "Mine Power", description = "nil% extra mine damage.", iconImageId = "138135219973840" },
    { id = "BullsFury", name = "Bull's Fury", description = "Boosts physical damage and movement speed by 30% while health is under 50%.", iconImageId = "99579458536104" },
    { id = "NegativeHealthBoost", name = "Negative Vitality", description = "-nil% health.", iconImageId = "92712417449524" },
    { id = "Fire", name = "Burn", description = "Deals nil% of weapon damage as fire per second for nil seconds. nil% chance on hit.", iconImageId = "130243970954297" },
    { id = "DashIFrame", name = "Phase", description = "nil% longer invincibility on dash.", iconImageId = "110461678599478" },
    { id = "Shield", name = "Shield", description = "Reduce incoming physical damage by nil%. Has nil% chance per hit.", iconImageId = "94132270840631" },
    { id = "AngelHolyHand", name = "Holy Hand", description = "Have infinite stamina while below 20% health.", iconImageId = "99579458536104" },
    { id = "AngelSmite", name = "Angel Smite", description = "50% chance to call upon Smite on-hit for 30% of physical damage.", iconImageId = "110063824255919" },
    { id = "NegativeStaminaBoost", name = "Negative Endurance", description = "-nil% stamina.", iconImageId = "99963424031166" },
    { id = "MineSpeed", name = "Swift Mining", description = "nil% faster mining.", iconImageId = "138135219973840" },
    { id = "CriticalChance", name = "Critical Chance", description = "Increase critical chance by nil%.", iconImageId = "118179174921595" },
    { id = "LuckBoost", name = "Luck", description = "nil% overall luck increase.", iconImageId = "109268611568059" },
    { id = "Snow", name = "Snow", description = "Applies nil% attack speed and movement speed slow for nil seconds. nil% chance on hit.", iconImageId = "103795067047772" },
    { id = "ExtraMineDrop", name = "Yield", description = "nil% chance to drop nil extra ore(s) from mines.", iconImageId = "134056473233081" },
    { id = "BadSmell", name = "Bad Smell", description = "Deals nil% poison damage around the character for nil seconds, fearing enemies. Has nil seconds cooldown. Activates when health is below 35%.", iconImageId = "133381322224239" },
    { id = "StaminaBoost", name = "Endurance", description = "nil% more stamina.", iconImageId = "99963424031166" },
    { id = "DashDistance", name = "Stride", description = "nil% longer dash distance.", iconImageId = "112354247336206" },
    { id = "DashCooldown", name = "Surge", description = "nil% less dash cooldown.", iconImageId = "132915742367432" },
    { id = "CriticalDamage", name = "Critical Damage", description = "Increase critical damage by nil%.", iconImageId = "134197413281062" },
    { id = "XPBoost", name = "EXP Boost", description = "nil% extra xp gain.", iconImageId = "92712417449524" },
    { id = "HealthBoost", name = "Vitality", description = "nil% extra health.", iconImageId = "92712417449524" },
    { id = "StunDamage", name = "Fracture", description = "nil% extra stun damage on-hit.", iconImageId = "129442737645310" },
    { id = "DemonCursedAura", name = "Cursed Aura", description = "Deal 10% of weapon damage as AoE while in-combat.", iconImageId = "126391228181883" },
    { id = "NegativeMoveSpeed", name = "Negative Swiftness", description = "-nil% movement speed.", iconImageId = "92712417449524" },
    { id = "DemonBackfire", name = "Backfire", description = "nil% chance to burn the enemy upon taking damage.", iconImageId = "126391228181883" },
    { id = "DamageBoost", name = "Lethality", description = "Increase physical damage by nil%.", iconImageId = "105965083804844" },
    { id = "ZombieAbsorb", name = "Absorb", description = "nil% to convert damage taken into health instead.", iconImageId = "94132270840631" },
    { id = "LifeSteal", name = "Life Steal", description = "Heal nil% of physical damage dealt on-hit.", iconImageId = "116807775361910" },
    { id = "Ice", name = "Ice", description = "Freeze enemies for nil seconds. nil% chance on hit. Has a cooldown of nil.", iconImageId = "132472537758179" },
}

local RuneTraitParamLabels = {
    Radioactive = { "AoE % Max HP" },
    Berserker = { "Buff % (DMG+MS)", "Buff Duration (s)", "Cooldown (s)" },
    Poison = { "Poison % / sec", "Duration (s)", "Proc Chance %" },
    FlatHealthRegen = { "HP / sec" },
    Thorn = { "Reflect % Damage" },
    AttackSpeedBoost = { "Attack Speed %" },
    JumpBoost = { "Jump Height %" },
    ShadowPhantomStep = { "Immortality Chance %" },
    ToxicVeins = { "Poison AoE % DMG", "Duration (s)", "Cooldown (s)" },
    MoveSpeed = { "Move Speed %" },
    Explosion = { "Explosion DMG %", "Proc Chance %" },
    MinePower = { "Mine Damage %" },
    NegativeHealthBoost = { "Max HP Penalty %" },
    Fire = { "Burn % / sec", "Duration (s)", "Proc Chance %" },
    DashIFrame = { "Dash I-Frame %" },
    Shield = { "Damage Reduction %", "Proc Chance %" },
    NegativeStaminaBoost = { "Stamina Penalty %" },
    MineSpeed = { "Mining Speed %" },
    CriticalChance = { "Crit Chance %" },
    LuckBoost = { "Luck %" },
    Snow = { "Slow Amount %", "Duration (s)", "Proc Chance %" },
    ExtraMineDrop = { "Extra Drop Chance %", "Extra Ores Count" },
    BadSmell = { "Poison AoE % DMG", "Duration (s)", "Cooldown (s)" },
    StaminaBoost = { "Stamina %" },
    DashDistance = { "Dash Distance %" },
    DashCooldown = { "Dash CD Reduction %" },
    CriticalDamage = { "Crit Damage %" },
    XPBoost = { "XP Gain %" },
    HealthBoost = { "Max HP %" },
    StunDamage = { "Stun Damage %" },
    NegativeMoveSpeed = { "Move Speed Penalty %" },
    DemonBackfire = { "Burn Proc Chance %" },
    DamageBoost = { "Physical Damage %" },
    ZombieAbsorb = { "Absorb Chance %" },
    LifeSteal = { "Life Steal %" },
    Ice = { "Freeze Duration (s)", "Proc Chance %", "Cooldown (s)" },
}

local RuneTraitStatOrder = {}
local function initRuneTraitStatOrder()
    local ok, Runes = pcall(function()
        return require(Shared:WaitForChild("Data"):WaitForChild("Runes"))
    end)
    if not ok or not Runes or type(Runes) ~= "table" then
        return
    end

    local pool = Runes.TraitPool or {}
    for traitId, traitData in pairs(pool) do
        local stats = traitData.Stats
        if type(stats) == "table" then
            local keys = {}
            for statName, _ in pairs(stats) do
                if statName ~= "Stackable" and statName ~= "UseLowest" then
                    table.insert(keys, statName)
                end
            end
            table.sort(keys)
            if #keys > 0 then
                RuneTraitStatOrder[traitId] = keys
            end
        end
    end
end
pcall(initRuneTraitStatOrder)

local function countNilPlaceholders(desc)
    local count = 0
    for _ in string.gmatch(desc or "", "nil") do
        count += 1
    end
    return count
end

----------------------------------------------------------------
-- GRAB ORE ICONS FROM REPLICATED STORAGE (Updated Method)
----------------------------------------------------------------
local OreIconSources = {}
local GenericOreIconTemplate = nil

-- Create a generic fallback icon if an asset is missing
local function createGenericOreIcon()
    local vf = Instance.new("ViewportFrame")
    vf.BackgroundTransparency = 1
    vf.BorderSizePixel = 0
    vf.Ambient = Color3.fromRGB(200, 200, 200)
    vf.LightColor = Color3.fromRGB(255, 255, 255)
    vf.LightDirection = Vector3.new(1, -1, 1)

    local wm = Instance.new("WorldModel")
    wm.Parent = vf

    local ore = Instance.new("Part")
    ore.Size = Vector3.new(2, 2, 2)
    ore.Shape = Enum.PartType.Block
    ore.Material = Enum.Material.SmoothPlastic
    ore.Color = Color3.fromRGB(120, 180, 255)
    ore.Anchored = true
    ore.Position = Vector3.new(0, 0, 0)
    ore.Parent = wm

    local bevel = Instance.new("SpecialMesh")
    bevel.MeshType = Enum.MeshType.Sphere
    bevel.Scale = Vector3.new(0.9, 0.9, 0.9)
    bevel.Parent = ore

    local cam = Instance.new("Camera")
    cam.CFrame = CFrame.new(Vector3.new(0, 3, 5), Vector3.new(0, 0, 0))
    cam.Parent = vf
    vf.CurrentCamera = cam

    return vf
end

-- MAIN FUNCTION: Creates a ViewportFrame with the 3D Ore
local function getOreIconTemplate(oreName)
    -- 1. Check if we already created a template for this ore
    if OreIconSources[oreName] then
        return OreIconSources[oreName]
    end

    -- 2. Try to find the asset in ReplicatedStorage.Assets.Ores
    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    local oresFolder = assetsFolder and assetsFolder:FindFirstChild("Ores")
    local oreAsset = oresFolder and oresFolder:FindFirstChild(oreName)

    if oreAsset then
        local vf = Instance.new("ViewportFrame")
        vf.BackgroundTransparency = 1
        vf.BorderSizePixel = 0
        vf.Size = UDim2.fromScale(1, 1)
        
        -- Lighting settings so the ore isn't dark
        vf.Ambient = Color3.fromRGB(220, 220, 220)
        vf.LightColor = Color3.fromRGB(255, 255, 255)
        vf.LightDirection = Vector3.new(1, -1, 1) -- Light coming from top-right

        -- Create a WorldModel
        local wm = Instance.new("WorldModel")
        wm.Parent = vf

        local oreClone = oreAsset:Clone()
        oreClone.Parent = wm

        -- 3. Calculate Bounding Box (Size of the ore)
        local cf, size
        if oreClone:IsA("Model") then
            cf, size = oreClone:GetBoundingBox()
        elseif oreClone:IsA("BasePart") then
            cf = oreClone.CFrame
            size = oreClone.Size
        end

        -- 4. Center the clone at 0,0,0 and rotate it slightly
        -- We rotate by 45 degrees so it looks 3D and not flat
        local targetCFrame = CFrame.new(Vector3.zero) * CFrame.Angles(0, math.rad(45), 0)

        if oreClone:IsA("Model") then
            oreClone:PivotTo(targetCFrame)
        elseif oreClone:IsA("BasePart") then
            oreClone.CFrame = targetCFrame
        end

        -- 5. Calculate optimal camera distance
        -- We get the largest dimension (X, Y or Z)
        local maxDimension = math.max(size.X, size.Y, size.Z)
        
        -- UPDATED: Reduced the multiplier from 2.0 to 1.25.
        -- Smaller multiplier = Camera closer = Object bigger.
        local dist = maxDimension * 1.25

        -- Setup Camera
        local cam = Instance.new("Camera")
        cam.Parent = vf
        vf.CurrentCamera = cam
        
        -- Position camera slightly up (Y) and back (Z) based on size
        cam.CFrame = CFrame.new(Vector3.new(0, maxDimension * 0.5, dist), Vector3.zero)

        -- Cache it
        OreIconSources[oreName] = vf
        return vf
    end

    -- 3. Fallback if asset not found
    if not GenericOreIconTemplate then
        GenericOreIconTemplate = createGenericOreIcon()
    end
    return GenericOreIconTemplate
end

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local function makeDefaultConfig()
    return {
        version         = 1,
        ores            = {},
        oreRarities     = {},
        essence         = {},
        essenceRarities = {},
        runes           = {},
        runeTraits      = {},
    }
end

local Config = nil

local function loadConfig()
    if not (isfile and readfile) then
        return makeDefaultConfig()
    end

    if not isfile(AutoSellConfigFile) then
        return makeDefaultConfig()
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(AutoSellConfigFile))
    end)

    if not ok or type(decoded) ~= "table" then
        return makeDefaultConfig()
    end

    decoded.version         = decoded.version or 1
    decoded.ores            = decoded.ores or {}
    decoded.oreRarities     = decoded.oreRarities or {}
    decoded.essence         = decoded.essence or {}
    decoded.essenceRarities = decoded.essenceRarities or {}
    decoded.runes           = decoded.runes or {}
    decoded.runeTraits      = decoded.runeTraits or {}

    for traitId, rule in pairs(decoded.runeTraits) do
        if type(rule) ~= "table" then
            decoded.runeTraits[traitId] = { enabled = false, params = {} }
        else
            rule.enabled = rule.enabled == true
            if type(rule.params) ~= "table" then
                rule.params = {}
            end
        end
    end

    return decoded
end

local function saveConfig()
    if not (writefile and HttpService.JSONEncode) then return end
    local ok, raw = pcall(function()
        return HttpService:JSONEncode(Config)
    end)
    if ok then
        pcall(writefile, AutoSellConfigFile, raw)
    end
end

Config = loadConfig()

----------------------------------------------------------------
-- UI HELPERS
----------------------------------------------------------------
local function safeParentGui(gui)
    if gethui then
        gui.Parent = gethui()
    elseif syn and syn.protect_gui then
        syn.protect_gui(gui)
        gui.Parent = CoreGui
    else
        gui.Parent = CoreGui
    end
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local function createUI()
    local existing = CoreGui:FindFirstChild("AutoSellConfigGui")
    if existing then
        existing:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AutoSellConfigGui"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    safeParentGui(gui)

    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

    -- main window
    local mainFrame = Instance.new("Frame")
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    if isMobile then
        mainFrame.Size = UDim2.new(0.96, 0, 0.85, 0)
    else
        mainFrame.Size = UDim2.new(0, 900, 0, 520)
    end
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    mainFrame.BorderSizePixel = 0
    mainFrame.ZIndex = 2
    mainFrame.Parent = gui

    local uicorner = Instance.new("UICorner")
    uicorner.CornerRadius = UDim.new(0, 12)
    uicorner.Parent = mainFrame

    local mfGrad = Instance.new("UIGradient")
    mfGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 12, 18)),
    })
    mfGrad.Rotation = 90
    mfGrad.Parent = mainFrame

    -- title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 38)
    titleBar.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    titleBar.BorderSizePixel = 0
    titleBar.ZIndex = 3
    titleBar.Parent = mainFrame

    local tbCorner = Instance.new("UICorner")
    tbCorner.CornerRadius = UDim.new(0, 12)
    tbCorner.Parent = titleBar

    local tbGrad = Instance.new("UIGradient")
    tbGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 90)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 24, 32)),
    })
    tbGrad.Rotation = 0
    tbGrad.Parent = titleBar

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(0, 340, 1, 0)
    titleText.Position = UDim2.new(0, 16, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 18
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleText.Text = "Cerberus • AutoSell Configuration"
    titleText.ZIndex = 4
    titleText.Parent = titleBar

    local subtitle = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -120, 1, 0)
    subtitle.Position = UDim2.new(0, 0, 0, 0)
    subtitle.BackgroundTransparency = 1
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = 12
    subtitle.TextXAlignment = Enum.TextXAlignment.Right
    subtitle.TextColor3 = Color3.fromRGB(185, 185, 210)
    subtitle.Text = "BETA - Please report any issues in the Cerberus Discord!"
    subtitle.ZIndex = 4
    subtitle.Parent = titleBar

    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 38, 1, 0)
    closeButton.Position = UDim2.new(1, -38, 0, 0)
    closeButton.BackgroundTransparency = 1
    closeButton.Text = "X"
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 18
    closeButton.TextColor3 = Color3.fromRGB(235, 90, 90)
    closeButton.ZIndex = 10
    closeButton.Parent = titleBar

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, -32, 0, 56)
    infoLabel.Position = UDim2.new(0, 16, 0, 44)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextSize = 13
    infoLabel.TextWrapped = true
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
    infoLabel.ZIndex = 3
    infoLabel.Text =
        "• Ores / Essences: Threshold = how many to keep; extras get auto-sold.\n" ..
        "• Rune Traits: enable traits + set stat filters (▲ = at or above, ▼ = at or below) to protect runes.\n" ..
        "• Changes save instantly; hit Reload AutoSell in the main script to actually apply."
    infoLabel.Parent = mainFrame

    ----------------------------------------------------------------
    -- TAB BAR
    ----------------------------------------------------------------
    local tabBar = Instance.new("ScrollingFrame")
    tabBar.Size = UDim2.new(1, -32, 0, 30)
    tabBar.Position = UDim2.new(0, 16, 0, 106)
    tabBar.BackgroundTransparency = 1
    tabBar.ZIndex = 3
    tabBar.ScrollBarThickness = isMobile and 6 or 3
    tabBar.ScrollingDirection = Enum.ScrollingDirection.X
    tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabBar.BorderSizePixel = 0
    tabBar.Parent = mainFrame

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 8)
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Parent = tabBar

    tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        tabBar.CanvasSize = UDim2.new(0, tabLayout.AbsoluteContentSize.X + 8, 0, 0)
    end)

    ----------------------------------------------------------------
    -- CONTENT AREA + SEARCH ROW
    ----------------------------------------------------------------
    local contentFrame                = Instance.new("Frame")
    contentFrame.Size                 = UDim2.new(1, -32, 1, -176)
    contentFrame.Position             = UDim2.new(0, 16, 0, 138)
    contentFrame.BackgroundColor3     = Color3.fromRGB(12, 12, 16)
    contentFrame.BorderSizePixel      = 0
    contentFrame.ZIndex               = 2
    contentFrame.Parent               = mainFrame

    local cfCorner                    = Instance.new("UICorner")
    cfCorner.CornerRadius             = UDim.new(0, 10)
    cfCorner.Parent                   = contentFrame

    local cfStroke                    = Instance.new("UIStroke")
    cfStroke.Color                    = Color3.fromRGB(60, 60, 90)
    cfStroke.Thickness                = 1
    cfStroke.Transparency             = 0.35
    cfStroke.Parent                   = contentFrame

    -- Header row: just the search bar
    local headerRow                   = Instance.new("Frame")
    headerRow.Size                    = UDim2.new(1, -8, 0, 28)
    headerRow.Position                = UDim2.new(0, 4, 0, 4)
    headerRow.BackgroundTransparency = 1
    headerRow.ZIndex                  = 3
    headerRow.Parent                  = contentFrame

    local searchBox                   = Instance.new("TextBox")
    searchBox.AnchorPoint             = Vector2.new(0, 0.5)
    searchBox.Position                = UDim2.new(0, 0, 0.5, 0)
    searchBox.Size                    = UDim2.new(1, 0, 1, 0)
    searchBox.BackgroundColor3        = Color3.fromRGB(24, 24, 34)
    searchBox.BorderSizePixel         = 0
    searchBox.PlaceholderText         = "Search..."
    searchBox.Font                    = Enum.Font.Gotham
    searchBox.TextSize                = 12
    searchBox.TextColor3              = Color3.fromRGB(255, 255, 255)
    searchBox.TextXAlignment          = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus        = false
    searchBox.ZIndex                  = 4
    searchBox.Text                    = ""
    searchBox.Parent                  = headerRow

    local sbCorner                    = Instance.new("UICorner")
    sbCorner.CornerRadius             = UDim.new(0, 6)
    sbCorner.Parent                   = searchBox

    local sbPadding                   = Instance.new("UIPadding")
    sbPadding.PaddingLeft             = UDim.new(0, 8)
    sbPadding.Parent                  = searchBox

    ----------------------------------------------------------------
    -- CARD SCROLL AREA
    ----------------------------------------------------------------
    local scroll                      = Instance.new("ScrollingFrame")
    scroll.Size                       = UDim2.new(1, -8, 1, -40)
    scroll.Position                   = UDim2.new(0, 4, 0, 36)
    scroll.CanvasSize                 = UDim2.new(0, 0, 0, 0)
    scroll.ScrollBarThickness         = isMobile and 10 or 6
    scroll.BackgroundTransparency     = 1
    scroll.ZIndex                     = 2
    scroll.BorderSizePixel            = 0
    scroll.Parent                     = contentFrame

    local grid                        = Instance.new("UIGridLayout")
    grid.CellSize                     = UDim2.new(0, 275, 0, 55)
    grid.CellPadding                  = UDim2.new(0, 8, 0, 8)
    grid.FillDirection                = Enum.FillDirection.Horizontal
    grid.SortOrder                    = Enum.SortOrder.LayoutOrder
    grid.Parent                       = scroll

    local padding                     = Instance.new("UIPadding")
    padding.PaddingTop                = UDim.new(0, 8)
    padding.PaddingLeft               = UDim.new(0, 8)
    padding.PaddingRight              = UDim.new(0, 8)
    padding.PaddingBottom             = UDim.new(0, 8)
    padding.Parent                    = scroll

    grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 16)
    end)

    ----------------------------------------------------------------
    -- RESPONSIVE GRID
    ----------------------------------------------------------------
    local currentCellHeight = 55

    local function updateGridLayout()
        local width = scroll.AbsoluteSize.X - 16
        if width <= 0 then return end

        local columns
        if width >= 820 then
            columns = 3
        elseif width >= 540 then
            columns = 2
        else
            columns = 1
        end

        local cardWidth = math.floor((width - (columns - 1) * 8) / columns)
        grid.CellSize = UDim2.new(0, cardWidth, 0, currentCellHeight)
    end

    scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridLayout)
    mainFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridLayout)
    task.defer(updateGridLayout)

    ----------------------------------------------------------------
    -- drag logic
    ----------------------------------------------------------------
    do
        local dragging, dragStart, startPos
        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                dragging  = true
                dragStart = input.Position
                startPos  = mainFrame.Position
            end
        end)
        titleBar.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                dragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (
                    input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch
                ) then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)
    end

    local function closeGui()
        gui:Destroy()
    end

    closeButton.MouseButton1Click:Connect(closeGui)

    ----------------------------------------------------------------
    -- Card helpers
    ----------------------------------------------------------------
    local function makeToggleButton(parent, initialEnabled, rarityName, onChanged)
        local btn = Instance.new("TextButton")
        btn.AnchorPoint = Vector2.new(1, 0.5)
        btn.Position = UDim2.new(1, -8, 0.5, 0)
        btn.Size = UDim2.new(0, 50, 0, 24)
        btn.BorderSizePixel = 0
        btn.ZIndex = 4
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.AutoButtonColor = false
        btn.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = btn

        local function applyState(enabled)
            if enabled then
                btn.Text = "ON"
                btn.BackgroundColor3 = rarityName and RarityColors[rarityName] or Color3.fromRGB(90, 200, 120)
            else
                btn.Text = "OFF"
                btn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
            end
        end

        applyState(initialEnabled)

        btn.MouseButton1Click:Connect(function()
            local enabled = (btn.Text ~= "ON")
            applyState(enabled)
            onChanged(enabled)
        end)

        return btn
    end

    -- item card (ores/essences/runes)
    local function createItemCard(labelText, initialEnabled, initialThreshold, onChanged, iconTemplate, rarityName,
                                  iconImageId)
        local card = Instance.new("Frame")
        card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        card.BorderSizePixel = 0
        card.ZIndex = 2

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Transparency = 0.35
        stroke.Color = rarityName and (RarityColors[rarityName] or Color3.fromRGB(70, 70, 90)) or
            Color3.fromRGB(70, 70, 90)
        stroke.Parent = card

        local grad = Instance.new("UIGradient")
        local base1 = Color3.fromRGB(26, 26, 36)
        local base2 = Color3.fromRGB(16, 16, 24)
        if rarityName and RarityColors[rarityName] then
            local tint = RarityColors[rarityName]
            base1 = Color3.new(
                (base1.R + tint.R) / 2,
                (base1.G + tint.G) / 2,
                (base1.B + tint.B) / 2
            )
        end
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, base1),
            ColorSequenceKeypoint.new(1, base2),
        })
        grad.Rotation = 90
        grad.Parent = card

        -- icon holder
        local iconHolder = Instance.new("Frame")
        iconHolder.AnchorPoint = Vector2.new(0, 0.5)
        iconHolder.Size = UDim2.new(0, 38, 0, 38)
        iconHolder.Position = UDim2.new(0, 8, 0.5, 0)
        iconHolder.BackgroundTransparency = 1
        iconHolder.ZIndex = 3
        iconHolder.Parent = card

        local iconBG = Instance.new("Frame")
        iconBG.Size = UDim2.new(1, 0, 1, 0)
        iconBG.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
        iconBG.BorderSizePixel = 0
        iconBG.ZIndex = 3
        iconBG.Parent = iconHolder

        local iconCorner = Instance.new("UICorner")
        iconCorner.CornerRadius = UDim.new(0, 6)
        iconCorner.Parent = iconBG

        local iconStroke = Instance.new("UIStroke")
        iconStroke.Color = stroke.Color
        iconStroke.Transparency = 0.25
        iconStroke.Thickness = 1
        iconStroke.Parent = iconBG

        local icon

        if iconTemplate then
            icon = iconTemplate:Clone()
            icon.Size = UDim2.fromScale(1, 1)
            icon.Position = UDim2.new(0, 0, 0, 0)
            icon.AnchorPoint = Vector2.new(0, 0)
            icon.BackgroundTransparency = 1
            icon.BorderSizePixel = 0
            icon.ZIndex = 4
            icon.Parent = iconBG
            
            -- If the template had a camera, it was cloned too.
            -- We just need to make sure the ViewportFrame uses it.
            local cam = icon:FindFirstChildOfClass("Camera")
            if cam then
                icon.CurrentCamera = cam
            end

        elseif iconImageId then
            icon = Instance.new("ImageLabel")
            icon.Size = UDim2.fromScale(1, 1)
            icon.Position = UDim2.new(0, 0, 0, 0)
            icon.AnchorPoint = Vector2.new(0, 0)
            icon.BackgroundTransparency = 1
            icon.BorderSizePixel = 0
            icon.Image = "rbxassetid://" .. iconImageId
            icon.ScaleType = Enum.ScaleType.Fit
            icon.ZIndex = 4
            icon.Parent = iconBG
        end

        -- name
        local nameLabel                  = Instance.new("TextLabel")
        nameLabel.Position               = UDim2.new(0, 54, 0, 0)
        nameLabel.Size                   = UDim2.new(1, -120, 1, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font                   = Enum.Font.GothamSemibold
        nameLabel.TextSize               = 13
        nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
        nameLabel.TextYAlignment         = Enum.TextYAlignment.Center
        nameLabel.TextColor3             = Color3.fromRGB(235, 235, 245)
        nameLabel.TextTruncate           = Enum.TextTruncate.AtEnd
        nameLabel.Text                   = labelText
        nameLabel.ZIndex                 = 4
        nameLabel.Parent                 = card

        local enabledState               = initialEnabled
        local currentThreshold           = initialThreshold or 0

        makeToggleButton(card, enabledState, rarityName, function(enabled)
            enabledState = enabled
            onChanged(enabledState, currentThreshold)
        end)

        local thresholdBox = Instance.new("TextBox")
        thresholdBox.AnchorPoint = Vector2.new(1, 0.5)
        thresholdBox.Size = UDim2.new(0, 44, 0, 24)
        thresholdBox.Position = UDim2.new(1, -64, 0.5, 0)
        thresholdBox.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        thresholdBox.BorderSizePixel = 0
        thresholdBox.Font = Enum.Font.Gotham
        thresholdBox.TextSize = 12
        thresholdBox.TextColor3 = Color3.fromRGB(255, 255, 255)
        thresholdBox.Text = tostring(initialThreshold or 0)
        thresholdBox.PlaceholderText = "0"
        thresholdBox.ClearTextOnFocus = false
        thresholdBox.ZIndex = 4
        thresholdBox.Parent = card

        local thCorner = Instance.new("UICorner")
        thCorner.CornerRadius = UDim.new(0, 6)
        thCorner.Parent = thresholdBox

        local function updateCallback()
            local txt = thresholdBox.Text:gsub("%D", "")
            local num = tonumber(txt) or 0
            num = math.clamp(num, 0, 999)
            thresholdBox.Text = tostring(num)
            currentThreshold = num
            onChanged(enabledState, currentThreshold)
        end

        thresholdBox.FocusLost:Connect(updateCallback)

        card.MouseEnter:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(26, 26, 36)
        end)
        card.MouseLeave:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        end)

        return card
    end

    local function createRarityCard(labelText, initialEnabled, onChanged, rarityName)
        local card = Instance.new("Frame")
        card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        card.BorderSizePixel = 0
        card.ZIndex = 2

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Transparency = 0.35
        stroke.Color = rarityName and (RarityColors[rarityName] or Color3.fromRGB(70, 70, 90)) or
            Color3.fromRGB(70, 70, 90)
        stroke.Parent = card

        local grad = Instance.new("UIGradient")
        local base1 = Color3.fromRGB(28, 28, 38)
        local base2 = Color3.fromRGB(16, 16, 24)
        if rarityName and RarityColors[rarityName] then
            local tint = RarityColors[rarityName]
            base1 = Color3.new(
                (base1.R + tint.R) / 2,
                (base1.G + tint.G) / 2,
                (base1.B + tint.B) / 2
            )
        end
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, base1),
            ColorSequenceKeypoint.new(1, base2),
        })
        grad.Rotation = 90
        grad.Parent = card

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Position = UDim2.new(0, 14, 0, 0)
        nameLabel.Size = UDim2.new(1, -70, 1, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextSize = 14
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextYAlignment = Enum.TextYAlignment.Center
        nameLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
        nameLabel.Text = labelText
        nameLabel.ZIndex = 4
        nameLabel.Parent = card

        local enabledState = initialEnabled
        makeToggleButton(card, enabledState, rarityName, function(enabled)
            enabledState = enabled
            onChanged(enabledState)
        end)

        card.MouseEnter:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(26, 26, 36)
        end)
        card.MouseLeave:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        end)

        return card
    end

    ----------------------------------------------------------------
    -- TRAIT CARD
    ----------------------------------------------------------------
    local function createTraitCard(traitDef, rule, onChanged)
        local traitId    = traitDef.id
        local statOrder  = RuneTraitStatOrder[traitId] or {}
        local paramCount = #statOrder

        -- fallback: if we somehow didn't get stats from the game, fall back to "nil" count
        if paramCount == 0 then
            paramCount = countNilPlaceholders(traitDef.description or "")
        end

        rule = rule or {}
        rule.enabled = rule.enabled == true
        rule.params = rule.params or {}

        for i = 1, paramCount do
            rule.params[i] = rule.params[i] or { value = 0, direction = "above" }
            if rule.params[i].direction ~= "below" then
                rule.params[i].direction = "above"
            end
            if type(rule.params[i].value) ~= "number" then
                rule.params[i].value = 0
            end
        end

        local card = Instance.new("Frame")
        card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        card.BorderSizePixel = 0
        card.ZIndex = 2

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Transparency = 0.35
        stroke.Color = Color3.fromRGB(90, 90, 130)
        stroke.Parent = card

        local grad = Instance.new("UIGradient")
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 44)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 16, 26)),
        })
        grad.Rotation = 90
        grad.Parent = card

        local topRow = Instance.new("Frame")
        topRow.BackgroundTransparency = 1
        topRow.Size = UDim2.new(1, -8, 0, 40)
        topRow.Position = UDim2.new(0, 4, 0, 2)
        topRow.ZIndex = 3
        topRow.Parent = card

        local iconHolder = Instance.new("Frame")
        iconHolder.AnchorPoint = Vector2.new(0, 0.5)
        iconHolder.Size = UDim2.new(0, 34, 0, 34)
        iconHolder.Position = UDim2.new(0, 4, 0.5, 0)
        iconHolder.BackgroundTransparency = 1
        iconHolder.ZIndex = 3
        iconHolder.Parent = topRow

        local iconBG = Instance.new("Frame")
        iconBG.Size = UDim2.new(1, 0, 1, 0)
        iconBG.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
        iconBG.BorderSizePixel = 0
        iconBG.ZIndex = 3
        iconBG.Parent = iconHolder

        local iconCorner = Instance.new("UICorner")
        iconCorner.CornerRadius = UDim.new(0, 6)
        iconCorner.Parent = iconBG

        local iconStroke = Instance.new("UIStroke")
        iconStroke.Color = stroke.Color
        iconStroke.Transparency = 0.25
        iconStroke.Thickness = 1
        iconStroke.Parent = iconBG

        local icon = Instance.new("ImageLabel")
        icon.Size = UDim2.fromScale(1, 1)
        icon.Position = UDim2.new(0, 0, 0, 0)
        icon.AnchorPoint = Vector2.new(0, 0)
        icon.BackgroundTransparency = 1
        icon.BorderSizePixel = 0
        icon.Image = "rbxassetid://" .. tostring(traitDef.iconImageId or "")
        icon.ScaleType = Enum.ScaleType.Fit
        icon.ZIndex = 4
        icon.Parent = iconBG

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Position = UDim2.new(0, 46, 0, 0)
        nameLabel.Size = UDim2.new(1, -140, 1, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextSize = 13
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextYAlignment = Enum.TextYAlignment.Center
        nameLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Text = traitDef.name or traitDef.id
        nameLabel.ZIndex = 4
        nameLabel.Parent = topRow

        local enabledState = rule.enabled
        local params = rule.params

        makeToggleButton(topRow, enabledState, nil, function(enabled)
            enabledState = enabled
            onChanged(enabledState, params)
        end)

        local paramContainer = Instance.new("Frame")
        paramContainer.BackgroundTransparency = 1
        paramContainer.Position = UDim2.new(0, 8, 0, 44)
        paramContainer.Size = UDim2.new(1, -16, 1, -50)
        paramContainer.ZIndex = 3
        paramContainer.Parent = card -- <--- THIS WAS THE FIX

        local paramLayout = Instance.new("UIListLayout")
        paramLayout.FillDirection = Enum.FillDirection.Vertical
        paramLayout.Padding = UDim.new(0, 4)
        paramLayout.SortOrder = Enum.SortOrder.LayoutOrder
        paramLayout.Parent = paramContainer

        local function applyDirection(btn, dir)
            if dir == "below" then
                btn.Text = "▼"
                btn.BackgroundColor3 = Color3.fromRGB(200, 90, 90)
            else
                btn.Text = "▲"
                btn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
            end
        end

        local function commit()
            onChanged(enabledState, params)
        end

        local overrideLabels = RuneTraitParamLabels[traitId]

        for i = 1, paramCount do
            local p = params[i]
            local statName = statOrder[i] -- may be nil if we fell back to nil-count

            local row = Instance.new("Frame")
            row.BackgroundTransparency = 1
            row.Size = UDim2.new(1, 0, 0, 22)
            row.ZIndex = 3
            row.Parent = paramContainer

            local label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.Position = UDim2.new(0, 0, 0, 0)
            label.Size = UDim2.new(0, 140, 1, 0)
            label.Font = Enum.Font.Gotham
            label.TextSize = 11
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.TextColor3 = Color3.fromRGB(180, 180, 200)

            local labelText

            if statName and statName ~= "" then
                labelText = statName
            else
                if type(overrideLabels) == "table" then
                    labelText = overrideLabels[statName] or overrideLabels[i]
                end
                if not labelText then
                    labelText = "Stat " .. i
                end
            end

            label.Text = labelText
            label.ZIndex = 4
            label.Parent = row

            local valueBox = Instance.new("TextBox")
            valueBox.AnchorPoint = Vector2.new(1, 0.5)
            valueBox.Size = UDim2.new(0, 48, 0, 20)
            valueBox.Position = UDim2.new(1, -4, 0.5, 0)
            valueBox.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
            valueBox.BorderSizePixel = 0
            valueBox.Font = Enum.Font.Gotham
            valueBox.TextSize = 11
            valueBox.TextColor3 = Color3.fromRGB(255, 255, 255)
            valueBox.Text = tostring(p.value or 0)
            valueBox.PlaceholderText = "0"
            valueBox.ClearTextOnFocus = false
            valueBox.ZIndex = 4
            valueBox.Parent = row

            local vbCorner = Instance.new("UICorner")
            vbCorner.CornerRadius = UDim.new(0, 5)
            vbCorner.Parent = valueBox

            local dirButton = Instance.new("TextButton")
            dirButton.AnchorPoint = Vector2.new(1, 0.5)
            dirButton.Size = UDim2.new(0, 24, 0, 20)
            dirButton.Position = UDim2.new(1, -54, 0.5, 0)
            dirButton.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
            dirButton.BorderSizePixel = 0
            dirButton.Font = Enum.Font.GothamBold
            dirButton.TextSize = 13
            dirButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            dirButton.AutoButtonColor = false
            dirButton.ZIndex = 4
            dirButton.Parent = row

            local dbCorner = Instance.new("UICorner")
            dbCorner.CornerRadius = UDim.new(0, 5)
            dbCorner.Parent = dirButton

            applyDirection(dirButton, p.direction)

            dirButton.MouseButton1Click:Connect(function()
                if p.direction == "below" then
                    p.direction = "above"
                else
                    p.direction = "below"
                end
                applyDirection(dirButton, p.direction)
                commit()
            end)

            valueBox.FocusLost:Connect(function()
                local txt = valueBox.Text:gsub("%D", "")
                local num = tonumber(txt) or 0
                num = math.clamp(num, 0, 9999)
                valueBox.Text = tostring(num)
                p.value = num
                commit()
            end)
        end

        card.MouseEnter:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(26, 26, 38)
        end)
        card.MouseLeave:Connect(function()
            card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        end)

        commit()

        return card
    end

    ----------------------------------------------------------------
    -- Tabs + Search integration
    ----------------------------------------------------------------
    local currentTab = nil
    local tabButtons = {}
    local currentSearchText = ""

    local function matchesSearch(name)
        if currentSearchText == "" then
            return true
        end
        name = string.lower(name or "")
        return string.find(name, currentSearchText, 1, true) ~= nil
    end

    local function clearCards()
        for _, child in ipairs(scroll:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
    end

    local function populateTab()
        if not currentTab then return end

        clearCards()

        if currentTab == "Ores" then
            for _, oreName in ipairs(OreNamesList) do
                if matchesSearch(oreName) then
                    local rule = Config.ores[oreName] or { enabled = false, threshold = 0 }
                    local iconTemplate = getOreIconTemplate(oreName)
                    local rarityName = OreRarityMap[oreName]

                    local card = createItemCard(
                        oreName,
                        rule.enabled,
                        rule.threshold or 0,
                        function(enabled, threshold)
                            Config.ores[oreName] = { enabled = enabled, threshold = threshold }
                            saveConfig()
                        end,
                        iconTemplate,
                        rarityName
                    )

                    card.Parent = scroll
                end
            end
        elseif currentTab == "Ore Rarities" then
            for _, rName in ipairs(OreRarityList) do
                if matchesSearch(rName) then
                    local rule = Config.oreRarities[rName] or { enabled = false, threshold = 0 }

                    local card = createRarityCard(
                        rName,
                        rule.enabled,
                        function(enabled)
                            Config.oreRarities[rName] = { enabled = enabled, threshold = 0 }
                            saveConfig()
                        end,
                        rName
                    )

                    card.Parent = scroll
                end
            end
        elseif currentTab == "Essence" then
            for _, essName in ipairs(EssenceNamesList) do
                if matchesSearch(essName) then
                    local rule = Config.essence[essName] or { enabled = false, threshold = 0 }
                    local rarityName = EssenceRarityMap[essName]
                    local imageId = EssenceImageIds[essName]

                    local card = createItemCard(
                        essName,
                        rule.enabled,
                        rule.threshold or 0,
                        function(enabled, threshold)
                            Config.essence[essName] = { enabled = enabled, threshold = threshold }
                            saveConfig()
                        end,
                        nil,
                        rarityName,
                        imageId
                    )

                    card.Parent = scroll
                end
            end
        elseif currentTab == "Essence Rarities" then
            for _, rName in ipairs(EssenceRarityList) do
                if matchesSearch(rName) then
                    local rule = Config.essenceRarities[rName] or { enabled = false, threshold = 0 }

                    local card = createRarityCard(
                        rName,
                        rule.enabled,
                        function(enabled)
                            Config.essenceRarities[rName] = { enabled = enabled, threshold = 0 }
                            saveConfig()
                        end,
                        rName
                    )

                    card.Parent = scroll
                end
            end
        elseif currentTab == "Runes" then
            for _, runeName in ipairs(RuneValues) do
                if matchesSearch(runeName) then
                    local rule = Config.runes[runeName] or { enabled = false, threshold = 0 }
                    local imageId = RuneImageIds[runeName]

                    local card = createItemCard(
                        runeName,
                        rule.enabled,
                        rule.threshold or 0,
                        function(enabled, threshold)
                            Config.runes[runeName] = { enabled = enabled, threshold = threshold }
                            saveConfig()
                        end,
                        nil,
                        "Rare",
                        imageId
                    )

                    card.Parent = scroll
                end
            end
        elseif currentTab == "Rune Traits" then
            for _, traitDef in ipairs(RuneTraitDefinitions) do
                local nameToMatch = (traitDef.name or traitDef.id or "")
                if matchesSearch(nameToMatch) then
                    local existingRule = Config.runeTraits[traitDef.id] or { enabled = false, params = {} }
                    local card = createTraitCard(
                        traitDef,
                        existingRule,
                        function(enabled, params)
                            Config.runeTraits[traitDef.id] = {
                                enabled = enabled,
                                params = params,
                            }
                            saveConfig()
                        end
                    )
                    card.Parent = scroll
                end
            end
        end

        task.defer(updateGridLayout)
    end

    local function setTab(name)
        currentTab = name
        for tabName, btn in pairs(tabButtons) do
            btn.BackgroundColor3 = (tabName == name) and Color3.fromRGB(70, 70, 110) or Color3.fromRGB(35, 35, 50)
        end

        if name == "Rune Traits" then
            currentCellHeight = 130
        else
            currentCellHeight = 55
        end
        updateGridLayout()

        populateTab()
    end

    local function makeTabButton(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 120, 1, 0)
        btn.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 13
        btn.TextColor3 = Color3.fromRGB(225, 225, 235)
        btn.Text = name
        btn.ZIndex = 3
        btn.Parent = tabBar

        local bCorner = Instance.new("UICorner")
        bCorner.CornerRadius = UDim.new(0, 6)
        bCorner.Parent = btn

        btn.MouseButton1Click:Connect(function()
            setTab(name)
        end)

        tabButtons[name] = btn
    end

    makeTabButton("Ores")
    makeTabButton("Ore Rarities")
    makeTabButton("Essence")
    makeTabButton("Essence Rarities")
    makeTabButton("Runes")
    makeTabButton("Rune Traits")

    -- Search integration: update currentSearchText and repopulate current tab
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        currentSearchText = string.lower(searchBox.Text or "")
        populateTab()
    end)

    setTab("Ores")

    return gui
end

-- Expose to main script
getgenv().OpenAutoSellConfig = function()
    createUI()
end

-- Auto-open when running standalone
createUI()
