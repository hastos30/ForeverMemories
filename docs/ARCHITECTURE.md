# Архитектура ForeverMemories

[English](ARCHITECTURE.en.md) · **Русский**

Аддон для одного клиента: World of Warcraft: Forever (`## Interface: 16001`), Lua 5.1.
Порядок загрузки файлов задаёт `ForeverMemories.toc`.

## 1. Папки
```
ForeverMemories/
  ForeverMemories.toc  Bindings.xml (горячие клавиши, грузится игрой сама)
  Core/      API, Logger, Util, Serialize, Database, Init, Registry, Events, Commands
  Capture/   Rules, Queue, UIState, Engine            — автосъёмка
  Modules/   данные и логика без интерфейса (см. §2)
  UI/        Media, Fonts, Widgets, Main, Dialogs, Capture, History, Settings*, Minimap
  Locales/   enUS, ruRU, ZoneNames (русские названия зон для английского клиента)
  Media/     свои текстуры (TGA) и шрифты (TTF)
  tests/     офлайн-тесты и фальшивый клиент   — в игру не копируются
  tools/     генераторы и сборка релиза        — в игру не копируются
  docs/      документация                     — в игру не копируется
```

## 2. Модули
| Модуль | За что отвечает |
|---|---|
| Core/API | Единственное место вызова функций клиента. Возвращает значение или `nil`; secret values никогда не попадают в арифметику. |
| Core/Init | Пространство имён `ns`, один диспетчер событий (`ns.On`), `SafeCall`, локализация, порядок старта. |
| Core/Database | Загрузка, миграции, проверка и ремонт `ForeverMemoriesDB`. Чистая логика. **Схема данных описана в начале этого файла.** |
| Core/Registry | 9 событий + `MANUAL` + `PASSIVE`: задержка, приоритет, иконка, доступность. |
| Core/Events | Событие клиента → `{type, key, info, character, zone}` → Journey и Engine. |
| Core/Serialize | Формат резервной копии `FMB1:…`. Свой парсер: текст никогда не выполняется как Lua. |
| Core/Commands | Команды `/fm …`. |
| Capture/* | Rules (событие + настройки → запрос), Queue (очередь с приоритетом), UIState (скрыть/вернуть интерфейс для чистого кадра), Engine (один снимок за раз, подтверждение по `SCREENSHOT_SUCCEEDED`, лимиты). |
| Modules/History | Записи и счётчики снимков. |
| Modules/Activity | Общие часы активной игры (1 с, не AFK): время по дням, секунды для Passive и UI. |
| Modules/Steps | Шагомер, свой таймер 0,5 с (см. §4). |
| Modules/Passive | Пассивная съёмка по накопленному активному времени. |
| Modules/Locations, ZoneCatalog, ZoneStats | Посещённые зоны, каталог зон Forever (ID AreaTable), время/шаги/посещения по зонам. |
| Modules/Stories, ArtPack | Короткие тексты о зонах; картинки из необязательного аддона `ForeverMemories_ArtPack`. |
| Modules/Adventure, Journey, Memories | Календарь и итоги, хроника важных моментов, «В этот день» и годовщины. |
| Modules/Records, SessionRecap | Личные рекорды, итоги игровой сессии. |
| Modules/Progress, Trackers | Состояния персонажа для достижений (деньги, репутации, профессии…). Только подтверждённые значения, прошлое не угадывается. |
| Modules/AchievementCatalog, Achievements | Каталог 106 достижений (персонаж + аккаунт, 54 карточки) и их проверка; цепочки ступеней (`chain`) и карточки для страницы. |
| Modules/Notifications | Три вида уведомлений (mini, discovery, legendary) и строка в чате. Своё место и размер у каждого вида (`ui.notify`). |
| Modules/DataTools, ProjectInfo | Персонажи, экспорт, резервная копия, удаление; диагностика без имени, сервера и GUID. |
| Modules/ChangelogData | **Генерируется** `tools/changelog.lua` из CHANGELOG.md и CHANGELOG.en.md. |
| UI/* | Только отображение. Снимки — через `Engine.ManualShot`. |

Автосъёмка и шагомер не вызывают друг друга. Каждый обработчик выполняется в `pcall`:
ошибка одного не останавливает другой.

## 3. Поток снимка
```
событие клиента → Events ─────────┐
часы Activity → Passive (интервал) ┴→ Engine.Submit → Rules → Queue
  → (задержка события) → UIState.Prepare (чистый кадр) → Screenshot()
  → SCREENSHOT_SUCCEEDED → History.AddShot → Notifications
  → FAILED / таймаут 5 с → в лог, счётчики не меняются
```
Таймеры несут token: смена состояния делает старые таймеры пустыми. Загрузка экрана и пауза
отменяют автоматические запросы.

## 4. Шагомер
Каждые 0,5 с: такси, транспорт, полёт, плавание — не считаем. Позиция — `UnitPosition`
(ярды) или карта → мир. Скачок дальше, чем `скорость × время × 1,5 + 1 ярд` (телепорт,
рывок) — не считаем. Шаги = ярды × 0,9144 / 1,5 м.

## 5. Данные
`ForeverMemoriesDB` (SavedVariables), схема **6**. Полное описание полей и правил
миграции — комментарий в начале `Core/Database.lua` (одно место, чтобы не расходилось).
Миграция идёт на копии и применяется, только если ни один итог (персонажи, снимки, шаги,
дни, зоны, достижения) не уменьшился. Файл от более новой версии аддона не трогается.

## 6. Оформление
- Палитра — `W.COLORS` в `UI/Widgets.lua`: тёмные матовые поверхности, тонкие золотые рамки.
- Все пути к своим текстурам и шрифтам — только в `UI/Media.lua`. Тест проверяет, что каждый
  указанный там файл существует.
- TGA: размер — степень двойки, без RLE-сжатия.
- `tools/make_borders.py` — рамки уведомлений (9-slice); `tools/make_mini_back.py` — фон
  мини-уведомления точно по форме рамки. Запуск: `python3 tools/<файл>` из корня (нужен Pillow).

## 7. Инструменты
| Файл | Что делает |
|---|---|
| `tools/changelog.lua` | CHANGELOG.md + CHANGELOG.en.md → `Modules/ChangelogData.lua`. Запускать после правки журнала. |
| `tools/release.sh <версия>` | Обновляет журнал, гоняет smoke-тест, собирает `dist/ForeverMemories-v<версия>.zip`. |
| `tools/make_*.py` | Генераторы текстур (см. §6). |

`Modules/AchievementCatalog.lua` и `Locales/ZoneNames.lua` когда-то генерировались из
`docs/catalog/`; исходников в репозитории больше нет, поэтому эти файлы правятся вручную.
