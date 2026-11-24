-- Modules/Profiles.lua
-- Presets are built in and read-only. Editing a preset creates the "Custom"
-- profile from it. A profile can be used by all characters (default) or
-- by one character (override).
--
-- A resolved profile is a full copy: { rules = {...}, limits = {...},
-- journey = {...} }. Requests copy what they need, so changing settings
-- never affects a capture that is already running.
local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles

Profiles.DEFAULT_LIMITS = { perHour = 60, perSession = 300, journeyPerHour = 12 }
Profiles.DEFAULT_JOURNEY = { interval = 10, randomMin = 5, randomMax = 30, moveThreshold = 0.05 }
Profiles.LIMIT_FIELDS = {
    perHour = { min = 1, max = 200, step = 5 },
    perSession = { min = 10, max = 1000, step = 10 },
    journeyPerHour = { min = 1, max = 12, step = 1 },
}
Profiles.JOURNEY_FIELDS = {
    interval = { min = 5, max = 60, step = 5 },
    randomMin = { min = 5, max = 30, step = 1 },
    randomMax = { min = 5, max = 30, step = 1 },
    moveThreshold = { min = 0, max = 0.2, step = 0.01 },
}

Profiles.PRESET_ORDER = { "Minimalist", "Explorer", "Adventurer", "Cinematic", "Archivist" }

local function allSupported(fields)
    local rules = {}
    for _, trigger in ipairs(ns.Registry.TRIGGERS) do
        if not trigger.unsupported and trigger.id ~= "JOURNEY" and trigger.id ~= "RANDOM" then
            rules[trigger.id] = ns.Util.Copy(fields)
        end
    end
    return rules
end

-- Only differences from the Adventurer defaults (Registry).
Profiles.PRESETS = {
    Minimalist = {
        rules = {
            ZONE = { enabled = false }, BOSS = { enabled = false },
            LOOT_EPIC = { enabled = false }, LOOT_LEGENDARY = { enabled = false },
            MOUNT = { enabled = false }, LEVEL = { frames = 1 }, MAX_LEVEL = { frames = 1 },
        },
    },
    Explorer = {
        rules = { ZONE = { frames = 2 }, JOURNEY = { enabled = true } },
        journey = { interval = 15 },
    },
    Adventurer = {},
    Cinematic = {
        rules = {
            LEVEL = { mode = "dual" }, MAX_LEVEL = { mode = "dual" },
            ZONE = { mode = "dual" }, BOSS = { frames = 3 },
        },
    },
    Archivist = {
        rules = allSupported({ enabled = true }),
        journey = { interval = 10 },
    },
}

function Profiles.IsPreset(name)
    return Profiles.PRESETS[name] ~= nil
end

function Profiles.Exists(name)
    return Profiles.IsPreset(name) or (ns.db and ns.db.profiles[name] ~= nil)
end

-- All profile names: presets first, then custom ones sorted.
function Profiles.List()
    local names = {}
    for _, name in ipairs(Profiles.PRESET_ORDER) do
        names[#names + 1] = name
    end
    for _, name in ipairs(ns.Util.SortedKeys(ns.db.profiles)) do
        names[#names + 1] = name
    end
    return names
end

function Profiles.ActiveName()
    local name = ns.character and ns.character.profile or ns.db.settings.defaultProfile
    if not Profiles.Exists(name) then
        name = "Adventurer"
    end
    return name
end

function Profiles.IsCharacterOverride()
    return ns.character ~= nil and ns.character.profile ~= nil
end

local function clampRule(id, rule)
    local defaults = ns.Registry.DefaultRule(id)
    for field, spec in pairs(ns.Registry.FIELDS) do
        rule[field] = ns.Util.Clamp(rule[field], spec.min, spec.max, defaults[field])
    end
    if id == "MANUAL" then
        rule.priority = 0
    end
    if not ns.Util.Contains(ns.Registry.MODES, rule.mode) then
        rule.mode = defaults.mode
    end
    rule.enabled = rule.enabled == true and ns.Registry.IsAvailable(id)
    rule.firstOnly = rule.firstOnly == true
    return rule
end

local function clampGroup(group, fields, defaults)
    for field, spec in pairs(fields) do
        group[field] = ns.Util.Clamp(group[field], spec.min, spec.max, defaults[field])
    end
    return group
end

-- Builds a full resolved profile by name (pure apart from reading ns.db).
function Profiles.Resolve(name)
    local result = { rules = {}, limits = ns.Util.Copy(Profiles.DEFAULT_LIMITS),
                     journey = ns.Util.Copy(Profiles.DEFAULT_JOURNEY) }
    for _, trigger in ipairs(ns.Registry.TRIGGERS) do
        result.rules[trigger.id] = ns.Registry.DefaultRule(trigger.id)
    end
    local custom = ns.db and ns.db.profiles[name]
    local preset = Profiles.PRESETS[name] or (custom and Profiles.PRESETS[custom.base]) or {}
    ns.Util.Overlay(result, ns.Util.Copy(preset))
    if custom then
        ns.Util.Overlay(result, { rules = custom.rules, limits = custom.limits, journey = custom.journey })
    end
    for id, rule in pairs(result.rules) do
        if ns.Registry.byId[id] then
            clampRule(id, rule)
        else
            result.rules[id] = nil
        end
    end
    clampGroup(result.limits, Profiles.LIMIT_FIELDS, Profiles.DEFAULT_LIMITS)
    clampGroup(result.journey, Profiles.JOURNEY_FIELDS, Profiles.DEFAULT_JOURNEY)
    if result.journey.randomMax < result.journey.randomMin then
        result.journey.randomMax = result.journey.randomMin
    end
    return result
end

local cache = nil

function Profiles.Invalidate()
    cache = nil
    for _, listener in ipairs(Profiles.listeners) do
        ns.SafeCall("profile listener", listener)
    end
end
Profiles.listeners = {}

-- Snapshot of the active profile. Do not modify the returned table.
function Profiles.Current()
    if not cache then
        cache = Profiles.Resolve(Profiles.ActiveName())
    end
    return cache
end

-- Makes `name` active for all characters, or for this character only.
function Profiles.SetActive(name, forCharacter)
    if not Profiles.Exists(name) then
        return false
    end
    if forCharacter and ns.character then
        ns.character.profile = name
    else
        ns.db.settings.defaultProfile = name
    end
    Profiles.Invalidate()
    return true
end

function Profiles.ClearCharacterOverride()
    if ns.character then
        ns.character.profile = nil
        Profiles.Invalidate()
    end
end

-- Returns the custom profile to write into; editing a preset switches the
-- active scope to "Custom" based on that preset.
local function editableProfile()
    local name = Profiles.ActiveName()
    if Profiles.IsPreset(name) then
        ns.db.profiles.Custom = { base = name, rules = {}, limits = {}, journey = {} }
        Profiles.SetActive("Custom", Profiles.IsCharacterOverride())
        name = "Custom"
    end
    return ns.db.profiles[name]
end

function Profiles.SetRule(id, field, value)
    local profile = editableProfile()
    profile.rules[id] = profile.rules[id] or {}
    profile.rules[id][field] = value
    Profiles.Invalidate()
end

function Profiles.SetLimit(field, value)
    editableProfile().limits[field] = value
    Profiles.Invalidate()
end

function Profiles.SetJourney(field, value)
    editableProfile().journey[field] = value
    Profiles.Invalidate()
end

-- Copies any profile into a new custom one. Returns ok, reason.
function Profiles.Copy(source, newName)
    if type(newName) ~= "string" or newName == "" then
        return false, "PROFILE_BAD_NAME"
    end
    if Profiles.Exists(newName) then
        return false, "PROFILE_EXISTS"
    end
    local custom = ns.db.profiles[source]
    if custom then
        ns.db.profiles[newName] = ns.Util.Copy(custom)
    elseif Profiles.IsPreset(source) then
        ns.db.profiles[newName] = { base = source, rules = {}, limits = {}, journey = {} }
    else
        return false, "PROFILE_MISSING"
    end
    return true
end

local function replaceReferences(oldName, newName)
    if ns.db.settings.defaultProfile == oldName then
        ns.db.settings.defaultProfile = newName or "Adventurer"
    end
    for _, character in pairs(ns.db.characters) do
        if character.profile == oldName then
            character.profile = newName
        end
    end
end

function Profiles.Rename(oldName, newName)
    if Profiles.IsPreset(oldName) or not ns.db.profiles[oldName] then
        return false, "PROFILE_READ_ONLY"
    end
    if type(newName) ~= "string" or newName == "" then
        return false, "PROFILE_BAD_NAME"
    end
    if Profiles.Exists(newName) then
        return false, "PROFILE_EXISTS"
    end
    ns.db.profiles[newName] = ns.db.profiles[oldName]
    ns.db.profiles[oldName] = nil
    replaceReferences(oldName, newName)
    Profiles.Invalidate()
    return true
end

function Profiles.Delete(name)
    if Profiles.IsPreset(name) or not ns.db.profiles[name] then
        return false, "PROFILE_READ_ONLY"
    end
    ns.db.profiles[name] = nil
    replaceReferences(name, nil)
    Profiles.Invalidate()
    return true
end

-- Clears the changes of a custom profile (back to its base preset).
function Profiles.Reset(name)
    local profile = ns.db.profiles[name]
    if not profile then
        return false, "PROFILE_READ_ONLY"
    end
    profile.rules, profile.limits, profile.journey = {}, {}, {}
    Profiles.Invalidate()
    return true
end
