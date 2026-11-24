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
}
