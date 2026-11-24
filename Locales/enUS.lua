-- Locales/enUS.lua - English strings and the fallback for every key.
local _, ns = ...

ns.locales.enUS = {
    THOUSANDS_SEP = ",",

    -- Window
    SLOGAN = "Your adventure. Your story.",
    TAB_home = "Home", TAB_capture = "Auto capture", TAB_history = "History", TAB_settings = "Settings",
    STATE_ACTIVE = "Active", STATE_PAUSED = "Paused",
    AUTO_CAPTURE = "Auto capture",
    PAUSE = "Pause auto capture", RESUME = "Resume auto capture",
    TIP_PAUSE = "Stops automatic screenshots until you resume. The step counter keeps working.",
    TIP_RESUME = "Automatic screenshots start again.",
    CLOSE = "Close", TIP_CLOSE = "Closes the window. /fm or the minimap button opens it again.",

    -- Home
    CURRENT_CHARACTER_STATS = "Statistics of the current character",
    STAT_TOTAL = "Total screenshots", STAT_TODAY = "Screenshots today", STAT_ZONES = "Zones",
    STAT_STEPS_TODAY = "Steps today",
    TIP_STAT_TOTAL = "Screenshots this character has saved since the addon was installed.",
    TIP_STAT_TODAY = "Screenshots saved today (since midnight, your computer's time).",
    TIP_STAT_ZONES = "Different zones where this character took screenshots.",
    STEPS_NOTE = "The number of steps is an estimate based on the character's movement.",
    RECENT_SHOTS = "Recent screenshots",
    NO_SHOTS_YET = "This character has no screenshots yet",
    VIEW_ALL_SHOTS = "View all screenshots  >",

    -- Auto capture
    HOW_TO_SHOOT = "How to take screenshots", WHEN_TO_SHOOT = "When to take screenshots",
    MODE_normal = "Normal shot", MODE_clean = "Clean shot",
    MODE_normal_HINT = "With the interface", MODE_clean_HINT = "Without the interface",
    TIP_MODE_normal = "The screenshot shows the game interface as you see it. Only this addon's window and messages are hidden for a moment.",
    TIP_MODE_clean = "The game interface is hidden for a split second and shown again right after the shot. In combat the interface is never hidden: a normal shot is taken instead.",
    EVENTS_ON = "%d of %d",
    EVENT_UNAVAILABLE = "Not available in this client:",

    EVENT_LEVEL = "New level", EVENT_DEATH = "Death", EVENT_BOSS = "Boss defeated (dungeon or raid)",
    EVENT_DUEL = "Duel won", EVENT_LOOT_RARE = "Rare item", EVENT_LOOT_EPIC = "Epic item",
    EVENT_LOOT_LEGENDARY = "Legendary item", EVENT_ZONE = "New zone", EVENT_GUILD = "Joined a guild",
    EVENT_MANUAL = "Manual screenshot",
    -- Records from earlier versions
    EVENT_MOUNT = "New mount", EVENT_DUNGEON = "Dungeon completed", EVENT_QUEST = "Quest completed",
    EVENT_FORM = "New druid form", EVENT_JOURNEY = "Journey", EVENT_RANDOM = "Random shot",
    EVENT_UNKNOWN = "Screenshot",
    TITLE_LEVEL = "Reached level %d",

    TIP_EVENT_LEVEL = "Every level you gain, the maximum level too.",
    TIP_EVENT_DEATH = "When your character dies.",
    TIP_EVENT_BOSS = "A boss of a dungeon or raid is defeated (the game reports the encounter as won).",
    TIP_EVENT_DUEL = "You win a duel. Someone else's win does not count.",
    TIP_EVENT_LOOT_RARE = "You receive a blue (rare) item.",
    TIP_EVENT_LOOT_EPIC = "You receive a purple (epic) item.",
    TIP_EVENT_LOOT_LEGENDARY = "You receive an orange (legendary) item.",
    TIP_EVENT_ZONE = "The first visit of this character to a zone. Zones visited before are not captured again.",
    TIP_EVENT_GUILD = "Your character joins a guild. Logging in is not a join.",

    -- History
    SUB_SHOTS = "Screenshots", SUB_STEPS = "Steps",
    SCREENSHOTS_FOLDER_NOTE = "Screenshots are saved in the game's Screenshots folder.",
    TOTAL_STEPS = "Total steps", LAST_7_DAYS = "Last 7 days", STEPS_HISTORY = "Steps by day",
    NO_STEPS_YET = "No steps recorded yet",
    TODAY = "Today",
    DATE_FORMAT = "%d %s",
    MONTH_1 = "January", MONTH_2 = "February", MONTH_3 = "March", MONTH_4 = "April",
    MONTH_5 = "May", MONTH_6 = "June", MONTH_7 = "July", MONTH_8 = "August",
    MONTH_9 = "September", MONTH_10 = "October", MONTH_11 = "November", MONTH_12 = "December",
    SHOTS_one = "screenshot", SHOTS_many = "screenshots",
    STEPS_one = "step", STEPS_many = "steps",

    -- Settings
    GENERAL_SETTINGS = "General settings",
    SET_MINIMAP = "Minimap button", SET_NOTIFICATIONS = "Screenshot notifications", SET_SOUND = "Sound",
    TIP_SET_MINIMAP = "Shows the addon button at the minimap. /fm opens the window without it.",
    TIP_SET_NOTIFICATIONS = "A short message after a screenshot is saved. It never appears in the screenshot.",
    TIP_SET_SOUND = "A quiet sound after a screenshot is saved.",
    SET_LANGUAGE = "Interface language", LANGUAGE_AUTO = "Automatic",
    TIP_SET_LANGUAGE = "Automatic uses the language of the game client. A change applies after reloading the interface.",
    SET_SCALE = "Window scale",
    TIP_SET_SCALE = "Size of this window, from 75% to 130%.",
    RESET_POSITION = "Reset window position",
    TIP_RESET_POSITION = "Moves the window back to the center of the screen.",
    RELOAD_FOR_LANGUAGE = "The language changes after reloading the interface. Reload now?",
    RELOAD_NOW = "Reload", LATER = "Later",
    RELOAD_MANUALLY = "Type /reload to apply the language.",

    -- Minimap
    MINIMAP_HINT_LEFT = "Left click: open / close the window",
    MINIMAP_HINT_RIGHT = "Right click: pause / resume auto capture",
    MINIMAP_HINT_MIDDLE = "Middle click: take a screenshot",
    MINIMAP_HINT_DRAG = "Drag: move the button around the minimap",

    -- Notifications and chat
    SHOT_SAVED = "Screenshot saved",
    MANUAL_NOT_TAKEN = "Screenshot not taken",
    STATUS_skipped = "skipped", STATUS_failed = "error", STATUS_unconfirmed = "not confirmed by the game",
    REASON_loading = "loading screen", REASON_expired = "too late", REASON_queue_full = "too many at once",
    REASON_limit_hour = "hourly limit reached", REASON_limit_session = "session limit reached",
    REASON_timeout = "the game did not confirm the screenshot", REASON_error = "the game refused the screenshot",
    REASON_client = "the game could not save the screenshot", REASON_not_loaded = "the addon is not ready yet",
    UI_RESTORED = "Game interface is shown again.",
    UI_RESTORE_COMBAT = "In combat the interface cannot be changed. It is shown when combat ends.",
    NOT_LOADED = "The addon is still loading. Try again in a moment.",
    TAKE_SHOT = "Take a screenshot", TOGGLE_WINDOW = "Open / close the window", OPEN_WINDOW = "Open ForeverMemories",
}
