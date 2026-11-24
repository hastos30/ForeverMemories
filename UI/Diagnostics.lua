-- UI/Diagnostics.lua
-- Client build, API availability, engine state, queue and recent log.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

-- Client functions the addon relies on (checked for presence only).
UI.PROBE_FUNCTIONS = {
    "Screenshot", "GetBuildInfo", "C_Timer.After", "C_Timer.NewTicker", "InCombatLockdown",
    "UnitIsAFK", "UnitLevel", "GetMaxPlayerLevel", "GetRealZoneText", "C_Map.GetBestMapForUnit",
    "C_Map.GetMapInfo", "C_Map.GetPlayerMapPosition", "IsInInstance", "issecretvalue",
    "C_EventUtils.IsEventValid", "C_Item.GetItemQualityByID", "GetNumShapeshiftForms", "IsInGuild",
}

function UI.DiagnosticsText()
    local lines = {}
    local build = ns.API.GetBuild()
    if build then
        lines[#lines + 1] = string.format("%s %s (%s), TOC %s", L.CLIENT, build.version, build.build, tostring(build.toc))
    end
    local session = ns.Engine.Session()
    lines[#lines + 1] = string.format(L.DIAG_ENGINE, ns.Engine.GetState(), ns.Engine.QueueSize(),
        session.calls, session.unattributed, ns.Journey.IsRunning() and L.ON or L.OFF)
    local missing = {}
    for _, name in ipairs(UI.PROBE_FUNCTIONS) do
        if not ns.API.Resolve(name) then
            missing[#missing + 1] = name
        end
    end
    lines[#lines + 1] = L.DIAG_FUNCTIONS .. ": " .. (#missing == 0 and ("|cff7CAA66" .. L.ALL_PRESENT .. "|r")
        or ("|cffff5555" .. table.concat(missing, ", ") .. "|r"))
    local unavailable = {}
    for _, trigger in ipairs(ns.Registry.TRIGGERS) do
        local ok, reason = ns.Registry.Status(trigger.id)
        if not ok then
            unavailable[#unavailable + 1] = trigger.id .. " (" .. tostring(L[reason]) .. ")"
        end
    end
    lines[#lines + 1] = L.DIAG_UNAVAILABLE .. ": " .. (#unavailable == 0 and "-" or table.concat(unavailable, "; "))
    return table.concat(lines, "\n")
end

UI.builders.diagnostics = function(parent)
    local summary = W.Text(parent, "", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 12, -12)
    summary:SetWidth(590)
    local logTitle = W.Heading(parent, L.RECENT_LOG)
    logTitle:SetPoint("TOPLEFT", 12, -130)
    local log = W.Text(parent, "", "GameFontHighlightSmall")
    log:SetPoint("TOPLEFT", 12, -156)
    log:SetWidth(590)
    log:SetJustifyV("TOP")
    local test = W.Button(parent, L.TEST_SHOT, 160, function() ns.Engine.SubmitManual() end)
    test:SetPoint("BOTTOMLEFT", 12, 12)
    local restore = W.Button(parent, L.RESTORE_UI, 160, function() ns.UIState.ForceShow() end)
    restore:SetPoint("LEFT", test, "RIGHT", 10, 0)
    return {
        Refresh = function()
            summary:SetText(UI.DiagnosticsText())
            local lines = {}
            for _, entry in ipairs(ns.Logger.Recent(16)) do
                lines[#lines + 1] = date("%H:%M:%S", entry.t) .. " " .. entry.level .. " " .. entry.msg
            end
            log:SetText(#lines > 0 and table.concat(lines, "\n") or "-")
        end,
    }
end
