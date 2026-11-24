-- tests/mock_wow.lua
-- A tiny fake of the WoW client, just enough for the spike modules.
-- It is NOT the real Forever API: passing these tests proves our logic,
-- not client compatibility.
local Mock = {}

function Mock.new(options)
    options = options or {}
    local env = { clock = 0, unix = 1795000000, timers = {}, frames = {}, chat = {},
                  screenshotMode = options.screenshotMode or "sync_success",
                  combat = false }

    _G.GetTime = function() return env.clock end
    _G.time = function() return env.unix + math.floor(env.clock) end
    _G.date = os.date
    _G.GetBuildInfo = function() return "1.60.1", "70338", "Nov 20 2026", 16001 end
    _G.InCombatLockdown = function() return env.combat end
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) env.chat[#env.chat + 1] = msg end }
    _G.SlashCmdList = {}
    _G.ForeverMemoriesDB = options.savedDB
    _G.C_Timer = { After = function(seconds, fn)
        env.timers[#env.timers + 1] = { at = env.clock + seconds, fn = fn }
    end }
    _G.C_EventUtils = { IsEventValid = function(event)
        return not (options.unknownEvents or {})[event]
    end }

    _G.CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(_, fn) self.onEvent = fn end
        env.frames[#env.frames + 1] = frame
        return frame
    end

    function env.fire(event, ...)
        for _, frame in ipairs(env.frames) do
            if frame.events[event] and frame.onEvent then
                frame.onEvent(frame, event, ...)
            end
        end
    end

    function env.advance(seconds)
        env.clock = env.clock + seconds
        local due = {}
        for i = #env.timers, 1, -1 do
            if env.timers[i].at <= env.clock then
                due[#due + 1] = table.remove(env.timers, i)
            end
        end
        for i = #due, 1, -1 do due[i].fn() end
    end

    _G.Screenshot = function()
        local mode = env.screenshotMode
        if mode == "error" then error("boom") end
        env.fire("SCREENSHOT_STARTED")
        if mode == "sync_success" then env.fire("SCREENSHOT_SUCCEEDED") end
        if mode == "sync_failed" then env.fire("SCREENSHOT_FAILED") end
        -- "async" and "silent": no result now
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

    return env
end

return Mock
