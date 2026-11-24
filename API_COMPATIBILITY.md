# API Compatibility — World of Warcraft: Forever

Протокол проверки игрового API. Источник истины — только реальный клиент Forever.
Документация (Warcraft Wiki, сайты сообщества) — это гипотеза, а не подтверждение.

Статусы: `PENDING` — ещё не проверено в клиенте, `PASS`, `FAIL`, `SKIP` (SKIP ≠ PASS).

## Окружение теста

| Поле | Значение |
|---|---|
| Клиент (`/fm status`, строка Client) | _заполнить_ |
| Build | _заполнить_ |
| TOC из `GetBuildInfo()` | _заполнить_ |
| Локаль клиента | _заполнить_ |
| Дата теста | _заполнить_ |
| Тестировал | _заполнить_ |

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
| `Screenshot` | съёмка | PENDING | |
| `GetBuildInfo` | диагностика | PENDING | |
| `C_Timer.After` | таймауты, задержки | PENDING | |
| `C_Timer.NewTimer` | отменяемые таймеры (v0.1.0) | PENDING | |
| `InCombatLockdown` | политика боя | PENDING | |
| `UnitIsAFK` | путешествие | PENDING | |
| `UnitLevel` | LEVEL | PENDING | |
| `GetMaxPlayerLevel` | MAX_LEVEL | PENDING | |
| `GetRealZoneText` | ZONE | PENDING | |
| `C_Map.GetBestMapForUnit` | стабильный ID зоны | PENDING | |
| `C_Map.GetPlayerMapPosition` | смена места (путешествие) | PENDING | может быть ограничена в инстансах |
| `IsInInstance` | контекст | PENDING | |
| `issecretvalue` | защита от secret values | PENDING | |
| `C_EventUtils.IsEventValid` | безопасная регистрация событий | PENDING | |
| `C_AddOns.GetAddOnMetadata` | версия из TOC | PENDING | |
| `GetLocale` | RU/EN | PENDING | |
| `GetTime`, `time`, `date` | время | PENDING | |

## События (регистрация — `/fm debug`; срабатывание — сценарий)

| Событие | Регистрация | Сценарий проверки | Сработало? | Примечание |
|---|---|---|---|---|
| `SCREENSHOT_STARTED` | PENDING | `/fm shot` | PENDING | |
| `SCREENSHOT_SUCCEEDED` | PENDING | `/fm shot`, файл появился | PENDING | синхронно или нет — см. `sync=` в `/fm status` |
| `SCREENSHOT_FAILED` | PENDING | трудно вызвать намеренно | PENDING | можно SKIP |
| `PLAYER_LEVEL_UP` | PENDING | получить уровень | PENDING | |
| `ZONE_CHANGED_NEW_AREA` | PENDING | сменить зону | PENDING | |
| `PLAYER_ENTERING_WORLD` | PENDING | вход / `/reload` | PENDING | |
| `PLAYER_LEAVING_WORLD` | PENDING | телепорт / выход | PENDING | |
| `PLAYER_REGEN_DISABLED/ENABLED` | PENDING | вход/выход из боя | PENDING | |
| `PLAYER_DEAD` | PENDING | смерть | PENDING | |
| `CHAT_MSG_LOOT` | PENDING | поднять предмет | PENDING | payload не сохраняется |
| `ENCOUNTER_END` | PENDING | убить босса подземелья | PENDING | |
| `ADDON_ACTION_BLOCKED/FORBIDDEN` | PENDING | должно НЕ срабатывать на `/fm shot` | PENDING | если сработало — `Screenshot()` защищён |

## Сценарии v0.0.1

| ID | Сценарий | Ожидание | Результат | Доказательство |
|---|---|---|---|---|
| S1 | Аддон виден в списке и загружается без «устарел» | нет ошибок Lua | PENDING | |
| S2 | `/fm shot` вне боя | статус `success`, новый файл в `Screenshots` | PENDING | имя файла |
| S3 | `/fm shot` в бою | кадр есть или понятная причина | PENDING | |
| S4 | 5 раз `/fm shot` подряд (по одному после ответа) | 5 файлов, 5 записей `success` | PENDING | |
| S5 | `/fm shot` дважды очень быстро (макрос) | второй — `busy`, один файл | PENDING | |
| S6 | Нативный Print Screen | в `/fm status` растёт `unattributed`, записи нет | PENDING | |
| S7 | `/reload`, затем `/fm status` | `loads` вырос на 1, история сохранена | PENDING | |
| S8 | Полный выход из игры и вход | история сохранена | PENDING | |
