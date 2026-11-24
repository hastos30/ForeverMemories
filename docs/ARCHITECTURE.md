# Архитектура (v0.5.0, дополнено в v0.6.0, v0.8.0, v0.9.0, v0.10.0)

## 1. Структура
```
ForeverMemories/
  ForeverMemories.toc   Bindings.xml (не в TOC)
  Core/     API, Logger, Util, Serialize, Database, Init, Registry, Events, Commands
  Capture/  Rules, Queue, UIState, Engine
  Modules/  History, Activity, Locations, ZoneCatalog, Steps, Passive, Notifications,
            Adventure, Journey, ProjectInfo, ChangelogData (генерируется), DataTools
  UI/       Widgets, Main (окно + Главная), Dialogs, Capture, History,
            Settings (+ General), SettingsData, SettingsAbout (About + Changelog), Minimap
  tools/    changelog.lua — CHANGELOG.md → Modules/ChangelogData.lua (в игру не копируется)
  Locales/  enUS, ruRU
  tests/    mock_wow.lua, run.lua (в игру не копируются)
  docs/
```
Удалены в 0.5.0: `Modules/Profiles`, `Journey`, `Journal`, `Statistics`, `Capture/Strategies`,
`UI/Rules`, `Journal`, `ManualPanel`, `Diagnostics`.

## 2. Модули и контракты
| Модуль | Ответственность |
|---|---|
| API | Единственное место вызова функций клиента. Возвращает значение или nil; secret values никогда не используются в арифметике. |
| Init | Пространство имён, один диспетчер событий (`ns.On`), `SafeCall`, локализация, `ns.Num`/`ns.Count`, порядок старта (`onReady`, `onLogin`). |
| Database | Загрузка, миграции (1→2→3), проверка и ремонт ForeverMemoriesDB. Чистая логика. |
| Registry | 9 событий + MANUAL + PASSIVE: внутренние задержка, приоритет, иконка; доступность в клиенте. |
| Events | Событие клиента → `{type, key, info, character, zone}` → Engine. |
| Rules | Чистая функция: событие + настройки → запрос или причина отказа. |
| Queue | Ограниченная очередь (20) с приоритетом, объединением (0,5 с) и TTL. |
| UIState | Скрыть/вернуть интерфейс вокруг снимка; в бою не скрывает; чужое скрытие не трогает. |
| Engine | Один активный запрос, один снимок; подтверждение по SCREENSHOT_SUCCEEDED; лимиты 60/час и 300/сессию. |
| History | Записи и счётчики снимков текущего персонажа; тексты записей. |
| Steps | Шагомер: свой таймер 0,5 с, независим от Engine. |
| Activity | Общие часы активной игры (v0.8.0): один таймер 1 с; «активно» = в мире и не AFK. Копит время в игре по дням (Playtime) и раздаёт секунды слушателям: Passive, Locations (смена дня), UI (перерисовка Главной). |
| Locations | Посещённые зоны (`visited`) и лог зон по дням; первое посещение для события ZONE. |
| Passive | Пассивная съёмка (v0.6.0): получает секунды от Activity, считает их, пока галочка включена и автосъёмка не на паузе; когда интервал набран и нет боя, отдаёт в Engine запрос `PASSIVE`. `Passive.Timer()` — состояние для Главной. Своего таймера и кода съёмки нет. |
| Notifications | Тост и строка в чате после сохранённого снимка. |
| ZoneCatalog | (v0.9.0) Каталог зон Forever по ID AreaTable, названия из клиента; прогресс исследования из `visited`/`visitedAt`. Своих данных не хранит, поэтому смена каталога прогресс не сбрасывает. |
| Adventure | (v0.9.0) Календарь (12 недель) и итоги недели/месяца — только чтение дневных данных других модулей. |
| Journey | (v0.9.0) Хроника: получает нормализованные события из `Events.emit` раньше Engine, поэтому не зависит от автосъёмки и не делает снимков. |
| ZoneStats | (v0.11.0) Время (от `Activity`), шаги (`Steps.onAdd`) и посещения (`Locations.Visit` → `Enter/Leave`) по ключу зоны; карточка зоны каталога суммирует все её ключи, снимки/дни/даты — из существующих данных. Своих таймеров нет. |
| Records | (v0.12.0) Личные рекорды из дневных данных персонажа (`steps.days`, `shotsByDay`, лог локаций, `playtime.days`, самая долгая сессия, серия дней). Кэш по персонажу и дню, сбрасывается слушателями History и Locations. |
| SessionRecap | (v0.12.0) Счётчики открытой сессии Activity: снимки (`Engine.onComplete`), шаги (`Steps.onAdd`), зоны и новые зоны (`Locations.listeners`), уровни (`Events.listeners`). Своих таймеров нет. |
| Memories | (v0.13.0) «В этот день» (хроника, первые посещения, снимки за ту же дату неделю/месяц/год назад) и годовщины от `journey.started`. Только чтение, кэш по персонажу и дню. |
| Achievements | (v0.13.0) Каталог 15 достижений; прогресс из `shotsTotal`, `steps.total`, `visited`, `Records.PlayedDays`, `ZoneCatalog.Explorer`. Проверка по группам из слушателей History, Steps, Locations и при входе; запись только для вошедшего персонажа. |
| Serialize | (v0.10.0) Текстовый формат резервной копии `FMB1:<схема>:<контрольная сумма>:<данные>`. Свой парсер: текст никогда не выполняется как Lua, принимаются только таблицы, строки, числа и логические значения. |
| DataTools | (v0.10.0) Список персонажей, экспорт статистики, резервная копия и её проверка/применение, очистка и удаление истории, строки диагностики (без имени, сервера, GUID). Импорт проходит те же миграции и проверку, что и SavedVariables (`Database.Load`). |
| ProjectInfo | (v0.10.0) Автор, лицензия, ссылки — только подтверждённые; `nil` скрывает строку. |
| ChangelogData | (v0.10.0) Генерируется `tools/changelog.lua` из CHANGELOG.md; тест падает, если файл устарел. |
| UI | Только отображение. Снимки — через `Engine.ManualShot` (горячая клавиша «чистый снимок» — `ManualShot("clean")`, в бою становится обычным). Тексты для копирования и вставки — `UI/Dialogs.lua`. |

Автосъёмка и шагомер не вызывают друг друга. Каждый обработчик события и каждый тик шагомера
выполняются в `pcall`: ошибка одного не останавливает другой. После 10 ошибок шагомер
останавливается до перезагрузки (и пишет это в лог), автосъёмка продолжает работать.

## 3. Поток снимка
```
событие клиента → Events ─────────┐
часы Activity → Passive (интервал) ┴→ Engine.Submit → Rules.Evaluate → Queue.Push
  → (задержка события) → Engine: PREPARING (UIState.Prepare) → CAPTURING (Screenshot)
  → WAIT_RESULT → SCREENSHOT_SUCCEEDED → History.AddShot → Notifications
                 → FAILED / таймаут 5 с → в лог, счётчики не меняются
```
Таймеры несут token: смена состояния делает старые таймеры пустыми. Загрузка, пауза —
автоматические запросы отменяются. Print Screen игрока считается как «unattributed».

## 4. Шагомер
Каждые 0,5 с (`Steps.Measure`):
1. Такси, транспорт, полёт, плавание → якорь сброшен, ничего не считаем. Если клиент не
   ответил (функции нет или secret) — тоже ничего.
2. Собственная скорость 0 (стоит, или везёт корабль/дирижабль) → якорь = текущая точка.
3. Позиция: `UnitPosition` (ярды, пространство инстанса) или карта → мир
   (`C_Map.GetPlayerMapPosition` + `GetWorldPosFromMapPos`, пространство континента).
   Сравниваются только точки одного пространства.
4. Расстояние больше `скорость × время × 1,5 + 1 ярд` → скачок (телепорт, рывок, транспорт) —
   не считаем.
5. Нет координат → `скорость × время` (при выполненном п. 1).
6. ярды × 0,9144 / 1,5 → шаги дня (`date("%Y-%m-%d")` по часам компьютера) и общий итог.

Загрузка, вход в мир, смена зоны — сброс якоря. Окно обновляет только число шагов, и только
когда меняется целая часть.

## 5. Данные (схема 5; 3 → 4 переводит шаги 0,75 м в 1,5 м; 4 → 5 — дневник v0.9.0)
```
ForeverMemoriesDB = {
  schemaVersion = 5,
  settings = { enabled, mode = "normal"|"clean", events = { LEVEL = true, ... },
               passive = true, passiveInterval = 15|30|45|60,       -- v0.6.0
               notifications, sound, minimap, minimapAngle, locale, scale },
  ui = { point = {...} },
  counters = { unattributed },
  characters = { ["Сервер:Имя"] = {
      name, realm, class, guid,
      shots = { { t, ev, zone, info, manual } ... },   -- до 5000, старые удаляются
      shotsTotal, shotsByDay = { ["2026-11-24"] = n }, shotZones = { [зона] = true },
      visited = { [ключ зоны] = true }, zonesSeeded, guild,
      steps = { total, days = { ["2026-11-24"] = x }, since },
      passive = { elapsed = секунды активной игры, interval = минуты },  -- v0.6.0
      playtime = { total, days = { ["2026-11-24"] = секунды },          -- v0.8.0
                   sinceDay, sessions, longest, session = { start, last, active } },  -- v0.9.0
                   -- v0.12.0: longestAt; session += { ended, shots, steps, zones = { [ключ] = true },
                   --   newZones, levels }; lastSession = { start, finish, endKnown, active,
                   --   shots, steps, zones (число), newZones, levels }
      achievements = { seeded, done = { [id] = время | 0 } },          -- v0.13.0
      locations = { days = { ["2026-11-24"] = { [ключ зоны | "inst:имя"] =
                    { name, t = первый приход за день, first, instance } } } },
      visitedAt = { [ключ зоны] = время первого зарегистрированного посещения },  -- v0.9.0
      journey = { started, events = { { t, kind, zone, info } }, firsts = { [kind] = t } } } },  -- v0.9.0
  zoneDump = { at, lines },   -- вывод /fm zones (v0.9.0)
  legacy = { записи 0.4.2 без владельца },
}
```
Счётчики не урезаются вместе с историей, поэтому «Всего снимков» не уменьшается.

## 6. Команды
`/fm` окно · `/fm on|off|toggle` · `/fm shot` · `/fm status` · `/fm debug` · `/fm log` · `/fm zones` ·
`/fm ui` (аварийно вернуть интерфейс, работает даже если аддон не загрузился) · `/fm reset`
(окно в центр). Горячие клавиши — Bindings.xml.
