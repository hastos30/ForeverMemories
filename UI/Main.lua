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
-- Window size (v0.15.0): the content keeps its designed width and is
-- centered; lists grow with the height. Layout modes by available width
-- (thresholds are starting points, to be measured in the client).
-- v1.0.0-beta.5: down to 440 x 600 (spec: compact 440 x 600, standard
-- 660 x 680, wide 900 x 760; changes near 520 and 780 at 100 %). Pages
-- that do not fit the height scroll.
UI.MIN_WIDTH, UI.MIN_HEIGHT = 440, 600
UI.MAX_WIDTH, UI.MAX_HEIGHT = 1400, 1200
UI.LAYOUTS = { { "compact", 0 }, { "standard", 520 }, { "wide", 780 } }
UI.CHROME_HEIGHT = 150 -- header, tabs and footer: content = window - 150
UI.builders = {}

local window, content, tabBar
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

-- Saved size clamped to the bounds and to the screen.
local function savedSize()
    local size = ns.db.ui.size
    local w, h = UI.WIDTH, UI.HEIGHT
    if type(size) == "table" and type(size[1]) == "number" and type(size[2]) == "number" then
        w, h = size[1], size[2]
    end
    return UI.ClampSize(w, h)
end

-- A size kept within the bounds and the screen (v1.0.1: also while dragging).
function UI.ClampSize(w, h)
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local scale = (ns.db.settings.scale or 1)
    local maxW, maxH = UI.MAX_WIDTH, UI.MAX_HEIGHT
    if type(screenW) == "number" and screenW > 0 and type(screenH) == "number" and screenH > 0 then
        maxW, maxH = math.min(maxW, screenW / scale), math.min(maxH, screenH / scale)
    end
    w = math.max(UI.MIN_WIDTH, math.min(w, maxW))
    h = math.max(UI.MIN_HEIGHT, math.min(h, maxH))
    return math.floor(w), math.floor(h)
end

-- v1.0.1: the content follows the width of the window (it used to keep
-- its designed 588 px). Pages read UI.CONTENT_WIDTH when they are built,
-- so after the size settles (mouse released, /reload, reset) the built
-- pages are built again at the new width. While dragging only the height
-- follows, which is cheap. Very wide windows keep the content centered.
UI.BASE_CONTENT_WIDTH = UI.CONTENT_WIDTH
UI.MIN_CONTENT_WIDTH = UI.MIN_WIDTH - 2 * UI.PAD -- v1.0.0-beta.5: 408
UI.MAX_CONTENT_WIDTH = 1000
function UI.ContentWidthFor(w)
    local cw = math.min(UI.MAX_CONTENT_WIDTH, (w or UI.WIDTH) - 2 * UI.PAD)
    return math.floor(math.max(UI.MIN_CONTENT_WIDTH, cw))
end

-- Tabs whose page has a fixed layout: it scrolls when the window is lower
-- than the page (v1.0.0-beta.5). The others are lists that scroll anyway.
UI.SCROLL_TABS = { home = true }

-- Main tab icons (v1.0.0-beta.8) and the narrowest tab that still shows one.
UI.TAB_ICONS = { home = "home", capture = "auto_capture", history = "history", settings = "settings" }
UI.TAB_ICON_MIN_WIDTH = 120
UI.GOAL_FULL_COUNT_WIDTH = 190 -- narrower goal cards on Home show a percent

local function placeTabs()
    if not tabBar then return end
    local gap = 6
    local tabWidth = (UI.CONTENT_WIDTH - gap * (#UI.TABS - 1)) / #UI.TABS
    tabBar:SetWidth(UI.CONTENT_WIDTH)
    for i, id in ipairs(UI.TABS) do
        local button = navButtons[id]
        button:SetWidth(tabWidth)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", (i - 1) * (tabWidth + gap), 0)
        -- v1.0.0-beta.8: icon left of the name when the tab has room for both.
        local roomy = tabWidth >= UI.TAB_ICON_MIN_WIDTH
        button.icon:SetShown(roomy)
        button.label:ClearAllPoints()
        button.label:SetPoint("CENTER", roomy and 12 or 0, 0)
    end
end

function UI.OnWidthChanged(w)
    UI.currentWidth = w
    -- v1.0.0-beta.5: a compact header keeps the status dot only.
    if statusText then
        statusText:SetShown(UI.Layout(w) ~= "compact")
    end
    local cw = UI.ContentWidthFor(w)
    if cw == UI.CONTENT_WIDTH then
        return
    end
    UI.CONTENT_WIDTH = cw
    if not content then
        return
    end
    content:SetWidth(cw)
    placeTabs()
    -- Build the pages again; the open one keeps its sub-page.
    local open = currentTab
    local option = open and tabs[open] and tabs[open].view.Current and tabs[open].view.Current()
    for _, frame in pairs(tabs) do
        frame:Hide()
    end
    tabs = {}
    W.ForgetStretched()
    if open then
        UI.ShowTab(open, option)
    end
end

local function applySize()
    local w, h = savedSize()
    window:SetSize(w, h)
    W.SetExtraHeight(h - UI.HEIGHT)
    UI.OnWidthChanged(w)
end

-- Layout mode of the current window width: "compact", "standard" or "wide".
function UI.Layout(width)
    width = width or (window and window:GetWidth()) or UI.WIDTH
    local mode = UI.LAYOUTS[1][1]
    for _, entry in ipairs(UI.LAYOUTS) do
        if width >= entry[2] then
            mode = entry[1]
        end
    end
    return mode
end

-- Settings / Appearance: "Reset size and position".
function UI.ResetGeometry()
    ns.db.ui.point, ns.db.ui.size = nil, nil
    if window then
        applySize()
        restorePosition()
    end
end

function UI.Resize(w, h)
    ns.db.ui.size = { w, h }
    if window then
        applySize()
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
        local built
        if UI.SCROLL_TABS[id] then
            local page = W.ScrollPage(frame, UI.CONTENT_WIDTH)
            built = UI.builders[id] and UI.builders[id](page.child) or {}
            page:SetContentHeight(built.height or (UI.HEIGHT - UI.CHROME_HEIGHT))
            frame.page = page
        else
            built = UI.builders[id] and UI.builders[id](frame) or {}
        end
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
-- Gold ornaments of the frame (v1.0.0-beta.8): the corner of the
-- decoration set in all four corners (mirrored with SetTexCoord) and the
-- compass divider in the middle of the footer line. Pure decoration:
-- textures only, no mouse, nothing depends on them.
UI.CORNER_SIZE = 36
function UI.Decorate(frame, footerLine)
    local M = ns.Media
    local corners = {
        { "TOPLEFT", 3, -3, 0, 1, 0, 1 }, { "TOPRIGHT", -3, -3, 1, 0, 0, 1 },
        { "BOTTOMLEFT", 3, 3, 0, 1, 1, 0 }, { "BOTTOMRIGHT", -3, 3, 1, 0, 1, 0 },
    }
    for _, c in ipairs(corners) do
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(M.DECOR.corner_large)
        tex:SetSize(UI.CORNER_SIZE, UI.CORNER_SIZE)
        tex:SetTexCoord(c[4], c[5], c[6], c[7])
        tex:SetPoint(c[1], c[2], c[3])
    end
    if footerLine then
        local ornament = frame:CreateTexture(nil, "ARTWORK")
        ornament:SetTexture(M.DECOR.divider_compass)
        ornament:SetSize(128, 32)
        ornament:SetPoint("CENTER", footerLine, "CENTER", 0, 0)
    end
end

local function build()
    window = CreateFrame("Frame", "ForeverMemoriesMainFrame", UIParent, "BackdropTemplate")
    window:SetSize(UI.WIDTH, UI.HEIGHT)
    window:SetFrameStrata("DIALOG")
    if window.SetResizable then
        window:SetResizable(true)
    end
    if window.SetResizeBounds then
        window:SetResizeBounds(UI.MIN_WIDTH, UI.MIN_HEIGHT, UI.MAX_WIDTH, UI.MAX_HEIGHT)
    elseif window.SetMinResize then
        window:SetMinResize(UI.MIN_WIDTH, UI.MIN_HEIGHT)
        if window.SetMaxResize then window:SetMaxResize(UI.MAX_WIDTH, UI.MAX_HEIGHT) end
    end
    window:SetClampedToScreen(true)
    -- v1.0.1-beta.3: while the corner is dragged the pages keep their width
    -- until the mouse is released, so nothing may be drawn outside the frame.
    if window.SetClipsChildren then
        window:SetClipsChildren(true)
    end
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    W.Backdrop(window, W.COLORS.background, 1, W.COLORS.divider, 1)
    -- Obsidian background: opaque, a light texture; the solid color under
    -- it stays if the texture cannot be shown.
    local backdrop = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    backdrop:SetPoint("TOPLEFT", 1, -1)
    backdrop:SetPoint("BOTTOMRIGHT", -1, 1)
    backdrop:SetTexture(ns.Media.BACKGROUND)
    backdrop:SetAlpha(0.9)
    window:Hide()
    ns.ownFrames[window] = true
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ForeverMemoriesMainFrame") -- Esc closes
    end
    local pad = UI.PAD

    -- Header: icon, name, slogan | status, pause, close.
    -- Compass and text in the header; the full logo is only on About.
    local logo = window:CreateTexture(nil, "ARTWORK")
    logo:SetSize(36, 36)
    logo:SetTexture(ns.Media.COMPASS)
    logo:SetPoint("TOPLEFT", pad + 2, -12)
    local title = window:CreateFontString(nil, "OVERLAY", ns.Fonts.Template("GameFontNormalLarge") == "GameFontNormalLarge"
        and "GameFontNormalLarge" or "ForeverMemoriesFontTitle")
    title:SetText("ForeverMemories")
    title:SetTextColor(W.COLORS.heading[1], W.COLORS.heading[2], W.COLORS.heading[3])
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
    tabBar = CreateFrame("Frame", nil, window)
    tabBar:SetSize(UI.CONTENT_WIDTH, 28)
    tabBar:SetPoint("TOP", 0, -68)
    for _, id in ipairs(UI.TABS) do
        navButtons[id] = W.Button(tabBar, L["TAB_" .. id], 100, 28, function()
            UI.ShowTab(id, id == "history" and "overview" or nil) -- History opens on "Overview"
        end)
        local button = navButtons[id]
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(20, 20)
        button.icon:SetTexture(ns.Media.NAV[UI.TAB_ICONS[id]])
        button.icon:SetPoint("RIGHT", button.label, "LEFT", -6, 0)
    end
    placeTabs()
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
    -- Designed width, centered; the height follows the window.
    content:SetWidth(UI.CONTENT_WIDTH)
    content:SetPoint("TOP", 0, -108)
    content:SetPoint("BOTTOM", 0, 42)

    -- Footer.
    local bottom = W.Divider(window)
    bottom:SetPoint("BOTTOMLEFT", pad, 34)
    bottom:SetPoint("BOTTOMRIGHT", -pad, 34)
    local game = W.Text(window, "World of Warcraft: Forever", "GameFontHighlightSmall", W.COLORS.muted)
    game:SetPoint("BOTTOMLEFT", pad + 8, 13)
    local version = W.Text(window, "v" .. ns.version .. "  ·  /fm", "GameFontHighlightSmall", W.COLORS.muted)
    version:SetPoint("BOTTOMRIGHT", -pad - 12, 13)
    UI.Decorate(window, bottom)
    version:SetJustifyH("RIGHT")

    -- Resize grip (v0.15.0): drag the bottom-right corner. The size is
    -- saved when the mouse is released and kept within the bounds.
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    -- v1.0.1: the size follows the cursor in our own code. The client's
    -- StartSizing jumped to the default and then to the largest size in
    -- Forever (the window is anchored at its center). Here the window is
    -- re-anchored by its top-left corner first, so only the right and the
    -- bottom edges move, and every step is kept within the bounds.
    local sizing
    local function cursor()
        local x, y = GetCursorPosition()
        local scale = window:GetEffectiveScale() or 1
        return (x or 0) / scale, (y or 0) / scale
    end
    local function sizeStep()
        if not sizing then return end
        local x, y = cursor()
        local w, h = UI.ClampSize(sizing.w + (x - sizing.x), sizing.h + (sizing.y - y))
        if w ~= math.floor(window:GetWidth() + 0.5) or h ~= math.floor(window:GetHeight() + 0.5) then
            window:SetSize(w, h)
            W.SetExtraHeight(h - UI.HEIGHT)
        end
    end
    local function stopSizing()
        if not sizing then return end
        sizing = nil
        grip:SetScript("OnUpdate", nil)
        content:SetAlpha(1)
        tabBar:SetAlpha(1)
        UI.Resize(math.floor(window:GetWidth() + 0.5), math.floor(window:GetHeight() + 0.5))
        savePosition()
    end
    grip:SetScript("OnMouseDown", function()
        local left, top = window:GetLeft(), window:GetTop()
        if type(left) == "number" and type(top) == "number" then
            window:ClearAllPoints()
            window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        local x, y = cursor()
        sizing = { x = x, y = y, w = window:GetWidth(), h = window:GetHeight() }
        -- A client without clipping: the pages wait hidden until release.
        if not window.SetClipsChildren then
            content:SetAlpha(0)
            tabBar:SetAlpha(0)
        end
        grip:SetScript("OnUpdate", function()
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                return stopSizing()
            end
            sizeStep()
        end)
    end)
    grip:SetScript("OnMouseUp", stopSizing)
    grip:SetScript("OnHide", stopSizing)
    UI.SizeStep = sizeStep -- tests
    UI.grip = grip
    window:SetScript("OnSizeChanged", function(_, _, h)
        W.SetExtraHeight((h or UI.HEIGHT) - UI.HEIGHT)
    end)

    window:SetScript("OnShow", function()
        local view = currentTab and tabs[currentTab].view
        if view and view.Reset then
            ns.SafeCall("tab " .. currentTab, view.Reset)
        end
        UI.ApplyScale()
        UI.Refresh()
    end)
    applySize()
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
    local image = W.Icon(card, icon, 24) -- v1.0.0-beta.8: our art, 24 px (was an 18 px game icon)
    image:SetPoint("TOP", 0, -7)
    card.value = W.Text(card, "0", "GameFontNormalHuge", W.COLORS.heading)
    card.value:SetPoint("TOP", image, "BOTTOM", 0, -3)
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
            if ns.Media.IsOwn(icon) then
                portrait:SetTexCoord(0, 1, 0, 1)
            else
                portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
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
UI.TimerView = timerView

UI.builders.home = function(parent)
    local refreshHeader = UI.CharacterHeader(parent, L.DAILY_ADVENTURE)
    local today = W.Text(parent, "", "GameFontHighlight", W.COLORS.text)
    today:SetPoint("TOPRIGHT", 0, -10)
    today:SetJustifyH("RIGHT")

    local cards, y = UI.Dashboard(parent, 46, {
        { "shots", ns.Media.ICON.shots, L.STAT_TODAY, L.TIP_STAT_TODAY },
        { "steps", ns.Media.ICON.steps, L.STAT_STEPS_TODAY, L.STEPS_NOTE },
        { "zones", ns.Media.ICON.zones, L.STAT_ZONES_TODAY, L.TIP_STAT_ZONES_TODAY },
        { "playtime", ns.Media.ICON.playtime, L.STAT_PLAYTIME_TODAY, L.TIP_STAT_PLAYTIME_TODAY },
    })

    -- Current location and the passive countdown, side by side (v0.16.0).
    local box = W.Panel(parent, W.COLORS.panel, W.COLORS.divider)
    box:SetSize(UI.CONTENT_WIDTH, 60)
    box:SetPoint("TOPLEFT", 0, -(y + 10))
    local half = UI.CONTENT_WIDTH / 2
    local pin = W.Icon(box, ns.Media.ICON.newZones, 18)
    pin:SetPoint("TOPLEFT", 12, -12)
    local zoneLabel = W.Text(box, L.CURRENT_LOCATION, "GameFontHighlightSmall", W.COLORS.muted)
    zoneLabel:SetPoint("TOPLEFT", pin, "TOPRIGHT", 10, 3)
    local zone = W.Text(box, "", "GameFontHighlight", W.COLORS.text)
    zone:SetPoint("BOTTOMLEFT", pin, "BOTTOMRIGHT", 10, -4)
    zone:SetWidth(half - 52)
    local split = box:CreateTexture(nil, "ARTWORK")
    local d = W.COLORS.divider
    split:SetColorTexture(d[1], d[2], d[3], 1)
    split:SetSize(1, 36)
    split:SetPoint("TOPLEFT", half, -10)
    local clock = W.Icon(box, ns.Media.ICON.playtime, 18)
    clock:SetPoint("TOPLEFT", half + 14, -12)
    local timerLabel = W.Text(box, L.NEXT_PASSIVE, "GameFontHighlightSmall", W.COLORS.muted)
    timerLabel:SetPoint("TOPLEFT", clock, "TOPRIGHT", 10, 3)
    local timer = W.Text(box, "", "GameFontNormal", W.COLORS.heading)
    timer:SetPoint("BOTTOMLEFT", clock, "BOTTOMRIGHT", 10, -4)
    local track = box:CreateTexture(nil, "ARTWORK")
    local trackWidth = UI.CONTENT_WIDTH - 24
    track:SetSize(trackWidth, 3)
    track:SetPoint("BOTTOMLEFT", 12, 6)
    track:SetColorTexture(d[1], d[2], d[3], 1)
    local fill = box:CreateTexture(nil, "OVERLAY")
    fill:SetHeight(3)
    fill:SetPoint("BOTTOMLEFT", 12, 6)
    local g = W.COLORS.gold
    fill:SetColorTexture(g[1], g[2], g[3], 1)
    W.Tooltip(box, L.TIP_NEXT_PASSIVE, L.NEXT_PASSIVE)

    -- Goals (v0.16.0): three small cards, pinned achievements first, then
    -- the nearest ones. A click opens the Hall of Memories.
    local goalsTop = y + 10 + 60 + 10
    local goalWidth = (UI.CONTENT_WIDTH - 2 * 8) / 3
    local goals = {}
    for i = 1, 3 do
        local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
        W.Backdrop(card, W.COLORS.panel, 0.95, W.COLORS.divider)
        card:SetSize(goalWidth, 46)
        card:SetPoint("TOPLEFT", (i - 1) * (goalWidth + 8), -goalsTop)
        card.medal = W.Medallion(card, 36)
        card.medal:SetPoint("LEFT", 4, 0)
        card.title = W.Text(card, "", "GameFontHighlightSmall", W.COLORS.text)
        card.title:SetPoint("TOPLEFT", card.medal, "TOPRIGHT", 4, -3)
        card.title:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        card.tag = W.Text(card, "", "GameFontHighlightSmall", W.COLORS.gold)
        card.tag:SetPoint("BOTTOMLEFT", card.medal, "BOTTOMRIGHT", 4, 6)
        card.count = W.Text(card, "", "GameFontHighlightSmall", W.COLORS.heading)
        card.count:SetPoint("BOTTOMRIGHT", -8, 9)
        card.count:SetJustifyH("RIGHT")
        -- v1.0.0-beta.9: the tag ends before the count (cut with "..."), never under it.
        card.tag:SetPoint("RIGHT", card.count, "LEFT", -4, 0)
        card.track = card:CreateTexture(nil, "ARTWORK")
        card.track:SetColorTexture(d[1], d[2], d[3], 1)
        card.track:SetHeight(2)
        card.track:SetPoint("BOTTOMLEFT", 44, 4)
        card.track:SetPoint("BOTTOMRIGHT", -8, 4)
        card.bar = card:CreateTexture(nil, "OVERLAY")
        card.bar:SetColorTexture(g[1], g[2], g[3], 1)
        card.bar:SetHeight(2)
        card.bar:SetPoint("BOTTOMLEFT", 44, 4)
        card:SetScript("OnClick", function() UI.ShowTab("history", "achievements") end)
        W.AddScript(card, "OnEnter", function() card:SetBackdropBorderColor(g[1], g[2], g[3], 1) end)
        W.AddScript(card, "OnLeave", function() card:SetBackdropBorderColor(d[1], d[2], d[3], 1) end)
        W.Tooltip(card, function() return card.tip end, function() return card.tipTitle end)
        card:Hide()
        goals[i] = card
    end
    local noGoals = W.Text(parent, L.HOME_NO_GOALS, "GameFontHighlightSmall", W.COLORS.muted)
    noGoals:SetPoint("TOPLEFT", 0, -(goalsTop + 16))
    local function refreshGoals()
        local list = ns.Achievements.Goals(3)
        for i, card in ipairs(goals) do
            local goal = list[i]
            card:SetShown(goal ~= nil)
            if goal then
                local a, def = goal.achievement, goal.achievement.def
                local M = ns.Media
                card.medal:Set(M.MEDALLIONS[def.medallion] or M.MEDALLIONS.special, M.FRAMES[def.rarity], 1)
                local title = ns.Achievements.Text(def, "title") or def.id
                card.title:SetText(title)
                card.tag:SetText(goal.pinned and L.HOME_PINNED or L.HOME_NEAREST)
                local value, target = a.value, a.target
                local part = 0
                if type(value) == "number" and type(target) == "number" and target > 0 then
                    value = math.min(value, target)
                    part = value / target
                    -- A narrow card (compact window) shows the percent: "19 850 / 36 000"
                    -- does not fit next to the tag there (v1.0.0-beta.9).
                    if goalWidth < UI.GOAL_FULL_COUNT_WIDTH then
                        card.count:SetText(math.floor(part * 100) .. "%")
                    else
                        card.count:SetText(ns.Num(value) .. " / " .. ns.Num(target))
                    end
                else
                    card.count:SetText("-")
                end
                card.bar:SetWidth(math.max(1, (goalWidth - 52) * part))
                card.bar:SetShown(part > 0)
                card.tipTitle = title
                card.tip = (ns.Achievements.Text(def, "description") or "") .. "\n\n"
                    .. (goal.pinned and L.TIP_HOME_PINNED or L.TIP_HOME_NEAREST)
            end
        end
        noGoals:SetShown(#list == 0)
    end

    -- Latest screenshots of today.
    local listTop = goalsTop + 46 + 8
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
    local annivIcon = W.Icon(anniversary, ns.Media.ICON.achievements, 20)
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
    -- v1.0.0-beta.7: "Last adventure" and "This week" side by side, or one
    -- under the other in a narrow window (the page scrolls then).
    local bottomTop = listTop + 26 + LATEST * 36 + 4
    local side = UI.CONTENT_WIDTH >= 560
    local panelW = side and (UI.CONTENT_WIDTH - 8) / 2 or UI.CONTENT_WIDTH
    local PANEL_H = 60
    local last = CreateFrame("Button", nil, parent, "BackdropTemplate")
    W.Backdrop(last, W.COLORS.panel, 0.95, W.COLORS.divider)
    last:SetSize(panelW, PANEL_H)
    last:SetPoint("TOPLEFT", 0, -bottomTop)
    local lastTitle = W.Text(last, L.LAST_ADVENTURE, "GameFontNormal", W.COLORS.heading)
    lastTitle:SetPoint("TOPLEFT", 12, -9)
    local lastMore = W.Text(last, L.DETAILS, "GameFontHighlightSmall", W.COLORS.gold)
    lastMore:SetPoint("TOPRIGHT", -12, -10)
    lastMore:SetJustifyH("RIGHT")
    local lastValues = W.Text(last, "", "GameFontHighlightSmall", W.COLORS.text)
    lastValues:SetPoint("TOPLEFT", 12, -28)
    lastValues:SetPoint("RIGHT", last, "RIGHT", -12, 0)
    if lastValues.SetWordWrap then lastValues:SetWordWrap(true) end
    lastValues:SetJustifyV("TOP")
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
        lastValues:SetText(table.concat(parts, "  ·  "))
    end
    -- This week (v1.0.0-beta.7): totals from Monday to today; a click opens
    -- History / Overview with the Recap.
    local weekTop = side and bottomTop or (bottomTop + PANEL_H + 8)
    local week = CreateFrame("Button", nil, parent, "BackdropTemplate")
    W.Backdrop(week, W.COLORS.panel, 0.95, W.COLORS.divider)
    week:SetSize(panelW, PANEL_H)
    week:SetPoint("TOPRIGHT", 0, -weekTop)
    local weekTitle = W.Text(week, L.HOME_WEEK, "GameFontNormal", W.COLORS.heading)
    weekTitle:SetPoint("TOPLEFT", 12, -9)
    local weekDays = W.Text(week, "", "GameFontHighlightSmall", W.COLORS.gold)
    weekDays:SetPoint("TOPRIGHT", -12, -10)
    weekDays:SetJustifyH("RIGHT")
    local weekValues = W.Text(week, "", "GameFontHighlightSmall", W.COLORS.text)
    weekValues:SetPoint("TOPLEFT", 12, -28)
    weekValues:SetPoint("RIGHT", week, "RIGHT", -12, 0)
    if weekValues.SetWordWrap then weekValues:SetWordWrap(true) end
    weekValues:SetJustifyV("TOP")
    W.AddScript(week, "OnEnter", function() local g = W.COLORS.gold; week:SetBackdropBorderColor(g[1], g[2], g[3], 1) end)
    W.AddScript(week, "OnLeave", function() local d = W.COLORS.divider; week:SetBackdropBorderColor(d[1], d[2], d[3], 1) end)
    W.Tooltip(week, L.TIP_HOME_WEEK, L.HOME_WEEK)
    week:SetScript("OnClick", function() UI.ShowTab("history", "overview") end)
    local function refreshWeek()
        local t = ns.Adventure.Week()
        weekDays:SetText(string.format(L.HOME_WEEK_DAYS, t.days))
        local parts = {
            ns.Count(t.shots, "SHOTS"), ns.Count(t.steps, "STEPS"), ns.Count(t.zones, "ZONES"),
            UI.FormatDuration(t.playtime),
        }
        if t.newZones > 0 then
            parts[#parts + 1] = string.format(L.HOME_WEEK_NEW, t.newZones)
        end
        weekValues:SetText(table.concat(parts, "  ·  "))
    end

    -- The link to the whole history sits next to "Latest screenshots".
    local all = W.Link(parent, L.VIEW_SHOT_HISTORY, function() UI.ShowTab("history", "shots") end)
    all:SetPoint("TOPRIGHT", 0, -(listTop - 2))

    local function refreshSteps()
        cards.steps.value:SetText(ns.Num(ns.Steps.Today()))
    end
    -- Every second while Home is open (driven by the shared clock).
    local function refreshClock()
        cards.playtime.value:SetText(UI.FormatDuration(ns.Activity.Today()))
        cards.zones.value:SetText(ns.Num(ns.Locations.Today()))
        zone:SetText(ns.ZoneText(ns.API.ZoneName()) or L.UNKNOWN_LOCATION)
        local state, left, fraction, extra = ns.Passive.Timer()
        local text, color = timerView(state, left, extra)
        timer:SetText(text)
        timer:SetTextColor(color[1], color[2], color[3])
        fill:SetWidth(math.max(1, trackWidth * fraction))
        fill:SetShown(fraction > 0 and state ~= "disabled")
    end
    return {
        height = weekTop + PANEL_H + 8, -- for the scroll page (v1.0.0-beta.5)
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
            refreshWeek()
            refreshGoals()
        end,
    }
end

-- Addon Compartment (TOC: AddonCompartmentFunc) opens the window.
function ForeverMemories_OnAddonCompartmentClick()
    UI.Toggle()
end
