-- UI/Main.lua
-- Main window (spec 3, 4, 14): header, four horizontal tabs, content and
-- footer. Tabs are built when first opened. The UI never calls Screenshot
-- directly: it goes through the Engine.
local _, ns = ...

local UI = {}
ns.UI = UI

local L = ns.L
local W = ns.Widgets

UI.WIDTH, UI.HEIGHT = 620, 720 -- 720 since v0.6.0 (passive capture block)
UI.PAD = 16
UI.CONTENT_WIDTH = UI.WIDTH - 2 * UI.PAD
UI.TABS = { "home", "capture", "history", "settings" }
UI.builders = {}

local window, content
local statusDot, statusText, pauseButton
local tabs, navButtons = {}, {}
local currentTab

---------------------------------------------------------------------------
-- Position and scale
---------------------------------------------------------------------------
local function savePosition()
    local point, _, relativePoint, x, y = window:GetPoint(1)
    ns.db.ui.point = { point, relativePoint, x, y }
end

local function restorePosition()
    window:ClearAllPoints()
    local p = ns.db.ui.point
    if type(p) == "table" and type(p[3]) == "number" then
        window:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        window:SetPoint("CENTER")
    end
end

-- Moves the window back to the center if it is off screen.
local function keepOnScreen()
    local left, bottom, width, height = window:GetRect()
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    if not left or not screenW or screenW == 0 then
        return
    end
    local scale = window:GetEffectiveScale() / UIParent:GetEffectiveScale()
    left, bottom, width, height = left * scale, bottom * scale, width * scale, height * scale
    if left + width < 40 or left > screenW - 40 or bottom > screenH - 40 or bottom + height < 40 then
        ns.db.ui.point = nil
        restorePosition()
    end
end

function UI.ResetPosition()
    ns.db.ui.point = nil
    if window then
        restorePosition()
    end
end

function UI.ApplyScale()
    if window then
        window:SetScale(ns.db.settings.scale)
        keepOnScreen()
    end
end

---------------------------------------------------------------------------
-- Header state
---------------------------------------------------------------------------
local function refreshHeader()
    local enabled = ns.db.settings.enabled
    statusDot:SetColor(enabled and W.COLORS.active or W.COLORS.paused)
    statusText:SetText(enabled and L.STATE_ACTIVE or L.STATE_PAUSED)
    local c = enabled and W.COLORS.active or W.COLORS.paused
    statusText:SetTextColor(c[1], c[2], c[3])
    pauseButton:SetLabel(enabled and "||||" or ">")
end

function UI.ShowTab(id, option)
    if not tabs[id] then
        local frame = CreateFrame("Frame", nil, content)
        frame:SetAllPoints(content)
        local built = UI.builders[id] and UI.builders[id](frame) or {}
        frame.view = built
        tabs[id] = frame
    end
    for tabId, frame in pairs(tabs) do
        frame:SetShown(tabId == id)
    end
    for tabId, button in pairs(navButtons) do
        button:SetSelected(tabId == id)
    end
    currentTab = id
    local view = tabs[id].view
    if option and view.Select then
        ns.SafeCall("tab " .. id, view.Select, option)
    end
    if view.Refresh then
        ns.SafeCall("tab " .. id, view.Refresh)
    end
end

function UI.CurrentTab()
    return currentTab
end

function UI.IsShown()
    return window ~= nil and window:IsShown()
end

function UI.Refresh()
    if window and window:IsShown() then
        refreshHeader()
        local view = currentTab and tabs[currentTab].view
        if view and view.Refresh then
            ns.SafeCall("tab " .. currentTab, view.Refresh)
        end
    end
end

-- Cheap partial updates of the open tab: `method` is "RefreshSteps"
-- (whole step changed) or "RefreshClock" (every second: playtime, zone,
-- passive countdown). Nothing is drawn while the window is closed.
local function refreshPart(method)
    if window and window:IsShown() then
        local view = currentTab and tabs[currentTab].view
        if view and view[method] then
            ns.SafeCall(method .. " " .. currentTab, view[method])
        end
    end
end

function UI.RefreshSteps()
    refreshPart("RefreshSteps")
end

function UI.RefreshClock()
    refreshPart("RefreshClock")
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function build()
    window = CreateFrame("Frame", "ForeverMemoriesMainFrame", UIParent, "BackdropTemplate")
    window:SetSize(UI.WIDTH, UI.HEIGHT)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    W.Backdrop(window, W.COLORS.background, 0.98, W.COLORS.gold, 0.9)
    window:Hide()
    ns.ownFrames[window] = true
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ForeverMemoriesMainFrame") -- Esc closes
    end
    local pad = UI.PAD

    -- Header: icon, name, slogan | status, pause, close.
    local logo = W.Icon(window, "Interface\\Icons\\INV_Misc_Spyglass_03", 30)
    logo:SetPoint("TOPLEFT", pad, -14)
    local title = W.Text(window, "ForeverMemories", "GameFontNormalLarge", W.COLORS.heading)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, 1)
    local slogan = W.Text(window, L.SLOGAN, "GameFontHighlightSmall", W.COLORS.muted)
    slogan:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 10, 0)

    local close = W.Button(window, "x", 24, 24, function() window:Hide() end)
    close:SetPoint("TOPRIGHT", -pad, -16)
    W.Tooltip(close, L.TIP_CLOSE, L.CLOSE)
    pauseButton = W.Button(window, "||||", 24, 24, function()
        ns.Engine.SetEnabled(not ns.db.settings.enabled)
    end)
    pauseButton:SetPoint("RIGHT", close, "LEFT", -6, 0)
    W.Tooltip(pauseButton, function()
        return ns.db.settings.enabled and L.TIP_PAUSE or L.TIP_RESUME
    end, function() return ns.db.settings.enabled and L.PAUSE or L.RESUME end)
    statusText = W.Text(window, "", "GameFontHighlightSmall")
    statusText:SetPoint("RIGHT", pauseButton, "LEFT", -10, 0)
    statusDot = W.Dot(window)
    statusDot:SetPoint("RIGHT", statusText, "LEFT", -6, 0)

    local top = W.Divider(window)
    top:SetPoint("TOPLEFT", pad, -58)
    top:SetPoint("TOPRIGHT", -pad, -58)

    -- Tabs.
    local gap = 6
    local tabWidth = (UI.CONTENT_WIDTH - gap * (#UI.TABS - 1)) / #UI.TABS
    for i, id in ipairs(UI.TABS) do
        local button = W.Button(window, L["TAB_" .. id], tabWidth, 28, function()
            UI.ShowTab(id, id == "history" and "shots" or nil) -- History opens on "Shots"
        end)
        button:SetPoint("TOPLEFT", pad + (i - 1) * (tabWidth + gap), -68)
        navButtons[id] = button
    end

    content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", pad, -108)
    content:SetPoint("BOTTOMRIGHT", -pad, 42)

    -- Footer.
    local bottom = W.Divider(window)
    bottom:SetPoint("BOTTOMLEFT", pad, 34)
    bottom:SetPoint("BOTTOMRIGHT", -pad, 34)
    local game = W.Text(window, "World of Warcraft: Forever", "GameFontHighlightSmall", W.COLORS.muted)
    game:SetPoint("BOTTOMLEFT", pad, 13)
    local version = W.Text(window, "v" .. ns.version .. "  ·  /fm", "GameFontHighlightSmall", W.COLORS.muted)
    version:SetPoint("BOTTOMRIGHT", -pad, 13)
    version:SetJustifyH("RIGHT")

    window:SetScript("OnShow", function()
        UI.ApplyScale()
        UI.Refresh()
    end)
    restorePosition()
    UI.ApplyScale()
    UI.ShowTab("home")
end

function UI.Toggle(tab, option)
    if not ns.db or not ns.character then
        return
    end
    if not window then
        build()
    end
    if window:IsShown() and not tab then
        window:Hide()
    else
        window:Show()
        if tab then
            UI.ShowTab(tab, option)
        end
        UI.Refresh()
    end
end

function UI.Open(tab, option)
    if not window or not window:IsShown() then
        UI.Toggle(tab or "home", option)
    elseif tab then
        UI.ShowTab(tab, option)
    end
end

-- Keep the window in sync with data changes.
table.insert(ns.History.listeners, UI.Refresh)
table.insert(ns.Engine.stateListeners, UI.Refresh)
table.insert(ns.Steps.listeners, UI.RefreshSteps)
table.insert(ns.Activity.listeners, UI.RefreshClock) -- no own timer

-- Asks before reloading the interface. The setting is already saved:
-- "Later" keeps it, and it applies at the next /reload or login.
function UI.ConfirmReload(text)
    StaticPopupDialogs.FOREVERMEMORIES_RELOAD = {
        text = text,
        button1 = L.RELOAD_NOW,
        button2 = L.LATER,
        OnAccept = function()
            local ok, reason = ns.API.ReloadUI()
            if not ok then
                ns.Logger.Warn("ReloadUI failed: " .. tostring(reason))
                ns.API.Print(L.RELOAD_MANUALLY)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FOREVERMEMORIES_RELOAD")
end

---------------------------------------------------------------------------
-- Shared pieces of Home and History.
---------------------------------------------------------------------------

-- Row of a shot (also used by the History tab).
function UI.MakeShotRow(parent, iconSize)
    local row = CreateFrame("Frame", nil, parent)
    row.icon = W.IconBox(row, ns.Registry.LEGACY_ICON, iconSize or 28)
    row.icon:SetPoint("LEFT", 0, 0)
    row.title = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.title:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    row.detail = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    row.time = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
    row.time:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.time:SetJustifyH("RIGHT")
    return row
end

function UI.FillShotRow(row, record, withDate)
    row.icon:SetIcon(ns.Registry.Icon(record.ev))
    row.title:SetText(ns.History.Title(record))
    row.detail:SetText(ns.History.Detail(record))
    row.time:SetText(date(withDate and "%d.%m %H:%M" or "%H:%M", record.t))
end

-- Class icon or a neutral portrait for the character line.
function UI.SetClassIcon(texture)
    local file, coords = ns.API.ClassIcon(ns.character and ns.character.class)
    if file then
        texture:SetTexture(file)
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- One statistics card (Home and History dashboards).
local CARD_HEIGHT = 80
local CARD_GAP = 8

function UI.StatCard(parent, icon, label, tip)
    local card = W.Panel(parent, W.COLORS.panel, W.COLORS.divider)
    card:SetSize((UI.CONTENT_WIDTH - CARD_GAP) / 2, CARD_HEIGHT)
    local image = W.Icon(card, icon, 18)
    image:SetPoint("TOP", 0, -9)
    card.value = W.Text(card, "0", "GameFontNormalHuge", W.COLORS.heading)
    card.value:SetPoint("TOP", image, "BOTTOM", 0, -5)
    card.value:SetJustifyH("CENTER")
    local caption = W.Text(card, label, "GameFontHighlightSmall", W.COLORS.muted)
    caption:SetPoint("BOTTOM", 0, 8)
    caption:SetJustifyH("CENTER")
    W.Tooltip(card, tip, label)
    return card
end

-- Four cards in a 2 x 2 grid starting `top` pixels below the parent's top.
-- `specs` = { { id, icon, label, tip }, ... } in reading order.
-- Returns the cards by id and the y offset right below the grid.
function UI.Dashboard(parent, top, specs)
    local cards = {}
    for i, spec in ipairs(specs) do
        local card = UI.StatCard(parent, spec[2], spec[3], spec[4])
        local row = math.floor((i - 1) / 2)
        card:SetPoint(i % 2 == 1 and "TOPLEFT" or "TOPRIGHT", 0, -top - row * (CARD_HEIGHT + CARD_GAP))
        cards[spec[1]] = card
    end
    return cards, top + 2 * CARD_HEIGHT + CARD_GAP
end

-- Character line: class icon, name, caption under the name.
function UI.CharacterHeader(parent, captionText)
    local portrait = parent:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(36, 36)
    portrait:SetPoint("TOPLEFT", 0, 0)
    local name = W.Text(parent, "", "GameFontNormalLarge", W.COLORS.heading)
    name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -2)
    local caption = W.Text(parent, captionText, "GameFontHighlightSmall", W.COLORS.muted)
    caption:SetPoint("BOTTOMLEFT", portrait, "BOTTOMRIGHT", 10, 2)
    return function()
        UI.SetClassIcon(portrait)
        name:SetText(ns.character and ns.character.name or "?")
    end
end

-- "5d 3h 30m" / "5 д 3 ч 30 мин" from a day on, "3h 42m" / "3 ч 42 мин"
-- from an hour on, otherwise only minutes: "42m".
function UI.FormatDuration(seconds)
    local minutes = math.floor((seconds or 0) / 60)
    local hours = math.floor(minutes / 60)
    local days = math.floor(hours / 24)
    if days > 0 then
        return string.format(L.DURATION_DHM, days, hours % 24, minutes % 60)
    end
    if hours > 0 then
        return string.format(L.DURATION_HM, hours, minutes % 60)
    end
    return string.format(L.DURATION_M, minutes)
end

-- "14:32": minutes and seconds left (minutes may exceed 59 for 60 min).
function UI.FormatCountdown(seconds)
    seconds = math.max(0, math.ceil(seconds or 0))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- Home: Daily adventure (v0.8.0). Only today of the current character.
---------------------------------------------------------------------------
local LATEST = 3

-- Countdown text and color for each state of the passive timer.
local function timerView(state, left, extra)
    if state == "countdown" then
        return UI.FormatCountdown(left), W.COLORS.heading
    elseif state == "waiting" then
        return L.TIMER_WAITING, W.COLORS.heading
    elseif state == "paused" then
        return extra == "afk" and L.TIMER_AFK or L.TIMER_PAUSED, W.COLORS.paused
    end
    return L.TIMER_DISABLED, W.COLORS.paused
end

UI.builders.home = function(parent)
    local refreshHeader = UI.CharacterHeader(parent, L.DAILY_ADVENTURE)
    local today = W.Text(parent, "", "GameFontHighlight", W.COLORS.text)
    today:SetPoint("TOPRIGHT", 0, -10)
    today:SetJustifyH("RIGHT")

    local cards, y = UI.Dashboard(parent, 46, {
        { "shots", "Interface\\Icons\\INV_Misc_Spyglass_03", L.STAT_TODAY, L.TIP_STAT_TODAY },
        { "steps", "Interface\\Icons\\Ability_Rogue_Sprint", L.STAT_STEPS_TODAY, L.STEPS_NOTE },
        { "zones", "Interface\\Icons\\INV_Misc_Map_01", L.STAT_ZONES_TODAY, L.TIP_STAT_ZONES_TODAY },
        { "playtime", "Interface\\Icons\\INV_Misc_PocketWatch_01", L.STAT_PLAYTIME_TODAY, L.TIP_STAT_PLAYTIME_TODAY },
    })

    -- Current location and the passive countdown.
    local box = W.Panel(parent, W.COLORS.panel, W.COLORS.divider)
    box:SetSize(UI.CONTENT_WIDTH, 96)
    box:SetPoint("TOPLEFT", 0, -(y + 10))
    local pin = W.Icon(box, "Interface\\Icons\\INV_Misc_Map_01", 18)
    pin:SetPoint("TOPLEFT", 12, -14)
    local zoneLabel = W.Text(box, L.CURRENT_LOCATION, "GameFontHighlightSmall", W.COLORS.muted)
    zoneLabel:SetPoint("TOPLEFT", pin, "TOPRIGHT", 10, 3)
    local zone = W.Text(box, "", "GameFontHighlight", W.COLORS.text)
    zone:SetPoint("BOTTOMLEFT", pin, "BOTTOMRIGHT", 10, -4)
    zone:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    local line = W.Divider(box)
    line:SetPoint("TOPLEFT", 12, -46)
    line:SetPoint("TOPRIGHT", -12, -46)
    local clock = W.Icon(box, "Interface\\Icons\\INV_Misc_PocketWatch_01", 16)
    clock:SetPoint("TOPLEFT", 13, -56)
    local timerLabel = W.Text(box, L.NEXT_PASSIVE, "GameFontHighlight", W.COLORS.text)
    timerLabel:SetPoint("LEFT", clock, "RIGHT", 10, 0)
    local timer = W.Text(box, "", "GameFontNormal", W.COLORS.heading)
    timer:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    timer:SetPoint("TOP", clock, "TOP", 0, 0)
    timer:SetJustifyH("RIGHT")
    local track = box:CreateTexture(nil, "ARTWORK")
    local trackWidth = UI.CONTENT_WIDTH - 24
    track:SetSize(trackWidth, 3)
    track:SetPoint("BOTTOMLEFT", 12, 12)
    local d = W.COLORS.divider
    track:SetColorTexture(d[1], d[2], d[3], 1)
    local fill = box:CreateTexture(nil, "OVERLAY")
    fill:SetHeight(3)
    fill:SetPoint("BOTTOMLEFT", 12, 12)
    local g = W.COLORS.gold
    fill:SetColorTexture(g[1], g[2], g[3], 1)
    W.Tooltip(box, L.TIP_NEXT_PASSIVE, L.NEXT_PASSIVE)

    -- Latest screenshots of today.
    local listTop = y + 10 + 96 + 14
    local heading = W.Heading(parent, L.LATEST_SHOTS)
    heading:SetPoint("TOPLEFT", 0, -listTop)
    local rows = {}
    for i = 1, LATEST do
        local row = UI.MakeShotRow(parent, 28)
        row:SetSize(UI.CONTENT_WIDTH, 32)
        row:SetPoint("TOPLEFT", 0, -(listTop + 26) - (i - 1) * 36)
        rows[i] = row
    end
    local empty = W.Text(parent, L.NO_SHOTS_TODAY, "GameFontHighlight", W.COLORS.muted)
    empty:SetPoint("TOPLEFT", 0, -(listTop + 34))
    local all = W.Link(parent, L.VIEW_SHOT_HISTORY, function() UI.ShowTab("history", "shots") end)
    all:SetPoint("BOTTOM", 0, 0)

    local function refreshSteps()
        cards.steps.value:SetText(ns.Num(ns.Steps.Today()))
    end
    -- Every second while Home is open (driven by the shared clock).
    local function refreshClock()
        cards.playtime.value:SetText(UI.FormatDuration(ns.Activity.Today()))
        cards.zones.value:SetText(ns.Num(ns.Locations.Today()))
        zone:SetText(ns.API.ZoneName() or L.UNKNOWN_LOCATION)
        local state, left, fraction, extra = ns.Passive.Timer()
        local text, color = timerView(state, left, extra)
        timer:SetText(text)
        timer:SetTextColor(color[1], color[2], color[3])
        fill:SetWidth(math.max(1, trackWidth * fraction))
        fill:SetShown(fraction > 0 and state ~= "disabled")
    end
    return {
        RefreshSteps = refreshSteps,
        RefreshClock = refreshClock,
        Refresh = function()
            refreshHeader()
            today:SetText(ns.History.DateText(ns.Util.DayKey(ns.API.Time())))
            cards.shots.value:SetText(ns.Num(ns.History.Stats().today))
            refreshSteps()
            refreshClock()
            local latest = ns.History.Today(LATEST)
            for i, row in ipairs(rows) do
                if latest[i] then
                    UI.FillShotRow(row, latest[i], false)
                    row:Show()
                else
                    row:Hide()
                end
            end
            empty:SetShown(#latest == 0)
        end,
    }
end

-- Addon Compartment (TOC: AddonCompartmentFunc) opens the window.
function ForeverMemories_OnAddonCompartmentClick()
    UI.Toggle()
end
