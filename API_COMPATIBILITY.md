# API Compatibility — World of Warcraft: Forever

Протокол проверки игрового API. Источник истины — только реальный клиент Forever.
Документация (Warcraft Wiki, сайты сообщества) — это гипотеза, а не подтверждение.

Статусы: `PENDING` — ещё не проверено в клиенте, `PASS`, `FAIL`, `SKIP` (SKIP ≠ PASS).

## Окружение теста

| Поле | Значение |
|---|---|
| Клиент (`/fm status`, строка Client) | 1.60.1 |
| Build | 71037 (Nov 18 2026) |
| TOC из `GetBuildInfo()` | 16001 — совпадает с `## Interface` |
| Локаль клиента | enUS (судя по интерфейсу) |
| Дата теста | 2026-11-24 |
| Тестировал | Viktor, Linux (Wine), вместе с другими аддонами |
| Папка снимков | `~/games/World of Warcraft/_forever_/Screenshots/` |

## Что известно до теста (документация, 2026-11-24)

| Факт | Источник | Уверенность |
|---|---|---|
| `## Interface: 16001` для Forever | [Warcraft Wiki: TOC format](https://warcraft.wiki.gg/wiki/TOC_format) | средняя, проверить через `GetBuildInfo()` |
| Forever использует Mainline API (как 12.1.5), а не Classic | Warcraft Wiki TOC format (changelog 1.60.1), [ForeverMeta](https://forevermeta.me/en/guides/wow-forever-addons-interface) | средняя |
| TOC-суффиксы `_Forever.toc` / `_Camelot.toc` | Warcraft Wiki TOC format | средняя; нам не нужны, т.к. поддерживаем только Forever |
| `Screenshot()` есть в Forever 1.60.1 (69913), файл `WoWScrnShot_MMDDYY_HHMMSS.jpg` | [API Screenshot](https://warcraft.wiki.gg/wiki/API_Screenshot) | средняя; защищённость не указана |
| `SCREENSHOT_STARTED/SUCCEEDED/FAILED` есть в Forever 1.60.1, payload отсутствует | [SUCCEEDED](https://warcraft.wiki.gg/wiki/Event:SCREENSHOT_SUCCEEDED), [FAILED](https://warcraft.wiki.gg/wiki/Event:SCREENSHOT_FAILED), [STARTED](https://warcraft.wiki.gg/wiki/Event:SCREENSHOT_STARTED) | средняя |
| Combat log недоступен аддонам, GUID обфусцированы, есть secret values | ForeverMeta, [wowforeverguides](https://wowforeverguides.com/addons/developers) | низкая (сайты сообщества) |
| Папка аддонов `World of Warcraft\_forever_\Interface\AddOns\` | wowforeverguides | низкая, проверить на диске |
| Был баг с восстановлением SavedVariables в сборке 69913, сообщают об исправлении в 70009 | wowforeverguides (форумный отчёт) | низкая |

## Функции (заполняется по `/fm debug`)

| Функция | Нужна для | Клиент | Примечание |
|---|---|---|---|
| `Screenshot` | съёмка | PASS | |
| `GetBuildInfo` | диагностика | PASS | |
| `C_Timer.After` | таймауты, задержки | PASS | |
| `C_Timer.NewTimer` | отменяемые таймеры (v0.1.0) | PASS | |
| `InCombatLockdown` | политика боя | PASS | |
| `UnitIsAFK` | путешествие | PASS | |
| `UnitLevel` | LEVEL | PASS | |
| `GetMaxPlayerLevel` | MAX_LEVEL | PASS | |
| `GetRealZoneText` | ZONE | PASS | |
| `C_Map.GetBestMapForUnit` | стабильный ID зоны | PASS | |
| `C_Map.GetPlayerMapPosition` | смена места (путешествие) | PASS | может быть ограничена в инстансах |
| `IsInInstance` | контекст | PASS | |
| `issecretvalue` | защита от secret values | PASS | |
| `C_EventUtils.IsEventValid` | безопасная регистрация событий | PASS | |
| `C_AddOns.GetAddOnMetadata` | версия из TOC | PASS | |
| `GetLocale` | RU/EN | PASS | |
| `GetTime`, `time`, `date` | время | PASS | |

## События (регистрация — `/fm debug`; срабатывание — сценарий)

| Событие | Регистрация | Сценарий проверки | Сработало? | Примечание |
|---|---|---|---|---|
| `SCREENSHOT_STARTED` | PASS | `/fm shot` | PASS | приходит перед результатом (`started=true`) |
| `SCREENSHOT_SUCCEEDED` | PASS | `/fm shot` | PASS | асинхронно (`sync=false`), ~0.08 с; в бою тоже; 2 сигнала = 2 файла, время файла совпадает с секундой записи |
| `SCREENSHOT_FAILED` | PASS | трудно вызвать намеренно | SKIP | |
| `PLAYER_LEVEL_UP` | PASS | получить уровень | PENDING | |
| `ZONE_CHANGED_NEW_AREA` | PASS | вход в мир | PASS (1 раз) | также при входе, не только при смене зоны |
| `PLAYER_ENTERING_WORLD` | PASS | вход / `/reload` | PASS | |
| `PLAYER_LEAVING_WORLD` | PASS | телепорт / выход | PENDING | |
| `PLAYER_REGEN_DISABLED/ENABLED` | PASS | вход/выход из боя | PENDING | `InCombatLockdown()` в бою = true (подтверждено `combat=true`) |
| `PLAYER_DEAD` | PASS | смерть | PENDING | |
| `CHAT_MSG_LOOT` | PASS | поднять предмет | PENDING | payload не сохраняется |
| `ENCOUNTER_END` | PASS | убить босса подземелья | PENDING | |
| `ADDON_ACTION_BLOCKED/FORBIDDEN` | PASS | должно НЕ срабатывать на `/fm shot` | PASS (не сработало) | `Screenshot()` из slash-команды не защищён, в т.ч. в бою |

## Сценарии v0.0.1

| ID | Сценарий | Ожидание | Результат | Доказательство |
|---|---|---|---|---|
| S1 | Аддон виден в списке и загружается без «устарел» | нет ошибок Lua | PASS | список аддонов, `/fm debug`; Lua Warning относится к другому аддону (Trailsmith) |
| S2 | `/fm shot` вне боя | статус `success`, новый файл в `Screenshots` | PASS | `Shot #1` 15:46:09 → `WoWScrnShot_112426_154609.jpg` (540 981 байт) |
| S3 | `/fm shot` в бою | кадр есть или понятная причина | PASS | `#2` 15:47:20, combat=true → `WoWScrnShot_112426_154720.jpg` (628 677 байт) |
| S4 | 5 раз `/fm shot` подряд (по одному после ответа) | 5 файлов, 5 записей `success` | PASS | снимки #1–#5 все `success` (за несколько сессий, не строго подряд) |
| S5 | `/fm shot` дважды очень быстро (макрос) | второй — `busy`, один файл | PASS | 2 запуска макроса: `skipped: busy (WAIT_RESULT)` + `Shot #3/#4: success`; файлы по словам тестировщика «всё ок» |
| S6 | Нативный Print Screen | в `/fm status` растёт `unattributed`, записи нет | PASS | 6 нажатий = 6 файлов = `unattributed 6`, новых записей нет; один снимок даёт один сигнал |
| S7 | `/reload`, затем `/fm status` | `loads` вырос на 1, история сохранена | PASS | `loads` 3 → 4, записи #1 и #2 на месте |
| S8 | Полный выход из игры и вход | история сохранена | PASS | после перезахода нумерация продолжилась: `Shot #5` (счётчик `nextShotId` восстановлен из SavedVariables) |

## v0.5.0: события автосъёмки (в клиенте не проверены)

Если клиент не знает событие, оно показывается неактивным с причиной; `/fm debug` → «Unavailable events».

| Событие ТЗ | Источник | Как отсекаются ложные | Регистрация | Срабатывание |
|---|---|---|---|---|
| Новый уровень | `PLAYER_LEVEL_UP` (level) | ключ `level:N`, окно 10 с | PASS (v0.0.1) | PENDING |
| Смерть | `PLAYER_DEAD` | окно 10 с | PASS (v0.0.1) | PENDING |
| Победа над боссом | `ENCOUNTER_END` (success = 1) + `IsInInstance()` = party/raid | неудача, открытый мир, secret — игнор | PASS (v0.0.1) | PENDING |
| Победа в дуэли | `CHAT_MSG_SYSTEM` + `DUEL_WINNER_KNOCKOUT/RETREAT` | победитель = `UnitName("player")` | PENDING | PENDING |
| Редкий / Эпический / Легендарный | `CHAT_MSG_LOOT` + `LOOT_ITEM_SELF*`/`LOOT_ITEM_PUSHED_SELF*`, качество `C_Item.GetItemQualityByID` или цвет ссылки | только свои строки; одно качество = одно событие; ключ `loot:itemID` | PASS (v0.0.1) | PENDING |
| Новая зона | `ZONE_CHANGED_NEW_AREA` + `C_Map.GetBestMapForUnit` | список посещённых у персонажа; зона входа не снимается | PASS (v0.0.1) | PENDING |
| Вступление в гильдию | `PLAYER_GUILD_UPDATE` + `IsInGuild`, `GetGuildInfo` | вступление = было «без гильдии» (сохранено) → стало «в гильдии»; «без гильдии» не записывается первые 30 с после входа | PENDING | PENDING |

## v0.5.0: шагомер (в клиенте не проверено)

Справка (warcraft.wiki.gg, 2026-11-24; это гипотеза, не подтверждение):
- `UnitPosition(unit)` → x, y, z, instanceID в **ярдах**; есть в Forever 1.60.1 (69913);
  с 7.1.0 возвращает nil в подземельях, рейдах, на полях боя и аренах.
- `GetUnitSpeed(unit)` → текущая, бег, полёт, плавание в **ярдах/с** (бег 7, эпический маунт 14);
  есть в Forever 1.60.1; помечена `SecretWhenUnitStatsRestricted` — может вернуть secret.
- `C_Map.GetWorldPosFromMapPos(mapID, pos)` → continentID, вектор; единицы на вики не указаны
  (по примерам — те же мировые ярды). Есть в Forever 1.60.1.
- Secret values (12.0+): нельзя сравнивать и считать — ошибка Lua. Аддон проверяет `issecretvalue`
  у каждого числа и при secret ничего не считает.

| Функция | Зачем | Наличие | Данные в мире | В подземелье |
|---|---|---|---|---|
| `UnitPosition` | позиция, ярды | PENDING | PENDING | ожидается nil |
| `C_Map.GetPlayerMapPosition` + `GetWorldPosFromMapPos` | позиция, если нет UnitPosition | PASS / PENDING | PENDING | PENDING |
| `GetUnitSpeed` | своя скорость; 0 на корабле | PENDING | PENDING | PENDING (secret?) |
| `IsSwimming`, `IsFlying`, `UnitOnTaxi`, `UnitInVehicle` | исключения | PENDING | PENDING | PENDING |
| `UnitGUID("player")` | сверка персонажа | PENDING | стабилен между сессиями? PENDING | — |

Пересчёт: ярды × 0,9144 = метры; метры / 1,5 = шаги (с v0.5.1; в v0.5.0 было 0,75). Проверка единиц в клиенте:
пробежать 30 с без препятствий по прямой — ожидается ≈ 7 × 30 = 210 ярдов ≈ 128 шагов (бег 100%).

## v0.8.2: всё игровое время (в клиенте не проверено)

| Функция / событие | Зачем | Наличие | Поведение |
|---|---|---|---|
| `RequestTimePlayed()` | число `/played` для «Всё игровое время» | PENDING (`/fm debug` → Missing functions) | PENDING |
| `TIME_PLAYED_MSG(total, level)` | ответ сервера, секунды | PENDING | PENDING: число = `/played` |
| `ChatFrameN:UnregisterEvent/RegisterEvent/IsEventRegistered("TIME_PLAYED_MSG")` | скрыть строку в чате только для запроса аддона | PENDING | PENDING: после входа нет строки в чате, ручной `/played` печатается |

Если функции нет, событие неизвестно или пришёл secret — показывается собственное время
активной игры аддона (с 0.8.0), в лог пишется предупреждение.

## v0.9.0: каталог зон и дневник (в клиенте не проверено)

Сверка каталога 2026-11-24 (ТЗ 7.6):

| Источник | Что есть | Расхождения с ТЗ |
|---|---|---|
| thewowdb.com/wow-forever/zones/ | 51 зона: ВК 27, Калимдор 23, Zephras Isle 1; ID в адресах (ID AreaTable: Dun Morogh 1, Elwynn 12, … новые: Riverglades 16591, Zephras Isle 16593, Shen'dralas 16651, Ruins of Gilneas 16756) | нет |
| theforeverera.com/en/map/ (сборка 1.60.1.71037) | 45 зон без столиц; «Other»: Zephras Isle, Gilneas | нет столиц в списке; «Gilneas» вместо «Ruins of Gilneas» |
| foreverguide.net/tools/map/ | 42 зоны + 8 городов, Zephras Isle (Contested 1-12) | нет Ruins of Gilneas |

Ни один источник не отмечает зоны как недоступные. Mount Hyjal и Riverglades «могут измениться после беты».

| Функция | Зачем | Наличие | Проверка |
|---|---|---|---|
| `C_Map.GetAreaInfo(areaID)` | названия зон каталога на языке клиента | PENDING | `/fm zones` → `status client`, `missing in client: -` |
| `C_Map.GetMapInfo(id).name` | имя карты для старых ключей `map:ID` | PASS (функция), имя PENDING | `/fm zones` → строка `here` |
| `C_Map.GetBestMapForUnit` | ключ зоны | PASS | — |
| `C_Map.GetMapChildrenInfo` | не используется (см. SPECIFICATION §12) | — | — |
| `GetMaxPlayerLevel` | хроника: максимальный уровень | PASS | `/fm debug` → Diary `max level` |
| `IsInInstance` | подземелье/рейд: босс, история посещений | PASS | зайти в подземелье |
| `SetClipsChildren` | обрезка строк прокрутки | PENDING | строки не вылезают за область при прокрутке |
| `EditBox` (`SetAutoFocus`, `SetTextInsets`, `OnTextChanged` с `userInput`) | поиск локаций | PENDING | ввод, Esc, Enter |
| Текстуры `RaidFrame\ReadyCheck-Ready`, `COMMON\Indicator-Gray`, `INV_Crown_01`, `INV_Misc_Head_Dragon_01`, `INV_Misc_Book_09`, `Ability_Hunter_Pathfinding`, `INV_Misc_PocketWatch_02` | иконки | PENDING | нет зелёных квадратов |

## v0.10.0: настройки, данные, горячие клавиши (в клиенте не проверено)

| Функция / механизм | Зачем | Наличие | Проверка |
|---|---|---|---|
| `UpdateAddOnMemoryUsage`, `GetAddOnMemoryUsage(name)` | «Оперативная память» на странице Данные | PENDING | число в КБ или «Недоступно»; без функции аддон работает |
| `LOCALIZED_CLASS_NAMES_MALE` | название класса в списке персонажей | PENDING | без таблицы — `Druid` из кода класса |
| `EditBox:SetMultiLine`, `SetMaxLetters(0)`, `HighlightText`, `SetFocus`, Ctrl+C / Ctrl+V | экспорт, копия, импорт, ссылки | PENDING | копирование и вставка больших текстов |
| `ScrollFrame:SetScrollChild`, `GetVerticalScrollRange`, `SetVerticalScroll` | прокрутка текста в окне копирования | PENDING | колесо мыши, курсор виден |
| `StaticPopup` с `showAlert` и текстом с `%s` уже подставленным | подтверждения удаления и импорта | PENDING | имя персонажа в вопросе |
| `FontString:GetStringHeight` (скрытая строка) | высота пунктов в «Обновлениях» | PENDING | текст не обрезается и не налезает |
| Bindings.xml: `FOREVERMEMORIES_TOGGLE/SHOT/AUTOCAPTURE/CLEANSHOT`, `category="ADDONS"`, `BINDING_NAME_*` | горячие клавиши | PENDING | 4 строки в меню, без клавиш по умолчанию |

Новых событий клиента нет. Аддон ничего не пишет на диск сам: всё копирует игрок; данные
сохраняет клиент в SavedVariables при выходе или `/reload`.

## v0.13.0: воспоминания и достижения (в клиенте не проверено)

Новых функций и событий клиента нет: «В этот день», годовщины и достижения считаются из
сохранённых данных. `Texture:SetAlpha` (бледные иконки невыполненных достижений) — PENDING;
текстура `INV_Crown_01` (карточка годовщины) уже в списке v0.9.0.

## v0.12.0: рекорды и сессии (в клиенте не проверено)

| Функция / механизм | Зачем | Наличие | Проверка |
|---|---|---|---|
| Событие `PLAYER_LOGOUT` | время конца сессии для «Последнего приключения» | PENDING | выйти, войти: «Конец» = время выхода; `/reload` сессию не завершает |
| `Frame:SetFrameLevel`, `GetFrameLevel` | панель подробностей сессии поверх Главной | PENDING | панель закрывает Главную, «Закрыть» работает |

Других новых функций клиента нет: рекорды и итоги аккаунта считаются из сохранённых данных.

## v0.6.0: пассивная съёмка (в клиенте не проверено)

| Функция | Зачем | Наличие | Поведение |
|---|---|---|---|
| `UnitIsAFK("player")` | не считать время в AFK | PENDING (`/fm debug` → Missing functions) | PENDING: `/afk` → строка Passive `afk true` |
| `C_Timer.NewTicker` | таймер 1 с | PASS (шагомер) | — |
| `InCombatLockdown` | отложить снимок в бою | PASS (v0.0.1) | — |

Допущение: если `UnitIsAFK` нет или он вернул secret, персонаж считается не-AFK — время идёт.
Новых событий клиента нет (только уже используемые `PLAYER_ENTERING_WORLD` / `PLAYER_LEAVING_WORLD`).

### Идентификация персонажа
ТЗ (12.3) предпочитает GUID. Сообщества пишут, что GUID в Forever обфусцированы. Если GUID
игрока меняется между сессиями, ключ по GUID «терял» бы историю при каждом входе. Поэтому
ключ — `Сервер:Имя` (уникален на сервере), GUID сохраняется и сверяется: `/fm debug` → строка
Character покажет `(changed!)`, если GUID при том же имени изменился. Проверить после 2–3 входов.

## События и API версии 0.4.0-beta (в клиенте не проверены)

Регистрация проверяется автоматически: если клиент не знает событие, триггер показывается как «недоступно» (вкладка «Диагностика»).

| Триггер | Событие / API | Регистрация | Срабатывание |
|---|---|---|---|
| MOUNT | `NEW_MOUNT_ADDED` | PENDING | PENDING |
| DUNGEON | `LFG_COMPLETION_REWARD` (только подземелья через поиск группы) | PENDING | PENDING |
| DUEL | `CHAT_MSG_SYSTEM` + `DUEL_WINNER_KNOCKOUT` / `DUEL_WINNER_RETREAT` | PENDING | PENDING |
| QUEST | `QUEST_TURNED_IN` | PENDING | PENDING |
| GUILD | `PLAYER_GUILD_UPDATE` + `IsInGuild()` | PENDING | PENDING |
| FORM | `UPDATE_SHAPESHIFT_FORMS` + `GetNumShapeshiftForms()` | PENDING | PENDING |
| LOOT_* | `CHAT_MSG_LOOT` + `LOOT_ITEM_SELF*`, `C_Item.GetItemQualityByID` | PASS (v0.0.1) | PENDING |
| clean | `UIParent:Hide()/Show()`, показ UI в `PLAYER_REGEN_DISABLED` | — | PENDING |
| Journey | `C_Timer.NewTicker`, `C_Map.GetPlayerMapPosition`, `UnitIsAFK` | PASS (функции есть) | PENDING |
| Options | `Settings.RegisterCanvasLayoutCategory`, `AddonCompartmentFunc` | PENDING | PENDING |
| Смена языка (0.4.1) | `ReloadUI()` из диалога `StaticPopup` | PENDING | PENDING |
| Выпадающий список (0.4.1) | `SetFrameStrata`, `SetClampedToScreen`, `SetColorTexture`, слой `HIGHLIGHT`, `UISpecialFrames` | PENDING | PENDING |
| Подсказки (0.4.2) | `GameTooltip:SetOwner/SetText/AddLine(..., wrap)/Show/Hide`, `Frame:HookScript`, `EnableMouse`, `SetHitRectInsets`, `FontString:GetStringWidth` | PENDING | PENDING |
