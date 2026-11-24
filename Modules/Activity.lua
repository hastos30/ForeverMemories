-- Modules/Activity.lua
-- The one clock of active play (v0.8.0). Every second it measures how much
-- of the last tick was active play and hands that to its listeners:
--   * the Playtime Tracker (this file): "Playtime today" on Home;
--   * the passive capture timer (Modules/Passive.lua);
--   * the Home countdown (UI), which only redraws, never counts.
-- So there is one ticker and one definition of "active" for both.
--
-- Active play = in the world (no loading screen) and not AFK. Time outside
-- the game is never counted: the clock is GetTime() deltas inside a
-- session, and a gap longer than MAX_GAP (loading, hitch) adds nothing.
-- Playtime is saved per character and per calendar day (local midnight
-- starts a new day), so it survives /reload and logout.
--
-- "Total playtime" in History (v0.8.2) is the game's own /played number:
-- asked once a few seconds after login, quietly (no chat line), and then
-- advanced by the session clock, like /played itself (AFK included).
-- If the client does not answer, our own active playtime is shown.
local _, ns = ...

local Activity = {}
ns.Activity = Activity

Activity.TICK = 1     -- seconds between checks
Activity.MAX_GAP = 5  -- longer gaps between ticks are not counted
Activity.PLAYED_DELAY = 3    -- seconds after login before asking /played
Activity.PLAYED_UNMUTE = 10  -- chat frames get the event back by then at the latest

-- listener(activeSeconds, reason): reason is nil while playing,
-- "loading" or "afk" otherwise (activeSeconds is 0 then).
Activity.listeners = {}

local API = ns.API
local ticker
local lastTickAt
local inWorld = false
local played           -- { total = seconds from the game, at = GetTime() }
local playedEvent      -- TIME_PLAYED_MSG is known to this client
local muted            -- chat frames that wait for TIME_PLAYED_MSG back

local function data()
    return ns.character and ns.character.playtime
end

-- Why the current moment is not active play, or nil.
function Activity.BlockReason()
    if not inWorld then
        return "loading"
    end
    if API.IsAFK() then
        return "afk"
    end
    return nil
end

-- Adds seconds of play to the day of `t` and to the total.
function Activity.Add(seconds, t)
    local playtime = data()
    if not playtime or seconds <= 0 then
        return
    end
    local day = ns.Util.DayKey(t or API.Time())
    playtime.days[day] = (playtime.days[day] or 0) + seconds
    playtime.total = playtime.total + seconds
end

-- One check. `now` is GetTime().
function Activity.Tick(now)
    local dt = lastTickAt and (now - lastTickAt) or 0
    lastTickAt = now
    local reason = Activity.BlockReason()
    local active = 0
    if not reason and dt > 0 and dt <= Activity.MAX_GAP then
        active = dt
        Activity.Add(active)
    end
    for i = 1, #Activity.listeners do
        ns.SafeCall("activity listener", Activity.listeners[i], active, reason)
    end
end

local function tick()
    ns.SafeCall("activity", Activity.Tick, API.Now())
end

function Activity.Start()
    if ticker then
        return
    end
    lastTickAt = nil
    ticker = API.NewTicker(Activity.TICK, tick)
end

-- Whole seconds of play of the current character today / on a day.
function Activity.OnDay(day)
    local playtime = data()
    return playtime and math.floor(playtime.days[day] or 0) or 0
end

function Activity.Today()
    return Activity.OnDay(ns.Util.DayKey(API.Time()))
end

-- Whole seconds of play of the current character in total (since v0.8.0,
-- playtime was not recorded before).
function Activity.Total()
    local playtime = data()
    return playtime and math.floor(playtime.total) or 0
end

-- All time of the character in the game and where it comes from:
-- "game" (/played, since the character was created) or "addon" (our
-- active playtime since v0.8.0, when the game did not answer).
function Activity.Lifetime()
    if played then
        return math.floor(played.total + math.max(0, API.Now() - played.at)), "game"
    end
    return Activity.Total(), "addon"
end

local function unmute()
    if muted then
        API.RestoreChatEvent(muted, "TIME_PLAYED_MSG")
        muted = nil
    end
end

-- Asks the game for /played without a line in the chat.
function Activity.RequestPlayed()
    if not playedEvent or muted then
        return
    end
    local ok, frames = API.RequestTimePlayed(true)
    if not ok then
        ns.Logger.Warn("Total playtime: " .. tostring(frames) .. ", using the addon's own count")
        return
    end
    muted = frames
    API.After(Activity.PLAYED_UNMUTE, unmute)
end

-- The answer to our request or to /played typed by the player.
playedEvent = ns.On("TIME_PLAYED_MSG", function(_, total)
    if API.IsPlainNumber(total) and total >= 0 then
        played = { total = total, at = API.Now() }
    end
    if muted then
        -- The chat frames have skipped this answer; give them the event back.
        API.After(0.5, unmute)
    end
end)

-- A loading screen breaks the chain: its time is not counted.
ns.On("PLAYER_ENTERING_WORLD", function()
    inWorld = true
    lastTickAt = nil
end)
ns.On("PLAYER_LEAVING_WORLD", function()
    inWorld = false
    lastTickAt = nil
end)

table.insert(ns.onLogin, Activity.Start)
table.insert(ns.onLogin, function()
    API.After(Activity.PLAYED_DELAY, function() ns.SafeCall("played", Activity.RequestPlayed) end)
end)
