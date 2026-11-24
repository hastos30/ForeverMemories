# Архитектура (v0.5.0)

## 1. Структура
```
ForeverMemories/
  ForeverMemories.toc   Bindings.xml (не в TOC)
  Core/     API, Logger, Util, Database, Init, Registry, Events, Commands
  Capture/  Rules, Queue, UIState, Engine
  Modules/  History, Steps, Notifications
  UI/       Widgets, Main (окно + Главная), Capture, History, Settings, Minimap
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
| Registry | 9 событий + MANUAL: внутренние задержка, приоритет, иконка; доступность в клиенте. |
| Events | Событие клиента → `{type, key, info, character, zone}` → Engine. |
| Rules | Чистая функция: событие + настройки → запрос или причина отказа. |
| Queue | Ограниченная очередь (20) с приоритетом, объединением (0,5 с) и TTL. |
| UIState | Скрыть/вернуть интерфейс вокруг снимка; в бою не скрывает; чужое скрытие не трогает. |
| Engine | Один активный запрос, один снимок; подтверждение по SCREENSHOT_SUCCEEDED; лимиты 60/час и 300/сессию. |
| History | Записи и счётчики снимков текущего персонажа; тексты записей. |
| Steps | Шагомер: свой таймер 0,5 с, независим от Engine. |
| Notifications | Тост после сохранённого снимка. |
| UI | Только отображение. Снимки — через `Engine.ManualShot`. |

Автосъёмка и шагомер не вызывают друг друга. Каждый обработчик события и каждый тик шагомера
выполняются в `pcall`: ошибка одного не останавливает другой. После 10 ошибок шагомер
останавливается до перезагрузки (и пишет это в лог), автосъёмка продолжает работать.

## 3. Поток снимка
```
событие клиента → Events → Engine.Submit → Rules.Evaluate → Queue.Push
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
6. ярды × 0,9144 / длина шага (ходьба ≤ 3 ярда/с — 0,9144 м, иначе 1,5 м) → шаги дня (`date("%Y-%m-%d")` по часам компьютера) и общий итог.

Загрузка, вход в мир, смена зоны — сброс якоря. Окно обновляет только число шагов, и только
когда меняется целая часть.

## 5. Данные (схема 4; миграция 3 → 4 переводит шаги 0,75 м в шаги 1,5 м)
```
ForeverMemoriesDB = {
  schemaVersion = 4,
  settings = { enabled, mode = "normal"|"clean", events = { LEVEL = true, ... },
               notifications, sound, minimap, minimapAngle, locale, scale },
  ui = { point = {...} },
  counters = { unattributed },
  characters = { ["Сервер:Имя"] = {
      name, realm, class, guid,
      shots = { { t, ev, zone, info, manual } ... },   -- до 5000, старые удаляются
      shotsTotal, shotsByDay = { ["2026-11-24"] = n }, shotZones = { [зона] = true },
      visited = { [ключ зоны] = true }, zonesSeeded, guild,
      steps = { total, days = { ["2026-11-24"] = x }, since } } },
  legacy = { записи 0.4.2 без владельца },
}
```
Счётчики не урезаются вместе с историей, поэтому «Всего снимков» не уменьшается.

## 6. Команды
`/fm` окно · `/fm on|off|toggle` · `/fm shot` · `/fm status` · `/fm debug` · `/fm log` ·
`/fm ui` (аварийно вернуть интерфейс, работает даже если аддон не загрузился) · `/fm reset`
(окно в центр). Горячие клавиши — Bindings.xml.
