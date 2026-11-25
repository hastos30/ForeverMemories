-- Core/Registry.lua
-- The nine approved game events (spec v0.5.0, section 5), the manual
-- shot and the passive (timed) shot. Delay and priority are internal: the player never sees or edits
-- them. Lower priority number = more important.
local _, ns = ...

local Registry = {}
ns.Registry = Registry

Registry.DEDUPE_WINDOW = 10 -- seconds: the same event key gives one shot

-- Order of the list on the "Auto capture" tab.
Registry.EVENTS = {
    "LEVEL", "DEATH", "BOSS", "DUEL", "LOOT_RARE", "LOOT_EPIC", "LOOT_LEGENDARY", "ZONE", "GUILD",
}

-- delay: seconds after the event (lets the effect appear on screen).
Registry.TRIGGERS = {
    LEVEL = { delay = 0.5, priority = 2, icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight" },
    DEATH = { delay = 1, priority = 3, icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" },
    BOSS = { delay = 1.5, priority = 1, icon = "Interface\\Icons\\Ability_DualWield" },
    DUEL = { delay = 1, priority = 3, icon = "Interface\\Icons\\Ability_Parry" },
    LOOT_RARE = { delay = 0.5, priority = 3, icon = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02", quality = 3 },
    LOOT_EPIC = { delay = 0.5, priority = 2, icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02", quality = 4 },
    LOOT_LEGENDARY = { delay = 0.5, priority = 1, icon = "Interface\\Icons\\INV_Misc_Gem_Topaz_02", quality = 5 },
    ZONE = { delay = 2, priority = 3, icon = "Interface\\AddOns\\ForeverMemories\\Media\\Notifications\\event_location.tga" },
    GUILD = { delay = 1, priority = 3, icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
    MANUAL = { delay = 0, priority = 0, icon = "Interface\\AddOns\\ForeverMemories\\Media\\Icons\\auto_capture.tga" },
    -- Passive capture (v0.6.0): a timer, not a game event. Its own switch
    -- (settings.passive), lowest priority, not in the EVENTS list.
    PASSIVE = { delay = 1, priority = 4, icon = "Interface\\AddOns\\ForeverMemories\\Media\\Icons\\playtime.tga", passive = true },
}

-- Icon for records of event types from older versions (kept in history).
Registry.LEGACY_ICON = "Interface\\AddOns\\ForeverMemories\\Media\\Icons\\screenshots.tga"

function Registry.Icon(id)
    local trigger = Registry.TRIGGERS[id]
    return trigger and trigger.icon or Registry.LEGACY_ICON
end

-- Runtime availability, filled by Events when it registers client events.
local status = {}

function Registry.SetStatus(id, available, reason)
    status[id] = { available = available, reason = reason }
end

-- Returns available (bool) and a reason when unavailable.
function Registry.Status(id)
    local s = status[id]
    if not s then
        return true
    end
    return s.available, s.reason
end

function Registry.IsAvailable(id)
    return (Registry.Status(id))
end
