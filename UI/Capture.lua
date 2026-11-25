-- UI/Capture.lua
-- "Auto capture" tab (spec 5; redesigned in v0.16.0). One scrolling page:
--   * the master switch: auto capture on / paused, with the reason;
--   * how to shoot: two mode cards with a small preview of the screen;
--   * when to shoot: the nine events in four groups (Progress, Combat,
--     Loot, World) that open and close, each with "n of m" and All / None;
--   * passive capture: the switch, the interval, a hint and the timer.
-- Delays, priorities and limits stay inside the Engine; the timer lives in
-- Modules/Passive.lua. Groups are closed by default; which ones are open
-- is kept in ns.db.ui.captureOpen.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local MODES = {
    { id = "normal", icon = ns.Media.ICON.camera },
    { id = "clean", icon = ns.Media.ICON.shots },
}

-- Event groups (v0.16.0). An event of the Registry that is in no group
-- goes to the last one, so a new event is never lost from the page.
UI.CAPTURE_GROUPS = {
    { id = "progress", icon = ns.Media.ICON.flag, events = { "LEVEL", "DEATH" } },
    { id = "combat", icon = ns.Media.MEDALLIONS.combat, events = { "BOSS", "DUEL" } },
    { id = "loot", icon = ns.Media.ICON.loot, events = { "LOOT_RARE", "LOOT_EPIC", "LOOT_LEGENDARY" } },
    { id = "world", icon = ns.Media.ICON.zones, events = { "ZONE", "GUILD" } },
}

local function groups()
    local known, list = {}, {}
    for i, group in ipairs(UI.CAPTURE_GROUPS) do
        list[i] = { id = group.id, icon = group.icon, events = {} }
        for _, id in ipairs(group.events) do
            known[id] = i
        end
    end
    for _, id in ipairs(ns.Registry.EVENTS) do
        local events = list[known[id] or #list].events
        events[#events + 1] = id
    end
    return list
end

local function openSet()
    local ui = ns.db.ui
    if type(ui.captureOpen) ~= "table" then
        ui.captureOpen = {}
    end
    return ui.captureOpen
end

local function countOn(events)
    local on, available = 0, 0
    for _, id in ipairs(events) do
        if ns.Registry.IsAvailable(id) then
            available = available + 1
            if ns.db.settings.events[id] then
                on = on + 1
            end
        end
    end
    return on, available
end

---------------------------------------------------------------------------
-- Mode card: icon, name, hint and a small picture of what the shot shows.
---------------------------------------------------------------------------
local PREVIEW_W, PREVIEW_H = 84, 50

local function preview(parent, withInterface)
    local screen = W.Panel(parent, W.COLORS.background, W.COLORS.divider)
    screen:SetSize(PREVIEW_W, PREVIEW_H)
    screen:EnableMouse(false)
    local c = W.COLORS
    local function box(x, y, w, h, color, alpha)
        local t = screen:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(color[1], color[2], color[3], alpha)
        t:SetPoint("TOPLEFT", x, -y)
        t:SetSize(w, h)
        return t
    end
    -- The world: sky and ground, in both modes.
    box(2, 2, PREVIEW_W - 4, 26, c.panel, 1)
    box(2, 28, PREVIEW_W - 4, PREVIEW_H - 30, c.divider, 0.8)
    if withInterface then
        box(4, 4, 18, 6, c.gold, 0.9)                         -- unit frame
        box(PREVIEW_W - 14, 4, 10, 10, c.muted, 0.9)          -- minimap
        box(16, PREVIEW_H - 9, PREVIEW_W - 32, 5, c.gold, 0.8) -- action bar
        box(PREVIEW_W - 12, 18, 6, 14, c.muted, 0.6)          -- quest list
    end
    return screen
end

local function modeCard(parent, mode, onPick)
    local card = W.Button(parent, "", (UI.CONTENT_WIDTH - 18) / 2, 84, function()
        ns.db.settings.mode = mode.id
        onPick()
    end)
    card.label:Hide()
    local icon = W.Icon(card, mode.icon, 20)
    icon:SetPoint("TOPLEFT", 12, -12)
    local title = W.Text(card, L["MODE_" .. mode.id], "GameFontNormal", W.COLORS.text)
    title:SetPoint("TOPLEFT", 12, -40)
    local hint = W.Text(card, L["MODE_" .. mode.id .. "_HINT"], "GameFontHighlightSmall", W.COLORS.muted)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    local screen = preview(card, mode.id == "normal")
    screen:SetPoint("RIGHT", -12, -4)
    local mark = card:CreateTexture(nil, "OVERLAY")
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    mark:SetSize(20, 20)
    mark:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    mark:SetVertexColor(W.COLORS.gold[1], W.COLORS.gold[2], W.COLORS.gold[3])
    W.Tooltip(card, L["TIP_MODE_" .. mode.id], L["MODE_" .. mode.id])
    function card:Refresh()
        local selected = ns.db.settings.mode == mode.id
        self:SetSelected(selected)
        mark:SetShown(selected)
        screen:SetAlpha(selected and 1 or 0.6)
        local col = selected and W.COLORS.heading or W.COLORS.text
        title:SetTextColor(col[1], col[2], col[3])
    end
    return card
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
UI.builders.capture = function(parent)
    local list
    local function redraw()
        list:Refresh()
    end

    local kinds = {}

    -- Master switch.
    kinds.status = { height = 56, make = function(p)
        local f = W.Panel(p, W.COLORS.panel, W.COLORS.divider)
        f.dot = W.Dot(f)
        f.dot:SetPoint("TOPLEFT", 14, -16)
        f.title = W.Text(f, "", "GameFontNormal", W.COLORS.heading)
        f.title:SetPoint("LEFT", f.dot, "RIGHT", 10, 0)
        f.hint = W.Text(f, "", "GameFontHighlightSmall", W.COLORS.muted)
        f.hint:SetPoint("TOPLEFT", 32, -32)
        f.hint:SetPoint("RIGHT", -190, 0)
        f.button = W.Button(f, "", 170, 28, function()
            ns.Engine.SetEnabled(not ns.db.settings.enabled)
        end)
        f.button:SetPoint("RIGHT", -12, 0)
        W.Tooltip(f.button, function()
            return ns.db.settings.enabled and L.TIP_PAUSE or L.TIP_RESUME
        end)
        return f
    end, fill = function(f)
        local enabled = ns.db.settings.enabled
        local c = enabled and W.COLORS.active or W.COLORS.paused
        f.dot:SetColor(c)
        f.title:SetText(enabled and L.CAPTURE_ON or L.CAPTURE_OFF)
        f.title:SetTextColor(c[1], c[2], c[3])
        f.hint:SetText(enabled and L.CAPTURE_ON_HINT or L.CAPTURE_OFF_HINT)
        f.button:SetLabel(enabled and L.CAPTURE_PAUSE or L.CAPTURE_RESUME)
    end }

    -- Section heading with an optional value on the right.
    kinds.heading = { height = 30, make = function(p)
        local f = CreateFrame("Frame", nil, p)
        f.icon = W.Icon(f, nil, 18)
        f.icon:SetPoint("LEFT", 0, -2)
        f.text = W.Heading(f, "")
        f.right = W.Text(f, "", "GameFontHighlightSmall", W.COLORS.muted)
        f.right:SetPoint("RIGHT", 0, -2)
        f.right:SetJustifyH("RIGHT")
        return f
    end, fill = function(f, item)
        f.text:ClearAllPoints()
        if item.icon then
            f.icon:SetIcon(item.icon)
            f.icon:Show()
            f.text:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
        else
            f.icon:Hide()
            f.text:SetPoint("LEFT", 0, -2)
        end
        f.text:SetText(item.text)
        f.right:SetText(item.right or "")
    end }

    -- Two mode cards (one frame: the cards keep their own state).
    kinds.modes = { height = 92, make = function(p)
        local f = CreateFrame("Frame", nil, p)
        f.cards = {}
        for i, mode in ipairs(MODES) do
            local card = modeCard(f, mode, redraw)
            card:SetPoint("TOPLEFT", (i - 1) * ((UI.CONTENT_WIDTH - 18) / 2 + 10), -2)
            f.cards[i] = card
        end
        return f
    end, fill = function(f)
        for _, card in ipairs(f.cards) do
            card:Refresh()
        end
    end }

    -- A group of events: click to open or close; All / None on the right.
    kinds.group = { height = 40, make = function(p)
        local f = CreateFrame("Button", nil, p)
        local back = W.Panel(f, W.COLORS.panel, W.COLORS.divider)
        back:SetPoint("TOPLEFT", 0, -2)
        back:SetPoint("BOTTOMRIGHT", 0, 2)
        back:EnableMouse(false)
        f.arrow = W.Text(back, "", "GameFontNormal", W.COLORS.gold)
        f.arrow:SetPoint("LEFT", 12, 0)
        f.icon = W.Icon(back, nil, 20)
        f.icon:SetPoint("LEFT", 32, 0)
        f.title = W.Text(back, "", "GameFontNormal", W.COLORS.text)
        f.title:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
        f.count = W.Text(back, "", "GameFontHighlightSmall", W.COLORS.muted)
        f.count:SetPoint("RIGHT", -130, 0)
        f.count:SetJustifyH("RIGHT")
        f.all = W.Button(back, "", 110, 24, function(button) -- beta.8: "Enable all" / "Disable all"
            local on, available = countOn(button.events)
            local value = on < available -- some off: turn all on; all on: turn all off
            for _, id in ipairs(button.events) do
                if ns.Registry.IsAvailable(id) then
                    ns.db.settings.events[id] = value
                end
            end
            redraw()
        end)
        f.all:SetPoint("RIGHT", -8, 0)
        W.Tooltip(f.all, L.TIP_CAPTURE_GROUP_ALL)
        f:RegisterForClicks("LeftButtonUp")
        f:SetScript("OnClick", function(self)
            local open = openSet()
            open[self.id] = not open[self.id] or nil
            redraw()
        end)
        W.Tooltip(f, L.TIP_CAPTURE_GROUP)
        return f
    end, fill = function(f, item)
        f.id = item.group.id
        f.all.events = item.group.events
        local on, available = countOn(item.group.events)
        f.arrow:SetText(item.open and "-" or "+")
        f.icon:SetIcon(item.group.icon)
        f.title:SetText(L["CAPTURE_GROUP_" .. item.group.id])
        f.count:SetText(string.format(L.EVENTS_ON, on, #item.group.events))
        f.all:SetLabel(on < available and L.CAPTURE_ALL or L.CAPTURE_NONE)
        f.all:SetDisabled(available == 0)
    end }

    -- One event of an open group.
    kinds.event = { height = 30, make = function(p)
        local f = CreateFrame("Frame", nil, p)
        local check
        check = W.Check(f, "",
            function() return ns.db.settings.events[check.id] end,
            function(value) ns.db.settings.events[check.id] = value end,
            UI.CONTENT_WIDTH - 40)
        check:SetPoint("LEFT", 30, 0)
        W.Tooltip(check, function()
            local id = check.id
            local available, reason = ns.Registry.Status(id)
            if available then
                return L["TIP_EVENT_" .. id]
            end
            return (L["TIP_EVENT_" .. id] or "") .. "\n\n" .. W.HEX.error .. L.EVENT_UNAVAILABLE .. "|r "
                .. W.HEX.muted .. tostring(reason) .. "|r"
        end, function() return L["EVENT_" .. check.id] end)
        f.Refresh = redraw -- a click on the check redraws the counters
        f.check = check
        return f
    end, fill = function(f, item)
        f.check.id = item.id
        f.check.label:SetText(L["EVENT_" .. item.id] or item.id)
        f.check:SetAvailable(ns.Registry.IsAvailable(item.id))
    end }

    kinds.divider = { height = 10, make = function(p)
        local f = CreateFrame("Frame", nil, p)
        local line = W.Divider(f)
        line:SetPoint("LEFT", 0, 0)
        line:SetPoint("RIGHT", 0, 0)
        return f
    end, fill = function() end }

    -- Passive capture.
    kinds.passive = { height = 30, make = function(p)
        local f = CreateFrame("Frame", nil, p)
        f.check = W.Check(f, L.SET_PASSIVE,
            function() return ns.db.settings.passive end,
            function(value) ns.db.settings.passive = value end,
            UI.CONTENT_WIDTH)
        f.check:SetPoint("LEFT", 0, 0)
        W.Tooltip(f.check, L.TIP_PASSIVE)
        f.Refresh = redraw
        return f
    end, fill = function(f)
        f.check:Refresh()
    end }

    kinds.intervals = { height = 58, make = function(p)
        local f = CreateFrame("Frame", nil, p)
        local label = W.Text(f, L.PASSIVE_INTERVAL, "GameFontHighlight", W.COLORS.text)
        label:SetPoint("TOPLEFT", 0, -2)
        f.buttons = {}
        for i, minutes in ipairs(ns.Passive.INTERVALS) do
            local button = W.Button(f, string.format(L.MINUTES_SHORT, minutes), 76, 24, function()
                ns.db.settings.passiveInterval = minutes -- the timer restarts by itself
                redraw()
            end)
            button:SetPoint("TOPLEFT", (i - 1) * 84, -24)
            W.Tooltip(button, L.TIP_PASSIVE_INTERVAL, L.PASSIVE_INTERVAL)
            button.minutes = minutes
            f.buttons[i] = button
        end
        return f
    end, fill = function(f)
        local settings = ns.db.settings
        for _, button in ipairs(f.buttons) do
            button:SetDisabled(not settings.passive)
            button:SetSelected(settings.passive and button.minutes == settings.passiveInterval)
        end
    end }

    kinds.note = { height = 24, make = function(p)
        local f = CreateFrame("Frame", nil, p)
        f.text = W.Text(f, "", "GameFontHighlightSmall", W.COLORS.muted)
        f.text:SetPoint("LEFT", 0, 0)
        f.text:SetPoint("RIGHT", 0, 0)
        return f
    end, fill = function(f, item)
        f.text:SetText(item.text())
    end }

    -- The real passive timer, the same as on Home.
    kinds.timer = { height = 30, make = function(p)
        local f = CreateFrame("Frame", nil, p)
        local label = W.Text(f, L.NEXT_PASSIVE, "GameFontHighlight", W.COLORS.text)
        label:SetPoint("LEFT", 0, 0)
        f.value = W.Text(f, "", "GameFontNormal", W.COLORS.heading)
        f.value:SetPoint("RIGHT", 0, 0)
        f.value:SetJustifyH("RIGHT")
        W.Tooltip(f, L.TIP_NEXT_PASSIVE, L.NEXT_PASSIVE)
        return f
    end, fill = function(f)
        local text, color = UI.TimerView(ns.Passive.Timer())
        f.value:SetText(text)
        f.value:SetTextColor(color[1], color[2], color[3])
    end }

    list = W.Stretch(W.FlexList(parent, UI.CONTENT_WIDTH + 8, UI.HEIGHT - 150, kinds))
    list:SetPoint("TOPLEFT", 0, 0)

    local function passiveHint()
        local settings = ns.db.settings
        if settings.passive then
            return string.format(L.PASSIVE_HINT, settings.passiveInterval)
        end
        return L.PASSIVE_OFF_HINT
    end

    function list:Refresh()
        local items = {
            { kind = "status" },
            { kind = "heading", text = L.HOW_TO_SHOOT },
            { kind = "modes" },
            { kind = "divider" },
        }
        local on, available = 0, 0
        local all = groups()
        for _, group in ipairs(all) do
            local o, a = countOn(group.events)
            on, available = on + o, available + #group.events
        end
        items[#items + 1] = { kind = "heading", text = L.WHEN_TO_SHOOT, right = string.format(L.EVENTS_ON, on, available) }
        local open = openSet()
        for _, group in ipairs(all) do
            items[#items + 1] = { kind = "group", group = group, open = open[group.id] and true or false }
            if open[group.id] then
                for _, id in ipairs(group.events) do
                    items[#items + 1] = { kind = "event", id = id }
                end
            end
        end
        items[#items + 1] = { kind = "divider" }
        items[#items + 1] = { kind = "heading", text = L.PASSIVE_HEADING, icon = ns.Media.ICON.playtime }
        items[#items + 1] = { kind = "passive" }
        items[#items + 1] = { kind = "intervals" }
        items[#items + 1] = { kind = "note", text = passiveHint }
        items[#items + 1] = { kind = "timer" }
        self:SetItems(items, true)
    end

    return {
        Refresh = function() list:Refresh() end,
        RefreshClock = function() list:Redraw() end,
        list = list,
    }
end
