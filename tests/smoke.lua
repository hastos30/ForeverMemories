-- tests/smoke.lua (v1.0.0-beta.8)
-- Offline smoke test with the fake client of tests/mock_wow.lua:
--   lua5.1 tests/smoke.lua        (from the addon root)
-- It loads the addon, logs in, opens every tab and every History /
-- Settings page in both languages, and checks that every texture path of
-- the addon's own art points to a file that exists. Passing proves that
-- the Lua runs without errors offline, NOT how it looks in Forever.
package.path = "./tests/?.lua;" .. package.path
local Mock = require("mock_wow")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. "\n     " .. tostring(err)) end
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

-- Client path "Interface\AddOns\ForeverMemories\Media\X\y.tga" -> "Media/X/y.tga".
local function localPath(texture)
    local rel = string.match(texture, "^Interface\\AddOns\\ForeverMemories\\(.+)$")
    return rel and (string.gsub(rel, "\\", "/"))
end

-- Every own-art path in a table (recursively) exists on disk.
local function checkPaths(t, where, seen)
    seen = seen or {}
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        if type(v) == "string" and localPath(v) then
            assert(exists(localPath(v)), where .. "." .. tostring(k) .. ": missing " .. v)
        elseif type(v) == "table" then
            checkPaths(v, where .. "." .. tostring(k), seen)
        end
    end
end

for _, locale in ipairs({ "enUS", "ruRU" }) do
    local env = Mock.new({ locale = locale })
    _G.GetLocale = function() return locale end
    local ns
    test(locale .. ": login", function() ns = env.login(".") assert(ns.UI and ns.Media) end)
    if ns then
        -- Errors caught by ns.SafeCall go to the log: collect them.
        local errors = {}
        local logError = ns.Logger.Error
        ns.Logger.Error = function(msg, ...) errors[#errors + 1] = tostring(msg); return logError(msg, ...) end
        test(locale .. ": own art exists", function()
            checkPaths(ns.Media, "Media")
            for id, trig in pairs(ns.Registry.TRIGGERS) do
                if localPath(trig.icon or "") then assert(exists(localPath(trig.icon)), id) end
            end
            assert(exists(localPath(ns.Registry.LEGACY_ICON)), "legacy icon")
            checkPaths(ns.Journey.ICONS, "Journey")
        end)
        for _, tab in ipairs(ns.UI.TABS) do
            test(locale .. ": open tab " .. tab, function() ns.UI.ShowTab(tab) ; ns.UI.Refresh() end)
        end
        for _, page in ipairs({ "overview", "shots", "steps", "zones", "playtime", "journey", "records", "achievements" }) do
            test(locale .. ": History / " .. page, function() ns.UI.ShowTab("history", page); ns.UI.Refresh() end)
        end
        for _, page in ipairs({ "general", "appearance", "notifications", "data", "about", "changelog" }) do
            test(locale .. ": Settings / " .. page, function() ns.UI.ShowTab("settings", page); ns.UI.Refresh() end)
        end
        test(locale .. ": narrow and wide window", function()
            ns.UI.Resize(440, 600); ns.UI.OnWidthChanged(440)
            ns.UI.Resize(1200, 900); ns.UI.OnWidthChanged(1200)
        end)
        test(locale .. ": notification editor opens under the card and saves", function()
            ns.UI.ShowTab("settings", "notifications")
            local N = ns.Notifications
            assert(N.StartEdit("discovery"))
            local editor = _G.ForeverMemoriesNotifyEditor
            assert(editor, "edit panel")
            editor:Open("Discovery")
            assert(editor.card == N.Card("discovery"), "panel follows the discovery card")
            N.EditScale(1.3)
            N.EndEdit(true)
            assert(ns.db.ui.notify.discovery.scale == 1.3, "own scale saved")
        end)
        test(locale .. ": edit panel presets move and scale the sample at once", function()
            local N = ns.Notifications
            assert(N.StartEdit("mini"))
            N.EditPreset("bottom")
            assert(N.EditPresetOf() == "bottom", "preset bottom")
            N.EditSize("large")
            local _, edit = N.Editing()
            assert(edit.scale == N.SIZES.large, "large scale")
            N.EndEdit(true)
            local own = ns.db.ui.notify.mini
            assert(own.point == "BOTTOM" and own.scale == N.SIZES.large, "saved as own place")
        end)
        test(locale .. ": preview toggles", function()
            local N = ns.Notifications
            N.Test("legendary")
            assert(N.IsPreviewing("legendary"), "shown")
            N.Test("legendary")
            assert(not N.IsPreviewing("legendary"), "hidden on the second press")
        end)
        test(locale .. ": mini card shows the inside of an event icon", function()
            ns.Notifications.Test("mini")
            local card = ns.Notifications.Card("mini")
            assert(card and card.icon, "mini card")
        end)
        test(locale .. ": no errors caught by SafeCall", function()
            assert(#errors == 0, table.concat(errors, "\n     "))
        end)
        test(locale .. ": changelog has this version first", function()
            assert(ns.CHANGELOG[1].version == ns.version, ns.CHANGELOG[1].version)
            assert(ns.CHANGELOG_EN[1].version == ns.version)
        end)
    end
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
