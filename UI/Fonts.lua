-- UI/Fonts.lua
-- Obsidian Journal fonts (v0.15.0): Cormorant Garamond for headings,
-- Inter for text and numbers. Both are SIL Open Font License 1.1
-- (Media/Fonts/OFL-*.txt) and contain full Cyrillic.
--
-- Our font objects are created once. A font counts as loaded only if the
-- client reports the same file back (GetFont); otherwise that object takes
-- the client's own font, so text never disappears. The setting `fonts`
-- (Settings / Appearance, "/fm fonts") turns them off entirely.
local _, ns = ...

local Fonts = {}
ns.Fonts = Fonts

-- name = { file key, size, fallback template }
Fonts.OBJECTS = {
    ForeverMemoriesFontTitle = { "title", 22, "GameFontNormalLarge" },
    ForeverMemoriesFontHeading = { "title", 18, "GameFontNormalLarge" },
    ForeverMemoriesFontBody = { "body", 12, "GameFontHighlight" },
    ForeverMemoriesFontBold = { "bold", 12, "GameFontNormal" },
    ForeverMemoriesFontSmall = { "body", 11, "GameFontHighlightSmall" },
    ForeverMemoriesFontNumber = { "bold", 18, "GameFontHighlightLarge" },
}

-- Client templates the widgets use -> our object.
Fonts.MAP = {
    GameFontNormalLarge = "ForeverMemoriesFontHeading",
    GameFontHighlightLarge = "ForeverMemoriesFontNumber",
    GameFontHighlight = "ForeverMemoriesFontBody",
    GameFontNormal = "ForeverMemoriesFontBold",
    GameFontHighlightSmall = "ForeverMemoriesFontSmall",
    GameFontNormalSmall = "ForeverMemoriesFontSmall",
    GameFontDisableSmall = "ForeverMemoriesFontSmall",
}

Fonts.loaded = {}   -- [name] = true when the client confirmed the file
Fonts.ok = false    -- at least the body font loaded

local function sameFile(a, b)
    return type(a) == "string" and type(b) == "string"
        and string.lower(string.gsub(a, "/", "\\")) == string.lower(string.gsub(b, "/", "\\"))
end

function Fonts.Init()
    if type(CreateFont) ~= "function" then
        return false
    end
    for name, spec in pairs(Fonts.OBJECTS) do
        local path = ns.Media.FONTS[spec[1]]
        local object = _G[name] or CreateFont(name)
        local ok = pcall(object.SetFont, object, path, spec[2], "")
        local current = ok and object.GetFont and object:GetFont()
        if ok and sameFile(current, path) then
            Fonts.loaded[name] = true
        else
            local fallback = _G[spec[3]]
            if fallback and object.SetFontObject then
                pcall(object.SetFontObject, object, fallback)
            end
        end
    end
    Fonts.ok = Fonts.loaded.ForeverMemoriesFontBody == true
    return Fonts.ok
end

-- Template to use for a widget: ours when enabled and loaded.
function Fonts.Template(template)
    local ours = Fonts.MAP[template or ""]
    local enabled = not ns.db or ns.db.settings.fonts ~= false
    if ours and enabled and Fonts.loaded[ours] then
        return ours
    end
    return template
end

Fonts.Init()
