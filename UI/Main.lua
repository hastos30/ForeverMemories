-- UI/Main.lua
-- Main window (UI_DESIGN.md): header with the auto-capture switch, a
-- sidebar of tabs and a content area. Tabs are built when first opened.
-- The UI never calls Screenshot directly: it goes through the Engine.
local _, ns = ...

local UI = {}
ns.UI = UI

local L = ns.L
local W = ns.Widgets

UI.TABS = { "home", "events", "capture", "journey", "journal", "profiles", "settings", "diagnostics", "about" }
UI.builders = {}

local window, content, autoButton
local tabs = {}
local navButtons = {}
local currentTab

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
    end
end

local function refreshHeader()
    local enabled = ns.db.settings.enabled
    autoButton:SetText(L.AUTO_CAPTURE .. ": " .. (enabled and L.ON or L.OFF))
end

function UI.ShowTab(id)
    if not tabs[id] then
        local frame = CreateFrame("Frame", nil, content)
        frame:SetAllPoints(content)
        local built = UI.builders[id] and UI.builders[id](frame)
        frame.Refresh = function()
            if built and built.Refresh then
                ns.SafeCall("tab " .. id, built.Refresh)
            end
        end
        tabs[id] = frame
    end
    for tabId, frame in pairs(tabs) do
        frame:SetShown(tabId == id)
    end
    for tabId, button in pairs(navButtons) do
        if tabId == id then button:LockHighlight() else button:UnlockHighlight() end
    end
    currentTab = id
    tabs[id]:Refresh()
end

function UI.Refresh()
    if window and window:IsShown() then
        refreshHeader()
        if currentTab then
            tabs[currentTab]:Refresh()
        end
    end
end

local function build()
    window = CreateFrame("Frame", "ForeverMemoriesMainFrame", UIParent, "BackdropTemplate")
    window:SetSize(800, 560)
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
    W.Backdrop(window, W.COLORS.background, 0.97)
    window:Hide()
    ns.ownFrames[window] = true
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ForeverMemoriesMainFrame") -- Esc closes
    end

    local title = W.Text(window, "ForeverMemories", "GameFontNormalLarge", W.COLORS.gold)
    title:SetPoint("TOPLEFT", 16, -14)

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    autoButton = W.Button(window, "", 190, function()
        ns.Engine.SetEnabled(not ns.db.settings.enabled)
    end)
    autoButton:SetPoint("TOPRIGHT", close, "TOPLEFT", -8, -4)

    local sidebar = CreateFrame("Frame", nil, window, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 10, -44)
    sidebar:SetSize(150, 470)
    W.Backdrop(sidebar, W.COLORS.panel, 0.9)
    for i, id in ipairs(UI.TABS) do
        local button = W.Button(sidebar, L["TAB_" .. id], 136, function() UI.ShowTab(id) end)
        button:SetPoint("TOP", sidebar, "TOP", 0, -8 - (i - 1) * 28)
        navButtons[id] = button
    end

    content = CreateFrame("Frame", nil, window, "BackdropTemplate")
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -10, 46)
    W.Backdrop(content, W.COLORS.panel, 0.9)

    local footer = W.Text(window, "Forever  -  v" .. ns.version .. "  -  /fm", "GameFontDisableSmall", W.COLORS.muted)
    footer:SetPoint("BOTTOMRIGHT", -16, 16)

    window:SetScript("OnShow", function()
        UI.ApplyScale()
        keepOnScreen()
        UI.Refresh()
    end)
    restorePosition()
    UI.ApplyScale()
    UI.ShowTab("home")
end

function UI.Toggle(tab)
    if not ns.db then
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
            UI.ShowTab(tab)
        end
        UI.Refresh()
    end
end

function UI.Open(tab)
    if not window or not window:IsShown() then
        UI.Toggle(tab)
    elseif tab then
        UI.ShowTab(tab)
    end
end

-- Keep the window in sync with data changes.
table.insert(ns.Journal.listeners, UI.Refresh)
table.insert(ns.Profiles.listeners, UI.Refresh)
table.insert(ns.Engine.stateListeners, UI.Refresh)

---------------------------------------------------------------------------
-- Home tab
---------------------------------------------------------------------------
local STATUS_ICON = {
    success = "|cff7CAA66OK|r", partial = "|cffC9A35E~|r", unconfirmed = "|cffC9A35E?|r",
    failed = "|cffff5555X|r", skipped = "|cff8c857a-|r",
}
UI.STATUS_ICON = STATUS_ICON

function UI.ProfileOptions()
    local options = {}
    for _, name in ipairs(ns.Profiles.List()) do
        options[#options + 1] = { value = name, text = L["PRESET_" .. name] ~= "PRESET_" .. name and L["PRESET_" .. name] or name }
    end
    return options
end

UI.builders.home = function(parent)
    local column = W.Column(parent, 16, 16)
    column:Add(W.Dropdown(parent, L.PROFILE, UI.ProfileOptions,
        function() return ns.Profiles.ActiveName() end,
        function(name) ns.Profiles.SetActive(name, ns.Profiles.IsCharacterOverride()) end, 160))
    local stats = column:Add(W.Text(parent, ""), 22)
    local pauseInfo = column:Add(W.Text(parent, ""), 22)
    local capsule = column:Add(W.Text(parent, "", "GameFontHighlightSmall"), 22)
    column:Space(6)
    column:Add(W.Heading(parent, L.RECENT_MEMORIES), 26)
    local lines = {}
    for i = 1, 5 do
        lines[i] = column:Add(W.Text(parent, ""), 20)
        lines[i]:SetWidth(560)
    end
    column:Space(10)
    local shot = W.Button(parent, L.TAKE_SHOT, 160, function() ns.Engine.ManualShot() end)
    column:Add(shot, 26)
    local pause = W.Button(parent, "", 160, function() ns.Engine.SetEnabled(not ns.db.settings.enabled) end)
    pause:SetPoint("LEFT", shot, "RIGHT", 10, 0)
    local panel = W.Button(parent, L.MANUAL_PANEL, 160, function() ns.ManualPanel.Toggle() end)
    panel:SetPoint("LEFT", pause, "RIGHT", 10, 0)

    return {
        Refresh = function()
            column:Refresh()
            local s = ns.Statistics.Get()
            stats:SetText(string.format(L.STATS_LINE, s.total, s.today, s.zones))
            if ns.db.settings.enabled then
                pauseInfo:SetText("|cff7CAA66" .. L.AUTO_ON_INFO .. "|r")
            else
                pauseInfo:SetText("|cffC9A35E" .. L.AUTO_OFF_INFO .. "|r")
            end
            local first, last = ns.Journal.DayCapsule(ns.API.Time())
            if first then
                capsule:SetText(string.format(L.CAPSULE_LINE, date("%H:%M", first.t), date("%H:%M", last.t)))
            else
                capsule:SetText(L.CAPSULE_EMPTY)
            end
            local items = ns.Journal.Query({ char = ns.characterKey }, 1)
            for i = 1, 5 do
                local entry = items[i]
                if entry then
                    lines[i]:SetText(string.format("%s  %s  %s%s", STATUS_ICON[entry.status] or "",
                        date("%H:%M", entry.t), ns.Notifications.EventNames(entry),
                        entry.zone and ("  |cff8c857a" .. entry.zone .. "|r") or ""))
                else
                    lines[i]:SetText(i == 1 and ("|cff8c857a" .. L.NO_MEMORIES .. "|r") or "")
                end
            end
            pause:SetText(ns.db.settings.enabled and L.PAUSE or L.RESUME)
        end,
    }
end

---------------------------------------------------------------------------
-- About tab
---------------------------------------------------------------------------
UI.builders.about = function(parent)
    local column = W.Column(parent, 16, 16)
    column:Add(W.Heading(parent, "ForeverMemories"), 28)
    column:Add(W.Text(parent, L.VERSION .. ": " .. ns.version), 20)
    column:Add(W.Text(parent, L.ABOUT_TARGET), 20)
    column:Add(W.Text(parent, L.AUTHOR .. ": -"), 20)
    column:Add(W.Text(parent, L.LICENSE .. ": " .. L.LICENSE_PENDING), 20)
    column:Add(W.Text(parent, "github.com/hastos30/ForeverMemories"), 20)
    local note = column:Add(W.Text(parent, L.ABOUT_FILES, "GameFontHighlightSmall"), 60)
    note:SetWidth(580)
    return {}
end

---------------------------------------------------------------------------
-- First run: short preset choice, no mandatory wizard.
---------------------------------------------------------------------------
function UI.ShowFirstRun()
    if ns.db.settings.firstRunDone then
        return
    end
    local frame = CreateFrame("Frame", "ForeverMemoriesFirstRun", UIParent, "BackdropTemplate")
    frame:SetSize(420, 250)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    W.Backdrop(frame, W.COLORS.background, 0.97)
    ns.ownFrames[frame] = true
    local title = W.Text(frame, L.FIRST_RUN_TITLE, "GameFontNormalLarge", W.COLORS.gold)
    title:SetPoint("TOP", 0, -16)
    local text = W.Text(frame, L.FIRST_RUN_TEXT, "GameFontHighlightSmall")
    text:SetPoint("TOP", 0, -44)
    text:SetWidth(380)
    for i, name in ipairs(ns.Profiles.PRESET_ORDER) do
        local button = W.Button(frame, L["PRESET_" .. name], 180, function()
            ns.Profiles.SetActive(name, false)
            ns.db.settings.firstRunDone = true
            ns.ownFrames[frame] = nil
            frame:Hide()
        end)
        local column = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        button:SetPoint("TOPLEFT", 20 + column * 200, -96 - row * 30)
    end
    local later = W.Button(frame, L.LATER, 120, function()
        ns.db.settings.firstRunDone = true
        ns.ownFrames[frame] = nil
        frame:Hide()
    end)
    later:SetPoint("BOTTOM", 0, 14)
    frame:Show()
end

table.insert(ns.onLogin, function()
    ns.API.After(5, function() ns.SafeCall("first run", UI.ShowFirstRun) end)
end)

-- Addon Compartment (TOC: AddonCompartmentFunc) opens the window.
function ForeverMemories_OnAddonCompartmentClick()
    UI.Toggle()
end
