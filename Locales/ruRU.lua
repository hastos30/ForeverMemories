-- Locales/ruRU.lua - русские строки. Отсутствующий ключ берётся из enUS.
local _, ns = ...

ns.locales.ruRU = {
    -- Вкладки
    TAB_home = "Главная", TAB_events = "События", TAB_capture = "Съёмка", TAB_journey = "Путешествие",
    TAB_journal = "Журнал", TAB_profiles = "Профили", TAB_settings = "Настройки",
    TAB_diagnostics = "Диагностика", TAB_about = "Об аддоне",

    -- Триггеры
    TRIGGER_LEVEL = "Новый уровень", TRIGGER_MAX_LEVEL = "Максимальный уровень", TRIGGER_ZONE = "Новая зона",
    TRIGGER_BOSS = "Победа над боссом", TRIGGER_LOOT_EPIC = "Эпическая добыча",
    TRIGGER_LOOT_LEGENDARY = "Легендарная добыча", TRIGGER_MOUNT = "Новый маунт",
    TRIGGER_RARE = "Редкий противник", TRIGGER_DUNGEON = "Подземелье пройдено",
    TRIGGER_REPUTATION = "Повышение репутации", TRIGGER_DUEL = "Победа в дуэли", TRIGGER_BG = "Победа на поле боя",
    TRIGGER_DEATH = "Смерть", TRIGGER_PROFESSION = "Максимум профессии", TRIGGER_QUEST = "Выбранное задание",
    TRIGGER_GUILD = "Вступление в гильдию", TRIGGER_FORM = "Новая форма друида",
    TRIGGER_JOURNEY = "Путешествие (интервал)", TRIGGER_RANDOM = "Случайный кадр", TRIGGER_MANUAL = "Ручной кадр",

    -- Статусы и режимы
    STATUS_success = "сохранено", STATUS_partial = "сохранено частично", STATUS_unconfirmed = "не подтверждено",
    STATUS_failed = "ошибка", STATUS_skipped = "пропущено",
    MODE_normal = "Обычный", MODE_clean = "Чистый (без UI)", MODE_dual = "Двойной",

    -- Пресеты
    PRESET_Minimalist = "Минималист", PRESET_Explorer = "Исследователь", PRESET_Adventurer = "Искатель приключений",
    PRESET_Cinematic = "Кинематограф", PRESET_Archivist = "Архивариус",

    -- Причины
    REASON_disabled = "событие выключено", REASON_paused = "автосъёмка на паузе",
    REASON_not_first = "уже не в первый раз", REASON_cooldown = "слишком часто",
    REASON_unknown_trigger = "неизвестное событие", REASON_limit_session = "достигнут лимит за сессию",
    REASON_limit_hour = "достигнут лимит за час", REASON_limit_journey = "достигнут лимит путешествия",
    REASON_queue_full = "очередь заполнена", REASON_expired = "слишком долгое ожидание",
    REASON_loading = "экран загрузки", REASON_timeout = "игра не подтвердила снимок",
    REASON_not_loaded = "аддон ещё не готов",
    REASON_NO_COMBAT_LOG = "в Forever аддонам недоступен журнал боя, поэтому надёжно определить редкого противника нельзя",
    REASON_NOT_VERIFIED = "для Forever пока не подтверждён надёжный сигнал игры",
    REASON_EVENT_REJECTED = "клиент игры не знает это событие",
    PROFILE_BAD_NAME = "Введите имя", PROFILE_EXISTS = "Профиль с таким именем уже есть",
    PROFILE_MISSING = "Профиль не найден", PROFILE_READ_ONLY = "Встроенные пресеты нельзя изменить",

    -- Заголовок, главная
    AUTO_CAPTURE = "Автосъёмка", ON = "ВКЛ", OFF = "ВЫКЛ", PROFILE = "Профиль",
    STATS_LINE = "Всего %d  |  Сегодня %d  |  Зон %d",
    AUTO_ON_INFO = "Автосъёмка включена.",
    AUTO_OFF_INFO = "Пауза: делаются только ручные кадры.",
    CAPSULE_LINE = "Капсула времени: первый кадр сегодня %s, последний %s",
    CAPSULE_EMPTY = "Капсула времени: сегодня кадров ещё нет",
    RECENT_MEMORIES = "Последние воспоминания", NO_MEMORIES = "Воспоминаний пока нет",
    TAKE_SHOT = "Сделать кадр", PAUSE = "Пауза", RESUME = "Продолжить", MANUAL_PANEL = "Ручная панель",
    TOGGLE_WINDOW = "Открыть / закрыть окно", OPEN_WINDOW = "Открыть ForeverMemories",

    -- События
    ADVANCED_MODE = "Расширенный режим", AVAILABLE = "Доступно", UNAVAILABLE = "недоступно",
    FIELD_DELAY = "Задержка", FIELD_FRAMES = "Кадры (циклы)", FIELD_INTERVAL = "Интервал",
    FIELD_MODE = "Режим", FIELD_PRIORITY = "Приоритет (1 = высший)", FIELD_COOLDOWN = "Перезарядка",
    FIELD_FIRST_ONLY = "Только в первый раз", QUEST_IDS = "ID заданий (через запятую, Enter - сохранить)",
    SIMPLE_HINT = "Включайте и выключайте события. В расширенном режиме можно менять задержку, кадры, режим и другое для выбранного события.",

    -- Съёмка
    MANUAL_SHOT = "Ручной кадр", MANUAL_TIMER = "Таймер", TIMER_OFF = "нет", SAFETY = "Безопасность",
    CLEAN_ALLOWED = "Разрешить чистый режим (на миг скрыть интерфейс)",
    CLEAN_NOTE = "В бою интерфейс никогда не скрывается: чистые кадры становятся обычными. Если интерфейс не вернулся, введите /fm ui.",
    LIMITS = "Лимиты", LIMIT_PER_HOUR = "Автокадров в час", LIMIT_PER_SESSION = "Автокадров за сессию",
    LIMIT_JOURNEY = "Кадров путешествия в час", TEST_SHOT = "Тестовый кадр", CANCEL_TIMER = "Отменить таймер",

    -- Путешествие
    ENABLED = "Включено", JOURNEY_INTERVAL = "Интервал", JOURNEY_MOVE = "Мин. перемещение (доля карты)",
    RANDOM_MIN = "Случайно: от", RANDOM_MAX = "Случайно: до",
    JOURNEY_NOTE = "Не снимает при загрузке, AFK, в бою, с открытой картой или меню. Где позиция на карте недоступна (подземелья), учитывается смена зоны, иначе только время. Случайный кадр не ищет красивые сцены.",

    -- Журнал
    ALL_CHARACTERS = "Все персонажи", THIS_CHARACTER = "Этот персонаж", ALL_EVENTS = "Все события",
    ALL_STATUSES = "Все статусы", ALL_TIME = "Всё время", TODAY = "Сегодня", LAST_7_DAYS = "7 дней",
    LAST_30_DAYS = "30 дней", FAVORITES = "Избранное", PAGE_OF = "Стр. %d / %d  (%d)",
    SELECT_ENTRY = "Выберите запись, чтобы увидеть подробности.", SAVE_NOTE = "Сохранить заметку",
    FAVORITE = "В избранное", UNFAVORITE = "Из избранного", DELETE = "Удалить",
    CONFIRM_DELETE_ENTRY = "Удалить запись журнала? Файл скриншота останется на диске.",
    DETAILS_MODES = "Режим: %s, фактически: %s, кадров успешно: %d, неуспешно: %d", SKIP_REASON = "Причина",

    -- Профили
    NEW_NAME = "Имя для копии / переименования", USE_FOR_ALL = "Для всех персонажей",
    USE_FOR_CHARACTER = "Для этого персонажа", COPY = "Копировать", RENAME = "Переименовать", RESET = "Сбросить",
    CHARACTER = "персонаж", CONFIRM_DELETE_PROFILE = "Удалить профиль \"%s\"?",
    CONFIRM_RESET_PROFILE = "Сбросить все изменения профиля \"%s\"?",
    PRESETS_READ_ONLY = "Встроенные пресеты не изменяются. Изменение настройки создаёт профиль \"Custom\".",

    -- Настройки
    LANGUAGE = "Язык", LANG_AUTO = "Язык игры", LANGUAGE_RELOAD = "Язык сменится после /reload.",
    SHOW_MINIMAP = "Кнопка у миникарты", NOTIFICATIONS = "Уведомления", SOUND = "Звук",
    NOTIFY_DURATION = "Время уведомления", WINDOW_SCALE = "Масштаб окна", RESET_POSITION = "Сбросить позицию окна",

    -- Диагностика, об аддоне
    CLIENT = "Клиент", DIAG_ENGINE = "Состояние %s, очередь %d, вызовов Screenshot() %d, чужих %d, таймер путешествия %s",
    DIAG_FUNCTIONS = "Функции клиента", ALL_PRESENT = "все есть", DIAG_UNAVAILABLE = "Недоступные события",
    RECENT_LOG = "Последние записи лога", RESTORE_UI = "Вернуть интерфейс", VERSION = "Версия",
    ABOUT_TARGET = "Только для World of Warcraft: Forever.", AUTHOR = "Автор", LICENSE = "Лицензия",
    LICENSE_PENDING = "MIT (после согласия автора)",
    ABOUT_FILES = "Скриншоты сохраняет игра в папку Screenshots. Аддон не может показывать, переименовывать или удалять файлы: журнал хранит только записи.",

    -- Сообщения
    MEMORY_SAVED = "Воспоминание сохранено", MEMORY_UNCONFIRMED = "Снимок запрошен (не подтверждён)",
    MANUAL_NOT_TAKEN = "Кадр не сделан", NOT_LOADED = "Аддон ещё загружается",
    UI_RESTORED = "Интерфейс показан.", UI_RESTORE_COMBAT = "Идёт бой: интерфейс вернётся после боя.",
    ANNIVERSARY_TITLE = "В этот день в прошлые годы:",
    TOOLTIP_TODAY = "Сохранено сегодня: %d", TOOLTIP_HINT = "ЛКМ: окно  ПКМ: пауза  СКМ: кадр",
    FIRST_RUN_TITLE = "Добро пожаловать в ForeverMemories",
    FIRST_RUN_TEXT = "Выберите, сколько моментов снимать. Изменить можно в любой момент во вкладке «Профили».",
    LATER = "Позже",
}
