-- Locales/enUS.lua - English strings (also the fallback for every key).
local _, ns = ...

ns.locales.enUS = {
    -- Tabs
    TAB_home = "Home", TAB_events = "Events", TAB_capture = "Capture", TAB_journey = "Journey",
    TAB_journal = "Journal", TAB_profiles = "Profiles", TAB_settings = "Settings",
    TAB_diagnostics = "Diagnostics", TAB_about = "About",

    -- Triggers
    TRIGGER_LEVEL = "New level", TRIGGER_MAX_LEVEL = "Max level", TRIGGER_ZONE = "First zone visit",
    TRIGGER_BOSS = "Boss defeated", TRIGGER_LOOT_EPIC = "Epic loot", TRIGGER_LOOT_LEGENDARY = "Legendary loot",
    TRIGGER_MOUNT = "New mount", TRIGGER_RARE = "Rare defeated", TRIGGER_DUNGEON = "Dungeon completed",
    TRIGGER_REPUTATION = "Reputation up", TRIGGER_DUEL = "Duel won", TRIGGER_BG = "Battleground won",
    TRIGGER_DEATH = "Death", TRIGGER_PROFESSION = "Profession maxed", TRIGGER_QUEST = "Selected quest",
    TRIGGER_GUILD = "Joined a guild", TRIGGER_FORM = "New druid form", TRIGGER_JOURNEY = "Journey (interval)",
    TRIGGER_RANDOM = "Random shot", TRIGGER_MANUAL = "Manual shot",

    -- Statuses and modes
    STATUS_success = "saved", STATUS_partial = "partly saved", STATUS_unconfirmed = "not confirmed",
    STATUS_failed = "failed", STATUS_skipped = "skipped",
    MODE_normal = "Normal", MODE_clean = "Clean (no UI)", MODE_dual = "Dual",

    -- Presets
    PRESET_Minimalist = "Minimalist", PRESET_Explorer = "Explorer", PRESET_Adventurer = "Adventurer",
    PRESET_Cinematic = "Cinematic", PRESET_Archivist = "Archivist",

    -- Reasons
    REASON_disabled = "trigger is off", REASON_paused = "automatic capture is paused",
    REASON_not_first = "not the first time", REASON_cooldown = "too soon after the same event",
    REASON_unknown_trigger = "unknown trigger", REASON_limit_session = "session limit reached",
    REASON_limit_hour = "hourly limit reached", REASON_limit_journey = "journey limit reached",
    REASON_queue_full = "queue is full", REASON_expired = "waited too long",
    REASON_loading = "loading screen", REASON_timeout = "no confirmation from the game",
    REASON_not_loaded = "addon is not ready yet",
    REASON_NO_COMBAT_LOG = "Forever gives addons no combat log, so a rare kill cannot be detected reliably",
    REASON_NOT_VERIFIED = "no reliable game signal confirmed for Forever yet",
    REASON_EVENT_REJECTED = "the game client does not know this event",
    PROFILE_BAD_NAME = "Enter a name", PROFILE_EXISTS = "A profile with this name exists",
    PROFILE_MISSING = "Profile not found", PROFILE_READ_ONLY = "Built-in presets cannot be changed",

    -- Header, home
    AUTO_CAPTURE = "Auto capture", ON = "ON", OFF = "OFF", PROFILE = "Profile",
    STATS_LINE = "Total %d  |  Today %d  |  Zones %d",
    AUTO_ON_INFO = "Automatic capture is on.",
    AUTO_OFF_INFO = "Paused: only manual shots are taken.",
    CAPSULE_LINE = "Time Capsule: first memory today %s, last %s",
    CAPSULE_EMPTY = "Time Capsule: no memories today yet",
    RECENT_MEMORIES = "Recent memories", NO_MEMORIES = "No memories yet",
    TAKE_SHOT = "Take a shot", PAUSE = "Pause", RESUME = "Resume", MANUAL_PANEL = "Manual panel",
    TOGGLE_WINDOW = "Open / close window", OPEN_WINDOW = "Open ForeverMemories",

    -- Events tab
    ADVANCED_MODE = "Advanced mode", AVAILABLE = "Available", UNAVAILABLE = "unavailable",
    FIELD_DELAY = "Delay", FIELD_FRAMES = "Frames (cycles)", FIELD_INTERVAL = "Interval",
    FIELD_MODE = "Mode", FIELD_PRIORITY = "Priority (1 = highest)", FIELD_COOLDOWN = "Cooldown",
    FIELD_FIRST_ONLY = "Only the first time", QUEST_IDS = "Quest IDs (comma separated, Enter to save)",
    SIMPLE_HINT = "Turn events on or off. Enable advanced mode to change delay, frames, mode and more for the selected event.",

    -- Capture tab
    MANUAL_SHOT = "Manual shot", MANUAL_TIMER = "Timer", TIMER_OFF = "off", SAFETY = "Safety",
    CLEAN_ALLOWED = "Allow clean mode (hide the UI for a moment)",
    CLEAN_NOTE = "In combat the UI is never hidden: clean shots become normal. If the UI does not come back, type /fm ui.",
    LIMITS = "Limits", LIMIT_PER_HOUR = "Automatic shots per hour", LIMIT_PER_SESSION = "Automatic shots per session",
    LIMIT_JOURNEY = "Journey shots per hour", TEST_SHOT = "Test shot", CANCEL_TIMER = "Cancel timer",

    -- Journey tab
    ENABLED = "Enabled", JOURNEY_INTERVAL = "Interval", JOURNEY_MOVE = "Minimum movement (map share)",
    RANDOM_MIN = "Random: from", RANDOM_MAX = "Random: to",
    JOURNEY_NOTE = "No shots while loading, AFK, in combat or with the map or menu open. Where the map position is not available (instances), a zone change is used instead, otherwise time only. Random shots do not try to find beautiful scenes.",

    -- Journal tab
    ALL_CHARACTERS = "All characters", THIS_CHARACTER = "This character", ALL_EVENTS = "All events",
    ALL_STATUSES = "All statuses", ALL_TIME = "All time", TODAY = "Today", LAST_7_DAYS = "7 days",
    LAST_30_DAYS = "30 days", FAVORITES = "Favorites", PAGE_OF = "Page %d / %d  (%d)",
    SELECT_ENTRY = "Select a record to see details.", SAVE_NOTE = "Save note", FAVORITE = "Favorite",
    UNFAVORITE = "Unfavorite", DELETE = "Delete",
    CONFIRM_DELETE_ENTRY = "Delete this journal record? The screenshot file stays on disk.",
    DETAILS_MODES = "Mode: %s, used: %s, frames ok: %d, not ok: %d", SKIP_REASON = "Reason",

    -- Profiles tab
    NEW_NAME = "Name for copy / rename", USE_FOR_ALL = "Use for all characters",
    USE_FOR_CHARACTER = "Use for this character", COPY = "Copy", RENAME = "Rename", RESET = "Reset",
    CHARACTER = "character", CONFIRM_DELETE_PROFILE = "Delete profile \"%s\"?",
    CONFIRM_RESET_PROFILE = "Reset all changes of profile \"%s\"?",
    PRESETS_READ_ONLY = "Built-in presets cannot be changed. Changing a setting creates the \"Custom\" profile.",

    -- Settings tab
    LANGUAGE = "Language", LANG_AUTO = "Game language", LANGUAGE_RELOAD = "Language changes apply after /reload.",
    CONFIRM_RELOAD_LANGUAGE = "The language is saved. Reload the interface now to apply it?",
    RELOAD_NOW = "Reload", LATER = "Later", RELOAD_MANUALLY = "Could not reload the interface. Type /reload.",
    SHOW_MINIMAP = "Minimap button", NOTIFICATIONS = "Notifications", SOUND = "Sound",
    NOTIFY_DURATION = "Notification time", WINDOW_SCALE = "Window scale", RESET_POSITION = "Reset window position",

    -- Diagnostics, about
    CLIENT = "Client", DIAG_ENGINE = "State %s, queue %d, Screenshot() calls %d, not ours %d, journey timer %s",
    DIAG_FUNCTIONS = "Client functions", ALL_PRESENT = "all present", DIAG_UNAVAILABLE = "Unavailable triggers",
    RECENT_LOG = "Recent log", RESTORE_UI = "Show UI again", VERSION = "Version",
    ABOUT_TARGET = "For World of Warcraft: Forever only.", AUTHOR = "Author", LICENSE = "License",
    LICENSE_PENDING = "MIT (pending author's consent)",
    ABOUT_FILES = "Screenshots are saved by the game in the Screenshots folder. The addon cannot show, rename or delete files: the journal only keeps records.",

    -- Messages
    MEMORY_SAVED = "Memory saved", MEMORY_UNCONFIRMED = "Screenshot requested (not confirmed)",
    MANUAL_NOT_TAKEN = "Shot not taken", NOT_LOADED = "Not loaded yet",
    UI_RESTORED = "Interface shown.", UI_RESTORE_COMBAT = "In combat: the interface will be shown after combat.",
    ANNIVERSARY_TITLE = "On this day in earlier years:",
    TOOLTIP_TODAY = "Saved today: %d", TOOLTIP_HINT = "Left: window  Right: pause  Middle: shot",
    FIRST_RUN_TITLE = "Welcome to ForeverMemories",
    FIRST_RUN_TEXT = "Choose how many moments to capture. You can change it any time in Profiles.",
    LATER = "Later",

    ---------------------------------------------------------------------------
    -- Mouse-over tooltips (TIP_*). The title is the option's name, so these
    -- texts only explain what the option does and when it applies.
    ---------------------------------------------------------------------------
    TIP_AUTO_CAPTURE = "Main switch for automatic shots (events, journey, random shots).\nOFF = pause: waiting automatic shots are cancelled and no new ones are made. Manual shots always work.",
    TIP_TAB_home = "Statistics, recent memories and quick buttons.",
    TIP_TAB_events = "Which game events take a shot. In advanced mode, fine-tune each event.",
    TIP_TAB_capture = "Manual shot options, clean mode permission and automatic capture limits.",
    TIP_TAB_journey = "Time-based shots: every N minutes on the road and at random moments.",
    TIP_TAB_journal = "Every shot taken or skipped, with filters, notes and favorites.",
    TIP_TAB_profiles = "Sets of settings: choose, copy, rename, delete.",
    TIP_TAB_settings = "Language, minimap button, notifications, sound and window.",
    TIP_TAB_diagnostics = "Technical details for troubleshooting: client version, available functions and events, log.",
    TIP_TAB_about = "Addon version and where to find the screenshots.",

    -- Home
    TIP_PROFILE = "The active set of settings. If this character has its own profile, that one is changed, otherwise the shared profile for all characters.",
    TIP_TAKE_SHOT = "Take a manual shot. If a timer is set in Capture, a countdown runs in chat first.\nWorks while paused too.",
    TIP_PAUSE = "Pause / resume automatic capture - same as the Auto capture button at the top. Manual shots work while paused.",
    TIP_MANUAL_PANEL = "Open / close a small panel for manual shots: mode, timer and frame count without the main window.",

    -- Events
    TIP_ADVANCED_MODE = "Show an editor for the selected event on the right: delay, frames, mode, priority and more.\nOff: only switch events on and off.",
    TIP_TRIGGER_ROW = "Checkbox: switch the event on or off. Click the row: select the event for the editor (advanced mode).",
    TIP_TRIGGER_LEVEL = "A shot when your character gains a level (except the max level, which has its own event).",
    TIP_TRIGGER_MAX_LEVEL = "A shot when your character reaches the max level. Replaces New level at that moment.",
    TIP_TRIGGER_ZONE = "A shot the first time this character enters a zone. The zone you stood in when the addon was installed does not count.",
    TIP_TRIGGER_BOSS = "A shot after a won dungeon or raid boss fight. The same boss on the same difficulty is one event.",
    TIP_TRIGGER_LOOT_EPIC = "A shot when you receive an epic (purple) item. Detected from the loot message in chat.",
    TIP_TRIGGER_LOOT_LEGENDARY = "A shot when you receive a legendary (orange) item. Detected from the loot message in chat.",
    TIP_TRIGGER_MOUNT = "A shot when a new mount is added to your collection.",
    TIP_TRIGGER_RARE = "A shot after defeating a rare enemy.",
    TIP_TRIGGER_DUNGEON = "A shot when the game gives the reward for completing a dungeon through the group finder.",
    TIP_TRIGGER_REPUTATION = "A shot when your standing with a faction goes up.",
    TIP_TRIGGER_DUEL = "A shot when you win a duel. Losses are not captured.",
    TIP_TRIGGER_BG = "A shot after a battleground win.",
    TIP_TRIGGER_DEATH = "A shot when your character dies.",
    TIP_TRIGGER_PROFESSION = "A shot when a profession reaches its maximum.",
    TIP_TRIGGER_QUEST = "A shot when you turn in a quest from your list. The ID list is set in this event's editor (advanced mode), per character.",
    TIP_TRIGGER_GUILD = "A shot when your character joins a guild. Logging in while already in a guild does not count.",
    TIP_TRIGGER_FORM = "Druids only: a shot when your character learns a new form.",
    TIP_TRIGGER_JOURNEY = "A shot every N minutes if you have moved. Interval and distance are in the Journey tab.",
    TIP_TRIGGER_RANDOM = "A shot at a random moment. Limits are in the Journey tab.",
    TIP_TRIGGER_MANUAL = "A shot on your command: button, minimap, key binding or /fm shot. Ignores pause and limits.",
    TIP_FIELD_DELAY = "Seconds to wait after the event before the first frame, e.g. to let an animation finish.",
    TIP_FIELD_FRAMES = "How many times to shoot in a row (series cycles). In dual mode each cycle is 2 screenshots: with and without the interface.",
    TIP_FIELD_INTERVAL = "Seconds between the cycles of a series. Matters only when there is more than one frame.",
    TIP_FIELD_MODE = "Normal - screenshot as is, with the interface.\nClean - the interface hides for a moment, the shot has none.\nDual - two screenshots in a row: with and without the interface.\nIn combat, or when clean mode is not allowed (Capture tab), the interface is not hidden: a clean shot becomes normal, and dual keeps only the normal one.",
    TIP_FIELD_PRIORITY = "How important the shot is, 1 = most important. When several shots wait at once, the more important goes first. When the queue is full, the least important is dropped first.",
    TIP_FIELD_COOLDOWN = "A repeat of the same event (same level, same boss, etc.) within this time is not captured. Automatic events use at least 10 s even if this is lower.",
    TIP_FIELD_FIRST_ONLY = "Shoot only if the same event (same boss, mount, quest, etc.) has never been saved in the journal before.",
    TIP_QUEST_IDS = "Quest numbers (IDs), separated by commas. Turning in one of them takes a shot. Press Enter to save. Each character has its own list.",

    -- Capture
    TIP_MANUAL_TIMER = "Countdown before a manual shot (Take shot button, minimap, key binding). Time to move the cursor away or strike a pose. \"off\" = shoot at once.",
    TIP_CLEAN_ALLOWED = "Allows the addon to hide the interface for a moment for clean shots.\nOff: clean shots are taken as normal, and dual mode keeps only the shot with the interface.",
    TIP_LIMIT_PER_HOUR = "How many automatic screenshots may be taken in the last 60 minutes. Every screenshot of a series counts. Manual shots do not.",
    TIP_LIMIT_PER_SESSION = "How many automatic screenshots may be taken since login or /reload. Manual shots do not count.",
    TIP_LIMIT_JOURNEY = "How many journey and random shots may be taken in the last 60 minutes.",
    TIP_TEST_SHOT = "Take one manual shot right away, without the timer, to check that screenshots are saved.",

    -- Journey
    TIP_JOURNEY_ENABLED = "Take a shot every N minutes while you travel. Never during loading, combat, AFK, or with the map or a menu open.",
    TIP_RANDOM_ENABLED = "Take a shot at a random moment between \"from\" and \"to\" minutes. Same conditions as the journey.",
    TIP_JOURNEY_INTERVAL = "Minimum time between journey shots.",
    TIP_JOURNEY_MOVE = "How far you must move from the last journey shot, as a share of the zone map. 0.05 = about 1/20 of the map width. 0 = any movement.\nWhere the position is unknown (dungeons), a zone change is needed.",
    TIP_RANDOM_MIN = "The shortest time until the next random shot.",
    TIP_RANDOM_MAX = "The longest time until the next random shot. Never less than \"from\".",

    -- Journal
    TIP_FILTER_CHAR = "Show records of all characters or only the current one.",
    TIP_FILTER_EVENT = "Show records of one event only.",
    TIP_FILTER_STATUS = "saved - every screenshot was taken.\npartly saved - part of the series failed.\nnot confirmed - requested, but the game did not answer.\nfailed - the screenshot was not taken.\nskipped - no shot was made (pause, limit, repeat, etc.).",
    TIP_FILTER_PERIOD = "Show records for a period, or favorites only.",
    TIP_FILTER_RESET = "Filters are not saved: they reset after /reload.",
    TIP_JOURNAL_ROW = "Click: show details below.\nOK saved, ~ partly, ? not confirmed, X failed, - skipped. Star = favorite.",
    TIP_PREV_PAGE = "Previous journal page.",
    TIP_NEXT_PAGE = "Next journal page.",
    TIP_NOTE = "Your note for the selected record. Enter or Save note saves it.",
    TIP_SAVE_NOTE = "Save the note text to the selected record.",
    TIP_FAVORITE = "Mark the record as a favorite. When the journal is full, old records are removed automatically but favorites are kept (up to 500). The Favorites filter shows only them.",
    TIP_DELETE_ENTRY = "Delete the selected record from the journal (asks first). The screenshot file stays on disk.",

    -- Profiles
    TIP_PROFILE_ROW = "Click: select the profile for the buttons on the right.\n* = active for all characters, (character) = active for this character only.",
    TIP_PRESET_Minimalist = "Only new levels and the max level, one frame each. Other events are off.",
    TIP_PRESET_Explorer = "Like Adventurer, plus 2 frames for new zones and a journey shot every 15 minutes.",
    TIP_PRESET_Adventurer = "Standard: levels, new zones, bosses, epic and legendary loot, new mounts.",
    TIP_PRESET_Cinematic = "Like Adventurer, but levels and new zones use dual shots (with and without the interface), bosses get 3 frames.",
    TIP_PRESET_Archivist = "Every event Forever supports (except journey and random shots).",
    TIP_NEW_NAME = "Type a name for Copy or Rename.",
    TIP_USE_FOR_ALL = "Make the selected profile the shared one for all characters. This character's own choice is cleared.",
    TIP_USE_FOR_CHARACTER = "Use the selected profile for this character only. Other characters do not change.",
    TIP_COPY = "Create a new profile - a copy of the selected one - with the name from the field above.",
    TIP_RENAME = "Rename the selected profile to the name from the field above. Built-in presets cannot be renamed.",
    TIP_DELETE_PROFILE = "Delete the selected profile (asks first). Characters that used it go back to the shared profile. Built-in presets cannot be deleted.",
    TIP_RESET_PROFILE = "Undo every change of the selected profile: back to the preset it was made from. Built-in presets are never changed, so they need no reset.",

    -- Settings
    TIP_LANGUAGE = "Addon language. \"Game language\" = same as the client. Saved at once, applied after an interface reload (/reload).",
    TIP_SHOW_MINIMAP = "Show the addon button at the minimap.",
    TIP_NOTIFICATIONS = "A short on-screen message after a shot: \"Memory saved\" or \"not confirmed\". If a manual shot is not taken, the reason always goes to chat.",
    TIP_SOUND = "A sound after a successfully saved shot. Works even with notifications off.",
    TIP_NOTIFY_DURATION = "How many seconds the notification stays on screen.",
    TIP_WINDOW_SCALE = "Size of the addon window. The rest of the game interface is not affected.",
    TIP_RESET_POSITION = "Move the addon window back to the screen center if it got lost.",

    -- Diagnostics, manual panel, first run, minimap
    TIP_RESTORE_UI = "Show the game interface if it did not come back after a clean shot. Same as /fm ui. In combat it comes back after combat.",
    TIP_PANEL_TEMP = "This value applies to this panel only, until /reload. Saved settings are in the Capture tab.",
    TIP_CANCEL_TIMER = "Stop the running countdown: no shot will be taken.",
    TIP_FIRST_RUN_LATER = "Close without choosing. The Adventurer profile stays; change it any time in Profiles.",
    TIP_OPEN_WINDOW = "Close the game options and open the addon window, where all ForeverMemories settings are. Same as /fm.",
    TIP_MINIMAP_DRAG = "Drag to move the button. Hide it in Settings.",
}
