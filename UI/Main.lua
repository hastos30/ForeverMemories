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
local statusDot, statusText, pauseButton, whatsNew
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

function UI.ShowTab(id, option, extra)
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
    local switching = currentTab ~= id
    currentTab = id
    ns.db.ui.lastTab = id -- "Remember the last tab" (v0.10.0)
    local view = tabs[id].view
    if switching and view.Reset then
        ns.SafeCall("tab " .. id, view.Reset)
    end
    if option and view.Select then
        ns.SafeCall("tab " .. id, view.Select, option, extra)
    end
    if view.Refresh then
        ns.SafeCall("tab " .. id, view.Refresh)
    end
end

-- The view object of a built tab (tests and cross-tab links).
function UI.TabView(id)
    return tabs[id] and tabs[id].view
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
            UI.ShowTab(id, id == "history" and "overview" or nil) -- History opens on "Overview"
        end)
        button:SetPoint("TOPLEFT", pad + (i - 1) * (tabWidth + gap), -68)
        navButtons[id] = button
    end
    -- "What's new" (v0.10.0): a small gold dot on Settings after an update,
    -- until Settings / Changelog is opened. No popup.
    whatsNew = W.Dot(navButtons.settings)
    whatsNew:SetColor(W.COLORS.heading)
    whatsNew:SetPoint("TOPRIGHT", -6, -6)
    W.Tooltip(navButtons.settings, function()
        return whatsNew:IsShown() and string.format(L.WHATS_NEW_TIP, ns.version) or nil
    end, L.WHATS_NEW)
    UI.RefreshWhatsNew()

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
        local view = currentTab and tabs[currentTab].view
        if view and view.Reset then
            ns.SafeCall("tab " .. currentTab, view.Reset)
        end
        UI.ApplyScale()
        UI.Refresh()
    end)
    restorePosition()
    UI.ApplyScale()
    UI.ShowTab(UI.StartTab())
end

-- Tab shown when the window opens without a request for a tab.
function UI.StartTab()
    local last = ns.db.ui.lastTab
    if ns.db.settings.rememberTab and ns.Util.Contains(UI.TABS, last) then
        return last
    end
    return "home"
end

function UI.WhatsNew()
    return ns.db.ui.seenVersion ~= ns.version
end

function UI.RefreshWhatsNew()
    if whatsNew then
        whatsNew:SetShown(UI.WhatsNew())
    end
end

function UI.MarkChangelogSeen()
    ns.db.ui.seenVersion = ns.version
    UI.RefreshWhatsNew()
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
        local wasShown = window:IsShown()
        window:Show()
        if tab then
            UI.ShowTab(tab, option)
        elseif not wasShown and not ns.db.settings.rememberTab and currentTab ~= "home" then
            UI.ShowTab("home")
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
table.insert(ns.Journey.listeners, UI.Refresh)
table.insert(ns.DataTools.listeners, UI.Refresh)

-- A fresh install has nothing new to show; an update shows the dot.
table.insert(ns.onReady, function()
    if ns.db.ui.seenVersion == nil and next(ns.db.characters) == nil then
        ns.db.ui.seenVersion = ns.version
    end
end)

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

function UI.StatCard(parent, icon, label, tip, width)
    local card = W.Panel(parent, W.COLORS.panel, W.COLORS.divider)
    card:SetSize(((width or UI.CONTENT_WIDTH) - CARD_GAP) / 2, CARD_HEIGHT)
    local image = W.Icon(card, icon, 18)
    image:SetPoint("TOP", 0, -9)
    card.value = W.Text(card, "0", "GameFontNormalHuge", W.COLORS.heading)
    card.value:SetPoint("TOP", image, "BOTTOM", 0, -5)
    card.value:SetJustifyH("CENTER")
    local caption = W.Text(card, label, "GameFontHighlightSmall", W.COLORS.muted)
    caption:SetPoint("BOTTOM", 0, 8)
    caption:SetJustifyH("CENTER")
    card.caption = caption
    W.Tooltip(card, tip, label)
    return card
end

-- Four cards in a 2 x 2 grid starting `top` pixels below the parent's top.
-- `specs` = { { id, icon, label, tip }, ... } in reading order.
-- Returns the cards by id and the y offset right below the grid.
-- `width` (optional) is the width of the grid, the content width by default.
function UI.Dashboard(parent, top, specs, width)
    local cards = {}
    for i, spec in ipairs(specs) do
        local card = UI.StatCard(parent, spec[2], spec[3], spec[4], width)
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
    -- refresh([caption], [title, icon]): the current (or viewed) character,
    -- or a title with an icon (History / All characters).
    return function(text, title, icon)
        if icon then
            portrait:SetTexture(icon)
            portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            UI.SetClassIcon(portrait)
        end
        name:SetText(title or (ns.character and ns.character.name) or "?")
        caption:SetText(text or captionText)
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
-- Details of a session (Home / Last adventure, v0.12.0): a panel over the
-- tab. Counters missing for sessions older than 0.12.0 say "no data"; an
-- end that the game did not report (a crash) is shown as the last active
-- moment and marked, never as an exact end.
---------------------------------------------------------------------------
local SESSION_ROWS = {
    { "start", "SESSION_START" }, { "finish", "SESSION_END" }, { "active", "SESSION_ACTIVE" },
    { "shots", "RECAP_SHOTS" }, { "steps", "RECAP_STEPS" }, { "zones", "RECAP_ZONES" },
    { "newZones", "RECAP_NEW_ZONES" }, { "levels", "SESSION_LEVELS" },
}

function UI.SessionDetails(parent)
    local panel = W.Panel(parent, W.COLORS.background, W.COLORS.gold)
    panel:SetPoint("TOPLEFT", 0, -46)
    panel:SetPoint("BOTTOMRIGHT", 0, 0)
    panel:SetFrameLevel((parent:GetFrameLevel() or 0) + 20)
    panel:EnableMouse(true)
    panel:Hide()
    local title = W.Text(panel, L.LAST_ADVENTURE, "GameFontNormalLarge", W.COLORS.heading)
    title:SetPoint("TOPLEFT", 16, -16)
    local close = W.Link(panel, L.CLOSE, function() panel:Hide() end)
    close:SetPoint("TOPRIGHT", -16, -18)
    local rows = {}
    for i, spec in ipairs(SESSION_ROWS) do
        local label = W.Text(panel, L[spec[2]], "GameFontHighlight", W.COLORS.text)
        label:SetPoint("TOPLEFT", 16, -56 - (i - 1) * 30)
        local value = W.Text(panel, "", "GameFontNormal", W.COLORS.heading)
        value:SetPoint("TOPRIGHT", -16, -56 - (i - 1) * 30)
        value:SetJustifyH("RIGHT")
        local line = W.Divider(panel)
        line:SetPoint("TOPLEFT", 16, -78 - (i - 1) * 30)
        line:SetPoint("TOPRIGHT", -16, -78 - (i - 1) * 30)
        rows[spec[1]] = { label = label, value = value }
    end
    local note = W.Text(panel, "", "GameFontHighlightSmall", W.COLORS.muted)
    note:SetPoint("TOPLEFT", 16, -64 - #SESSION_ROWS * 30)
    note:SetPoint("RIGHT", panel, "RIGHT", -16, 0)

    function panel:ShowSession(s)
        local function count(v) return v and ns.Num(v) or L.NO_DATA end
        local texts = {
            start = date("%d.%m.%Y %H:%M", s.start),
            finish = s.finish and date("%d.%m.%Y %H:%M", s.finish) or L.NO_DATA,
            active = UI.FormatDuration(s.active),
            shots = count(s.shots), steps = count(s.steps), zones = count(s.zones),
            newZones = count(s.newZones), levels = count(s.levels),
        }
        for id, row in pairs(rows) do
            row.value:SetText(texts[id])
        end
        rows.finish.label:SetText(s.endKnown and L.SESSION_END or L.SESSION_LAST_ACTIVE)
        local notes = {}
        if not s.endKnown then
            notes[#notes + 1] = L.SESSION_END_UNKNOWN
        end
        if not s.shots then
            notes[#notes + 1] = L.SESSION_OLD
        end
        notes[#notes + 1] = L.SESSION_NOTE
        note:SetText(table.concat(notes, " "))
        self:Show()
    end
    return panel
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

    -- Adventure Anniversary (v0.13.0): on a memorable day it takes the
    -- place of the third latest screenshot. It counts from the first login
    -- with ForeverMemories, not from the creation of the character.
    local anniversary = W.Panel(parent, W.COLORS.panel, W.COLORS.gold)
    anniversary:SetSize(UI.CONTENT_WIDTH, 32)
    anniversary:SetPoint("TOPLEFT", 0, -(listTop + 26) - (LATEST - 1) * 36)
    local annivIcon = W.Icon(anniversary, "Interface\\Icons\\INV_Crown_01", 20)
    annivIcon:SetPoint("LEFT", 8, 0)
    local annivTitle = W.Text(anniversary, "", "GameFontNormal", W.COLORS.heading)
    annivTitle:SetPoint("LEFT", annivIcon, "RIGHT", 8, 0)
    local annivStats = W.Text(anniversary, "", "GameFontHighlightSmall", W.COLORS.text)
    annivStats:SetPoint("RIGHT", -10, 0)
    annivStats:SetJustifyH("RIGHT")
    W.Tooltip(anniversary, L.TIP_ANNIVERSARY, L.ANNIVERSARY)
    anniversary:Hide()
    local function refreshAnniversary()
        local a = ns.Memories.Anniversary()
        anniversary:SetShown(a ~= nil)
        if not a then
            return false
        end
        annivTitle:SetText(a.kind == "YEAR" and string.format(L.ANNIV_YEAR, ns.Count(a.years, "YEARS"))
            or L["ANNIV_" .. a.kind])
        local s = ns.DataTools.Summary(ns.character)
        annivStats:SetText(table.concat({
            string.format(L.ANNIV_SINCE, date("%d.%m.%Y", a.started)),
            ns.Count(s.shots, "SHOTS"), ns.Count(s.steps, "STEPS"), ns.Count(s.zones, "ZONES"),
        }, "  ·  "))
        return true
    end

    -- Last adventure (v0.12.0, replaces "Adventure This Week", which stays
    -- in History / Overview): the last completed session of this
    -- character; a click opens its details.
    local last = CreateFrame("Button", nil, parent, "BackdropTemplate")
    W.Backdrop(last, W.COLORS.panel, 0.95, W.COLORS.divider)
    last:SetSize(UI.CONTENT_WIDTH, 52)
    last:SetPoint("TOPLEFT", 0, -(listTop + 26 + LATEST * 36 + 4))
    local lastTitle = W.Text(last, L.LAST_ADVENTURE, "GameFontNormal", W.COLORS.heading)
    lastTitle:SetPoint("TOPLEFT", 12, -9)
    local lastMore = W.Text(last, L.DETAILS, "GameFontHighlightSmall", W.COLORS.gold)
    lastMore:SetPoint("TOPRIGHT", -12, -10)
    lastMore:SetJustifyH("RIGHT")
    local lastValues = W.Text(last, "", "GameFontHighlightSmall", W.COLORS.text)
    lastValues:SetPoint("BOTTOMLEFT", 12, 9)
    lastValues:SetPoint("RIGHT", last, "RIGHT", -12, 0)
    W.AddScript(last, "OnEnter", function() local g = W.COLORS.gold; last:SetBackdropBorderColor(g[1], g[2], g[3], 1) end)
    W.AddScript(last, "OnLeave", function() local d = W.COLORS.divider; last:SetBackdropBorderColor(d[1], d[2], d[3], 1) end)
    W.Tooltip(last, L.TIP_LAST_ADVENTURE, L.LAST_ADVENTURE)
    local details = UI.SessionDetails(parent)
    last:SetScript("OnClick", function()
        local session = ns.Activity.LastSession()
        if session then
            details:ShowSession(session)
        end
    end)
    local function refreshLast()
        local session = ns.Activity.LastSession()
        lastMore:SetShown(session ~= nil)
        if not session then
            lastValues:SetText(L.NO_LAST_ADVENTURE)
            return
        end
        local parts = { date("%d.%m", session.start), UI.FormatDuration(session.active) }
        if session.shots then
            parts[#parts + 1] = ns.Count(session.shots, "SHOTS")
            parts[#parts + 1] = ns.Count(session.steps or 0, "STEPS")
            parts[#parts + 1] = ns.Count(session.zones or 0, "ZONES")
        end
        lastValues:SetText(table.concat(parts, "   ·   "))
    end
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
        LastAdventure = last,
        RefreshSteps = refreshSteps,
        RefreshClock = refreshClock,
        Refresh = function()
            refreshHeader()
            today:SetText(ns.History.DateText(ns.Util.DayKey(ns.API.Time())))
            cards.shots.value:SetText(ns.Num(ns.History.Stats().today))
            refreshSteps()
            refreshClock()
            local shown = refreshAnniversary() and LATEST - 1 or LATEST
            local latest = ns.History.Today(shown)
            for i, row in ipairs(rows) do
                if latest[i] and i <= shown then
                    UI.FillShotRow(row, latest[i], false)
                    row:Show()
                else
                    row:Hide()
                end
            end
            empty:SetShown(#latest == 0)
            refreshLast()
        end,
    }
end

-- Addon Compartment (TOC: AddonCompartmentFunc) opens the window.
function ForeverMemories_OnAddonCompartmentClick()
    UI.Toggle()
end
