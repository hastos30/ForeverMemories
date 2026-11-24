-- UI/ManualPanel.lua
-- Small panel: mode, timer, series, shot and cancel-timer buttons.
-- It is one of our own frames, so it hides itself during capture.
local _, ns = ...

local L = ns.L
local W = ns.Widgets

local ManualPanel = {}
ns.ManualPanel = ManualPanel

local panel
local options = { mode = nil, frames = nil, timer = nil }

local function build()
    panel = CreateFrame("Frame", "ForeverMemoriesManualPanel", UIParent, "BackdropTemplate")
    panel:SetSize(330, 170)
    panel:SetPoint("CENTER", 0, -200)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    W.Backdrop(panel, W.COLORS.background, 0.95)
    ns.ownFrames[panel] = true

    local title = W.Text(panel, L.MANUAL_PANEL, "GameFontNormal", W.COLORS.gold)
    title:SetPoint("TOPLEFT", 10, -8)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local rule = function() return ns.Profiles.Current().rules.MANUAL end
    local column = W.Column(panel, 10, 30)
    -- Panel values are not saved: say so under each explanation.
    local function tip(text)
        return text .. "\n\n|cff8c857a" .. L.TIP_PANEL_TEMP .. "|r"
    end
    column:Add(W.Tooltip(W.Dropdown(panel, L.FIELD_MODE, {
            { value = "normal", text = L.MODE_normal }, { value = "clean", text = L.MODE_clean },
            { value = "dual", text = L.MODE_dual },
        },
        function() return options.mode or rule().mode end,
        function(value) options.mode = value end), tip(L.TIP_FIELD_MODE)))
    column:Add(W.Tooltip(W.Dropdown(panel, L.MANUAL_TIMER, {
            { value = 0, text = L.TIMER_OFF }, { value = 3, text = "3 s" },
            { value = 5, text = "5 s" }, { value = 10, text = "10 s" },
        },
        function() return options.timer or ns.db.settings.manualTimer end,
        function(value) options.timer = value end), tip(L.TIP_MANUAL_TIMER)))
    column:Add(W.Tooltip(W.Stepper(panel, L.FIELD_FRAMES, ns.Registry.FIELDS.frames,
        function() return options.frames or rule().frames end,
        function(value) options.frames = value end), tip(L.TIP_FIELD_FRAMES)))
    panel.Refresh = function() column:Refresh() end

    local shot = W.Button(panel, L.TAKE_SHOT, 150, function() ns.Engine.ManualShot(options) end)
    shot:SetPoint("BOTTOMLEFT", 10, 10)
    W.Tooltip(shot, L.TIP_TAKE_SHOT, L.TAKE_SHOT)
    local cancel = W.Button(panel, L.CANCEL_TIMER, 150, function() ns.Engine.CancelCountdown() end)
    cancel:SetPoint("LEFT", shot, "RIGHT", 10, 0)
    W.Tooltip(cancel, L.TIP_CANCEL_TIMER, L.CANCEL_TIMER)
    panel:Hide()
end

function ManualPanel.Toggle()
    if not panel then
        build()
    end
    panel:SetShown(not panel:IsShown())
    if panel:IsShown() then
        panel:Refresh()
    end
end
