# Архитектура
## 1. Проверка платформы (блокирующий этап)
В клиенте Forever зафиксировать GetBuildInfo(), фактический TOC Interface, доступность Screenshot(), событий результата, таймеров, SavedVariables, состояния боя/AFK/загрузки, безопасного управления UI и получения зоны. Кандидаты на события: PLAYER_LEVEL_UP, ZONE_CHANGED_NEW_AREA, PLAYER_ENTERING_WORLD, PLAYER_LEAVING_WORLD, PLAYER_REGEN_DISABLED/ENABLED, PLAYER_DEAD, CHAT_MSG_LOOT, ENCOUNTER_END, SCREENSHOT_SUCCEEDED/FAILED. Это не подтверждённый список для Forever. Проверить регистрацию, полезную нагрузку, права доступа и реальные сценарии. Записать результаты в API_COMPATIBILITY.md (сборка, дата, тест, результат). Не обходить protected/secret values и не предполагать, что API других веток идентичен. Если результат съёмки не доступен, обозначать unconfirmed. Если сам Screenshot недоступен, остановить релиз автоматической съёмки.
## 2. Структура
```
ForeverMemories/
  ForeverMemories.toc
  Core/{Init,API,Database,Events,Registry,Logger}.lua
  Capture/{Rules,Queue,Engine,Strategies,UIState}.lua
  Modules/{Journey,Journal,Profiles,Notifications,Statistics}.lua
  UI/{Main,Rules,Journal,Minimap,Settings,Diagnostics}.lua
  Locales/{enUS,ruRU}.lua
  Media/
  Bindings.xml
  tests/
  docs/
```
TOC содержит проверенный Interface, SavedVariables ForeverMemoriesDB, порядок загрузки файлов. Единое пространство имён addonName, ns. Без обязательных библиотек.
## 3. Контракты модулей
API: обёртки возвращают value либо nil,reason; только здесь привязка к клиентским API. Events: один dispatcher, регистрация только поддерживаемых событий; нормализация в {type,key,ts,character,zone,payload}. Registry: описание триггеров и capability. Rules: чистая функция evaluate(event,profile,context) → request или reason. Queue: push/pop/expire/cancel, ограниченная очередь. Engine: один активный request; управление таймерами и результатами. UIState: snapshot/prepare/restore, восстановление только изменённого аддоном состояния. Journal: append/query/update/trim. Profiles: resolve/apply/reset. UI: отображение, не вызывает Screenshot напрямую. Logger: кольцевой буфер 200 сообщений, без приватного чата.
## 4. Машина состояний
IDLE → QUEUED → PREPARING → CAPTURING → WAIT_RESULT → RESTORING → COMPLETED → IDLE. Серия: после восстановления и интервала повторить PREPARING. Ошибка, таймаут, отмена, вход в бой или загрузка: RESTORING → завершение/пропуск. Использовать generation token для отмены устаревших таймеров; callbacks проверяют текущий token. Перед каждым кадром заново проверить состояние и лимиты. Не начинать следующий кадр, пока предыдущий не подтверждён или не истёк таймаут (проектно 5 с). При таймауте не повторять автоматически, пометить unconfirmed, выдержать карантин результатов 5 с; при неоднозначности не приписывать чужой результат своему кадру. Нативные ручные скриншоты клиента могут дать глобальный сигнал без ID: документировать ограничение корреляции, не заявлять абсолютную точность. Восстановление UI идемпотентно; если безопасное восстановление не доказано в клиенте, отключить clean. Никаких бесконечных циклов/постоянного OnUpdate.
## 5. Данные
```
ForeverMemoriesDB = {
 schemaVersion=1,
 settings={enabled=true,locale="auto",notifications=true},
 profiles={Default={rules={},limits={},journey={}}},
 characters={ ["realm:character"]={profile="Default",visited={},firstEvents={}} },
 journal={}, counters={}, ui={}
}
```
Не сохранять секретные/непрозрачные игровые значения. Проверять типы, диапазоны и неизвестные ключи при загрузке. Миграции schemaVersion последовательные, тестируемые; повреждённые ветки заменить безопасными defaults с диагностикой. SavedVariables сохраняются клиентом, не гарантировать запись при аварийном завершении. Счётчики лимитов обновлять по фактическим вызовам съёмки, включая неподтверждённые; статистику успешных кадров вести отдельно. Профили применяются атомарно, активная операция использует snapshot конфигурации.
## 6. Команды
/fm — окно; /fm on, off, toggle — автоматика; /fm shot — ручной кадр; /fm status — состояние; /fm debug — диагностика. Неизвестная команда показывает справку. Горячая клавиша регистрируется через поддерживаемый клиентом механизм.
