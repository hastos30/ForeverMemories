-- Core/Commands.lua
-- Slash commands and key bindings. Technical diagnostics live here, not
-- in the window (spec 8).
--   /fm               window
--   /fm on|off|toggle automatic capture
--   /fm shot          manual shot
--   /fm status        short state in chat
--   /fm debug         diagnostics: client, API, events, step tracker, passive timer
--   /fm log           last 20 log lines
--   /fm ui            show the game interface again (emergency)
--   /fm reset         window back to the center
local _, ns = ...

local L = ns.L
local Print = ns.API.Print

-- Client functions the addon relies on (checked for presence only).
local PROBE_FUNCTIONS = {
    "Screenshot", "GetBuildInfo", "C_Timer.After", "C_Timer.NewTicker", "InCombatLockdown",
    "GetRealZoneText", "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetPlayerMapPosition",
    "C_Map.GetWorldPosFromMapPos", "UnitPosition", "GetUnitSpeed", "IsSwimming", "IsFlying",
    "UnitOnTaxi", "UnitInVehicle", "UnitIsAFK", "UnitGUID", "IsInInstance", "issecretvalue",
    "C_EventUtils.IsEventValid", "C_Item.GetItemQualityByID", "IsInGuild", "GetGuildInfo",
}

local commands = {}

function commands.on() ns.Engine.SetEnabled(true); Print(L.AUTO_CAPTURE .. ": " .. L.STATE_ACTIVE) end
function commands.off() ns.Engine.SetEnabled(false); Print(L.AUTO_CAPTURE .. ": " .. L.STATE_PAUSED) end
function commands.toggle()
    if ns.db.settings.enabled then commands.off() else commands.on() end
end

function commands.shot()
    ns.Engine.ManualShot()
end

function commands.status()
    local s = ns.History.Stats()
    local session = ns.Engine.Session()
    Print(string.format("v%s  %s: %s  %s", ns.version, L.AUTO_CAPTURE,
        ns.db.settings.enabled and L.STATE_ACTIVE or L.STATE_PAUSED, ns.characterKey))
    Print(string.format("%s %s, %s %s, %s %s, %s %s, %s %s", L.STAT_TOTAL, ns.Num(s.total), L.STAT_TODAY,
        ns.Num(s.today), L.STAT_STEPS_TODAY, ns.Num(ns.Steps.Today()), L.STAT_ZONES_TODAY,
        ns.Num(ns.Locations.Today()), L.STAT_PLAYTIME_TODAY, ns.UI.FormatDuration(ns.Activity.Today())))
    Print(string.format("engine %s, queue %d, calls %d, saved %d, unattributed %d",
        ns.Engine.GetState(), ns.Engine.QueueSize(), session.calls, session.saved, session.unattributed))
end

function commands.debug()
    local build = ns.API.GetBuild()
    if build then
        Print(string.format("Client %s (%s), TOC %s, locale %s", build.version, build.build,
            tostring(build.toc), ns.API.GetLocale()))
    end
    local missing = {}
    for _, name in ipairs(PROBE_FUNCTIONS) do
        if not ns.API.Resolve(name) then
            missing[#missing + 1] = name
        end
    end
    Print("Missing functions: " .. (#missing == 0 and "-" or table.concat(missing, ", ")))
    local unavailable = {}
    for _, id in ipairs(ns.Registry.EVENTS) do
        local ok, reason = ns.Registry.Status(id)
        if not ok then
            unavailable[#unavailable + 1] = id .. " (" .. tostring(reason) .. ")"
        end
    end
    Print("Unavailable events: " .. (#unavailable == 0 and "-" or table.concat(unavailable, "; ")))
    local source, reason, errors = ns.Steps.Status()
    local space, x, y, from = ns.API.WorldPosition()
    Print(string.format("Steps: running %s, source %s, last %s, errors %d, speed %s, exclusion %s",
        tostring(ns.Steps.IsRunning()), source, reason, errors, tostring(ns.API.UnitSpeed()),
        tostring(ns.API.MovementExclusion() or "-")))
    Print(string.format("Position: %s %s %s (%s)", tostring(space), x and string.format("%.1f", x) or "-",
        y and string.format("%.1f", y) or "-", tostring(from)))
    local passiveState, elapsed, due = ns.Passive.Status()
    Print(string.format("Passive: %s, interval %d min, counted %d:%02d of %d:00, state %s, afk %s",
        ns.db.settings.passive and "on" or "off", ns.db.settings.passiveInterval,
        math.floor(elapsed / 60), math.floor(elapsed % 60), due / 60, passiveState,
        tostring(ns.API.IsAFK())))
    local playtime = ns.character.playtime
    Print(string.format("Playtime: today %ds, total %ds, now %s; zones today %d, visited %d, days played %d",
        ns.Activity.Today(), math.floor(playtime.total), ns.Activity.BlockReason() or "active",
        ns.Locations.Today(), ns.Locations.Total(), ns.Activity.DaysPlayed()))
    local character = ns.character
    Print(string.format("Character: %s, GUID %s%s, guild %s", ns.characterKey, tostring(character.guid),
        character.guidChanged and " (changed!)" or "", tostring(character.guild)))
end

function commands.log()
    for _, entry in ipairs(ns.Logger.Recent(20)) do
        Print(date("%H:%M:%S", entry.t) .. " " .. entry.level .. " " .. entry.msg)
    end
end

function commands.ui()
    if ns.UIState.ForceShow() then
        Print(L.UI_RESTORED)
    else
        Print(L.UI_RESTORE_COMBAT)
    end
end

function commands.reset()
    ns.UI.ResetPosition()
end

function commands.help()
    Print("/fm  |  on  off  toggle  |  shot  |  status  debug  log  |  ui  reset")
end

SLASH_FOREVERMEMORIES1 = "/fm"
SLASH_FOREVERMEMORIES2 = "/forevermemories"
SlashCmdList.FOREVERMEMORIES = function(message)
    local name, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    name = string.lower(name or "")
    -- The emergency restore works even if the addon did not load fully.
    if name == "ui" then
        ns.SafeCall("/fm ui", commands.ui)
        return
    end
    if not ns.db or not ns.characterKey then
        Print(L.NOT_LOADED)
        return
    end
    if name == "" then
        ns.UI.Toggle()
        return
    end
    local command = commands[name] or commands.help
    ns.SafeCall("/fm " .. name, command, rest)
end

-- Key bindings (Bindings.xml is loaded by the client and must NOT be
-- listed in the TOC).
BINDING_HEADER_FOREVERMEMORIES = "ForeverMemories"
table.insert(ns.onReady, function()
    BINDING_NAME_FOREVERMEMORIES_SHOT = L.TAKE_SHOT
    BINDING_NAME_FOREVERMEMORIES_TOGGLE = L.TOGGLE_WINDOW
end)

function ForeverMemories_ManualShot()
    if ns.db and ns.characterKey then
        ns.Engine.ManualShot()
    end
end

function ForeverMemories_ToggleWindow()
    ns.UI.Toggle()
end

-- Entry in the game's Options -> AddOns list, if this client supports it.
table.insert(ns.onReady, function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end
    local canvas = CreateFrame("Frame")
    local title = ns.Widgets.Text(canvas, "ForeverMemories", "GameFontNormalLarge", ns.Widgets.COLORS.heading)
    title:SetPoint("TOPLEFT", 16, -16)
    local open = ns.Widgets.Button(canvas, L.OPEN_WINDOW, 200, 26, function()
        if SettingsPanel and SettingsPanel.Close then
            pcall(SettingsPanel.Close, SettingsPanel)
        end
        ns.UI.Open()
    end)
    open:SetPoint("TOPLEFT", 16, -50)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, "ForeverMemories")
    Settings.RegisterAddOnCategory(category)
end)
