-- Core/Commands.lua
-- Slash commands (ARCHITECTURE.md section 6) and the key binding.
--   /fm               window
--   /fm on|off|toggle automatic capture
--   /fm shot          manual shot (uses the timer from settings)
--   /fm status        state in chat
--   /fm debug         diagnostics
--   /fm log           last 20 log lines
--   /fm ui            show the interface again (emergency)
--   /fm panel         manual panel
--   /fm quest add|remove <id>  quests for the QUEST trigger
local _, ns = ...

local L = ns.L
local Print = ns.API.Print

local commands = {}

function commands.on() ns.Engine.SetEnabled(true); Print(L.AUTO_CAPTURE .. ": " .. L.ON) end
function commands.off() ns.Engine.SetEnabled(false); Print(L.AUTO_CAPTURE .. ": " .. L.OFF) end
function commands.toggle()
    if ns.db.settings.enabled then commands.off() else commands.on() end
end

function commands.shot()
    local ok, reason = ns.Engine.ManualShot()
    if not ok and reason then
        Print(L.MANUAL_NOT_TAKEN .. ": " .. L["REASON_" .. reason])
    end
end

function commands.status()
    local session = ns.Engine.Session()
    Print(string.format("v%s, %s: %s, %s: %s", ns.version, L.AUTO_CAPTURE,
        ns.db.settings.enabled and L.ON or L.OFF, L.PROFILE, ns.Profiles.ActiveName()))
    Print(string.format(L.DIAG_ENGINE, ns.Engine.GetState(), ns.Engine.QueueSize(),
        session.calls, session.unattributed, ns.Journey.IsRunning() and L.ON or L.OFF))
    local items = ns.Journal.Query({}, 1)
    for i = math.min(5, #items), 1, -1 do
        local e = items[i]
        Print(string.format("#%d %s %s %s (%d/%d)", e.id, date("%H:%M:%S", e.t),
            ns.Notifications.EventNames(e), L["STATUS_" .. e.status], e.ok or 0, (e.ok or 0) + (e.failed or 0)))
    end
end

function commands.debug()
    for line in string.gmatch(ns.UI.DiagnosticsText(), "[^\n]+") do
        Print(line)
    end
    ns.UI.Open("diagnostics")
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

function commands.panel() ns.ManualPanel.Toggle() end

function commands.quest(args)
    local action, id = string.match(args or "", "^(%a+)%s+(%d+)")
    id = tonumber(id)
    if not id or (action ~= "add" and action ~= "remove") then
        Print("/fm quest add|remove <questID>")
        return
    end
    ns.character.quests[id] = action == "add" or nil
    Print(string.format("%s %d", action == "add" and "+" or "-", id))
end

function commands.help()
    Print("/fm  |  on  off  toggle  |  shot  panel  |  status  debug  log  |  ui  |  quest add|remove <id>")
end

SLASH_FOREVERMEMORIES1 = "/fm"
SLASH_FOREVERMEMORIES2 = "/forevermemories"
SlashCmdList.FOREVERMEMORIES = function(message)
    if not ns.db or not ns.characterKey then
        Print(L.NOT_LOADED)
        return
    end
    local name, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    name = string.lower(name or "")
    if name == "" then
        ns.UI.Toggle()
        return
    end
    local command = commands[name] or commands.help
    ns.SafeCall("/fm " .. name, command, rest)
end

-- Key binding (Bindings.xml). Bindings.xml is loaded by the client
-- automatically and must NOT be listed in the TOC.
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
    local title = ns.Widgets.Text(canvas, "ForeverMemories", "GameFontNormalLarge", ns.Widgets.COLORS.gold)
    title:SetPoint("TOPLEFT", 16, -16)
    local open = ns.Widgets.Button(canvas, L.OPEN_WINDOW, 200, function()
        if SettingsPanel and SettingsPanel.Close then
            pcall(SettingsPanel.Close, SettingsPanel)
        end
        ns.UI.Open()
    end)
    open:SetPoint("TOPLEFT", 16, -50)
    ns.Widgets.Tooltip(open, L.TIP_OPEN_WINDOW, L.OPEN_WINDOW)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, "ForeverMemories")
    Settings.RegisterAddOnCategory(category)
end)
