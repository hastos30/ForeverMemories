# ForeverMemories

Аддон для **World of Warcraft: Forever**: сам делает скриншоты важных моментов
(новый уровень, новая зона, босс, эпическая добыча и другие) и ведёт журнал воспоминаний.

Версия **0.4.2-beta**: вся функциональность ТЗ собрана, логика покрыта офлайн-тестами,
но в игровом клиенте проверены только ручной снимок и базовый API (v0.0.1).
Ход работ: [PROGRESS.md](PROGRESS.md). Техническое задание: [docs/](docs/).

## Установка
В папку `World of Warcraft/_forever_/Interface/AddOns/ForeverMemories/` нужны:
```
ForeverMemories.toc
Bindings.xml
Core/  Capture/  Modules/  UI/  Locales/
```
`tests/` и `docs/` игре не нужны. Для разработки удобно сделать ссылку:
`ln -s ~/projects/ForeverMemories ".../_forever_/Interface/AddOns/ForeverMemories"`.

## Как пользоваться
- При первом входе выберите пресет (можно позже во вкладке «Профили»).
- `/fm` — основное окно; кнопка у миникарты: ЛКМ окно, ПКМ пауза, СКМ кадр.
- `/fm shot` — ручной кадр, `/fm on` / `/fm off` — автосъёмка.
- `/fm status`, `/fm debug`, `/fm log` — диагностика.
- `/fm ui` — вернуть интерфейс, если он вдруг остался скрытым после «чистого» кадра.
- Горячие клавиши: Esc → Options → Keybindings → AddOns → ForeverMemories.

Скриншоты сохраняет сама игра в `_forever_/Screenshots`. Аддон не может показывать,
переименовывать или удалять файлы — журнал хранит только записи.

## Тесты без игры
```
lua5.1 tests/run.lua
```
