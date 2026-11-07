# Продолжение Black & White на Godot

Дата состояния: 7 ноября 2026. Цель пользователя — пройти исходную кампанию
на новом движке, сохранив ощущение оригинала. Работа идёт в **native Godot**,
оригинальный exe во время игры не запускается. Полная реставрация не закончена.

Уточнение цели: некоммерческий фанатский ремейк с узнаваемой основой и
последующей глубокой модернизацией. Файлы оригинала могут требоваться и в
готовой версии; автономный импорт не блокирует выпуск. Контракт Claude —
TASK_CLAUDE_RU.md. Сначала CLEAN_ROOM_RU.md определяет роль/доступ: эта
инструкция содержит legacy research и не передаётся чистому реализатору.

## Текущий checkpoint: Preview 9.1

На 7 ноября origin/main и все удалённые ветки содержали только 7c7358f:
новых изменений после передачи Claude в этом репозитории не было. Продолжена
проверенная база Preview 9. В рабочей ветке fix/preview9-1-physics исправлены
проваливания при окончательном вращении камня, собственные sweep-контакты и
отсутствовавшие коллизии с исходными валунами. Это ремонт legacy-реализации
по геометрическим регрессиям, без заявления о clean-room происхождении.

Preview 9.1 — отдельный collision checkpoint, не сдача Preview 10 с четырьмя
исправлениями. Склады, перенос ресурсов и жест броска остаются открытыми.
Точное пользовательское место проваливания остаётся на проверке; найденные
случаи описаны в BUGS_RU.md. Отчёт — development/preview9.1-verification.json.
Проверены physics12 headless/rendered, hand/world18, gate/key24,
scroll/keeper/key27, port199 и полный rendered opening до первого ключа.
Исходный тест на Preview9 даёт7PASS/5FAIL, тот же probe на9.1 —12PASS.

Для новой сборки сначала используй отдельную папку; `$godot` задаётся
в разделе «Окружение и запуск» ниже:

```powershell
& ./tools/build_preview.ps1 -Godot $godot -OutputDirectory ./build/preview9.1-candidate
```

Normal launcher и ярлык переключаются только после проверки exact exe.
Preview9 сохранена как предыдущая версия. Старые отчёты ниже описывают
историческую проверку9; не переносить их счётчики в новый report как новые PASS.

Для BW-001 подготовлена настоящая Ghidra12.2+Temurin25 portable toolchain
в `%LOCALAPPDATA%/BW-Restoration/Tools`; project и raw evidence находятся
в соседней Research, внеGit. Импорт фактического exe завершён. Отчёт
`cleanroom/research-status-2026-11-07.md` — DRAFT, а не approved спецификация.
Новая изолированная реализация и общая система ресурсов ещё не созданы.

## С чего начать

1. Прочитать `BUGS_RU.md`: там последние замечания пользователя, статус
   каждого пункта и критерии их закрытия. Предыдущие проверки не отменяют баги.
2. Прочитать актуальные разделы Preview 7–9 в `REMASTER.md`.
3. Запустить исходники или собрать Preview 9 командами ниже.
4. После исправлений проверять реальные модели/данные и игровой ввод,
   сохранять изменения в Git. Не заменять исходный сюжет фиктивными флагами.

Репозиторий: https://github.com/VolkMicro/B-W-Remake, удалённая ветка `main`.
На исходном компьютере локальная ветка называется `master`; имена не совпадают.

## Проверенное состояние Preview 9

Работают исходные сценарии вступления первого острова: семья и спасение,
ролик, обучение камерой, путь в деревню, демонстрация дерева, строительство
нейтрального храма, вход в его главный зал, золотой свиток, знакомство с
хранителем, получение и передача первого тигриного ключа на пьедестал,
исходная реакция хранителя и запуск LostBrother. В мире загружаются оригинальные
ландшафт, дома, жители и статические объекты. Есть музыка, голоса и анимации.

Последний проверенный локальный exe: `GodotIsland-village-preview9.exe`, SHA256:
`02C376D866799231EFFB9220A4C3E0BAE543ECB38B8351DA6DCC366870C3D43C`.
Запись проверки сохранена в `development/preview9-verification.json`.
Это происхождение конкретного локального файла; новая сборка может иметь другой
хеш. Готовый exe и локальные логи лежат в игнорируемой папке `build/story-preview`.
Скрипты для её воссоздания включены в Git.

Последний полный автоматический прогон с отрисовкой прошёл до первого ключа
без ошибок движка/скриптов. Он ускоряет время и пропускает медиа; это не ручное
прохождение с обычной скоростью. Отдельно проверен запуск экспортированного exe
с отрисовкой и без неё. Проверки: hand-pose 30, hand/world 18, construction 38,
village workflow 10, source-tutorial workflow 11, gate/key 24, scroll/keeper/key
27, story 100, island 54, port 199. Сообщения `error: {}` внутри строки PASS
не означают ошибку движка; проверять прежде всего строки `ERROR:`/`SCRIPT ERROR:`.

Остальные ключи, LostBrother, ThrowingStones, TheLostFlock, открытие ворот и
полный исходный выбор/обучение существа ещё не восстановлены. Полной кампании,
всей экономики, физики оригинала и импортера ресурсов нет. Старый прототип
существ/обучения не равнозначен подключённому сюжетному прохождению.

## Окружение и запуск

Проверено на Windows с Godot **4.7.2**, соответствующими export templates,
FFmpeg в PATH и оригиналом `C:/Games/Black and White Complete Collection`.
Путь передаётся через `--bw=...` либо `BW_GAME_DIR` у .cmd-запуска.
Для музыки используется собственный `game/bin/bw_audio_decode.exe`; его CC0
исходник и minimp3 включены в Git. Собственные `design/*.json` и сгенерированный
`game/scripts/data.gd` тоже сохранены. Декодер уже включён в checkout; при
необходимости пересобрать из собственного C-исходника через Zig:

```powershell
$zig = 'C:/path/to/zig.exe'
& $zig cc -O2 -std=c99 -I tools/vendor/minimp3 tools/bw_audio_decode.c -o game/bin/bw_audio_decode.exe
```

PowerShell, из корня репозитория:

```powershell
$godot = "$env:LOCALAPPDATA/Microsoft/WinGet/Links/godot_console.exe"
$bw = 'C:/Games/Black and White Complete Collection'
& $godot --path game -- '--story-preview' "--bw=$bw"
```

На другой машине задать путь к своему Godot. Для сборки:

```powershell
& ./tools/build_preview.ps1 -Godot $godot
& ./build/story-preview/Launch-Story-Preview.cmd
```

Сборка экспортирует проект, копирует декодер, инструкции и .cmd-файлы и создаёт
локальный ярлык. Требуются установленные export templates. FFmpeg нужен для
первой подготовки исходного Bink-ролика; его кэш создаётся в user://movie-cache.
Запуск без исходной установки не поддерживается; такая зависимость допустима
и в готовом ремейке. Для текущей сборки установку оригинала сохранять.

`Launch-Village-Test.cmd` ускоренно проходит вступление и возвращает обычное
ручное управление у деревни. `Launch-Key-Test.cmd` делает то же после знакомства
с хранителем; сам ключ не собирает. Они используют исходники и установленный
Godot, а обычный launcher — экспортированный exe. На другой установке Godot
можно задать `BW_GODOT`. Уже открытое старое окно не обновляется после сборки.

## Основные команды проверки

```powershell
& $godot --headless --path game --script res://tests/verify_hand_world.gd -- "--bw=$bw"
& $godot --headless --path game --script res://tests/verify_gate_keys.gd -- "--bw=$bw"
& $godot --headless --path game --script res://tests/verify_citadel_construction.gd -- "--bw=$bw"
& $godot --headless --path game --script res://tests/verify_story_scrolls.gd -- "--bw=$bw" --deliver-key
& $godot --headless --path game --script res://tests/verify_item_contacts.gd -- "--bw=$bw"
& $godot --path game --fixed-fps 15 --script res://tests/verify_opening_runtime.gd -- --story-preview "--bw=$bw" --runtime-automation --runtime-key --runtime-seconds=1300
```

Полный прогон должен вывести `OPENING RESULT PASS`, `TEMPLE VISITED true`,
`DOOR WAIT STABLE true` и `FIRST KEY true bits=2`. Дополнительно проверить лог
на ошибки движка: код выхода 0 сам по себе недостаточен.
Для реальной игры не включать --fixed-fps/--runtime-automation.

Остальные focused tests находятся в `game/tests`; большинство принимают
`--bw=...`. `verify_port.gd`, `verify_story.gd`, `verify_landmark_spawn.gd`
проверяют базовые системы и совместимость bytecode. Изменение design-таблиц
нужно отразить в data.gd через существующий генератор `tools/gen.py`.

## Карта кода и важные ограничения

- `main.gd`: загрузка, ввод, камера, рука, интеграция всех story-компонентов.
- `story_vm.gd`, `story_natives.gd`, `chl_reader.gd`: исполнение исходной LHVM.
  Неизвестные native сохраняют стек и состояние задания; закрывать их заглушкой
  «успех» запрещено направлением проекта.
- `lnd_reader.gd`, `g3d_reader.gd`, `l3d_rig.gd`, `anm_reader.gd`,
  `morph_reader.gd`: оригинальные форматы, signed-scale и отражение оси Z.
  Godot 4 bone pose — parent-local absolute, не дополнительная дельта к rest.
- `story_hand_pose.gd`: hh.HBN/hndspec5, правое отражение по X, точки пальца
  и хвата. `story_wood_hand.gd`: учёт дерева для записанной демонстрации;
  это ещё не общая интерактивная система зерна/дерева.
- `story_world_geometry.gd`: native TriangleMesh BVH видимых поверхностей,
  клиппинг строящегося храма, sweep контактов. `Thing._fly`: приближённая
  физика бросаемых предметов, не полный исходный solver.
- `story_gate_plinth.gd`: только реальные слоты ключей; обычное столкновение
  не засчитывает передачу. Solid hulls пьедестала 336/337/338, ворот 219/220.
- `story_citadel_construction.gd`: реальные ресурсы и animation-cycle work,
  metadata `story_wood_stock` у складов, пауза на 90%, bounded сухопутный A*.
  Это не полный исходный footpath/Hug solver.

Локальное исследование использовало https://github.com/openblack/bw1-decomp
на commit `2fdb8f18212ffb3e1abb59b084587f774155a8a8`, папку
`build/research-bw1-decomp` (не включена в Git), и исходные данные своего
оригинала. Программы анализа находятся в `tools/inspect_host_*.py` и
`tools/dump_story.gd`; Python research packages нужны только для исследования.
Не переносить в проект целиком чужой движок или его распакованные игровые данные.

Последнее исследование новых четырёх ошибок, найденные source offsets и
неподтверждённые гипотезы записаны в `BUGS_RU.md`. Не принимать их за готовые
исправления. В этой Git-передаче игровой код остаётся на проверенном Preview 9.

Перед передачей из отдельного `git archive` собрана копия проекта без прежних
build/research/cache-каталогов. Экспорт, headless и rendered startup прошли
без ошибок. Повторные focused проверки дали hand/world18 и contact probe3.
Результаты этой проверки checkout сохранены в
`development/handoff-2026-11-06.json`; она не закрывает новые пользовательские
баги и не заменяет исторический полный прогон Preview 9.
