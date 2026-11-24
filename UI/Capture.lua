-- UI/Capture.lua
-- "Auto capture" tab (spec 5): how to shoot (two modes), when (nine
-- events) and passive capture by time (v0.6.0). Delays, priorities and
-- limits stay inside the Engine; the timer lives in Modules/Passive.lua.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local MODES = {
    { id = "normal", icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
    { id = "clean", icon = "Interface\\Icons\\INV_Misc_Eye_01" },
}

local function modeCard(parent, mode)
    local card = W.Button(parent, "", (UI.CONTENT_WIDTH - 10) / 2, 78, function()
        ns.db.settings.mode = mode.id
        parent:Refresh()
    end)
    card.label:Hide()
    local icon = W.Icon(card, mode.icon, 20)
    icon:SetPoint("TOPLEFT", 12, -12)
    local title = W.Text(card, L["MODE_" .. mode.id], "GameFontNormal", W.COLORS.text)
    title:SetPoint("TOPLEFT", 12, -40)
    local hint = W.Text(card, L["MODE_" .. mode.id .. "_HINT"], "GameFontHighlightSmall", W.COLORS.muted)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    local mark = card:CreateTexture(nil, "OVERLAY")
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    mark:SetSize(22, 22)
    mark:SetPoint("TOPRIGHT", -8, -8)
    mark:SetVertexColor(W.COLORS.gold[1], W.COLORS.gold[2], W.COLORS.gold[3])
    W.Tooltip(card, L["TIP_MODE_" .. mode.id], L["MODE_" .. mode.id])
    function card:Refresh()
        local selected = ns.db.settings.mode == mode.id
        self:SetSelected(selected)
        mark:SetShown(selected)
        local c = selected and W.COLORS.heading or W.COLORS.text
        title:SetTextColor(c[1], c[2], c[3])
    end
    return card
end

UI.builders.capture = function(parent)
    local how = W.Heading(parent, L.HOW_TO_SHOOT)
    how:SetPoint("TOPLEFT", 0, 0)
    local cards = {}
    for i, mode in ipairs(MODES) do
        local card = modeCard(parent, mode)
        card:SetPoint("TOPLEFT", (i - 1) * ((UI.CONTENT_WIDTH - 10) / 2 + 10), -28)
        cards[i] = card
    end
    local line = W.Divider(parent)
    line:SetPoint("TOPLEFT", 0, -122)
    line:SetPoint("TOPRIGHT", 0, -122)

    local when = W.Heading(parent, L.WHEN_TO_SHOOT)
    when:SetPoint("TOPLEFT", 0, -136)
    local counter = W.Text(parent, "", "GameFontHighlightSmall", W.COLORS.muted)
    counter:SetPoint("TOPRIGHT", 0, -140)
    counter:SetJustifyH("RIGHT")

    local checks = {}
    for i, id in ipairs(ns.Registry.EVENTS) do
        local check = W.Check(parent, L["EVENT_" .. id],
            function() return ns.db.settings.events[id] end,
            function(value) ns.db.settings.events[id] = value end,
            UI.CONTENT_WIDTH)
        check:SetPoint("TOPLEFT", 0, -164 - (i - 1) * 28)
        W.Tooltip(check, function()
            local available, reason = ns.Registry.Status(id)
            if available then
                return L["TIP_EVENT_" .. id]
            end
            return L["TIP_EVENT_" .. id] .. "\n\n" .. W.HEX.error .. L.EVENT_UNAVAILABLE .. "|r "
                .. W.HEX.muted .. tostring(reason) .. "|r"
        end)
        checks[i] = check
    end

    -- Passive capture: one switch and the interval (15 / 30 / 45 / 60 min).
    local line2 = W.Divider(parent)
    line2:SetPoint("TOPLEFT", 0, -422)
    line2:SetPoint("TOPRIGHT", 0, -422)
    local clock = W.Icon(parent, "Interface\\Icons\\INV_Misc_PocketWatch_01", 18)
    clock:SetPoint("TOPLEFT", 0, -434)
    local passiveHeading = W.Heading(parent, L.PASSIVE_HEADING)
    passiveHeading:SetPoint("LEFT", clock, "RIGHT", 8, 0)
    local passiveCheck = W.Check(parent, L.SET_PASSIVE,
        function() return ns.db.settings.passive end,
        function(value) ns.db.settings.passive = value end,
        UI.CONTENT_WIDTH)
    passiveCheck:SetPoint("TOPLEFT", 0, -460)
    W.Tooltip(passiveCheck, L.TIP_PASSIVE)
    local intervalLabel = W.Text(parent, L.PASSIVE_INTERVAL, "GameFontHighlight", W.COLORS.text)
    intervalLabel:SetPoint("TOPLEFT", 0, -494)
    local intervalButtons = {}
    for i, minutes in ipairs(ns.Passive.INTERVALS) do
        local button = W.Button(parent, string.format(L.MINUTES_SHORT, minutes), 76, 24, function()
            ns.db.settings.passiveInterval = minutes -- the timer restarts by itself
            parent:Refresh()
        end)
        button:SetPoint("TOPLEFT", (i - 1) * 84, -512)
        W.Tooltip(button, L.TIP_PASSIVE_INTERVAL, L.PASSIVE_INTERVAL)
        button.minutes = minutes
        intervalButtons[i] = button
    end
    local passiveHint = W.Text(parent, "", "GameFontHighlightSmall", W.COLORS.muted)
    passiveHint:SetPoint("TOPLEFT", 0, -546)
    passiveHint:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local function refreshPassive()
        local settings = ns.db.settings
        passiveCheck:Refresh()
        for _, button in ipairs(intervalButtons) do
            button:SetDisabled(not settings.passive)
            button:SetSelected(settings.passive and button.minutes == settings.passiveInterval)
        end
        if settings.passive then
            passiveHint:SetText(string.format(L.PASSIVE_HINT, settings.passiveInterval))
        else
            passiveHint:SetText(L.PASSIVE_OFF_HINT)
        end
    end

    function parent:Refresh()
        refreshPassive()
        for _, card in ipairs(cards) do
            card:Refresh()
        end
        local on, total = 0, 0
        for i, id in ipairs(ns.Registry.EVENTS) do
            local available = ns.Registry.IsAvailable(id)
            checks[i]:SetAvailable(available)
            total = total + 1
            if available and ns.db.settings.events[id] then
                on = on + 1
            end
        end
        counter:SetText(string.format(L.EVENTS_ON, on, total))
    end
    return { Refresh = function() parent:Refresh() end }
end
