-- Spike/Probe.lua
-- Checks which client functions and events exist in this Forever build and
-- counts how often candidate events actually fire while you play.
-- Only counts and times are stored: never event payloads, so no chat text
-- and no secret values end up in SavedVariables.
local _, ns = ...

local Probe = {}
ns.Probe = Probe

-- Candidates from ARCHITECTURE.md section 1, plus helpers for later stages.
Probe.FUNCTIONS = {
    "Screenshot", "GetBuildInfo", "C_Timer.After", "C_Timer.NewTimer",
    "InCombatLockdown", "UnitIsAFK", "UnitLevel", "GetMaxPlayerLevel",
    "GetRealZoneText", "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition",
    "IsInInstance", "issecretvalue", "C_EventUtils.IsEventValid",
    "C_AddOns.GetAddOnMetadata", "GetLocale", "GetTime", "time", "date",
}

Probe.EVENTS = {
    "SCREENSHOT_STARTED", "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
    "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
    "CHAT_MSG_LOOT", "ENCOUNTER_END",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}

-- These two tell us if the client blocked one of our calls; their payload
-- is the addon name and the function name, so it is safe to log.
local BLOCK_EVENTS = { ADDON_ACTION_BLOCKED = true, ADDON_ACTION_FORBIDDEN = true }

local function observe(event, ...)
    local stats = ns.db.spike.events[event]
    if type(stats) ~= "table" then
        stats = { count = 0 }
        ns.db.spike.events[event] = stats
    end
    stats.count = stats.count + 1
    stats.last = ns.API.Time()
    if BLOCK_EVENTS[event] then
        local blockedAddon, blockedFunction = ...
        if blockedAddon == ns.name then
            ns.Logger.Error(event .. ": " .. tostring(blockedFunction))
            ns.API.Print("|cffff5555" .. event .. "|r " .. tostring(blockedFunction))
        end
    end
end

-- Runs once per session: records availability and subscribes the observer.
function Probe.Run()
    local result = { t = ns.API.Time(), build = ns.API.GetBuild(), functions = {}, events = {} }
    for _, name in ipairs(Probe.FUNCTIONS) do
        result.functions[name] = ns.API.Resolve(name) ~= nil
    end
    for _, event in ipairs(Probe.EVENTS) do
        local ok, reason = ns.On(event, observe)
        result.events[event] = ok and "registered" or ("rejected: " .. tostring(reason))
    end
    ns.Database.AppendCapped(ns.db.spike.probes, result, ns.Database.MAX_PROBES)
    Probe.last = result
    ns.Logger.Info("Probe done")
    return result
end

table.insert(ns.onReady, Probe.Run)
