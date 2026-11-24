-- UI/Widgets.lua
-- Small building blocks for the window: text, buttons, checkboxes,
-- "- value +" steppers and dropdown lists.
-- Every input widget has :Refresh() that re-reads its value.
-- Any widget can get a mouse-over explanation with W.Tooltip().
-- Only long-standing templates are used (UIPanelButtonTemplate,
-- UICheckButtonTemplate, InputBoxTemplate, BackdropTemplate).
local _, ns = ...

local W = {}
ns.Widgets = W

W.COLORS = {
    background = { 0.063, 0.063, 0.059 }, -- #10100F
    panel = { 0.157, 0.129, 0.086 },      -- #282116
    gold = { 0.788, 0.639, 0.369 },       -- #C9A35E
    text = { 0.910, 0.863, 0.753 },       -- #E8DCC0
    active = { 0.486, 0.667, 0.400 },     -- #7CAA66
    muted = { 0.55, 0.52, 0.46 },
}

function W.Backdrop(frame, color, alpha)
    if not frame.SetBackdrop then
        return
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local c = color or W.COLORS.panel
    frame:SetBackdropColor(c[1], c[2], c[3], alpha or 0.95)
    local g = W.COLORS.gold
    frame:SetBackdropBorderColor(g[1], g[2], g[3], 0.8)
end

---------------------------------------------------------------------------
-- Tooltips: a gold title and a white explanation on mouse over.
-- W.Tooltip(widget, text, title)
--   text  - string, or a function returning one (called on every mouse
--           over, so it can describe the current state);
--   title - string or function, optional. Checkboxes, steppers and
--           dropdowns already use their label as the title.
-- A widget made of several frames (a stepper: row, "-" and "+") shows the
-- same tooltip over each of them.
-- Only GameTooltip SetOwner/SetText/AddLine/Show/Hide are used: the same
-- calls as the minimap button tooltip.
---------------------------------------------------------------------------
-- Weak tables (__mode = "k"): they never keep a frame alive by themselves.
local tipInfo = setmetatable({}, { __mode = "k" }) -- frame -> { text, title, targets }
local tipHooked = setmetatable({}, { __mode = "k" }) -- frame -> true

local function resolve(value)
    if type(value) == "function" then
        return value()
    end
    return value
end

local function showTooltip(self)
    local info = tipInfo[self]
    local text = info and resolve(info.text)
    if type(text) ~= "string" or text == "" then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local title = resolve(info.title)
    if type(title) == "string" and title ~= "" then
        local g = W.COLORS.gold
        GameTooltip:SetText(title, g[1], g[2], g[3])
        GameTooltip:AddLine(text, 1, 1, 1, true) -- true = wrap long text
    else
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

-- Adds fn to a script without replacing what a template already does.
local function addScript(frame, script, fn)
    if frame:GetScript(script) then
        frame:HookScript(script, fn)
    else
        frame:SetScript(script, fn)
    end
end

-- Used by the widgets below: default title and the frames that react.
local function tipDefaults(widget, title, targets)
    tipInfo[widget] = { title = title, targets = targets or { widget } }
end

function W.Tooltip(widget, text, title)
    local info = tipInfo[widget] or { targets = { widget } }
    info.text = text
    info.title = title or info.title
    for _, target in ipairs(info.targets) do
        tipInfo[target] = info
        if not tipHooked[target] then
            tipHooked[target] = true
            target:EnableMouse(true) -- a plain frame gets no OnEnter without it
            addScript(target, "OnEnter", showTooltip)
            addScript(target, "OnLeave", hideTooltip)
        end
    end
    return widget
end

function W.Text(parent, text, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    local c = color or W.COLORS.text
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

function W.Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, 22)
    button:SetText(text)
    button:SetScript("OnClick", function(self, mouseButton)
        ns.SafeCall("button", onClick, self, mouseButton)
    end)
    return button
end

function W.Check(parent, label, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check.label = W.Text(check, label)
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    -- The label is part of the checkbox: hover shows the tooltip,
    -- a click toggles it (as in the game's own options).
    check:SetHitRectInsets(0, -((check.label:GetStringWidth() or 0) + 4), 0, 0)
    tipDefaults(check, label)
    check:SetScript("OnClick", function(self)
        ns.SafeCall("check", set, self:GetChecked() and true or false)
        if parent.Refresh then parent:Refresh() end
    end)
    function check:Refresh()
        self:SetChecked(get() and true or false)
    end
    return check
end

local function formatNumber(value, step)
    if step < 1 then
        local decimals = step < 0.1 and 2 or 1
        return string.format("%." .. decimals .. "f", value)
    end
    return tostring(math.floor(value + 0.5))
end

-- Row: "label   [-] value [+]"
function W.Stepper(parent, label, spec, get, set, suffix)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, 24)
    row.label = W.Text(row, label)
    row.label:SetPoint("LEFT")
    row.label:SetWidth(170)
    local minus = W.Button(row, "-", 24)
    minus:SetPoint("LEFT", row, "LEFT", 172, 0)
    row.value = W.Text(row, "", "GameFontHighlight")
    row.value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    row.value:SetWidth(56)
    row.value:SetJustifyH("CENTER")
    local plus = W.Button(row, "+", 24)
    plus:SetPoint("LEFT", row.value, "RIGHT", 4, 0)
    tipDefaults(row, label, { row, minus, plus })

    local function change(direction)
        local value = (get() or spec.min) + direction * spec.step
        value = math.floor(value / spec.step + 0.5) * spec.step
        value = ns.Util.Clamp(value, spec.min, spec.max, spec.min)
        set(value)
        if parent.Refresh then parent:Refresh() else row:Refresh() end
    end
    minus:SetScript("OnClick", function() ns.SafeCall("stepper", change, -1) end)
    plus:SetScript("OnClick", function() ns.SafeCall("stepper", change, 1) end)

    function row:Refresh()
        local value = get()
        row.value:SetText(value and (formatNumber(value, spec.step) .. (suffix or "")) or "-")
    end
    function row:SetEnabled(enabled)
        minus:SetEnabled(enabled)
        plus:SetEnabled(enabled)
    end
    return row
end

---------------------------------------------------------------------------
-- Dropdown: "label   [current option]". A click opens a list of all
-- options under the button; a click on an option selects it.
-- One shared list frame serves every dropdown, so only one list is open.
-- Built from plain frames on purpose: UIDropDownMenu and the newer Menu
-- API differ between client versions and are not confirmed in Forever.
---------------------------------------------------------------------------
local LIST_ROW_HEIGHT = 18
local LIST_MAX_ROWS = 15 -- longer lists wrap into the next column

local list -- created on first use

local function closeList()
    if list then
        list:Hide() -- OnHide also hides the click catcher
    end
end
W.CloseDropdown = closeList

local function createList()
    -- Invisible full-screen button under the list: a click outside closes it.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetScript("OnClick", closeList)
    catcher:Hide()

    list = CreateFrame("Frame", "ForeverMemoriesDropdownList", UIParent, "BackdropTemplate")
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    W.Backdrop(list, W.COLORS.background, 0.97)
    list.rows = {}
    list.catcher = catcher
    list:SetScript("OnHide", function(self)
        self.owner = nil
        self.catcher:Hide()
    end)
    list:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ForeverMemoriesDropdownList") -- Esc closes
    end
    return list
end

local function listRow(i)
    if list.rows[i] then
        return list.rows[i]
    end
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(LIST_ROW_HEIGHT)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT") -- shown on mouse over
    highlight:SetAllPoints()
    local g = W.COLORS.gold
    highlight:SetColorTexture(g[1], g[2], g[3], 0.25)
    row.text = W.Text(row, "")
    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row:SetScript("OnClick", function(self)
        local owner = list.owner
        closeList()
        if owner then
            owner:Choose(self.value)
        end
    end)
    list.rows[i] = row
    return row
end

-- Shows the options under the owner button; a second click closes them.
local function openList(owner, options, current)
    list = list or createList()
    if list:IsShown() and list.owner == owner then
        return closeList()
    end
    local width = owner:GetWidth()
    local columns = math.ceil(#options / LIST_MAX_ROWS)
    local perColumn = math.ceil(#options / columns)
    for i, option in ipairs(options) do
        local row = listRow(i)
        local column, line = math.floor((i - 1) / perColumn), (i - 1) % perColumn
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 4 + column * width, -4 - line * LIST_ROW_HEIGHT)
        row:SetWidth(width)
        row.value = option.value
        row.text:SetText(option.text)
        local c = option.value == current and W.COLORS.active or W.COLORS.text
        row.text:SetTextColor(c[1], c[2], c[3])
        row:Show()
    end
    for i = #options + 1, #list.rows do
        list.rows[i]:Hide()
    end
    list:SetSize(columns * width + 8, perColumn * LIST_ROW_HEIGHT + 8)
    -- Same size as the window the button is in (the window has its own scale).
    list:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    list.owner = owner
    list:Show()
    list.catcher:Show()
end

-- options: list of { value = ..., text = ... } or a function returning it.
-- set(value) is called only when the player picks a different value.
function W.Dropdown(parent, label, options, get, set, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, 24)
    row.label = W.Text(row, label)
    row.label:SetPoint("LEFT")
    row.label:SetWidth(170)

    local function optionList()
        return type(options) == "function" and options() or options
    end
    local button = W.Button(row, "", width or 120, function(self)
        local opts = optionList()
        if #opts > 0 then
            openList(self, opts, get())
        end
    end)
    button:SetPoint("LEFT", row, "LEFT", 172, 0)
    row.button = button
    tipDefaults(row, label, { row, button })

    function button:Choose(value)
        if value ~= get() then
            ns.SafeCall("dropdown", set, value)
        end
        if parent.Refresh then parent:Refresh() else row:Refresh() end
    end
    -- Window closed or tab switched: the list must not stay on screen.
    button:SetScript("OnHide", function(self)
        if list and list.owner == self then
            closeList()
        end
    end)

    function row:Refresh()
        local current = get()
        local text = tostring(current)
        for _, option in ipairs(optionList()) do
            if option.value == current then
                text = option.text
                break
            end
        end
        button:SetText(text)
    end
    function row:SetEnabled(enabled)
        button:SetEnabled(enabled)
        if not enabled and list and list.owner == button then
            closeList()
        end
    end
    return row
end

function W.Input(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width or 160, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(200)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- Vertical layout: each Add() places a widget under the previous one.
function W.Column(parent, x, y, gap)
    local column = { y = y, widgets = {} }
    function column:Add(widget, height, indent)
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (indent or 0), -self.y)
        self.y = self.y + (height or 26) + (gap or 2)
        if widget.Refresh then
            self.widgets[#self.widgets + 1] = widget
        end
        return widget
    end
    function column:Space(height)
        self.y = self.y + height
    end
    function column:Refresh()
        for _, widget in ipairs(self.widgets) do
            widget:Refresh()
        end
    end
    return column
end

-- A titled block of text (used for headings).
function W.Heading(parent, text)
    return W.Text(parent, text, "GameFontNormalLarge", W.COLORS.gold)
end
