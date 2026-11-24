-- tests/mock_wow.lua
-- A fake WoW client, just enough for the addon to load and run offline.
-- It is NOT the real Forever API: passing these tests proves our logic,
-- not client compatibility. Screenshot results are asynchronous (~0.08 s)
-- by default, as measured in Forever 1.60.1 (71037).
local Mock = {}

local function newFrame(env, kind, name)
    local frame = { kind = kind, shown = true, scripts = {}, events = {}, checked = false,
                    text = "", width = 100, height = 20 }
    local methods = {}
    function methods:Show() self.shown = true end
    function methods:Hide() self.shown = false end
    function methods:SetShown(value) self.shown = value and true or false end
    function methods:IsShown() return self.shown end
    function methods:IsVisible() return self.shown end
    function methods:RegisterEvent(event)
        if env.unknownEvents[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
        self.events[event] = true
    end
    function methods:SetScript(script, fn) self.scripts[script] = fn end
    function methods:GetScript(script) return self.scripts[script] end
    function methods:HookScript(script, fn)
        local before = self.scripts[script]
        self.scripts[script] = function(...)
            if before then before(...) end
            fn(...)
        end
    end
    function methods:SetValue(v) self.value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
    function methods:GetValue() return self.value end
    function methods:IsOwned(owner) return self.owner == owner end
    function methods:SetOwner(owner) self.owner = owner end
    function methods:SetChecked(value) self.checked = value and true or false end
    function methods:GetChecked() return self.checked end
    function methods:SetText(value) self.text = value end
    function methods:GetText() return self.text end
    function methods:HasFocus() return false end
    function methods:GetVerticalScroll() return 0 end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    function methods:SetSize(w, h) self.width, self.height = w, h end
    function methods:SetWidth(w) self.width = w end
    function methods:SetHeight(h) self.height = h end
    function methods:GetRect() return 100, 100, self.width, self.height end
    function methods:GetCenter() return 500, 400 end
    function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function methods:GetEffectiveScale() return 1 end
    function methods:CreateFontString() return newFrame(env, "FontString") end
    function methods:CreateTexture() return newFrame(env, "Texture") end
    function methods:Click(button)
        if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
    end
    -- StartMoving is used as a script value
    methods.StartMoving = function() end
    methods.StopMovingOrSizing = function() end
    setmetatable(frame, { __index = function(_, key)
        -- Like the client: methods start with a capital letter; any other
        -- missing field is nil.
        if methods[key] then return methods[key] end
        if type(key) == "string" and string.match(key, "^%u") then return function() end end
        return nil
    end })
    if name then _G[name] = frame end
    env.frames[#env.frames + 1] = frame
    return frame
end

function Mock.new(options)
    options = options or {}
    local env = {
        clock = 0, unix = 1795000000, timers = {}, frames = {}, chat = {},
        screenshotMode = options.screenshotMode or "async",
        combat = false, afk = false, level = 10, maxLevel = 60, inGuild = false, forms = 2,
        class = "DRUID", zone = "Elwynn Forest", mapID = 37, position = { 0.5, 0.5 },
        -- Movement: world position in yards (UnitPosition), own speed in yards/s.
        world = { x = 0, y = 0, instance = 0 }, speed = 0, unitPosition = true,
        swimming = false, flying = false, taxi = false, vehicle = false,
        instanceType = "none", guid = "Player-1-0000ABCD", guildName = "Heroes",
        unknownEvents = options.unknownEvents or {}, screenshotCalls = 0,
    }

    _G.GetTime = function() return env.clock end
    _G.time = function(t) if t then return os.time(t) end return env.unix + math.floor(env.clock) end
    _G.date = os.date
    _G.GetBuildInfo = function() return "1.60.1", "71037", "Nov 18 2026", 16001 end
    _G.InCombatLockdown = function() return env.combat end
    _G.UnitIsAFK = function() return env.afk end
    _G.UnitName = function() return "Nedisan" end
    _G.UnitClass = function() return "Druid", env.class end
    _G.UnitLevel = function() return env.level end
    _G.GetMaxPlayerLevel = function() return env.maxLevel end
    _G.GetRealmName = function() return "Forever" end
    _G.GetRealZoneText = function() return env.zone end
    _G.GetLocale = function() return options.locale or "enUS" end
    _G.IsInInstance = function() return env.instanceType ~= "none", env.instanceType end
    _G.UnitGUID = function() return env.guid end
    _G.GetUnitSpeed = function() return env.speed, 7, 7, 4.7 end
    _G.UnitPosition = function()
        if not env.unitPosition then return nil end
        return env.world.y, env.world.x, 0, env.world.instance
    end
    _G.IsSwimming = function() return env.swimming end
    _G.IsFlying = function() return env.flying end
    _G.UnitOnTaxi = function() return env.taxi end
    _G.UnitInVehicle = function() return env.vehicle end
    _G.CLASS_ICON_TCOORDS = { DRUID = { 0.75, 1, 0, 0.25 } }
    _G.GetInstanceInfo = function() return "Deadmines" end
    _G.IsInGuild = function() return env.inGuild end
    _G.GetGuildInfo = function() return env.inGuild and env.guildName or nil end
    _G.GetNumShapeshiftForms = function() return env.forms end
    _G.GetCursorPosition = function() return 600, 400 end
    _G.Enum = { UIMapType = { Zone = 3 } }
    _G.C_Map = {
        GetBestMapForUnit = function() return env.mapID end,
        GetMapInfo = function(id) return { mapType = 3, parentMapID = 0 } end,
        GetPlayerMapPosition = function()
            return { GetXY = function() return env.position[1], env.position[2] end }
        end,
    }
    _G.C_Item = { GetItemQualityByID = function() return nil end }
    _G.issecretvalue = function() return false end
    _G.LOOT_ITEM_SELF = "You receive loot: %s."
    _G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    _G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
    _G.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
    _G.DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
    _G.DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
    _G.YES, _G.NO = "Yes", "No"
    _G.UISpecialFrames = {}
    _G.StaticPopupDialogs = {}
    env.popups = {}
    _G.StaticPopup_Show = function(name)
        local dialog = StaticPopupDialogs[name]
        env.popups[#env.popups + 1] = dialog and dialog.text
        if dialog and dialog.OnAccept and env.autoConfirm then dialog.OnAccept() end
    end
    env.reloads = 0
    _G.ReloadUI = function() env.reloads = env.reloads + 1 end
    _G.Settings = {
        RegisterCanvasLayoutCategory = function() return {} end,
        RegisterAddOnCategory = function() end,
    }
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) env.chat[#env.chat + 1] = msg end }
    _G.SlashCmdList = {}
    _G.ForeverMemoriesDB = options.savedDB
    _G.C_Timer = {
        After = function(seconds, fn)
            env.timers[#env.timers + 1] = { at = env.clock + seconds, fn = fn }
        end,
        NewTicker = function(seconds, fn)
            local ticker = { cancelled = false }
            local function tick()
                if ticker.cancelled then return end
                fn()
                env.timers[#env.timers + 1] = { at = env.clock + seconds, fn = tick }
            end
            env.timers[#env.timers + 1] = { at = env.clock + seconds, fn = tick }
            function ticker:Cancel() self.cancelled = true end
            env.tickers = (env.tickers or 0) + 1
            return ticker
        end,
    }
    _G.C_EventUtils = { IsEventValid = function(event) return not env.unknownEvents[event] end }

    _G.CreateFrame = function(kind, name, parent, template)
        local frame = newFrame(env, kind, name)
        frame.parent, frame.template = parent, template
        return frame
    end
    _G.UIParent = newFrame(env, "Frame", "UIParent")
    UIParent.width, UIParent.height = 1920, 1080
    _G.Minimap = newFrame(env, "Frame", "Minimap")
    _G.GameTooltip = newFrame(env, "GameTooltip", "GameTooltip")
    -- Remembers the lines of the last tooltip: env.tooltip = { title, line, ... }
    env.tooltip = {}
    GameTooltip.SetText = function(_, text) env.tooltip = { text } end
    GameTooltip.AddLine = function(_, text) env.tooltip[#env.tooltip + 1] = text end

    function env.fire(event, ...)
        for _, frame in ipairs(env.frames) do
            if frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end

    -- Advances the fake clock, running timers in time order (also timers
    -- created while running).
    function env.advance(seconds)
        local target = env.clock + seconds
        while true do
            local index
            for i, timer in ipairs(env.timers) do
                if timer.at <= target and (not index or timer.at < env.timers[index].at) then
                    index = i
                end
            end
            if not index then break end
            local timer = table.remove(env.timers, index)
            env.clock = math.max(env.clock, timer.at)
            timer.fn()
        end
        env.clock = target
    end

    _G.Screenshot = function()
        env.screenshotCalls = env.screenshotCalls + 1
        env.uiShownAtShot = UIParent:IsShown()
        local mode = env.screenshotMode
        if mode == "error" then error("boom") end
        env.fire("SCREENSHOT_STARTED")
        if mode == "async" then
            C_Timer.After(0.08, function() env.fire("SCREENSHOT_SUCCEEDED") end)
        elseif mode == "failed" then
            C_Timer.After(0.08, function() env.fire("SCREENSHOT_FAILED") end)
        end
        -- "silent": no result at all
    end

    -- Loads the addon files in TOC order with the (addonName, ns) varargs.
    function env.loadAddon(root)
        local ns = {}
        local toc = assert(io.open(root .. "/ForeverMemories.toc")):read("*a")
        for line in toc:gmatch("[^\r\n]+") do
            if line:match("%.lua$") then
                local chunk = assert(loadfile(root .. "/" .. line:gsub("\\", "/")))
                chunk("ForeverMemories", ns)
            end
        end
        env.ns = ns
        return ns
    end

    -- Full login: ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD.
    function env.login(root)
        local ns = env.loadAddon(root or ".")
        env.fire("ADDON_LOADED", "ForeverMemories")
        env.fire("PLAYER_LOGIN")
        env.fire("PLAYER_ENTERING_WORLD")
        return ns
    end

    return env
end

return Mock
