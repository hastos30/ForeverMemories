-- Core/Commands.lua
-- Slash commands for the v0.0.1 spike:
--   /fm shot    take one manual screenshot
--   /fm status  state, build and the last 5 shots
--   /fm debug   API probe results and event counters
--   /fm log     last 20 log lines
-- /fm on|off|toggle and the main window arrive in v0.1.0.
local _, ns = ...

local Print = ns.API.Print

local function yesNo(value)
    return value and "|cff7CAA66yes|r" or "|cffff5555no|r"
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function showBuild()
    local build = ns.API.GetBuild()
    if build then
        Print(string.format("Client %s (build %s, %s), TOC %s",
            build.version, build.build, build.date, tostring(build.toc)))
    else
        Print("Client build unknown")
    end
end

local commands = {}

function commands.shot()
    local ok, reason = ns.ManualShot.Request()
    if not ok then
        Print("Shot skipped: " .. tostring(reason))
    end
end

function commands.status()
    local spike = ns.db.spike
    Print("v" .. ns.version .. ", state " .. ns.ManualShot.GetState()
        .. ", loads " .. spike.loadCount
        .. ", Screenshot() calls " .. spike.screenshotCalls
        .. ", unattributed results " .. spike.unattributedResults)
    showBuild()
    local shots = spike.shots
    for i = math.max(1, #shots - 4), #shots do
        local s = shots[i]
        Print(string.format("#%d %s %s %.2fs sync=%s started=%s combat=%s",
            s.id, date("%H:%M:%S", s.t), s.status, s.seconds,
            tostring(s.synchronous), tostring(s.sawStarted), tostring(s.inCombat)))
    end
end

function commands.debug()
    local probe = ns.Probe.last
    if not probe then
        Print("Probe has not run")
        return
    end
    showBuild()
    Print("Functions:")
    for _, name in ipairs(sortedKeys(probe.functions)) do
        Print("  " .. name .. " " .. yesNo(probe.functions[name]))
    end
    Print("Events (seen this account since install):")
    for _, event in ipairs(sortedKeys(probe.events)) do
        local stats = ns.db.spike.events[event]
        Print(string.format("  %s %s, fired %d", event, probe.events[event],
            stats and stats.count or 0))
    end
end

function commands.log()
    for _, entry in ipairs(ns.Logger.Recent(20)) do
        Print(date("%H:%M:%S", entry.t) .. " " .. entry.level .. " " .. entry.msg)
    end
end

function commands.help()
    Print("/fm shot | status | debug | log")
end

SLASH_FOREVERMEMORIES1 = "/fm"
SLASH_FOREVERMEMORIES2 = "/forevermemories"
SlashCmdList.FOREVERMEMORIES = function(message)
    local name = string.lower(string.match(message or "", "^%s*(%S*)") or "")
    local command = commands[name] or commands.help
    if not ns.db and command ~= commands.help then
        Print("Not loaded yet")
        return
    end
    command()
end
