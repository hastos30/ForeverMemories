-- Core/Registry.lua
-- Description of every trigger (SPECIFICATION.md section 2) and whether
-- this client can support it. Defaults here are the "Adventurer" values.
local _, ns = ...

local Registry = {}
ns.Registry = Registry

Registry.DEDUPE_WINDOW = 10   -- seconds, same event key
Registry.DEFAULT_INTERVAL = 2 -- seconds between series cycles
Registry.MODES = { "normal", "clean", "dual" }

-- category is used to group triggers in the UI.
-- unsupported = reason key when no reliable data source exists in Forever.
Registry.TRIGGERS = {
    { id = "LEVEL", category = "progress", enabled = true, delay = 0.2, frames = 2, mode = "clean", priority = 2 },
    { id = "MAX_LEVEL", category = "progress", enabled = true, delay = 0.2, frames = 3, mode = "clean", priority = 1 },
    { id = "ZONE", category = "world", enabled = true, delay = 2, frames = 1, mode = "clean", priority = 3 },
    { id = "BOSS", category = "combat", enabled = true, delay = 1, frames = 2, mode = "normal", priority = 2 },
    { id = "LOOT_EPIC", category = "loot", enabled = true, delay = 0.5, frames = 1, mode = "normal", priority = 2 },
    { id = "LOOT_LEGENDARY", category = "loot", enabled = true, delay = 0.5, frames = 1, mode = "normal", priority = 1 },
    { id = "MOUNT", category = "loot", enabled = true, delay = 1, frames = 1, mode = "normal", priority = 2 },
    { id = "RARE", category = "combat", enabled = false, delay = 1, frames = 1, mode = "normal", priority = 2,
      unsupported = "REASON_NO_COMBAT_LOG" },
    { id = "DUNGEON", category = "combat", enabled = false, delay = 1, frames = 1, mode = "normal", priority = 2 },
    { id = "REPUTATION", category = "progress", enabled = false, delay = 0.5, frames = 1, mode = "normal", priority = 3,
      unsupported = "REASON_NOT_VERIFIED" },
    { id = "DUEL", category = "combat", enabled = false, delay = 1, frames = 1, mode = "normal", priority = 3 },
    { id = "BG", category = "combat", enabled = false, delay = 1, frames = 1, mode = "normal", priority = 2,
      unsupported = "REASON_NOT_VERIFIED" },
    { id = "DEATH", category = "combat", enabled = false, delay = 1, frames = 1, mode = "normal", priority = 3 },
    { id = "PROFESSION", category = "progress", enabled = false, delay = 1, frames = 1, mode = "normal", priority = 3,
      unsupported = "REASON_NOT_VERIFIED" },
    { id = "QUEST", category = "progress", enabled = false, delay = 1, frames = 1, mode = "normal", priority = 3 },
    { id = "GUILD", category = "social", enabled = false, delay = 1, frames = 1, mode = "normal", priority = 3 },
    { id = "FORM", category = "progress", enabled = false, delay = 1, frames = 1, mode = "normal", priority = 3 },
    { id = "JOURNEY", category = "world", enabled = false, delay = 0, frames = 1, mode = "clean", priority = 4 },
    { id = "RANDOM", category = "world", enabled = false, delay = 0, frames = 1, mode = "clean", priority = 4 },
    { id = "MANUAL", category = "manual", enabled = true, delay = 0, frames = 1, mode = "normal", priority = 0 },
}

Registry.byId = {}
for _, trigger in ipairs(Registry.TRIGGERS) do
    trigger.interval = Registry.DEFAULT_INTERVAL
    trigger.cooldown = trigger.id == "MANUAL" and 0 or Registry.DEDUPE_WINDOW
    trigger.firstOnly = false
    Registry.byId[trigger.id] = trigger
end

-- Editable rule fields with their limits (UI_DESIGN.md, "События").
Registry.FIELDS = {
    delay = { min = 0, max = 10, step = 0.5 },
    frames = { min = 1, max = 5, step = 1 },
    interval = { min = 1, max = 10, step = 1 },
    priority = { min = 1, max = 4, step = 1 },
    cooldown = { min = 0, max = 120, step = 5 },
}

-- Runtime availability, filled by Events when it registers client events.
local status = {}

function Registry.SetStatus(id, available, reason)
    status[id] = { available = available, reason = reason }
end

-- Returns available (bool) and a reason key/text when unavailable.
function Registry.Status(id)
    local trigger = Registry.byId[id]
    if trigger and trigger.unsupported then
        return false, trigger.unsupported
    end
    local s = status[id]
    if not s then
        return true
    end
    return s.available, s.reason
end

function Registry.IsAvailable(id)
    return (Registry.Status(id))
end

-- The rule a fresh profile gets for a trigger.
function Registry.DefaultRule(id)
    local t = Registry.byId[id]
    return {
        enabled = t.enabled and not t.unsupported,
        delay = t.delay, frames = t.frames, interval = t.interval,
        mode = t.mode, priority = t.priority, cooldown = t.cooldown,
        firstOnly = t.firstOnly,
    }
end
