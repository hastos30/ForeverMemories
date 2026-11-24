# Changelog

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), версии: [SemVer](https://semver.org/lang/ru/).

## [0.0.1] — 2026-11-24

Проверено в клиенте World of Warcraft: Forever 1.60.1 (71037): см. API_COMPATIBILITY.md.

### Added
- Минимальный TOC для World of Warcraft: Forever (`Interface: 16001` по документации, требует подтверждения).
- Ручной снимок `/fm shot`: одна операция за раз, результат только по `SCREENSHOT_SUCCEEDED/FAILED`, иначе `unconfirmed` через 5 с и карантин 5 с.
- `/fm status`, `/fm debug`, `/fm log` для диагностики.
- Проба API: наличие функций, регистрация событий-кандидатов, счётчики срабатываний (без payload).
- SavedVariables `ForeverMemoriesDB` с проверкой типов и восстановлением повреждённых данных.
- Офлайн-тесты логики на mock API (`lua5.1 tests/run.lua`).
- PROGRESS.md, API_COMPATIBILITY.md.
