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
