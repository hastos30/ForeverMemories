-- UI/SettingsAbout.lua
-- Settings / About and Settings / Changelog (v0.10.0). Both are one
-- scrolling list (W.FlexList) of rows of different kinds.
--   About:     logo, name, slogan, version, description, author and
--              copyright, community links (only confirmed ones, copied
--              from a text box). v1.0.0-beta.4: no technical block; the
--              diagnostics are in chat (/fm debug, /fm diag).
--   Changelog: one collapsible card per version from CHANGELOG.md
--              (Modules/ChangelogData.lua); the newest is open.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local WIDTH = UI.SETTINGS_WIDTH
local INNER = WIDTH - 8
local function measureWidth() -- the width follows the window and the side menu
    WIDTH = UI.SETTINGS_WIDTH
    INNER = WIDTH - 8
end
local LOGO = ns.Media.COMPASS

local function setColor(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
end

-- Height of a wrapped text at `width`. Measured with a hidden font string
-- when the client can, estimated otherwise.
local measure
local function textHeight(text, width, template)
    if not measure then
        measure = UIParent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        measure:Hide()
        if measure.SetWordWrap then measure:SetWordWrap(true) end
    end
    measure:SetFontObject(template or "GameFontHighlightSmall")
    measure:SetWidth(width)
    measure:SetText(text)
    local height = measure:GetStringHeight()
    if type(height) == "number" and height > 0 then
        return math.ceil(height)
    end
    local chars = select(2, string.gsub(text, "[^\128-\191]", ""))
    return math.ceil(chars * 6 / width) * 13
end

-- Wrapped text block (descriptions, changelog items).
local paragraph = {
    height = 20,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.text = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.text)
        if row.text.SetWordWrap then row.text:SetWordWrap(true) end
        row.text:SetJustifyV("TOP")
        return row
    end,
    fill = function(row, item)
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", item.indent or 0, -2)
        row.text:SetPoint("BOTTOMRIGHT", -8, 0)
        row.text:SetText(item.text)
        row.text:SetJustifyH(item.center and "CENTER" or "LEFT")
        setColor(row.text, item.color or W.COLORS.text)
    end,
}

local heading = {
    height = 34,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.text = W.Text(row, "", "GameFontNormalLarge", W.COLORS.heading)
        row.text:SetPoint("BOTTOMLEFT", 0, 6)
        row.line = W.Divider(row)
        row.line:SetPoint("TOPLEFT", 0, 0)
        row.line:SetPoint("TOPRIGHT", -8, 0)
        return row
    end,
    fill = function(row, item)
        row.text:SetText(item.text)
    end,
}

-- Label on the left, value on the right; optionally clickable.
local info = {
    height = 28,
    make = function(parent)
        local row = CreateFrame("Button", nil, parent)
        row.icon = W.Icon(row, LOGO, 16)
        row.icon:SetPoint("LEFT", 0, 0)
        row.label = W.Text(row, "", "GameFontHighlight", W.COLORS.text)
        row.value = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
        row.value:SetPoint("RIGHT", -8, 0)
        row.value:SetJustifyH("RIGHT")
        local g = W.COLORS.gold
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(g[1], g[2], g[3], 0.06)
        row:SetScript("OnClick", function(self)
            if self.onClick then ns.SafeCall("about row", self.onClick) end
        end)
        return row
    end,
    fill = function(row, item)
        row.icon:SetShown(item.icon ~= nil)
        if item.icon then row.icon:SetIcon(item.icon) end
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", item.icon and 26 or 0, 0)
        row.label:SetPoint("RIGHT", row.value, "LEFT", -12, 0)
        row.label:SetText(item.label)
        row.value:SetText(item.value or "")
        setColor(row.value, item.onClick and W.COLORS.gold or W.COLORS.muted)
        row.onClick = item.onClick
        row.highlight:SetShown(item.onClick ~= nil)
        row:EnableMouse(item.onClick ~= nil)
    end,
}

-- A clickable full-width bar: "Technical information v", version cards.
local toggle = {
    height = 40,
    make = function(parent)
        local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        W.Backdrop(row, W.COLORS.panel, 0.95, W.COLORS.divider)
        row.title = W.Text(row, "", "GameFontNormal", W.COLORS.heading)
        row.title:SetPoint("TOPLEFT", 12, -8)
        row.subtitle = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
        row.subtitle:SetPoint("BOTTOMLEFT", 12, 8)
        row.arrow = W.Text(row, "", "GameFontNormal", W.COLORS.gold)
        row.arrow:SetPoint("RIGHT", -12, 0)
        row:SetScript("OnClick", function(self)
            if self.onClick then ns.SafeCall("toggle", self.onClick) end
        end)
        W.AddScript(row, "OnEnter", function(self) local g = W.COLORS.gold; self:SetBackdropBorderColor(g[1], g[2], g[3], 1) end)
        W.AddScript(row, "OnLeave", function(self) local d = W.COLORS.divider; self:SetBackdropBorderColor(d[1], d[2], d[3], 1) end)
        return row
    end,
    fill = function(row, item)
        row.title:ClearAllPoints()
        if item.subtitle then
            row.title:SetPoint("TOPLEFT", 12, -8)
        else
            row.title:SetPoint("LEFT", 12, 0)
        end
        row.title:SetText(item.title)
        row.subtitle:SetText(item.subtitle or "")
        row.arrow:SetText(item.open and "v" or ">")
        row.onClick = item.onClick
    end,
}

local spacer = {
    height = 10,
    make = function(parent) return CreateFrame("Frame", nil, parent) end,
    fill = function() end,
}

---------------------------------------------------------------------------
-- About
---------------------------------------------------------------------------
local logoKind = {
    height = 196,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        -- Full logo (v0.15.0): only here, never in the header.
        local logo = row:CreateTexture(nil, "ARTWORK")
        logo:SetSize(288, 144)
        logo:SetTexture(ns.Media.LOGO)
        logo:SetPoint("TOP", 0, 0)
        local name = W.Text(row, "", "GameFontNormalHuge", W.COLORS.heading)
        name:SetPoint("TOP", logo, "BOTTOM", 0, 0)
        name:SetHeight(1)
        local slogan = W.Text(row, L.SLOGAN, "GameFontHighlight", W.COLORS.muted)
        slogan:SetPoint("TOP", name, "BOTTOM", 0, -6)
        slogan:SetJustifyH("CENTER")
        row.version = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.text)
        row.version:SetPoint("TOP", slogan, "BOTTOM", 0, -6)
        row.version:SetJustifyH("CENTER")
        return row
    end,
    fill = function(row)
        row.version:SetText(string.format(L.VERSION_LABEL, ns.version) .. "  ·  " .. ns.ProjectInfo.game)
    end,
}

-- "DESIGNED & DEVELOPED BY", the name and the copyright, centered.
local credit = {
    height = 78,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.caption = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.gold)
        row.caption:SetPoint("TOP", 0, -10)
        row.name = W.Text(row, "", "GameFontNormalLarge", W.COLORS.heading)
        row.name:SetPoint("TOP", row.caption, "BOTTOM", 0, -6)
        row.copyright = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.muted)
        row.copyright:SetPoint("TOP", row.name, "BOTTOM", 0, -8)
        return row
    end,
    fill = function(row, item)
        row.caption:SetText(item.caption)
        row.name:SetText(item.name)
        row.copyright:SetText(item.copyright or "")
    end,
}

local function copyLink(label, url)
    UI.ShowCopyText(label, url, L.LINK_HINT)
end

UI.settingsPages.about = function(parent)
    measureWidth()
    local list = W.FlexList(parent, WIDTH, UI.SettingsPageHeight("about"), {
        logo = logoKind, paragraph = paragraph, heading = heading, info = info,
        credit = credit, spacer = spacer,
    })
    W.Stretch(list)
    list:SetPoint("TOPLEFT", 0, 0)
    local refresh

    local function build()
        local p = ns.ProjectInfo
        local items = { { kind = "logo" } }
        items[#items + 1] = { kind = "paragraph", text = L.ABOUT_DESCRIPTION, color = W.COLORS.text, center = true,
            height = textHeight(L.ABOUT_DESCRIPTION, INNER - 8) + 12 }
        if p.author then
            items[#items + 1] = { kind = "credit", caption = L.DESIGNED_BY, name = p.author,
                copyright = p.copyright }
        end
        if p.license then items[#items + 1] = { kind = "info", label = L.ABOUT_LICENSE, value = p.license } end
        if p.thanks then items[#items + 1] = { kind = "info", label = L.ABOUT_THANKS, value = p.thanks } end
        -- Only confirmed links; nothing at all while there are none.
        local links = {}
        for _, link in ipairs(p.links) do
            if type(link.url) == "string" and link.url ~= "" then
                local label = L["LINK_" .. link.id]
                links[#links + 1] = { kind = "info", label = label, value = L.COPY_LINK,
                    icon = ns.Media.ICON.calendar,
                    onClick = function() copyLink(label, link.url) end }
            end
        end
        if #links > 0 then
            items[#items + 1] = { kind = "spacer" }
            items[#items + 1] = { kind = "heading", text = L.COMMUNITY }
            for _, row in ipairs(links) do
                items[#items + 1] = row
            end
        end
        return items
    end
    refresh = function(keep)
        list:SetItems(build(), keep)
    end
    return { Refresh = function() refresh(true) end }
end

---------------------------------------------------------------------------
-- Changelog
---------------------------------------------------------------------------
local SECTION_ORDER = { "added", "improved", "fixed", "removed" }

local section = {
    height = 26,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.text = W.Text(row, "", "GameFontNormal", W.COLORS.gold)
        row.text:SetPoint("BOTTOMLEFT", 12, 4)
        return row
    end,
    fill = function(row, item)
        row.text:SetText(item.text)
    end,
}

-- "24 November 2026" style date of a "2026-11-24" key.
local function releaseDate(day)
    if not day then
        return nil
    end
    return ns.History.DateText(day)
end

function UI.ChangelogList()
    if ns.activeLocaleCode ~= "ruRU" and ns.CHANGELOG_EN and ns.CHANGELOG_EN[1] then
        return ns.CHANGELOG_EN
    end
    return ns.CHANGELOG or {}
end

UI.settingsPages.changelog = function(parent)
    measureWidth()
    local list = W.FlexList(parent, WIDTH, UI.SettingsPageHeight("changelog"), {
        toggle = toggle, section = section, paragraph = paragraph, spacer = spacer, heading = heading,
    })
    W.Stretch(list)
    list:SetPoint("TOPLEFT", 0, 0)
    -- v0.17.0: the history in the language of the game (Russian or English).
    local history = UI.ChangelogList()
    local open = {}
    if history[1] then
        open[history[1].version] = true -- the newest is open
    end
    local refresh

    local function build()
        local items = {} -- the page header names the page (v1.0.0-beta.4)
        for _, v in ipairs(history) do
            local subtitle = v.title
            local dateText = releaseDate(v.date)
            if dateText then
                subtitle = subtitle and (subtitle .. "  ·  " .. dateText) or dateText
            end
            items[#items + 1] = { kind = "toggle", title = "v" .. v.version, subtitle = subtitle,
                height = subtitle and 48 or 40, open = open[v.version],
                onClick = function() open[v.version] = not open[v.version]; refresh(true) end }
            if open[v.version] then
                for _, kind in ipairs(SECTION_ORDER) do
                    for _, s in ipairs(v.sections) do
                        if s.kind == kind and #s.items > 0 then
                            items[#items + 1] = { kind = "section", text = L["CHANGELOG_" .. string.upper(kind)] }
                            for _, text in ipairs(s.items) do
                                local line = "•  " .. text
                                items[#items + 1] = { kind = "paragraph", text = line, indent = 12,
                                    height = textHeight(line, INNER - 20) + 6 }
                            end
                        end
                    end
                end
            end
            items[#items + 1] = { kind = "spacer", height = 8 }
        end
        return items
    end
    refresh = function(keep)
        list:SetItems(build(), keep)
    end
    return { Refresh = function() refresh(true) end }
end
