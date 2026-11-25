-- Modules/ArtPack.lua
-- Optional zone illustrations (v0.18.0) from the separate add-on
-- ForeverMemories_ArtPack. It registers the global table
-- ForeverMemories_ArtPack = { api, version, root, uv, zones = { [area] = file } }.
-- Nothing here calls an add-on API: the table is read when a picture is
-- needed, so the load order of the two add-ons does not matter. Without
-- the ArtPack, with a table of another format, or with the "artpack"
-- setting off, every caller gets nil and shows its usual compass.
local _, ns = ...

local ArtPack = {}
ns.ArtPack = ArtPack

ArtPack.API = 1
ArtPack.GLOBAL = "ForeverMemories_ArtPack"
-- Size of the picture inside each 512 x 256 texture (16:9).
ArtPack.WIDTH, ArtPack.HEIGHT = 448, 252

local function valid(pack)
    if type(pack) ~= "table" or pack.api ~= ArtPack.API or type(pack.root) ~= "string"
        or type(pack.zones) ~= "table" or type(pack.uv) ~= "table" then
        return false
    end
    for i = 1, 4 do
        local v = pack.uv[i]
        if type(v) ~= "number" or v < 0 or v > 1 then
            return false
        end
    end
    return pack.uv[1] < pack.uv[2] and pack.uv[3] < pack.uv[4]
end

-- "loaded" | "missing" | "incompatible", and the version of the pack.
function ArtPack.Status()
    local pack = _G[ArtPack.GLOBAL]
    if pack == nil then
        return "missing"
    end
    if not valid(pack) then
        return "incompatible"
    end
    return "loaded", type(pack.version) == "string" and pack.version or "?"
end

-- Number of zones with a picture (0 without a usable pack).
function ArtPack.Count()
    if ArtPack.Status() ~= "loaded" then
        return 0
    end
    local n = 0
    for _, file in pairs(_G[ArtPack.GLOBAL].zones) do
        if type(file) == "string" then n = n + 1 end
    end
    return n
end

-- Centered crop of the picture for a frame of `aspect` = width / height.
-- Returns left, right, top, bottom texture coordinates; never stretches.
function ArtPack.Crop(uv, aspect)
    local l, r, t, b = uv[1], uv[2], uv[3], uv[4]
    local full = ArtPack.WIDTH / ArtPack.HEIGHT
    if not aspect or aspect <= 0 then
        return l, r, t, b
    end
    if aspect > full then -- wider: full width, a band of the height
        local h = (b - t) * full / aspect
        local mid = (t + b) / 2
        return l, r, mid - h / 2, mid + h / 2
    end
    local w = (r - l) * aspect / full -- narrower: full height
    local mid = (l + r) / 2
    return mid - w / 2, mid + w / 2, t, b
end

-- Texture path and crop of a catalog area, or nil.
function ArtPack.Zone(area, aspect)
    if not area or not (ns.db and ns.db.settings.artpack) or ArtPack.Status() ~= "loaded" then
        return nil
    end
    local pack = _G[ArtPack.GLOBAL]
    local file = pack.zones[area]
    if type(file) ~= "string" or file == "" then
        return nil
    end
    return pack.root .. file, ArtPack.Crop(pack.uv, aspect)
end
