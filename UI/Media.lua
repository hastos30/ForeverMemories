-- UI/Media.lua
-- Textures and fonts that ship with the addon (Media/, v0.15.0). The art
-- is the approved "Obsidian Journal" set by Nedisan. Paths are built here only, so a test can check
-- that every referenced file exists. All TGA files are power-of-two and
-- saved WITHOUT RLE compression (the safest format for the client).
-- Nothing here proves the client loads them: see docs/TESTING.md.
local _, ns = ...

local Media = {}
ns.Media = Media

Media.ROOT = "Interface\\AddOns\\ForeverMemories\\Media\\"

-- Relative path ("Branding/compass_emblem.tga") -> client path.
function Media.Path(relative)
    return Media.ROOT .. string.gsub(relative, "/", "\\")
end

local referenced = {}
local function file(relative)
    referenced[#referenced + 1] = relative
    return Media.Path(relative)
end

Media.COMPASS = file("Branding/compass_emblem.tga")
Media.LOGO = file("Branding/logo_full.tga")               -- 512x256, About only
Media.MINIMAP = file("Branding/minimap_icon_32.tga")
Media.MINIMAP_48 = file("Branding/minimap_icon_48.tga")    -- 48 px shown from a 64 px texture
Media.MINIMAP_64 = file("Branding/minimap_icon_64.tga")
Media.BACKGROUND = file("Backgrounds/background_obsidian.tga")

-- Navigation icons (12). Overview and the other Settings pages use text.
Media.NAV = {}
for _, name in ipairs({ "home", "auto_capture", "history", "settings", "screenshots", "steps",
                        "locations", "playtime", "chronicle", "records", "achievements", "account" }) do
    Media.NAV[name] = file("Icons/" .. name .. ".tga")
end

-- Achievement medallions (11 categories) and rarity frames (4).
Media.MEDALLIONS = {}
for _, name in ipairs({ "memories", "steps", "travel", "locations", "time", "combat",
                        "chronicle", "social", "special", "records", "legacy" }) do
    Media.MEDALLIONS[name] = file("Achievements/Medallions/" .. name .. ".tga")
end
Media.FRAMES = {}
for _, rarity in ipairs({ "common", "rare", "epic", "legendary" }) do
    Media.FRAMES[rarity] = file("Achievements/Frames/" .. rarity .. ".tga")
end

Media.DECOR = {}
for _, name in ipairs({ "accent_diamond", "accent_star", "checkbox_off", "checkbox_on", "corner_large",
                        "divider_compass", "divider_diamond", "divider_knot", "divider_small",
                        "divider_triple", "laurels", "parchment_card", "parchment_fold", "radio_off",
                        "radio_on", "toggle_off", "toggle_on" }) do
    Media.DECOR[name] = file("Decorations/" .. name .. ".tga")
end

-- v1.0.1: crops of the divider accents used as small icons (left, right,
-- top, bottom): the star and the diamond without their gold lines.
Media.CROP = {
    star = { 0.37, 0.65, 0.12, 0.88 },
    diamond = { 0.155, 0.57, 0.29, 0.71 },
}

-- Notification pack: modular parts (Discovery / Legendary frames are
-- temporary 9-slice borders until the final art exists).
Media.NOTIFY = {}
for _, name in ipairs({ "mini_frame", "mini_back", "mini_border_9slice", "discovery_border_9slice", "discovery_compass",
                        "legendary_border_9slice", "legendary_gem", "laurel_left", "laurel_right",
                        "golden_glow", "golden_particles", "event_success", "event_warning", "event_error",
                        "event_flag", "event_location", "event_loot" }) do
    Media.NOTIFY[name] = file("Notifications/" .. name .. ".tga")
end

-- v1.0.0-beta.8: our icons for the places that used game icons (cards,
-- Records, Settings menu, capture groups). One table, so the whole window
-- uses one set of art. Keys are meanings, not files.
Media.ICON = {
    shots = Media.NAV.screenshots, camera = Media.NAV.auto_capture, steps = Media.NAV.steps,
    zones = Media.NAV.locations, newZones = Media.NOTIFY.event_location, playtime = Media.NAV.playtime,
    sessions = Media.NAV.playtime, days = Media.NAV.chronicle, calendar = Media.NAV.chronicle,
    records = Media.NAV.records, achievements = Media.NAV.achievements, account = Media.NAV.account,
    history = Media.NAV.history, settings = Media.NAV.settings, home = Media.NAV.home,
    compass = Media.COMPASS, flag = Media.NOTIFY.event_flag, loot = Media.NOTIFY.event_loot,
    success = Media.NOTIFY.event_success, warning = Media.NOTIFY.event_warning,
}

-- True for a texture that ships with the addon (no game-icon border to crop).
function Media.IsOwn(texture)
    return type(texture) == "string" and string.find(texture, Media.ROOT, 1, true) == 1
end

Media.FONTS = {
    title = file("Fonts/CormorantGaramond-SemiBold.ttf"),
    body = file("Fonts/Inter-Regular.ttf"),
    bold = file("Fonts/Inter-SemiBold.ttf"),
}

-- Every file this module references (relative to Media/), for tests.
function Media.Referenced()
    return referenced
end
