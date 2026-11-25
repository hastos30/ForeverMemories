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
-- beta.16: each answer (and the final value at logout) is also saved as
-- playtime.played = { total, at }, so History shows /played of another
-- character too (as of its last logout), not only the addon's count.
local _, ns = ...

local Activity = {}
ns.Activity = Activity

Activity.TICK = 1     -- seconds between checks
Activity.MAX_GAP = 5  -- longer gaps between ticks are not counted
Activity.PLAYED_DELAY = 3    -- seconds after login before asking /played
Activity.PLAYED_UNMUTE = 10  -- chat frames get the event back by then at the latest
-- A login within this many seconds after the last tick of the previous
-- one (a /reload, a short disconnect) continues the same session.
Activity.SESSION_GAP = 180

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
    if playtime.session then
        playtime.session.active = playtime.session.active + seconds
    end
end

---------------------------------------------------------------------------
-- Sessions (v0.9.0): one session = one stay in the game, a /reload does
-- not end it. Its length is active play (AFK and loading excluded), the
-- same seconds as Playtime. Sessions before 0.9.0 are unknown.
---------------------------------------------------------------------------
-- v0.12.0: a closed session is kept as playtime.lastSession for "Last
-- adventure" on Home. Its end is the logout time when the game reported
-- one (PLAYER_LOGOUT); after a crash only the last active moment is
-- known, and it is marked so (endKnown = false), never presented as exact.
local function counted(session, field)
    return type(session[field]) == "number" and math.floor(session[field]) or nil
end

local function closeSession(playtime)
    local session = playtime.session
    if session and session.active > 0 then
        playtime.sessions = playtime.sessions + 1
        if session.active > playtime.longest then
            playtime.longest = session.active
            playtime.longestAt = session.start
        end
        local zones = 0
        for _ in pairs(type(session.zones) == "table" and session.zones or {}) do
            zones = zones + 1
        end
        playtime.lastSession = {
            start = session.start, finish = session.ended or session.last, endKnown = session.ended ~= nil,
            active = math.floor(session.active),
            -- Counters exist only for sessions started with v0.12.0 or later.
            shots = counted(session, "shots"), steps = counted(session, "steps"),
            zones = session.zones and zones or nil, newZones = counted(session, "newZones"),
            levels = counted(session, "levels"),
        }
    end
    playtime.session = nil
end

function Activity.StartSession()
    local playtime = data()
    if not playtime then
        return
    end
    local now = API.Time()
    playtime.sinceDay = playtime.sinceDay or ns.Util.DayKey(now)
    local session = playtime.session
    if session and now - session.last <= Activity.SESSION_GAP and now >= session.last then
        session.ended = nil -- a /reload, not a logout
        return -- the same session goes on
    end
    closeSession(playtime)
    playtime.session = { start = now, last = now, active = 0,
        shots = 0, steps = 0, zones = {}, newZones = 0, levels = 0 }
end

-- The open session of the current character (counters of the recap).
function Activity.Session()
    local playtime = data()
    return playtime and playtime.session
end

-- The last completed session of the current character, or nil.
function Activity.LastSession()
    local playtime = data()
    return playtime and playtime.lastSession
end

-- Longest session and the day it started (nil when it is older than 0.12.0).
function Activity.Longest()
    local playtime = data()
    if not playtime then
        return 0, nil
    end
    local longest, at = playtime.longest, playtime.longestAt
    local session = playtime.session
    if session and session.active > longest then
        longest, at = session.active, session.start
    end
    return math.floor(longest), at
end

-- Number of sessions and the longest one (seconds), the current included.
function Activity.Sessions()
    local playtime = data()
    if not playtime then
        return 0, 0
    end
    local count, longest = playtime.sessions, playtime.longest
    local session = playtime.session
    if session and session.active > 0 then
        count = count + 1
        longest = math.max(longest, session.active)
    end
    return count, math.floor(longest)
end

-- Days with recorded active play, their total and the average per day.
function Activity.PlayedDays()
    local playtime = data()
    local days, total = 0, 0
    for _, seconds in pairs(playtime and playtime.days or {}) do
        if seconds > 0 then
            days = days + 1
            total = total + seconds
        end
    end
    return days, math.floor(total), days > 0 and math.floor(total / days) or 0
end

-- First day the tracker counted (nil before the first login with it).
function Activity.SinceDay()
    local playtime = data()
    return playtime and playtime.sinceDay
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
    local playtime = data()
    if playtime and playtime.session then
        playtime.session.last = API.Time()
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
    -- The live /played belongs to the logged-in character only (History
    -- may show another one read-only, v0.12.0); any character has the
    -- last saved one.
    if played and ns.character == ns.db.characters[ns.characterKey] then
        return math.floor(played.total + math.max(0, API.Now() - played.at)), "game"
    end
    local saved = data() and data().played
    if saved then
        return math.floor(saved.total), "game"
    end
    return Activity.Total(), "addon"
end

-- Keeps the current /played in the logged-in character's data.
local function savePlayed()
    local own = ns.db and ns.characterKey and ns.db.characters[ns.characterKey]
    if played and own and type(own.playtime) == "table" then
        own.playtime.played = {
            total = math.floor(played.total + math.max(0, API.Now() - played.at)),
            at = API.Time(),
        }
    end
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
        savePlayed()
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
-- Logout, quit or /reload: the moment is remembered as the possible end
-- of the session; a login within SESSION_GAP clears it again (/reload).
ns.On("PLAYER_LOGOUT", function()
    savePlayed()
    local playtime = data()
    if playtime and playtime.session then
        playtime.session.ended = API.Time()
    end
end)

table.insert(ns.onLogin, Activity.StartSession)
table.insert(ns.onLogin, Activity.Start)
table.insert(ns.onLogin, function()
    API.After(Activity.PLAYED_DELAY, function() ns.SafeCall("played", Activity.RequestPlayed) end)
end)
