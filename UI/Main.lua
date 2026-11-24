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

-- Cheap update for the step counter: only the numbers that show it.
function UI.RefreshSteps()
    if window and window:IsShown() then
        local view = currentTab and tabs[currentTab].view
        if view and view.RefreshSteps then
            ns.SafeCall("steps " .. currentTab, view.RefreshSteps)
        end
    end
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
-- Home tab: current character, four statistics cards, last five shots.
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

local function statCard(parent, icon, label, tip)
    local card = W.Panel(parent, W.COLORS.panel, W.COLORS.divider)
    card:SetSize((UI.CONTENT_WIDTH - 8) / 2, 92)
    local image = W.Icon(card, icon, 22)
    image:SetPoint("TOP", 0, -10)
    card.value = W.Text(card, "0", "GameFontNormalHuge", W.COLORS.heading)
    card.value:SetPoint("TOP", image, "BOTTOM", 0, -6)
    card.value:SetJustifyH("CENTER")
    local caption = W.Text(card, label, "GameFontHighlightSmall", W.COLORS.muted)
    caption:SetPoint("BOTTOM", 0, 10)
    caption:SetJustifyH("CENTER")
    W.Tooltip(card, tip, label)
    return card
end

UI.builders.home = function(parent)
    local portrait = parent:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(40, 40)
    portrait:SetPoint("TOPLEFT", 0, 0)
    local name = W.Text(parent, "", "GameFontNormalLarge", W.COLORS.heading)
    name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 12, -3)
    local caption = W.Text(parent, L.CURRENT_CHARACTER_STATS, "GameFontHighlightSmall", W.COLORS.muted)
    caption:SetPoint("BOTTOMLEFT", portrait, "BOTTOMRIGHT", 12, 3)

    local cards = {
        total = statCard(parent, "Interface\\Icons\\INV_Misc_Spyglass_03", L.STAT_TOTAL, L.TIP_STAT_TOTAL),
        today = statCard(parent, "Interface\\Icons\\INV_Misc_PocketWatch_01", L.STAT_TODAY, L.TIP_STAT_TODAY),
        distance = statCard(parent, "Interface\\Icons\\INV_Misc_Map_01", L.STAT_DISTANCE, L.TIP_STAT_DISTANCE),
        steps = statCard(parent, "Interface\\Icons\\Ability_Rogue_Sprint", L.STAT_STEPS_TODAY, L.STEPS_NOTE),
    }
    cards.total:SetPoint("TOPLEFT", 0, -50)
    cards.today:SetPoint("TOPRIGHT", 0, -50)
    cards.distance:SetPoint("TOPLEFT", 0, -150)
    cards.steps:SetPoint("TOPRIGHT", 0, -150)

    local heading = W.Heading(parent, L.RECENT_SHOTS)
    heading:SetPoint("TOPLEFT", 0, -254)
    local rows = {}
    for i = 1, 5 do
        local row = UI.MakeShotRow(parent, 28)
        row:SetSize(UI.CONTENT_WIDTH, 32)
        row:SetPoint("TOPLEFT", 0, -280 - (i - 1) * 36)
        rows[i] = row
    end
    local empty = W.Text(parent, L.NO_SHOTS_YET, "GameFontHighlight", W.COLORS.muted)
    empty:SetPoint("TOPLEFT", 0, -290)
    local all = W.Link(parent, L.VIEW_ALL_SHOTS, function() UI.ShowTab("history", "shots") end)
    all:SetPoint("BOTTOM", 0, 0)

    local function refreshSteps()
        cards.steps.value:SetText(ns.Num(ns.Steps.Today()))
        cards.distance.value:SetText(ns.Dec(ns.Steps.TotalThousands(), 2))
    end
    return {
        RefreshSteps = refreshSteps,
        Refresh = function()
            UI.SetClassIcon(portrait)
            name:SetText(ns.character and ns.character.name or "?")
            local s = ns.History.Stats()
            cards.total.value:SetText(ns.Num(s.total))
            cards.today.value:SetText(ns.Num(s.today))
            refreshSteps()
            local recent = ns.History.Recent(5)
            for i, row in ipairs(rows) do
                if recent[i] then
                    UI.FillShotRow(row, recent[i], true)
                    row:Show()
                else
                    row:Hide()
                end
            end
            empty:SetShown(#recent == 0)
        end,
    }
end

-- Addon Compartment (TOC: AddonCompartmentFunc) opens the window.
function ForeverMemories_OnAddonCompartmentClick()
    UI.Toggle()
end
