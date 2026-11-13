# Продолжение Black & White на Godot

Дата состояния: 13 ноября 2026. Цель пользователя — пройти исходную кампанию
на новом движке, сохранив ощущение оригинала. Работа идёт в **native Godot**,
оригинальный exe во время игры не запускается. Полная реставрация не закончена.

Уточнение цели: некоммерческий фанатский ремейк с узнаваемой основой и
последующей глубокой модернизацией. Файлы оригинала могут требоваться и в
готовой версии; автономный импорт не блокирует выпуск. Контракт Claude —
TASK_CLAUDE_RU.md. Сначала CLEAN_ROOM_RU.md определяет роль/доступ: эта
инструкция содержит legacy research и не передаётся чистому реализатору.

## Текущий checkpoint: Preview 9.5 — 13 ноября 2026

Source commitafb3e9d. Exe: `build/story-preview/GodotIsland-village-preview9.5.exe`,
SHA256 `342AB0F102E9B343A0AFE792336A4E48EB83BA6F808358389F8BFE36AC3BE4A6`.
Отчёт: development/preview9.5-verification.json. Preview9.4 сохранён.

Пользователь сообщил, что все свитки и подсказки не нажимаются обеими кнопками.
Воспроизведён конкретный блокер: отпускание Shift во время ролика терялось,
а handover не сбрасывал Shift, оставляя Action закрытым для всех трёх типов.
Теперь release учитывается до GUI/cinematic gates, а focus loss и handover
сбрасывают жесты без сброса/броска предмета. Точный исходный жест пользователя
не был записан; это доказанная причина такого симптома, не всеобщая гарантия.

Вторая ошибка: DYK entries с текстом, но без voice sample, молча отбрасывались.
Теперь исходный caption выводится в новой карточке. Закрытие: «Продолжить»,
Escape или ПКМ вне карточки. Пока она открыта, камера/мировые действия заблокированы.
Язык текста берётся из установки. Main/HUD/OriginalDialogue — legacy/coordinator
adapters, без нового clean-room заявления.

Exact-pack:11 focused headless прогонов396 checks, rendered input43 PASS,
все11 DYK и длиннейший текст при1600x900/1280x720/1024x768. Input тест проходит
через настоящий viewport/GUI, а не прямой вызов _unhandled_input. Exported startup
headless/rendered и fresh Git export/input42/LostBrother58/оба startup PASS.
Rendered full opening повторён до второго камня: bits3/journal.5/camera0 PASS.
Это ускоренный тест с пропуском медиа, не ручное прохождение. Engine/script errors0.
Fresh headless forced-exit по-прежнему иногда предупреждает о4 ObjectDB instances.

Следующий рубеж сохраняется: SetupSculptor/native51/address34914/line35,
поиск незанятых сценарием камней, затем третий камень и реальный выбор существа.
Приватные CHL listings — Research/ThirdStone; первый read-only Claude review
исчерпал16 turns без отчёта, отдельный tool-less research review завершён.
Ghidra native/query passes exit0/save, результаты и открытые вопросы —
cleanroom/third-stone-frontier-2026-11-13.md. Не приписывать им готовую
реализацию. Нормальный launcher переключён на9.5 после
проверок, старые окна требуется закрыть и запустить заново.

## Предыдущий checkpoint: Preview 9.4 — 11 ноября 2026 (история)

Source commit4d2460d. Exe: `build/story-preview/GodotIsland-village-preview9.4.exe`,
SHA256 `BA4AC5D63F015FDB8DA37FC06D71E8D3D1EEDE5123766967B775B96B7AB213A5`.
Отчёт: `development/preview9.4-verification.json`. Preview9.3 сохранён.

Пройден исходный путь до **второго установленного камня**: scroll19 LostBrother,
раненый живой брат, animation253, перенос к сестре, воссоединение, GiveReward,
получение существующего subtype49 и доставка рукой на пьедестал. Итог:
bits3, два физических камня, journal55=0.5, flags91/92=1 и93=0, камера0.
Награда не засчитывается до доставки; quest flags не подменяются.

Добавлены10 bounded native bindings (всего145), Track39, здоровье/защита,
source wander parameters, исходная музыкальная тема59. Исправлены подсветка
анимированного брата, следование influence за актёром, NULL cleanup и fade
удаляемых персонажей. Новая погода получена от tool-less Claude по reviewed
v3 packet; модуль не менялся, адаптеры остаются coordinator/legacy.
Разбор Ghidra и границы точности — cleanroom/second-stone-observations-2026-11-11.md.

Exact exported pack:15 focused headless прогонов982 checks, rendered weather284
и LostBrother58, полный opening до второго камня PASS. Ускорение4x, fixed-fps15,
медиа пропускается; это **не ручное прохождение**. Exact exe startup headless/
rendered PASS. Fresh git archive4d2460d: export, LostBrother58 и оба startup PASS.
Engine/script errors0. В headless forced-exit startup встречается предупреждение
о4 ObjectDB instances; gate/scroll teardown тоже иногда сообщает2/4, не скрывать.

Обычный запуск — Launch-Story-Preview.cmd. Новый Launch-Second-Stone-Test.cmd
автоматически проходит первый камень и передаёт обычное управление для спасения
брата. Он использует исходники/установленный Godot, без искусственного checkpoint.
Далее: золотой свиток у дома → ПКМ поднять брата → медленно опустить рядом с
сестрой → дождаться награды → доставить камень на пьедестал.

Точная граница продолжения: TheSculptor стартует, SetupSculptor останавливается
на native51 (bytecode34914, line35). Стек и bytecode остаются pending. Третий
камень, ворота и выбор существа не завершены. Следующий координатор продолжает
эту реальную операцию; новый independent worker получает только approved packet.
Bezier camera, wander, погода/частицы/ветер, fade2s и часть физики приближены.
Остальные ограничения Preview9.3, включая aftertouch/feel, сохраняются.

## Предыдущий checkpoint: Preview 9.3 — 11 ноября 2026 (история)

Source commit 9c3324e. Exe: `build/story-preview/GodotIsland-village-preview9.3.exe`,
SHA256 `05A67FEDE7EFE107BA7FFBD060270C750616AAB8FEECB4A4380F0EE7B4993FFE`.
Отчёт с командами/ограничениями: `development/preview9.3-verification.json`.
Normal launcher переключён только после startup и relevant exact-pack tests.
Preview9.2 сохранён. Это следующий checkpoint, не полная приёмка Preview10.

Перенесены Action-сбор/остановка/возврат зерна и дерева, реальные количественные
кучки, исходные hand meshes/poses, видимый поток и бросок жестом. Склады,
стройка, рука и кучки используют один stock. При медленном сбросе предмет
падает из grip без переноса к отдельной точке земли. Масштаб упавшей кучки
не зависит от камеры. Колесо/WASD/QE отменяют случайный бросок от движения камеры.

Рука больше не имеет постоянной ширины76px и не компенсирует движение
анимированного пальца. Bounded source laws: радиальная глубина, scale,
нормализация по bind-bone span555.294372558594, absolute-cursor lag80px,
gain20, pow(.03,dt), линейное смешивание поз за0.13с. FOV70 horizontal;
aspect-correct widescreen — явная политика порта. HND+28 **не доказан** как
hand root/contact, не возвращать прежнее присваивание этого поля положению руки.

Новые independent модули: ResourceHand/ResourceStream353, HandMomentum133,
HandSurfaceMotion124, HandPointerDynamics74 checks. Packets/reviews/manifests
в cleanroom/specs. Tool-less Claude2.1.311 работал со свежими запросами,
tools/MCP пустыми; это граница возможностей модели, не OS-sandbox и не
сертификация main/StoryHandPose/geometry/resource/adviser adapters.
Follow-up research использовал Ghidra12.1.4/JDK21; raw — вне Git.

Проверено:14 focused прогонов1345 checks; native-input resource55 headless,
57 rendered exact pack; hand-world20; actual storage25 rendered; advisers32
при максимальном zoom и трёх пропорциях окна. Exported opening PASS:
обучение, построенный храм, стабильное ожидание двери, вход, хранитель,
первый ключ и его установка(bits2). Это ускоренный fixture с пропуском медиа,
не обычное ручное прохождение. Exact exe startup headless/rendered PASS.
Fresh Git archive9c3324e: export, resource55 и оба startup PASS, без копирования
build/cache/research. Gate fixture имеет известный teardown warning2 objects;
engine/script errors0.

Пользователь подтвердил захват в обычной диагностической сцене до последнего
исправления движения. Полный новый feel с запущенным оригиналом не сравнивался.
Частицы, размер ресурса в руке, часть object/special-state paths, aftertouch
и полная физика остаются приближёнными/неперенесёнными. Случай freeze помощников
при zoom с тем же aspect не воспроизведён; исправлена screen placement при resize.

Управление: ЛКМ — камера; ПКМ — Action/свиток/дверь; СКМ или Shift — rotation;
колесо — zoom. Сбор: holdПКМ, release оставляет ресурс, следующий Action
передаёт/сбрасывает. Бросок: второй holdПКМ, движение, release.
Быстрая обычная сцена руки: `build/story-preview/Launch-Hand-Test.cmd`.
Она диагностическая, не замена сюжету. `Launch-Village-Test.cmd` возвращает
ручное управление у сюжетной деревни. Открытые старые окна не обновляются.

Следующее: сравнить ordinary hand/camera/object feel с реальным оригиналом,
не подменяя это численными PASS; уточнить source gating и additive reference.
Проверить исходный пользовательский эпизод BW-003. Продолжать первый остров:
остальные ключи/задания, ворота и настоящий выбор существа. Неперенесённый native
должен оставлять bytecode pending и сообщать действительную операцию.

## Предыдущий checkpoint: Preview 9.2 (история)

Восстановлено видимое заполнение обоих складов первого острова: исходное зерно,
пять моделей древесины, настоящие ExtraMetrics anchors и единый stock для
склада, строителей и givewood-демонстрации. Уровень плавно меняется при расходе;
пустые кучи скрываются. Начальные food20000/wood30000 сохраняются полностью,
включая overflow сверх визуального номинала. Это промежуточный storage checkpoint,
не завершённый Preview10: ручной сбор/возврат и жест броска ещё впереди.

Source commit: cf74fad. Проверенный exe: GodotIsland-village-preview9.2.exe,
SHA256 `7B7183ABCA04D81C9BA84884A5959B9D3C1D206F12790A6F441534A579C4FFE6`.
Отчёт: development/preview9.2-verification.json. ResourceStore161 и
StockPilesView149 synthetic PASS; actual storage22 headless/25 rendered PASS.
Повторены construction38, workflow10/11, hand30/world18, key24, contacts12,
scrolls27, port199. Старые key/scroll fixtures дают teardown ObjectDB warnings2/4;
новых engine/script errors нет. Rendered opening на exported pack прошёл до
первого ключа с temple/door/keeper/key true; он ускорен и пропускает media.
Отдельно exact exe startup headless/rendered и fresh Git-source build/startup PASS.
Это не ручное прохождение с обычной скоростью.

Normal Launch-Story-Preview.cmd и локальный ярлык указывают9.2. Для быстрого
попадания к деревне — build/story-preview/Launch-Village-Test.cmd, затем
приблизить склад; нового ручного сбора в этой версии нет. Preview9/9.1 сохранены.

```powershell
& ./tools/build_preview.ps1 -Godot $godot -PreviewVersion 9.2 -OutputDirectory ./build/preview9.2-candidate
& $godot --headless --path game --script res://tests/verify_storage_piles.gd -- "--bw=$bw"
```

Новое происхождение ограничено двумя модулями: exact approved packets,
отдельные tool-less Claude requests и manifests в cleanroom/specs. Parser,
main и construction adapters остаются coordinator/legacy-кодом; весь repo не
сертифицирован clean-room. Граница remote-модели описана в CLEAN_ROOM_RU.md.
Для BW-002 подготовлен resource-hand-observations-draft.md и отдельный research
review; утверждены только bounded static observations. Нужен отдельный
implementation packet и дальнейшая интеграция.

## Предыдущий checkpoint: Preview 9.1 (история)

Следующий блок описывает прежний checkpoint, а не текущий статус ресурсов.

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
