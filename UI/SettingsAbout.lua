-- UI/SettingsAbout.lua
-- Settings / About and Settings / Changelog (v0.10.0). Both are one
-- scrolling list (W.FlexList) of rows of different kinds.
--   About:     logo, name, slogan, version, description, project facts,
--              community links (only confirmed ones, copied from a text
--              box), and a collapsible technical block with "Copy
--              diagnostics".
--   Changelog: one collapsible card per version from CHANGELOG.md
--              (Modules/ChangelogData.lua); the newest is open.
local _, ns = ...

local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local WIDTH = UI.CONTENT_WIDTH
local INNER = WIDTH - 8
local PAGE_HEIGHT = 570 - UI.SETTINGS_PAGE_TOP
local LOGO = "Interface\\Icons\\INV_Misc_Spyglass_03"

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
        if item.icon then row.icon:SetTexture(item.icon) end
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

local button = {
    height = 40,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row.button = W.Button(row, "", INNER, 28, function()
            if row.onClick then row.onClick() end
        end)
        row.button:SetPoint("TOPLEFT", 0, -6)
        return row
    end,
    fill = function(row, item)
        row.button:SetLabel(item.text)
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
    height = 150,
    make = function(parent)
        local row = CreateFrame("Frame", nil, parent)
        local box = W.IconBox(row, LOGO, 56)
        box:SetPoint("TOP", 0, -4)
        local name = W.Text(row, "ForeverMemories", "GameFontNormalHuge", W.COLORS.heading)
        name:SetPoint("TOP", box, "BOTTOM", 0, -10)
        name:SetJustifyH("CENTER")
        local slogan = W.Text(row, L.SLOGAN, "GameFontHighlight", W.COLORS.muted)
        slogan:SetPoint("TOP", name, "BOTTOM", 0, -6)
        slogan:SetJustifyH("CENTER")
        row.version = W.Text(row, "", "GameFontHighlightSmall", W.COLORS.text)
        row.version:SetPoint("TOP", slogan, "BOTTOM", 0, -6)
        row.version:SetJustifyH("CENTER")
        return row
    end,
    fill = function(row)
        row.version:SetText(string.format(L.VERSION_LABEL, ns.version))
    end,
}

local function copyLink(label, url)
    UI.ShowCopyText(label, url, L.LINK_HINT)
end

UI.settingsPages.about = function(parent)
    local list = W.FlexList(parent, WIDTH, PAGE_HEIGHT, {
        logo = logoKind, paragraph = paragraph, heading = heading, info = info,
        toggle = toggle, button = button, spacer = spacer,
    })
    list:SetPoint("TOPLEFT", 0, 0)
    local techOpen = false
    local refresh

    local function build()
        local p = ns.ProjectInfo
        local items = { { kind = "logo" } }
        items[#items + 1] = { kind = "paragraph", text = L.ABOUT_DESCRIPTION, color = W.COLORS.text,
            height = textHeight(L.ABOUT_DESCRIPTION, INNER - 8) + 12 }
        items[#items + 1] = { kind = "spacer" }
        items[#items + 1] = { kind = "info", label = L.ABOUT_VERSION, value = ns.version }
        if p.author then items[#items + 1] = { kind = "info", label = L.ABOUT_AUTHOR, value = p.author } end
        if p.license then items[#items + 1] = { kind = "info", label = L.ABOUT_LICENSE, value = p.license } end
        items[#items + 1] = { kind = "info", label = L.ABOUT_GAME, value = p.game }
        items[#items + 1] = { kind = "info", label = L.ABOUT_LANGUAGES, value = p.languages }
        items[#items + 1] = { kind = "info", label = L.ABOUT_STORAGE, value = L.ABOUT_STORAGE_LOCAL }
        if p.thanks then items[#items + 1] = { kind = "info", label = L.ABOUT_THANKS, value = p.thanks } end

        items[#items + 1] = { kind = "spacer" }
        items[#items + 1] = { kind = "heading", text = L.COMMUNITY }
        local links = 0
        for _, link in ipairs(p.links) do
            if type(link.url) == "string" and link.url ~= "" then
                links = links + 1
                local label = L["LINK_" .. link.id]
                items[#items + 1] = { kind = "info", label = label, value = L.COPY_LINK,
                    icon = "Interface\\Icons\\INV_Misc_Note_01",
                    onClick = function() copyLink(label, link.url) end }
            end
        end
        if links == 0 then
            items[#items + 1] = { kind = "paragraph", text = L.NO_LINKS_YET, color = W.COLORS.muted,
                height = textHeight(L.NO_LINKS_YET, INNER - 8) + 10 }
        end

        items[#items + 1] = { kind = "spacer" }
        items[#items + 1] = { kind = "toggle", title = L.TECH_INFO, open = techOpen,
            onClick = function() techOpen = not techOpen; refresh(true) end }
        if techOpen then
            for _, row in ipairs(ns.DataTools.DiagnosticsRows()) do
                items[#items + 1] = { kind = "info", label = row[1], value = row[2] }
            end
            items[#items + 1] = { kind = "button", text = L.COPY_DIAGNOSTICS, onClick = function()
                UI.ShowCopyText(L.COPY_DIAGNOSTICS, ns.DataTools.DiagnosticsText(), L.DIAGNOSTICS_HINT)
            end }
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

UI.settingsPages.changelog = function(parent)
    local list = W.FlexList(parent, WIDTH, PAGE_HEIGHT, {
        toggle = toggle, section = section, paragraph = paragraph, spacer = spacer, heading = heading,
    })
    list:SetPoint("TOPLEFT", 0, 0)
    local open = {}
    if ns.CHANGELOG and ns.CHANGELOG[1] then
        open[ns.CHANGELOG[1].version] = true -- the newest is open
    end
    local refresh

    local function build()
        local items = { { kind = "heading", text = L.CHANGELOG_HEADING, height = 30 } }
        for _, v in ipairs(ns.CHANGELOG or {}) do
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
