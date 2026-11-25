-- UI/Widgets.lua
-- Building blocks of the window in the v0.5.0 style (spec 14): dark matte
-- surfaces, thin gold borders, flat buttons, checkboxes, a dropdown, a
-- slider, an icon and a scrolling list that reuses its rows.
-- Only plain frames, BackdropTemplate and solid-color textures are used:
-- no templates whose look differs between client versions.
-- Every input widget has :Refresh() that re-reads its value.
local _, ns = ...

local W = {}
ns.Widgets = W

local function rgb(hex)
    return {
        tonumber(string.sub(hex, 1, 2), 16) / 255,
        tonumber(string.sub(hex, 3, 4), 16) / 255,
        tonumber(string.sub(hex, 5, 6), 16) / 255,
    }
end

-- Obsidian Journal palette (v0.15.0, TZ v1.0 §1): background #1B1815,
-- surfaces #2D2821, gold #D0AB70, text #EDDFC5, secondary #B0A18B,
-- lines #504232; success #8CAC80, warning #D5AD62, error #C57570.
W.COLORS = {
    background = rgb("1B1815"),
    panel = rgb("2D2821"),
    gold = rgb("D0AB70"),
    heading = rgb("D0AB70"),
    text = rgb("EDDFC5"),
    muted = rgb("B0A18B"),
    active = rgb("8CAC80"),
    warning = rgb("D5AD62"),
    divider = rgb("504232"),
    selected = rgb("4A3C27"),  -- selected tab / mode card (gold over the surface)
    hover = rgb("38322A"),
    error = rgb("C57570"),
    paused = rgb("8A857C"),
    rare = rgb("88A5CE"), epic = rgb("B198C9"), legendary = rgb("D8A558"),
}

W.HEX = {
    gold = "|cffD0AB70", heading = "|cffD0AB70", text = "|cffEDDFC5",
    muted = "|cffB0A18B", active = "|cff8CAC80", error = "|cffC57570", warning = "|cffD5AD62",
}

function W.Backdrop(frame, color, alpha, border, borderAlpha)
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
    local b = border or W.COLORS.divider
    frame:SetBackdropBorderColor(b[1], b[2], b[3], borderAlpha or 1)
end

function W.Panel(parent, color, border)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.Backdrop(frame, color or W.COLORS.panel, 0.95, border)
    return frame
end

---------------------------------------------------------------------------
-- Tooltips: a gold title and a white explanation on mouse over.
-- W.Tooltip(widget, text, title): text and title may be functions.
---------------------------------------------------------------------------
local tipInfo = setmetatable({}, { __mode = "k" })
local tipHooked = setmetatable({}, { __mode = "k" })

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
        local g = W.COLORS.heading
        GameTooltip:SetText(title, g[1], g[2], g[3])
        GameTooltip:AddLine(text, 1, 1, 1, true)
    else
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

-- Adds fn to a script without replacing what is already there.
local function addScript(frame, script, fn)
    if frame:GetScript(script) then
        frame:HookScript(script, fn)
    else
        frame:SetScript(script, fn)
    end
end
W.AddScript = addScript

function W.Tooltip(widget, text, title)
    local info = tipInfo[widget] or { targets = { widget } }
    info.text = text
    info.title = title or info.title
    for _, target in ipairs(info.targets) do
        tipInfo[target] = info
        if not tipHooked[target] then
            tipHooked[target] = true
            target:EnableMouse(true)
            addScript(target, "OnEnter", showTooltip)
            addScript(target, "OnLeave", hideTooltip)
        end
    end
    return widget
end

local function tipDefaults(widget, title, targets)
    tipInfo[widget] = { title = title, targets = targets or { widget } }
end

---------------------------------------------------------------------------
-- Text, icons, lines
---------------------------------------------------------------------------
function W.Text(parent, text, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", ns.Fonts.Template(template or "GameFontHighlight"))
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    local c = color or W.COLORS.text
    fs:SetTextColor(c[1], c[2], c[3])
    if fs.SetWordWrap then
        fs:SetWordWrap(false) -- single line: long text is cut with "...", never overlaps
    end
    return fs
end

function W.Heading(parent, text)
    return W.Text(parent, text, "GameFontNormalLarge", W.COLORS.heading)
end

-- A game icon with the outer border trimmed.
function W.Icon(parent, texture, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    function icon:SetIcon(path)
        self:SetTexture(path)
        -- Game icons have a border to crop; the addon's own art does not.
        if ns.Media.IsOwn(path) then
            self:SetTexCoord(0, 1, 0, 1)
        else
            self:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    icon:SetIcon(texture)
    return icon
end

-- An achievement medallion with its rarity frame on top (v0.15.0). Both
-- are centered; the frame is a little larger than the medallion so the
-- two rims never double up.
function W.Medallion(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    local art = holder:CreateTexture(nil, "ARTWORK")
    art:SetPoint("CENTER")
    art:SetSize(size * 0.78, size * 0.78)
    local rim = holder:CreateTexture(nil, "OVERLAY")
    rim:SetPoint("CENTER")
    rim:SetSize(size, size)
    -- v1.0.0-beta.8: `locked` = grey and dim (desaturated where the client
    -- can), so an earned medallion stands out in full color.
    function holder:Set(medallion, frame, alpha, locked)
        art:SetTexture(medallion)
        rim:SetTexture(frame)
        rim:SetShown(frame ~= nil)
        if art.SetDesaturated then
            art:SetDesaturated(locked and true or false)
            rim:SetDesaturated(locked and true or false)
        end
        art:SetAlpha(alpha or 1)
        rim:SetAlpha(alpha or 1)
    end
    holder.art, holder.rim = art, rim
    return holder
end

-- An icon in a small dark square (event rows, cards).
function W.IconBox(parent, texture, size)
    local box = W.Panel(parent, W.COLORS.background, W.COLORS.divider)
    box:SetSize(size, size)
    box.icon = W.Icon(box, texture, size - 8)
    box.icon:SetPoint("CENTER")
    function box:SetIcon(path)
        self.icon:SetIcon(path)
    end
    return box
end

function W.Divider(parent, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    local c = W.COLORS.divider
    line:SetColorTexture(c[1], c[2], c[3], 1)
    line:SetHeight(1)
    if width then
        line:SetWidth(width)
    end
    return line
end

-- A small round-looking status dot (a square texture, 8 px).
function W.Dot(parent)
    local dot = parent:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8)
    function dot:SetColor(c)
        self:SetColorTexture(c[1], c[2], c[3], 1)
    end
    return dot
end

---------------------------------------------------------------------------
-- Flat button: dark surface, thin border, gold when selected or hovered.
---------------------------------------------------------------------------
local function paintButton(button)
    local c = W.COLORS
    local bg = button.selected and c.selected or (button.hovered and c.hover or c.panel)
    local border = (button.selected or button.hovered) and c.gold or c.divider
    if button.disabled then
        bg, border = c.panel, c.divider
    end
    W.Backdrop(button, bg, 0.97, border, button.selected and 1 or 0.9)
    local tc = button.disabled and c.muted or (button.selected and c.heading or c.text)
    button.label:SetTextColor(tc[1], tc[2], tc[3])
end

function W.Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 120, height or 26)
    button.label = W.Text(button, text, "GameFontHighlight")
    button.label:SetPoint("CENTER")
    button.label:SetJustifyH("CENTER")
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if not self.disabled and onClick then
            ns.SafeCall("button", onClick, self, mouseButton)
        end
    end)
    addScript(button, "OnEnter", function(self) self.hovered = true; paintButton(self) end)
    addScript(button, "OnLeave", function(self) self.hovered = false; paintButton(self) end)
    function button:SetLabel(value) self.label:SetText(value) end
    function button:SetSelected(value)
        self.selected = value and true or false
        paintButton(self)
    end
    function button:SetDisabled(value)
        self.disabled = value and true or false
        paintButton(self)
    end
    paintButton(button)
    return button
end

-- A border from a square 9-slice texture (v0.17.0: notifications): corners
-- keep their size, edges stretch. `texSize` and `corner` are in texture
-- pixels; `size` is the corner on screen. Only SetTexCoord is used.
-- `filled` (v1.0.0-beta.9): the texture also holds the background, so the
-- center is drawn too and everything goes to the BACKGROUND layer (a card
-- with cut corners has no square backdrop under it).
function W.NineSlice(frame, file, texSize, corner, size, filled)
    local c = corner / texSize
    local parts = {}
    local function part(l, r, t, b)
        local tex = frame:CreateTexture(nil, filled and "BACKGROUND" or "BORDER", nil, filled and -1 or nil)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        parts[#parts + 1] = tex
        return tex
    end
    local tl = part(0, c, 0, c); tl:SetSize(size, size); tl:SetPoint("TOPLEFT")
    local tr = part(1 - c, 1, 0, c); tr:SetSize(size, size); tr:SetPoint("TOPRIGHT")
    local bl = part(0, c, 1 - c, 1); bl:SetSize(size, size); bl:SetPoint("BOTTOMLEFT")
    local br = part(1 - c, 1, 1 - c, 1); br:SetSize(size, size); br:SetPoint("BOTTOMRIGHT")
    local top = part(c, 1 - c, 0, c); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    local bottom = part(c, 1 - c, 1 - c, 1); bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local left = part(0, c, c, 1 - c); left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local right = part(1 - c, 1, c, 1 - c); right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    if filled then
        local center = part(c, 1 - c, c, 1 - c)
        center:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
        center:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    end
    return parts
end

-- Square icon button (v0.16.0: the History menu). The name is kept in a
-- hidden label (tooltip title, tests) and shown in the tooltip.
function W.IconButton(parent, texture, size, name, tip, onClick)
    local button = W.Button(parent, name, size, size, onClick)
    button.label:Hide()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("CENTER")
    button.icon:SetSize(size - 10, size - 10)
    button.icon:SetTexture(texture)
    local mark = button:CreateTexture(nil, "OVERLAY")
    local g = W.COLORS.gold
    mark:SetColorTexture(g[1], g[2], g[3], 1)
    mark:SetWidth(3)
    mark:SetPoint("TOPLEFT", 0, -4)
    mark:SetPoint("BOTTOMLEFT", 0, 4)
    mark:Hide()
    local setSelected = button.SetSelected
    function button:SetSelected(value)
        setSelected(self, value)
        mark:SetShown(self.selected)
        self.icon:SetAlpha((self.selected or self.hovered) and 1 or 0.75)
    end
    button:SetSelected(false)
    W.Tooltip(button, tip, name)
    return button
end

-- Side menu entry (v1.0.0-beta.4: Settings): an icon and the name, left
-- aligned, with the gold mark of the selected entry. `collapsed` shows the
-- icon only; the name is then in the tooltip (and kept in the label).
function W.MenuButton(parent, texture, text, width, height, onClick, collapsed)
    local button = W.Button(parent, text, width, height, onClick)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(collapsed and height - 10 or 20, collapsed and height - 10 or 20)
    button.icon:SetTexture(texture)
    -- Game icons have a border to crop; the addon's own art does not.
    if not ns.Media.IsOwn(texture) then
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    button.label:ClearAllPoints()
    if collapsed then
        button.icon:SetPoint("CENTER")
        button.label:Hide()
        W.Tooltip(button, nil, text)
    else
        button.icon:SetPoint("LEFT", 10, 0)
        button.label:SetPoint("LEFT", button.icon, "RIGHT", 8, 0)
        button.label:SetPoint("RIGHT", -6, 0)
        button.label:SetJustifyH("LEFT")
    end
    local mark = button:CreateTexture(nil, "OVERLAY")
    local g = W.COLORS.gold
    mark:SetColorTexture(g[1], g[2], g[3], 1)
    mark:SetWidth(3)
    mark:SetPoint("TOPLEFT", 0, -4)
    mark:SetPoint("BOTTOMLEFT", 0, 4)
    mark:Hide()
    local setSelected = button.SetSelected
    function button:SetSelected(value)
        setSelected(self, value)
        mark:SetShown(self.selected)
        self.icon:SetAlpha((self.selected or self.hovered) and 1 or 0.75)
    end
    button:SetSelected(false)
    return button
end

-- Text link such as "View all screenshots ->".
function W.Link(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent)
    button.label = W.Text(button, text, "GameFontNormal", W.COLORS.gold)
    button.label:SetPoint("CENTER")
    button:SetSize((button.label:GetStringWidth() or 100) + 16, 22)
    button:SetScript("OnClick", function() ns.SafeCall("link", onClick) end)
    addScript(button, "OnEnter", function() local c = W.COLORS.heading; button.label:SetTextColor(c[1], c[2], c[3]) end)
    addScript(button, "OnLeave", function() local c = W.COLORS.gold; button.label:SetTextColor(c[1], c[2], c[3]) end)
    return button
end

---------------------------------------------------------------------------
-- Checkbox: a gold-framed box, a check mark and a clickable label.
---------------------------------------------------------------------------
function W.Check(parent, label, get, set, width)
    local check = CreateFrame("Button", nil, parent)
    check:SetSize(width or 300, 24)
    -- v1.0.1: the Obsidian checkbox art (the box and the mark are one
    -- picture, so the mark can never slip out of the box). The art fills
    -- 26..102 of 128 px: the crop keeps a thin margin around it.
    local box = check:CreateTexture(nil, "ARTWORK")
    box:SetSize(20, 20)
    box:SetPoint("LEFT", 0, 0)
    box:SetTexture(ns.Media.DECOR.checkbox_off)
    box:SetTexCoord(0.17, 0.83, 0.17, 0.83)
    local g = W.COLORS.gold
    check.label = W.Text(check, label)
    check.label:SetPoint("LEFT", box, "RIGHT", 10, 0)
    check.label:SetPoint("RIGHT", check, "RIGHT", 0, 0)
    local highlight = check:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(g[1], g[2], g[3], 0.06)
    tipDefaults(check, label)
    check.available = true

    check:SetScript("OnClick", function(self)
        if not self.available then
            return
        end
        ns.SafeCall("check", set, not get())
        self:Refresh()
        if parent.Refresh then parent:Refresh() end
    end)
    function check:Refresh()
        local on = self.available and get() and true or false
        box:SetTexture(on and ns.Media.DECOR.checkbox_on or ns.Media.DECOR.checkbox_off)
        box:SetTexCoord(0.17, 0.83, 0.17, 0.83)
        if box.SetDesaturated then
            box:SetDesaturated(not self.available)
        end
        box:SetAlpha(self.available and 1 or 0.5)
        local c = self.available and W.COLORS.text or W.COLORS.muted
        self.label:SetTextColor(c[1], c[2], c[3])
    end
    check.box = box
    check.IsOn = function() return check.available and get() and true or false end
    -- An event the client cannot report is shown greyed out.
    function check:SetAvailable(value)
        self.available = value and true or false
        self:Refresh()
    end
    return check
end

---------------------------------------------------------------------------
-- Dropdown: a button that opens a list of options under it. One shared
-- list frame serves every dropdown. Built from plain frames on purpose.
---------------------------------------------------------------------------
local LIST_ROW_HEIGHT = 20
local LIST_MAX_ROWS = 14 -- longer lists scroll with the mouse wheel (v0.11.0)
local list

local function closeList()
    if list then
        list:Hide()
    end
end
W.CloseDropdown = closeList

local function createList()
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetScript("OnClick", closeList)
    catcher:Hide()

    list = CreateFrame("Frame", "ForeverMemoriesDropdownList", UIParent, "BackdropTemplate")
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    W.Backdrop(list, W.COLORS.background, 0.98, W.COLORS.gold)
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
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    local g = W.COLORS.gold
    highlight:SetColorTexture(g[1], g[2], g[3], 0.2)
    row.text = W.Text(row, "")
    row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
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

local function drawList()
    local options, current, width = list.options, list.current, list.width
    local shown = math.min(#options, LIST_MAX_ROWS)
    list.offset = math.max(0, math.min(list.offset or 0, #options - shown))
    for i = 1, shown do
        local option = options[list.offset + i]
        local row = listRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2 - (i - 1) * LIST_ROW_HEIGHT)
        row:SetWidth(width - 4)
        row.value = option.value
        row.text:SetText(option.text)
        local c = option.value == current and W.COLORS.heading or W.COLORS.text
        row.text:SetTextColor(c[1], c[2], c[3])
        row:Show()
    end
    for i = shown + 1, #list.rows do
        list.rows[i]:Hide()
    end
    return shown
end

local function openList(owner, options, current)
    list = list or createList()
    if list:IsShown() and list.owner == owner then
        return closeList()
    end
    local width = owner:GetWidth()
    list.options, list.current, list.width, list.offset = options, current, width, 0
    -- Start with the chosen option in view.
    for i, option in ipairs(options) do
        if option.value == current and i > LIST_MAX_ROWS then
            list.offset = i - LIST_MAX_ROWS
        end
    end
    local shown = drawList()
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list.offset = (list.offset or 0) - delta * 3
        drawList()
    end)
    list:SetSize(width, shown * LIST_ROW_HEIGHT + 4)
    list:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    list.owner = owner
    list:Show()
    list.catcher:Show()
end

-- options: list of { value = ..., text = ... }. set(value) is called only
-- when the player picks a different value.
function W.Dropdown(parent, options, get, set, width)
    local button = W.Button(parent, "", width or 140, 26, function(self)
        openList(self, options, get())
    end)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 10, 0)
    button.label:SetPoint("RIGHT", -22, 0)
    local arrow = W.Text(button, "v", "GameFontHighlightSmall", W.COLORS.gold)
    arrow:SetPoint("RIGHT", -8, 0)

    function button:Choose(value)
        if value ~= get() then
            ns.SafeCall("dropdown", set, value)
        end
        self:Refresh()
    end
    button:SetScript("OnHide", function(self)
        if list and list.owner == self then
            closeList()
        end
    end)
    function button:Refresh()
        local current = get()
        for _, option in ipairs(options) do
            if option.value == current then
                self:SetLabel(option.text)
                return
            end
        end
        self:SetLabel(tostring(current))
    end
    return button
end

---------------------------------------------------------------------------
-- Slider: a thin track, a gold filled part and a square thumb.
---------------------------------------------------------------------------
function W.Slider(parent, width, min, max, step, get, set)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetSize(width, 20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    local c = W.COLORS
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(c.divider[1], c.divider[2], c.divider[3], 1)
    track:SetHeight(6)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(c.gold[1], c.gold[2], c.gold[3], 1)
    fill:SetHeight(6)
    fill:SetPoint("LEFT", 0, 0)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(c.heading[1], c.heading[2], c.heading[3], 1)
    thumb:SetSize(14, 18)
    slider:SetThumbTexture(thumb)

    local updating = false
    local function paint(value)
        fill:SetWidth(math.max(1, (value - min) / (max - min) * width))
    end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        paint(value)
        if not updating and value ~= get() then
            ns.SafeCall("slider", set, value)
        end
    end)
    function slider:Refresh()
        updating = true
        self:SetValue(get())
        paint(get())
        updating = false
    end
    return slider
end

---------------------------------------------------------------------------
-- Height of a wrapped text at `width` (v1.0.1, shared). Measured with a
-- hidden font string when the client can, estimated otherwise.
---------------------------------------------------------------------------
local measurer
function W.TextHeight(text, width, template)
    text = tostring(text or "")
    if not measurer then
        measurer = UIParent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        measurer:Hide()
        if measurer.SetWordWrap then measurer:SetWordWrap(true) end
    end
    measurer:SetFontObject(template or "GameFontHighlightSmall")
    measurer:SetWidth(width)
    measurer:SetText(text)
    local height = measurer:GetStringHeight()
    if type(height) == "number" and height > 0 then
        return math.ceil(height)
    end
    local chars = select(2, string.gsub(text, "[^\128-\191]", ""))
    return math.max(1, math.ceil(chars * 6 / width)) * 13
end

---------------------------------------------------------------------------
-- Scroll bar (v1.0.1): a track along the right edge and a thumb that can be
-- dragged with the mouse; a click on the track moves the thumb there.
-- setFraction(f) scrolls the list to f (0 = top, 1 = bottom).
---------------------------------------------------------------------------
W.SCROLLBAR_WIDTH = 8

local function cursorY(frame)
    local _, y = GetCursorPosition()
    return (y or 0) / (frame:GetEffectiveScale() or 1)
end

local function makeScrollBar(box, setFraction)
    local c = W.COLORS
    local track = CreateFrame("Button", nil, box)
    track:SetWidth(W.SCROLLBAR_WIDTH)
    track:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    if track.SetFrameLevel and box.GetFrameLevel then
        track:SetFrameLevel((box:GetFrameLevel() or 1) + 20)
    end
    local rail = track:CreateTexture(nil, "BACKGROUND")
    rail:SetWidth(2)
    rail:SetPoint("TOP", track, "TOP", 0, 0)
    rail:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    rail:SetColorTexture(c.divider[1], c.divider[2], c.divider[3], 0.8)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(W.SCROLLBAR_WIDTH)
    local knob = thumb:CreateTexture(nil, "ARTWORK")
    knob:SetWidth(4)
    knob:SetPoint("TOP", thumb, "TOP", 0, 0)
    knob:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
    knob:SetColorTexture(c.gold[1], c.gold[2], c.gold[3], 0.7)
    local glow = thumb:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(knob)
    glow:SetColorTexture(c.heading[1], c.heading[2], c.heading[3], 0.5)
    track.thumb = thumb

    local view, size, top = 0, 0, 0 -- track height, thumb height, thumb offset
    local function free() return math.max(1, view - size) end
    -- Places the thumb: viewHeight of the list, thumbHeight, fraction 0..1.
    function track:Place(viewHeight, thumbHeight, fraction)
        view, size = viewHeight, thumbHeight
        top = (view - size) * fraction
        thumb:SetHeight(size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -top)
    end
    local function moveTo(newTop)
        newTop = math.max(0, math.min(newTop, view - size))
        setFraction(newTop / free())
    end
    -- Drag: the thumb follows the cursor from where it was grabbed.
    local grab
    local function stop(self)
        grab = nil
        self:SetScript("OnUpdate", nil)
    end
    thumb:SetScript("OnMouseDown", function(self)
        grab = { y = cursorY(self), top = top }
        self:SetScript("OnUpdate", function(frame)
            if not grab then return end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                return stop(frame)
            end
            moveTo(grab.top + (grab.y - cursorY(frame)))
        end)
    end)
    thumb:SetScript("OnMouseUp", stop)
    thumb:SetScript("OnHide", stop)
    -- A click on the track: the thumb's middle goes under the cursor.
    track:SetScript("OnMouseDown", function(self)
        local trackTop = self:GetTop()
        if type(trackTop) == "number" then
            moveTo(trackTop - cursorY(self) - size / 2)
        end
    end)
    track:EnableMouseWheel(true)
    track:SetScript("OnMouseWheel", function(_, delta) box:Scroll(delta) end)
    -- For the tests: drag by dy pixels (positive = down).
    function track:DragBy(dy)
        moveTo(top + dy)
    end
    return track
end

---------------------------------------------------------------------------
-- Scrolling list that creates only the rows that fit on screen and
-- refills them while scrolling: thousands of records, a dozen frames.
--   makeRow(parent) -> row frame       fillRow(row, item)
---------------------------------------------------------------------------
function W.ScrollList(parent, width, height, rowHeight, makeRow, fillRow)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height)
    box:EnableMouseWheel(true)
    local visible = math.floor(height / rowHeight)
    local rows, items, offset = {}, {}, 0
    for i = 1, visible do
        local row = makeRow(box)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetSize(width - 8, rowHeight)
        rows[i] = row
    end
    local function maxOffset()
        return math.max(0, #items - visible)
    end
    local bar = makeScrollBar(box, function(fraction)
        offset = math.floor(fraction * maxOffset() + 0.5)
        box:Redraw()
    end)
    function box:Redraw()
        offset = ns.Util.Clamp(offset, 0, maxOffset(), 0)
        for i, row in ipairs(rows) do
            local item = items[offset + i]
            if item then
                fillRow(row, item)
                row:Show()
            else
                row:Hide()
            end
        end
        if maxOffset() > 0 then
            bar:Place(height, math.max(24, height * visible / #items), offset / maxOffset())
            bar:Show()
        else
            bar:Hide()
        end
    end
    function box:SetItems(newItems, keepOffset)
        items = newItems or {}
        if not keepOffset then
            offset = 0
        end
        self:Redraw()
    end
    function box:Scroll(delta)
        offset = offset - delta * 3
        self:Redraw()
    end
    box:SetScript("OnMouseWheel", function(self, delta) self:Scroll(delta) end)
    box.rows = rows
    box.bar = bar
    return box
end

---------------------------------------------------------------------------
-- Scrolling list with rows of different kinds and heights (v0.9.0): one
-- scroll area for a whole History sub-view (charts, panels, rows), no
-- nested scrolling. Only the visible items get a frame; frames are reused
-- per kind.
--   kinds[kind] = { height = n, make = fn(parent) -> frame,
--                   fill = fn(frame, item) }   item.height overrides height
---------------------------------------------------------------------------
W.SCROLL_STEP = 40

function W.FlexList(parent, width, height, kinds)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height)
    box:EnableMouseWheel(true)
    local clips = box.SetClipsChildren ~= nil
    if clips then
        box:SetClipsChildren(true)
    end
    local items, tops, total, scroll = {}, {}, 0, 0
    local pools = {}

    -- v1.0.1: a kind may measure its item (wrapped text): measure(item, w).
    local function heightOf(item)
        if item.height then
            return item.height
        end
        local kind = kinds[item.kind]
        if kind.measure then
            item.measured = item.measured or math.max(kind.height, kind.measure(item, width - 8))
            return item.measured
        end
        return kind.height
    end
    local function maxScroll()
        return math.max(0, total - height)
    end
    local bar = makeScrollBar(box, function(fraction)
        scroll = fraction * maxScroll()
        box:Redraw()
    end)
    local function take(kind)
        local pool = pools[kind]
        if not pool then
            pool = { frames = {}, used = 0 }
            pools[kind] = pool
        end
        pool.used = pool.used + 1
        local frame = pool.frames[pool.used]
        if not frame then
            frame = kinds[kind].make(box)
            pool.frames[pool.used] = frame
        end
        return frame
    end

    function box:Redraw()
        scroll = ns.Util.Clamp(scroll, 0, maxScroll(), 0)
        for _, pool in pairs(pools) do
            pool.used = 0
        end
        for i, item in ipairs(items) do
            local top, h = tops[i] - scroll, heightOf(item)
            local visible = top + h > 0 and top < height
            if not clips then
                visible = top >= 0 and top + h <= height + 1 -- no clipping: whole items only
            end
            if visible then
                local frame = take(item.kind)
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -top)
                frame:SetSize(width - 8, h)
                kinds[item.kind].fill(frame, item)
                frame:Show()
            end
        end
        for _, pool in pairs(pools) do
            for i = pool.used + 1, #pool.frames do
                pool.frames[i]:Hide()
            end
        end
        if maxScroll() > 0 then
            bar:Place(height, math.max(24, height * height / total), scroll / maxScroll())
            bar:Show()
        else
            bar:Hide()
        end
    end
    function box:SetItems(newItems, keepScroll)
        items = newItems or {}
        total = 0
        for i, item in ipairs(items) do
            tops[i] = total
            total = total + heightOf(item)
        end
        if not keepScroll then
            scroll = 0
        end
        self:Redraw()
    end
    -- Scrolls so that the first item for which `match(item)` is true is on top.
    function box:ScrollTo(match)
        for i, item in ipairs(items) do
            if match(item) then
                scroll = tops[i]
                self:Redraw()
                return true
            end
        end
        return false
    end
    function box:Scroll(delta)
        scroll = scroll - delta * W.SCROLL_STEP
        self:Redraw()
    end
    function box:Offset()
        return scroll
    end
    -- New visible height (the window was resized, v0.15.0).
    function box:SetViewHeight(newHeight)
        if newHeight and newHeight > 0 and newHeight ~= height then
            height = newHeight
            self:SetHeight(height)
            self:Redraw()
        end
    end
    function box:ViewHeight()
        return height
    end
    box:SetScript("OnMouseWheel", function(self, delta) self:Scroll(delta) end)
    box.items = function() return items end
    box.bar = bar
    return box
end

-- Lists that grow with the window (v0.15.0): their height is
-- base + extra, where extra = window height - default window height.
W.stretchable = {}
W.extraHeight = 0
function W.Stretch(list)
    W.stretchable[#W.stretchable + 1] = { list = list, base = list:ViewHeight() }
    if W.extraHeight ~= 0 then
        list:SetViewHeight(math.max(W.MIN_LIST_HEIGHT, list:ViewHeight() + W.extraHeight))
    end
    return list
end
-- The pages are built again at a new width (v1.0.1): their old lists go.
function W.ForgetStretched()
    W.stretchable = {}
end
-- v1.0.0-beta.5: extra is negative in a window lower than the default; a
-- list keeps at least W.MIN_LIST_HEIGHT.
W.MIN_LIST_HEIGHT = 120
function W.SetExtraHeight(extra)
    W.extraHeight = extra or 0
    for _, entry in ipairs(W.stretchable) do
        entry.list:SetViewHeight(math.max(W.MIN_LIST_HEIGHT, entry.base + W.extraHeight))
    end
end

---------------------------------------------------------------------------
-- Scroll page (v1.0.0-beta.5): a page with a fixed layout (Home, most
-- Settings pages) inside a ScrollFrame. It scrolls with the mouse wheel
-- and a scroll bar when the window is lower than the page. The bar sits in
-- the window margin right of the page, so the page keeps its full width.
-- Build the page into box.child, then call box:SetContentHeight(h).
---------------------------------------------------------------------------
W.SCROLL_STEP = 40
function W.ScrollPage(parent, width)
    local box = CreateFrame("Frame", nil, parent)
    box:SetAllPoints(parent)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetAllPoints(box)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 1)
    scroll:SetScrollChild(child)
    box.scroll, box.child = scroll, child
    local contentHeight, offset = 0, 0

    local function viewHeight()
        local h = box:GetHeight()
        return (type(h) == "number" and h > 0) and h or contentHeight
    end
    local bar
    function box:Update()
        local view = viewHeight()
        local free = math.max(0, contentHeight - view)
        offset = math.max(0, math.min(offset, free))
        scroll:SetVerticalScroll(offset)
        bar:SetShown(free > 0)
        if free > 0 then
            bar:Place(view, math.max(24, view * view / contentHeight), offset / free)
        end
    end
    bar = makeScrollBar(box, function(fraction)
        offset = fraction * math.max(0, contentHeight - viewHeight())
        box:Update()
    end)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    box.bar = bar

    function box:SetContentHeight(h)
        contentHeight = h
        child:SetHeight(h)
        self:Update()
    end
    function box:Scroll(delta)
        offset = offset - delta * W.SCROLL_STEP
        self:Update()
    end
    function box:Offset() return offset end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) box:Scroll(delta) end)
    W.AddScript(box, "OnSizeChanged", function() box:Update() end)
    return box
end

-- Text field for search: dark box, gold border on focus, a grey hint while
-- empty. onChange(text) is called for typing only.
function W.SearchBox(parent, hint, width, onChange)
    local edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    edit:SetSize(width or 200, 28)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlight")
    edit:SetTextInsets(12, 12, 0, 0)
    edit:SetMaxLetters(40)
    W.Backdrop(edit, W.COLORS.background, 0.95, W.COLORS.divider)
    local placeholder = W.Text(edit, hint, "GameFontHighlight", W.COLORS.muted)
    placeholder:SetPoint("LEFT", 12, 0)
    local function paint(focused)
        local b = focused and W.COLORS.gold or W.COLORS.divider
        edit:SetBackdropBorderColor(b[1], b[2], b[3], 1)
    end
    edit:SetScript("OnEditFocusGained", function() paint(true) end)
    edit:SetScript("OnEditFocusLost", function() paint(false) end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        placeholder:SetShown(text == "")
        if userInput then
            ns.SafeCall("search", onChange, text)
        end
    end)
    return edit
end

-- A row of small pill buttons, one selected: "Week | Month", "7 | 30".
-- options = { { value, text }, ... }; onSelect(value).
function W.Segmented(parent, options, width, onSelect)
    local holder = CreateFrame("Frame", nil, parent)
    local each = (width or 160) / #options
    holder:SetSize(width or 160, 24)
    local buttons = {}
    for i, option in ipairs(options) do
        local button = W.Button(holder, option[2], each - 4, 22, function()
            holder:SetValue(option[1])
            ns.SafeCall("segment", onSelect, option[1])
        end)
        button:SetPoint("LEFT", (i - 1) * each, 0)
        button.value = option[1]
        buttons[i] = button
    end
    function holder:SetValue(value)
        self.value = value
        for _, button in ipairs(buttons) do
            button:SetSelected(button.value == value)
        end
    end
    holder.buttons = buttons
    return holder
end
