-- tools/changelog.lua
-- Builds Modules/ChangelogData.lua (Settings / Changelog in the game) from
-- CHANGELOG.md (Russian) and CHANGELOG.en.md (English), so the window shows
-- the real history and nothing else.
-- Run from the addon root after editing either file:
--   lua5.1 tools/changelog.lua
-- tests/run.lua fails when the generated file is out of date.
--
-- Version header: "## [0.10.0] — 2026-11-25 — Title (note)"; the title is
-- optional. Sections Added / Changed / Improved / Fixed / Removed are
-- kept ("Changed" is shown as "Improved"); other sections (for example
-- "Для разработки" / "Development") are not shown. A version with nothing
-- to show is left out, so the page lists only changes of the add-on itself.
local M = {}

local SECTIONS = { added = "added", changed = "improved", improved = "improved", fixed = "fixed", removed = "removed" }

local function plain(text)
    text = text:gsub("%*%*(.-)%*%*", "%1")
    text = text:gsub("`([^`]*)`", "%1")
    text = text:gsub("%[([^%]]-)%]%([^%)]*%)", "%1")
    text = text:gsub("%s+", " ")
    text = text:gsub("|", "||") -- a single | starts an escape code in a FontString
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.Parse(markdown)
    local versions, version, section, item = {}, nil, nil, nil
    local function flush()
        if item and section then
            section.items[#section.items + 1] = plain(item)
        end
        item = nil
    end
    for line in (markdown .. "\n"):gmatch("([^\n]*)\n") do
        local ver, rest = line:match("^## %[([^%]]+)%]%s*—%s*(.*)$")
        local heading = line:match("^### (.+)$")
        if ver then
            flush()
            local day, tail = rest:match("^(%d%d%d%d%-%d%d%-%d%d)(.*)$")
            local title = tail and tail:match("^%s*—%s*(.-)%s*%(") or (tail and tail:match("^%s*—%s*(.-)%s*$"))
            version = { version = ver, date = day, title = title ~= "" and title or nil, sections = {} }
            versions[#versions + 1] = version
            section = nil
        elseif heading and version then
            flush()
            local kind = SECTIONS[heading:lower():match("^(%a+)")]
            section = nil
            if kind then
                for _, existing in ipairs(version.sections) do
                    if existing.kind == kind then section = existing end
                end
                if not section then
                    section = { kind = kind, items = {} }
                    version.sections[#version.sections + 1] = section
                end
            end
        elseif line:match("^##") then
            flush()
            section = nil
        elseif section then
            local bullet = line:match("^%s*%- (.*)$")
            local indent = line:match("^(%s*)%-")
            if bullet then
                flush()
                item = (#indent > 0 and "– " or "") .. bullet
            elseif item and line:match("^%s+%S") then
                item = item .. " " .. line
            else
                flush()
            end
        end
    end
    flush()
    local shown = {}
    for _, v in ipairs(versions) do
        if #v.sections > 0 then shown[#shown + 1] = v end
    end
    return shown
end

local function q(s)
    return string.format("%q", s):gsub("\\\n", "\\n")
end

local function renderTable(out, name, versions)
    out[#out + 1] = name .. " = {"
    for _, v in ipairs(versions) do
        out[#out + 1] = "    {"
        out[#out + 1] = "        version = " .. q(v.version) .. ","
        if v.date then out[#out + 1] = "        date = " .. q(v.date) .. "," end
        if v.title then out[#out + 1] = "        title = " .. q(v.title) .. "," end
        out[#out + 1] = "        sections = {"
        for _, s in ipairs(v.sections) do
            out[#out + 1] = "            { kind = " .. q(s.kind) .. ", items = {"
            for _, text in ipairs(s.items) do
                out[#out + 1] = "                " .. q(text) .. ","
            end
            out[#out + 1] = "            } },"
        end
        out[#out + 1] = "        },"
        out[#out + 1] = "    },"
    end
    out[#out + 1] = "}"
end

-- ru, en: parsed versions; en is optional.
function M.Render(ru, en)
    local out = {
        "-- Modules/ChangelogData.lua",
        "-- GENERATED from CHANGELOG.md and CHANGELOG.en.md by tools/changelog.lua. Do not edit by hand.",
        "local _, ns = ...",
        "",
    }
    renderTable(out, "ns.CHANGELOG", ru)
    if en then renderTable(out, "ns.CHANGELOG_EN", en) end
    return table.concat(out, "\n") .. "\n"
end

local function read(path)
    local file = io.open(path)
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

function M.Build(root)
    root = root or "."
    local ru = assert(read(root .. "/CHANGELOG.md"), "CHANGELOG.md not found")
    local en = read(root .. "/CHANGELOG.en.md")
    return M.Render(M.Parse(ru), en and M.Parse(en))
end

if not ... or ... ~= "changelog" then
    -- Run as a script.
    local text = M.Build(".")
    local file = assert(io.open("Modules/ChangelogData.lua", "w"))
    file:write(text)
    file:close()
    print("Modules/ChangelogData.lua written")
end

return M
