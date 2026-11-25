-- UI/Settings.lua
-- "Settings" tab (v0.10.0). Since v1.0.0-beta.4 a side menu on the left
-- (icons and names; icons only in a narrow window) and six pages, each
-- under a header (eyebrow, title, subtitle):
--   General       - language, behavior, minimap clicks, key bindings (this file)
--   Appearance    - scale, window layout, ArtPack, fonts, animations (this file)
--   Notifications - kinds, preview, duration, position, size (this file)
--   Data          - cards, characters, export, backup, import, resets (SettingsData.lua)
--   About         - logo, name, version, author (SettingsAbout.lua)
--   Changelog     - history of updates from CHANGELOG.md (SettingsAbout.lua)
-- Pages are built when first opened. Diagnostics stay in chat:
-- /fm status, /fm debug, /fm log and /fm diag (copy box).
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

UI.SETTINGS_PAGES = { "general", "appearance", "notifications", "data", "about", "changelog" }
UI.settingsPages = {} -- builders: id -> function(parent) -> view
UI.SETTINGS_PAGE_TOP = 64      -- below the page header
UI.SETTINGS_MENU_WIDE = 150    -- side menu with names
UI.SETTINGS_MENU_NARROW = 44   -- icons only
UI.SETTINGS_MENU_GAP = 14
UI.SETTINGS_MENU_NAMES_FROM = 720 -- content width that has room for the names
UI.SETTINGS_WIDTH = UI.CONTENT_WIDTH - UI.SETTINGS_MENU_NARROW - UI.SETTINGS_MENU_GAP

local PAGE_ICONS = {
    general = ns.Media.ICON.settings,
    appearance = ns.Media.ICON.compass,
    notifications = ns.Media.ICON.flag,
    data = ns.Media.ICON.history,
    about = ns.Media.ICON.home,
    changelog = ns.Media.ICON.calendar,
}

UI.SETTINGS_BAR_HEIGHT = 54 -- compact: the menu is a row of icons on top (beta.9: was 44, touched the caption)

-- Pages with a fixed layout and their height: they scroll in a low window
-- (v1.0.0-beta.5). About and Changelog are lists.
UI.SETTINGS_FIXED = { general = 446, appearance = 376, notifications = 440, data = 490 }

-- Compact window (v1.0.0-beta.5): the menu goes on top as a row of icons.
function UI.SettingsCompact()
    return UI.CONTENT_WIDTH + 2 * UI.PAD < UI.LAYOUTS[2][2]
end

-- Width of the side menu and of the pages for the current content width.
function UI.SettingsMenuWidth()
    if UI.SettingsCompact() then
        return 0
    elseif UI.CONTENT_WIDTH >= UI.SETTINGS_MENU_NAMES_FROM then
        return UI.SETTINGS_MENU_WIDE
    end
    return UI.SETTINGS_MENU_NARROW
end

-- Top of the page header (below the icon row in a compact window).
function UI.SettingsTop()
    return UI.SettingsCompact() and UI.SETTINGS_BAR_HEIGHT or 0
end

-- Height of a page below its header (About has no header).
function UI.SettingsPageHeight(id)
    return UI.HEIGHT - UI.CHROME_HEIGHT - UI.SettingsTop() - (id == "about" and 0 or UI.SETTINGS_PAGE_TOP)
end

local SCALE_MIN, SCALE_MAX, SCALE_STEP = ns.Database.SETTINGS.scale.min, ns.Database.SETTINGS.scale.max, 0.05

local function settingCheck(parent, key, label, tip, after, width)
    local check = W.Check(parent, label,
        function() return ns.db.settings[key] end,
        function(value)
            ns.db.settings[key] = value
            if after then after(value) end
        end, width or UI.SETTINGS_WIDTH)
    return W.Tooltip(check, tip)
end

-- Language: saved at once; a reload is offered, never forced.
local function setLanguage(value)
    local before = ns.activeLocaleCode
    ns.db.settings.locale = value
    if ns.ResolveLocaleCode(value) ~= before then
        UI.ConfirmReload(L.RELOAD_FOR_LANGUAGE)
    end
end

-- "Restore default settings" of one page, after a confirmation.
local function restoreButton(parent, keys, after)
    local button = W.Button(parent, L.RESTORE_DEFAULTS, UI.SETTINGS_WIDTH, 28, function()
        UI.Confirm(L.CONFIRM_RESTORE_DEFAULTS, L.RESTORE, function()
            ns.Database.ResetKeys(ns.db, keys)
            if after then after() end
            parent:Refresh()
        end)
    end)
    return button
end

-- Shared page parts (v1.0.0-beta.4).
-- Section title in gold with a thin line under it.
function UI.SettingsSection(parent, text, y)
    local title = W.Text(parent, text, "GameFontNormal", W.COLORS.gold)
    title:SetPoint("TOPLEFT", 0, -y)
    local line = W.Divider(parent)
    line:SetPoint("TOPLEFT", 0, -(y + 18))
    line:SetPoint("TOPRIGHT", 0, -(y + 18))
    return title
end

-- Label on the left, value on the right (minimap clicks, key bindings).
function UI.SettingsInfoRow(parent, y, label, value)
    local left = W.Text(parent, label, "GameFontHighlightSmall", W.COLORS.text)
    left:SetPoint("TOPLEFT", 0, -y)
    local right = W.Text(parent, value or "", "GameFontHighlightSmall", W.COLORS.muted)
    right:SetPoint("TOPRIGHT", 0, -y)
    right:SetJustifyH("RIGHT")
    return left, right
end

-- A labelled action: name and a short note on the left, a button on the
-- right (Data, Appearance).
function UI.SettingsActionRow(parent, y, label, note, buttonText, onClick, tip)
    local name = W.Text(parent, label, "GameFontHighlight", W.COLORS.text)
    name:SetPoint("TOPLEFT", 0, -(note and y or y + 6))
    if note then
        local small = W.Text(parent, note, "GameFontHighlightSmall", W.COLORS.muted)
        small:SetPoint("TOPLEFT", 0, -(y + 16))
        small:SetPoint("RIGHT", parent, "RIGHT", -130, 0)
    end
    local button = W.Button(parent, buttonText, 120, 26, onClick)
    button:SetPoint("TOPRIGHT", 0, -y)
    W.Tooltip(button, tip, label)
    return button, name
end

---------------------------------------------------------------------------
-- General (v1.0.0-beta.4)
---------------------------------------------------------------------------
local BINDINGS = {
    { "FOREVERMEMORIES_TOGGLE", "BINDING_TOGGLE" },
    { "FOREVERMEMORIES_SHOT", "BINDING_SHOT" },
    { "FOREVERMEMORIES_AUTOCAPTURE", "BINDING_AUTOCAPTURE" },
    { "FOREVERMEMORIES_CLEANSHOT", "BINDING_CLEANSHOT" },
}
UI.SETTINGS_BINDINGS = BINDINGS

UI.settingsPages.general = function(parent)
    local width = UI.SETTINGS_WIDTH
    UI.SettingsSection(parent, L.SET_SECTION_LANGUAGE, 0)
    local languageLabel = W.Text(parent, L.SET_LANGUAGE)
    languageLabel:SetPoint("TOPLEFT", 0, -28)
    local languageNote = W.Text(parent, L.SET_LANGUAGE_NOTE, "GameFontHighlightSmall", W.COLORS.muted)
    languageNote:SetPoint("TOPLEFT", 0, -44)
    local language = W.Dropdown(parent, {
        { value = "auto", text = L.LANGUAGE_AUTO },
        { value = "enUS", text = "English" },
        { value = "ruRU", text = "Русский" },
    }, function() return ns.db.settings.locale end, setLanguage, math.min(200, math.floor(width * 0.4)))
    language:SetPoint("TOPRIGHT", 0, -28)
    -- v1.0.0-beta.9: the label and the note end before the list (cut with "...").
    languageLabel:SetPoint("RIGHT", language, "LEFT", -10, 0)
    languageNote:SetPoint("RIGHT", language, "LEFT", -10, 0)
    W.Tooltip(language, L.TIP_SET_LANGUAGE, L.SET_LANGUAGE)

    UI.SettingsSection(parent, L.SET_SECTION_BEHAVIOR, 72)
    local checks = {
        settingCheck(parent, "minimap", L.SET_MINIMAP, L.TIP_SET_MINIMAP, function() ns.Minimap.Update() end),
        settingCheck(parent, "rememberTab", L.SET_REMEMBER_TAB, L.TIP_SET_REMEMBER_TAB),
    }
    checks[1]:SetPoint("TOPLEFT", 0, -98)
    checks[2]:SetPoint("TOPLEFT", 0, -124)

    UI.SettingsSection(parent, L.MINIMAP_CONTROLS, 160)
    local controls = {
        { L.CLICK_LEFT, L.ACTION_TOGGLE_WINDOW },
        { L.CLICK_RIGHT, L.ACTION_PAUSE },
        { L.CLICK_MIDDLE, L.ACTION_MANUAL },
        { L.COMMAND, "/fm" },
    }
    for i, row in ipairs(controls) do
        UI.SettingsInfoRow(parent, 186 + (i - 1) * 20, row[1], row[2])
    end

    UI.SettingsSection(parent, L.KEY_BINDINGS, 276)
    local keys = {}
    for i, binding in ipairs(BINDINGS) do
        local _, value = UI.SettingsInfoRow(parent, 302 + (i - 1) * 20, L[binding[2]], "")
        keys[i] = value
    end
    local hint = W.Text(parent, "", "GameFontHighlightSmall", W.COLORS.muted)
    hint:SetPoint("TOPLEFT", 0, -426)
    hint:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    local open = W.Button(parent, L.OPEN_KEY_BINDINGS, math.min(260, width), 26, function()
        if not ns.API.OpenKeyBindings() then
            hint:SetText(L.KEY_BINDINGS_HINT)
        end
    end)
    open:SetPoint("TOPLEFT", 0, -390)
    W.Tooltip(open, L.TIP_OPEN_KEY_BINDINGS, L.OPEN_KEY_BINDINGS)

    function parent:Refresh()
        for _, check in ipairs(checks) do
            check:Refresh()
        end
        language:Refresh()
        for i, binding in ipairs(BINDINGS) do
            local key = ns.API.BindingKey(binding[1])
            keys[i]:SetText(key or L.NOT_ASSIGNED)
            local c = key and W.COLORS.heading or W.COLORS.muted
            keys[i]:SetTextColor(c[1], c[2], c[3])
        end
    end
    return { Refresh = function() parent:Refresh() end }
end

---------------------------------------------------------------------------
-- Appearance (v0.17.0; own page since v1.0.0-beta.4)
---------------------------------------------------------------------------
-- Compact / Standard / Wide from the window width (spec: about 520 and 780
-- at 100 %). Shown read-only: it is never a setting.
function UI.LayoutName(windowWidth)
    return UI.Layout(windowWidth or (UI.CONTENT_WIDTH + 2 * UI.PAD))
end

UI.settingsPages.appearance = function(parent)
    local width = UI.SETTINGS_WIDTH
    UI.SettingsSection(parent, L.SET_SECTION_SCALE, 0)
    local scaleLabel = W.Text(parent, L.SET_SCALE)
    scaleLabel:SetPoint("TOPLEFT", 0, -28)
    local scaleValue = W.Text(parent, "", "GameFontNormal", W.COLORS.heading)
    scaleValue:SetPoint("TOPRIGHT", 0, -28)
    scaleValue:SetJustifyH("RIGHT")
    local function showScale()
        scaleValue:SetText(math.floor(ns.db.settings.scale * 100 + 0.5) .. "%")
    end
    local slider = W.Slider(parent, width - 20, SCALE_MIN, SCALE_MAX, SCALE_STEP,
        function() return ns.db.settings.scale end,
        function(value)
            ns.db.settings.scale = ns.Util.Clamp(value, SCALE_MIN, SCALE_MAX, 1)
            showScale()
            UI.ApplyScale()
        end)
    slider:SetPoint("TOPLEFT", 10, -52)
    W.Tooltip(slider, L.TIP_SET_SCALE, L.SET_SCALE)

    local layoutLabel = W.Text(parent, L.WINDOW_LAYOUT)
    layoutLabel:SetPoint("TOPLEFT", 0, -86)
    local layoutNote = W.Text(parent, L.WINDOW_LAYOUT_NOTE, "GameFontHighlightSmall", W.COLORS.muted)
    layoutNote:SetPoint("TOPLEFT", 0, -102)
    local layoutValue = W.Text(parent, "", "GameFontHighlightSmall", W.COLORS.heading)
    layoutValue:SetPoint("TOPRIGHT", 0, -88)
    layoutValue:SetJustifyH("RIGHT")
    W.Tooltip(layoutLabel, L.TIP_WINDOW_LAYOUT, L.WINDOW_LAYOUT)

    local half = (width - 8) / 2
    local resetScale = W.Button(parent, L.RESET_SCALE, half, 26, function()
        ns.db.settings.scale = ns.Database.SETTINGS.scale.default
        UI.ApplyScale()
        parent:Refresh()
    end)
    resetScale:SetPoint("TOPLEFT", 0, -126)
    W.Tooltip(resetScale, L.TIP_RESET_SCALE, L.RESET_SCALE)
    local position = W.Button(parent, L.RESET_POSITION, half, 26, function()
        UI.ResetGeometry()
    end)
    position:SetPoint("TOPRIGHT", 0, -126)
    W.Tooltip(position, L.TIP_RESET_POSITION, L.RESET_POSITION)

    -- ArtPack (v0.18.0): one preference, Classic or Illustrated, and the
    -- state of the optional pack. Illustrated without the pack is allowed:
    -- the choice is kept and the compass is shown.
    UI.SettingsSection(parent, L.ARTPACK_SECTION, 172)
    local artLabel = W.Text(parent, L.SET_ARTPACK_STYLE)
    artLabel:SetPoint("TOPLEFT", 0, -200)
    local artStatus = W.Text(parent, "", "GameFontHighlightSmall", W.COLORS.muted)
    artStatus:SetPoint("TOPLEFT", 0, -216)
    local styleWidth = math.min(300, width - 150) -- beta.8: room for "С иллюстрациями"
    artStatus:SetPoint("RIGHT", parent, "RIGHT", -(styleWidth + 10), 0)
    local style = W.Segmented(parent, { { false, L.ART_CLASSIC }, { true, L.ART_ILLUSTRATED } }, styleWidth,
        function(value) ns.db.settings.artpack = value; parent:Refresh() end)
    style:SetPoint("TOPRIGHT", 0, -200)
    W.Tooltip(artLabel, L.TIP_SET_ARTPACK, L.SET_ARTPACK_STYLE)
    local function showArtPack()
        local status, version = ns.ArtPack.Status()
        local text
        if status == "loaded" then
            text = string.format(L.ARTPACK_LOADED, version, ns.ArtPack.Count())
            artStatus:SetTextColor(W.COLORS.active[1], W.COLORS.active[2], W.COLORS.active[3])
        else
            text = L["ARTPACK_" .. string.upper(status)]
            artStatus:SetTextColor(W.COLORS.muted[1], W.COLORS.muted[2], W.COLORS.muted[3])
        end
        if not ns.db.settings.artpack then
            text = text .. "  ·  " .. L.ARTPACK_DISABLED
        end
        artStatus:SetText(text)
        style:SetValue(ns.db.settings.artpack)
    end

    local fontsBefore = ns.db.settings.fonts
    local function fontsChanged()
        if ns.db.settings.fonts ~= fontsBefore then
            fontsBefore = ns.db.settings.fonts
            UI.ConfirmReload(L.RELOAD_FOR_FONTS)
        end
    end
    local checks = {
        settingCheck(parent, "fonts", L.SET_FONTS, L.TIP_SET_FONTS, fontsChanged),
        settingCheck(parent, "animations", L.SET_ANIMATIONS, L.TIP_SET_ANIMATIONS),
    }
    checks[1]:SetPoint("TOPLEFT", 0, -244)
    checks[2]:SetPoint("TOPLEFT", 0, -270)

    local line = W.Divider(parent)
    line:SetPoint("TOPLEFT", 0, -308)
    line:SetPoint("TOPRIGHT", 0, -308)
    local defaults = W.Button(parent, L.RESET_APPEARANCE, width, 28, function()
        UI.Confirm(L.CONFIRM_RESET_APPEARANCE, L.RESTORE, function()
            ns.Database.ResetKeys(ns.db, ns.Database.APPEARANCE_SETTINGS)
            UI.ResetGeometry()
            UI.ApplyScale()
            fontsChanged()
            parent:Refresh()
        end)
    end)
    defaults:SetPoint("TOPLEFT", 0, -320)
    W.Tooltip(defaults, L.TIP_RESET_APPEARANCE, L.RESET_APPEARANCE)
    local note = W.Text(parent, L.RESET_APPEARANCE_NOTE, "GameFontHighlightSmall", W.COLORS.muted)
    note:SetPoint("TOPLEFT", 0, -356)

    function parent:Refresh()
        for _, check in ipairs(checks) do
            check:Refresh()
        end
        slider:Refresh()
        showScale()
        showArtPack()
        layoutValue:SetText(L["LAYOUT_" .. string.upper(UI.LayoutName())] .. "  ·  " .. L.LAYOUT_AUTO)
    end
    return { Refresh = function() parent:Refresh() end }
end

---------------------------------------------------------------------------
-- Notifications (v0.17.0; v1.0.0-beta.6: time and place for each kind)
---------------------------------------------------------------------------
-- id, setting, short name (beta.6: Mini / Discovery / Legendary), long name, tip
local KINDS = {
    { "mini", "notifyMini", "KIND_MINI", "SET_NOTIFY_MINI", "TIP_NOTIFY_MINI" },
    { "discovery", "notifyDiscovery", "KIND_DISCOVERY", "SET_NOTIFY_DISCOVERY", "TIP_NOTIFY_DISCOVERY" },
    { "legendary", "notifyLegendary", "KIND_LEGENDARY", "SET_NOTIFY_LEGENDARY", "TIP_NOTIFY_LEGENDARY" },
}

-- Edit panel (v1.0.0-beta.9): it opens right under the sample notification
-- on screen (or above it near the bottom of the screen) and follows it
-- while it is dragged. It belongs to UIParent, not to the Settings page,
-- and it is opaque.
UI.EDITOR_WIDTH, UI.EDITOR_HEIGHT, UI.EDITOR_GAP = 340, 236, 8
local function editorPanel(onEnd)
    local width = UI.EDITOR_WIDTH
    local panel = CreateFrame("Frame", "ForeverMemoriesNotifyEditor", UIParent, "BackdropTemplate")
    W.Backdrop(panel, W.COLORS.background, 1, W.COLORS.gold)
    panel:SetSize(width, UI.EDITOR_HEIGHT)
    panel:SetFrameStrata("DIALOG")
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    panel:EnableMouse(true)
    ns.ownFrames[panel] = true -- hidden before each capture like the window
    local title = W.Text(panel, "", "GameFontNormal", W.COLORS.heading)
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    local hint = W.Text(panel, L.EDIT_POSITION_HINT, "GameFontHighlightSmall", W.COLORS.muted)
    hint:SetPoint("TOPLEFT", 12, -28)
    hint:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    -- v1.0.0-beta.10: place and size of this kind, applied to the sample at once.
    local presetW = width - 24 - 96
    local placeLabel = W.Text(panel, L.SET_NOTIFY_POSITION)
    placeLabel:SetPoint("TOPLEFT", 12, -56)
    local place = W.Segmented(panel, {
        { "top", L.POSITION_TOP }, { "middle", L.POSITION_MIDDLE }, { "bottom", L.POSITION_BOTTOM },
    }, presetW, function(value) ns.Notifications.EditPreset(value) end)
    place:SetPoint("TOPRIGHT", -12, -52)
    W.Tooltip(placeLabel, L.TIP_NOTIFY_POSITION, L.SET_NOTIFY_POSITION)
    local sizeLabel = W.Text(panel, L.SET_NOTIFY_SIZE)
    sizeLabel:SetPoint("TOPLEFT", 12, -86)
    local showScale
    local size = W.Segmented(panel, {
        { "small", L.SIZE_SMALL }, { "normal", L.SIZE_NORMAL }, { "large", L.SIZE_LARGE },
    }, presetW, function(value) ns.Notifications.EditSize(value); panel:Refresh() end)
    size:SetPoint("TOPRIGHT", -12, -82)
    W.Tooltip(sizeLabel, L.TIP_NOTIFY_SIZE, L.SET_NOTIFY_SIZE)
    local scaleLabel = W.Text(panel, L.SET_NOTIFY_SCALE)
    scaleLabel:SetPoint("TOPLEFT", 12, -118)
    local scaleValue = W.Text(panel, "", "GameFontNormal", W.COLORS.heading)
    scaleValue:SetPoint("TOPRIGHT", -12, -118)
    local function sizeOf(scale)
        for name, value in pairs(ns.Notifications.SIZES) do
            if math.abs(value - scale) < 0.001 then return name end
        end
        return nil
    end
    showScale = function()
        local _, edit = ns.Notifications.Editing()
        local scale = (edit and edit.scale) or 1
        scaleValue:SetText(math.floor(scale * 100 + 0.5) .. "%")
        size:SetValue(sizeOf(scale))
        place:SetValue(ns.Notifications.EditPresetOf())
    end
    local slider = W.Slider(panel, width - 40, 0.5, 2, 0.05,
        function() local _, edit = ns.Notifications.Editing(); return edit and edit.scale or 1 end,
        function(value) ns.Notifications.EditScale(value); showScale() end)
    slider:SetPoint("TOPLEFT", 20, -138)
    local lock = W.Check(panel, L.EDIT_LOCK,
        function() local _, edit = ns.Notifications.Editing(); return edit and edit.locked end,
        function(value) ns.Notifications.EditLock(value) end, width - 24)
    lock:SetPoint("TOPLEFT", 12, -164)
    W.Tooltip(lock, L.TIP_EDIT_LOCK, L.EDIT_LOCK)
    local third = (width - 24 - 12) / 3
    local reset = W.Button(panel, L.EDIT_RESET, third, 24, function()
        ns.Notifications.EditReset()
        panel:Refresh()
    end)
    reset:SetPoint("BOTTOMLEFT", 12, 12)
    W.Tooltip(reset, L.TIP_EDIT_RESET, L.EDIT_RESET)
    local cancel = W.Button(panel, L.CANCEL, third, 24, function()
        ns.Notifications.EndEdit(false)
        panel:Hide()
        onEnd()
    end)
    cancel:SetPoint("BOTTOMLEFT", 12 + third + 6, 12)
    local done = W.Button(panel, L.EDIT_DONE, third, 24, function()
        ns.Notifications.EndEdit(true)
        panel:Hide()
        onEnd()
    end)
    done:SetPoint("BOTTOMLEFT", 12 + 2 * (third + 6), 12)

    -- Under the card, or above it when there is no room below.
    local anchoredBelow
    function panel:Follow()
        local kind = ns.Notifications.Editing()
        local card = kind and ns.Notifications.Card(kind)
        if not card then return end
        local bottom = card:GetBottom()
        local below = true
        if bottom then
            local need = (UI.EDITOR_HEIGHT + UI.EDITOR_GAP) * self:GetEffectiveScale()
            below = bottom * card:GetEffectiveScale() > need
        end
        if below ~= anchoredBelow or self.card ~= card then
            anchoredBelow, self.card = below, card
            self:ClearAllPoints()
            if below then
                self:SetPoint("TOP", card, "BOTTOM", 0, -UI.EDITOR_GAP)
            else
                self:SetPoint("BOTTOM", card, "TOP", 0, UI.EDITOR_GAP)
            end
        end
    end
    panel:SetScript("OnUpdate", function(self) self:Follow() end)

    function panel:Open(kindLabel)
        title:SetText(string.format(L.EDIT_POSITION_TITLE, kindLabel))
        anchoredBelow, self.card = nil, nil
        self:Follow()
        self:Show()
        self:Refresh()
    end
    function panel:Refresh()
        slider:Refresh()
        lock:Refresh()
        showScale()
    end
    panel:Hide()
    return panel
end

UI.settingsPages.notifications = function(parent)
    local width = UI.SETTINGS_WIDTH
    local editor
    local switches = {}
    local checks = {}

    -- All notifications (v1.0.0-beta.9): the settings shared by the three
    -- kinds. v1.0.0-beta.10: place and size moved into "Edit" of each kind.
    UI.SettingsSection(parent, L.SET_NOTIFY_ALL, 0)
    local common = {
        settingCheck(parent, "notifications", L.SET_NOTIFICATIONS, L.TIP_SET_NOTIFICATIONS),
        settingCheck(parent, "sound", L.SET_SOUND, L.TIP_SET_SOUND),
        settingCheck(parent, "notifyCombatDefer", L.SET_NOTIFY_COMBAT, L.TIP_NOTIFY_COMBAT),
        settingCheck(parent, "notifyMerge", L.SET_NOTIFY_MERGE, L.TIP_NOTIFY_MERGE),
    }
    for i, check in ipairs(common) do
        check:SetPoint("TOPLEFT", 0, -(26 + (i - 1) * 24))
        checks[#checks + 1] = check
    end

    -- Each kind (v1.0.0-beta.10): a card with on/off and the name, Preview
    -- and Edit on the first line, the time on screen on the second.
    local kindsTop = 26 + 4 * 24 + 12
    UI.SettingsSection(parent, L.SET_NOTIFY_KINDS, kindsTop)
    local CARD_H, CARD_GAP = 66, 8
    local buttonsW = math.min(100, (width - 200) / 2)
    local own, previews = {}, {}
    for i, kind in ipairs(KINDS) do
        local card = W.Panel(parent, W.COLORS.panel, W.COLORS.divider)
        card:SetPoint("TOPLEFT", 0, -(kindsTop + 28 + (i - 1) * (CARD_H + CARD_GAP)))
        card:SetSize(width, CARD_H)
        local check = settingCheck(card, kind[2], L[kind[3]], nil, nil, width - 2 * buttonsW - 40)
        W.Tooltip(check, L[kind[5]], L[kind[4]])
        check:SetPoint("TOPLEFT", 10, -8)
        checks[#checks + 1] = check
        local position = W.Button(card, L.EDIT_POSITION, buttonsW, 24, function()
            if ns.Notifications.StartEdit(kind[1]) then
                editor:Open(L[kind[3]])
                parent:Refresh()
            end
        end)
        position:SetPoint("TOPRIGHT", -10, -8)
        W.Tooltip(position, L.TIP_EDIT_POSITION, L.EDIT_POSITION)
        local preview = W.Button(card, L.PREVIEW, buttonsW, 24, function()
            ns.Notifications.Test(kind[1])
            parent:Refresh()
        end)
        preview:SetPoint("RIGHT", position, "LEFT", -6, 0)
        W.Tooltip(preview, L.TIP_PREVIEW, L.PREVIEW)
        previews[kind[1]] = preview
        local timeLabel = W.Text(card, L.SET_NOTIFY_TIME, "GameFontHighlightSmall", W.COLORS.muted)
        timeLabel:SetPoint("BOTTOMLEFT", 36, 13)
        own[kind[1]] = W.Text(card, "", "GameFontHighlightSmall", W.COLORS.gold)
        own[kind[1]]:SetPoint("LEFT", timeLabel, "RIGHT", 10, 0)
        local key = ns.Notifications.DURATION[kind[1]]
        local options = {}
        for n, seconds in ipairs(ns.Database.SETTINGS[key].values) do
            options[n] = { seconds, string.format(L.SECONDS_SHORT, seconds) }
        end
        local switch = W.Segmented(card, options, 2 * buttonsW + 6, function(value)
            ns.db.settings[key] = value
        end)
        switch.key = key
        switches[#switches + 1] = switch
        switch:SetPoint("BOTTOMRIGHT", -10, 8)
        W.Tooltip(timeLabel, L.TIP_SET_TOAST_DURATION, L.SET_NOTIFY_TIME)
    end
    -- The preview closes by itself: the labels follow it.
    local watcher = CreateFrame("Frame", nil, parent)
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.25 then return end
        elapsed = 0
        for kind, button in pairs(previews) do
            button:SetLabel(ns.Notifications.IsPreviewing(kind) and L.PREVIEW_HIDE or L.PREVIEW)
        end
    end)

    local defaults = restoreButton(parent, ns.Database.NOTIFY_SETTINGS, function()
        ns.Notifications.EndEdit(false)
        ns.db.ui.notify = nil -- own places too
    end)
    defaults:SetPoint("TOPLEFT", 0, -(kindsTop + 28 + 3 * (CARD_H + CARD_GAP) + 4))
    W.Tooltip(defaults, L.TIP_RESTORE_NOTIFY, L.RESTORE_DEFAULTS)

    editor = editorPanel(function() parent:Refresh() end)
    -- Leaving the page or Settings cancels the editor (the sample goes away).
    W.AddScript(parent, "OnHide", function()
        if ns.Notifications.Editing() then
            ns.Notifications.EndEdit(false)
        end
        editor:Hide()
    end)

    function parent:Refresh()
        for _, check in ipairs(checks) do
            check:Refresh()
        end
        for _, switch in ipairs(switches) do
            switch:SetValue(ns.db.settings[switch.key])
        end
        for kind, text in pairs(own) do
            text:SetText(ns.Notifications.Layout(kind) and L.OWN_PLACE or "")
        end
        for kind, button in pairs(previews) do
            button:SetLabel(ns.Notifications.IsPreviewing(kind) and L.PREVIEW_HIDE or L.PREVIEW)
        end
        if not ns.Notifications.Editing() then
            editor:Hide()
        end
    end
    return { Refresh = function() parent:Refresh() end, Editor = editor }
end

---------------------------------------------------------------------------
-- The tab: the side menu, the header and the selected page.
---------------------------------------------------------------------------
UI.builders.settings = function(parent)
    local pages, buttons = {}, {}
    local current = "general"
    local menuW = UI.SettingsMenuWidth()
    local compact = menuW == 0
    local named = menuW == UI.SETTINGS_MENU_WIDE
    local left = compact and 0 or (menuW + UI.SETTINGS_MENU_GAP)
    local headTop = UI.SettingsTop()
    UI.SETTINGS_WIDTH = UI.CONTENT_WIDTH - left

    -- Header: eyebrow, title and subtitle of the page.
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", left, -headTop)
    header:SetSize(UI.SETTINGS_WIDTH, UI.SETTINGS_PAGE_TOP)
    local eyebrow = W.Text(header, L.JOURNAL_EYEBROW, "GameFontHighlightSmall", W.COLORS.gold)
    eyebrow:SetPoint("TOPLEFT", 0, 0)
    local title = W.Text(header, "", "GameFontNormalLarge", W.COLORS.heading)
    title:SetPoint("TOPLEFT", 0, -16)
    local subtitle = W.Text(header, "", "GameFontHighlightSmall", W.COLORS.muted)
    subtitle:SetPoint("TOPLEFT", 0, -40)
    UI.settingsHeader = { eyebrow = eyebrow, title = title, subtitle = subtitle }

    local function select(id)
        current = UI.settingsPages[id] and id or "general"
        local top = headTop + (current == "about" and 0 or UI.SETTINGS_PAGE_TOP)
        if not pages[current] then
            local frame = CreateFrame("Frame", nil, parent)
            frame:SetPoint("TOPLEFT", left, -top)
            frame:SetPoint("BOTTOMRIGHT", 0, 0)
            local fixed = UI.SETTINGS_FIXED[current]
            if fixed then
                frame.page = W.ScrollPage(frame, UI.SETTINGS_WIDTH)
                frame.view = UI.settingsPages[current](frame.page.child) or {}
                frame.page:SetContentHeight(fixed)
            else
                frame.view = UI.settingsPages[current](frame) or {}
            end
            pages[current] = frame
        end
        for key, frame in pairs(pages) do
            frame:SetShown(key == current)
        end
        for key, button in pairs(buttons) do
            button:SetSelected(key == current)
        end
        header:SetShown(current ~= "about")
        title:SetText(L["SETTINGS_" .. string.upper(current)])
        subtitle:SetText(L["SETTINGS_SUB_" .. string.upper(current)] or "")
        if current == "changelog" then
            UI.MarkChangelogSeen()
        end
        local view = pages[current].view
        if view.Refresh then
            ns.SafeCall("settings " .. current, view.Refresh)
        end
    end
    local size = named and 30 or 40
    for i, id in ipairs(UI.SETTINGS_PAGES) do
        local button = W.MenuButton(parent, PAGE_ICONS[id], L["SETTINGS_" .. string.upper(id)],
            named and menuW or size, size, function() select(id) end, not named)
        if compact then
            button:SetPoint("TOPLEFT", (i - 1) * (size + 4), 0)
        else
            button:SetPoint("TOPLEFT", 0, -(i - 1) * (size + 4))
        end
        buttons[id] = button
    end
    return {
        Select = function(id) current = UI.settingsPages[id] and id or current end,
        Refresh = function() select(current) end,
        Current = function() return current end,
    }
end
