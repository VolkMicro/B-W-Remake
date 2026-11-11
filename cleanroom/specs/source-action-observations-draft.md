# Source Action/Move и вход в храм — observations 0.1

**DRAFT: требуется отдельный review. Не продуктовая реализация.**

Исследователь `/root/resource_hand_research`, 7 ноября2026. Роль имеет доступ
к legacy checkout/research; чистому реализатору этот контекст не передаётся.
Ни оригинальная игра, ни её input loop в этом шаге не запускались.

## Источники и граница

Исследован фактический установленный executable, SHA256:
`525a6a31ba208ebace5365a10f6afc76c7a76f138722e132b838a2c2c71f1054`.
Ghidra12.2/JDK25.0.5+8, существующий hash-guarded project. Три bounded-прохода
по8,7,4 входа:19 успешных экспортов,0 failed, три save succeeded/exit0.
Охват: defaults, считывание mouse codes, display labels, profile override,
события Win32/LHMouse, entrance tap/validation и начало перехода в интерьер.
Общая autoanalysis и выполнение кода оригинала не производились.

Названия кандидатов из legacy hints использованы только исследователем;
решающие значения проверены в настоящих машинных инструкциях. Низкоуровневые
адреса/код остаются в private Research, в этот draft не включены.

Evidence IDs:

- `ACTION-STATIC-20261107-A`: первый bounded-проход8
  функций defaults, input states, profile overrides, temple tap/validation.
- `ACTION-STATIC-20261107-B`: второй bounded-проход7 функций, включая
  mouse-code labels, LHMouse и edge helpers.
- `ACTION-STATIC-20261107-C`: третий bounded-проход4 функций, Win32 mouse
  messages, keyboard-state aliases, text helper и temple transition.
- `ACTION-LABELS-20261107-A`: установленный UTF16 InfoScript2.txt, полный
  порядок6974 ADD_TEXT независимо от первого аргумента0/1; соответствие
  численных text IDs наименованиям Move/Action/LMB/RMB/MMB.
- `ACTION-PROFILES-20261107-A`: installed Profiles вместе с Backup
  рекурсивно не содержат файлов. Это ограниченный поиск только этой установки.
- `ACTION-TEXT-20261107-A`: исходные CITADEL_GUIDE_03,
  NEW_INTERFACE_05, INTERFACE_LOOK_AT_SKY_01..06 и control label IDs.
- `ACTION-LEGACY-CAMERA-20261107-A`: чтение legacy CameraModeNew3 при поиске
  контекста camera combinations. Помечено отдельно: весь большой camera
  update не был независимо проанализирован в этом бинарном проходе.

SHA256 InfoScript2.txt:
`2a393be70fc107752c994b9272cb3e45ae366ecdfd19daf86adb328adb13c1d4`.
Raw и manifests только в `%LOCALAPPDATA%/BW-Restoration/Research`:
`raw/ACTION-static-A`..`C`, `action-*-console.log`, `action-labels.json`,
`action-research-evidence-manifest.json`. Не включать их в Git/packet.

## Установленная default схема

**Move — ЛКМ, Action — ПКМ.** Это результат цепочки из executable defaults,
исходных display labels и Win32 button messages; не догадка по `$m2`.

| Семантика | Default control mapping | Физическое соответствие обычной Windows-схемы |
| --- | --- | --- |
| Move | Отдельное bindable действие, mouse-code1 | ЛКМ |
| Action | Отдельное bindable действие, mouse-code5 | ПКМ |
| Tilt/Rotate Around Mouse On | mouse-code2 при наличии третьей кнопки | СКМ, удержание колеса |
| Tilt/Rotate On | keyboard code0x36, mouse-code0 | Shift; reader принимает обе Shift |

Связь названий проверена независимо:

- Default Move получает label HELP_TEXT_ACTIONS_SELECT, численный textID2652.
- Default Action получает HELP_TEXT_ACTIONS_APPLY, textID2653.
- Mouse-code1 использует HELP_TEXT_ACTIONS_LEFTMOUSEBUTTON, textID2680=LMB.
- Mouse-code5 использует HELP_TEXT_ACTIONS_RIGHTMOUSEBUTTON, textID2681=RMB.
- Mouse-code2 использует HELP_TEXT_ACTIONS_MIDDLEMOUSEBUTTON, textID2682=MMB.
- Windows left-down сообщение создаёт heldmask1, right-down — heldmask2,
  middle-down — heldmask64. Считывание кодов1/5/2 использует именно эти маски.

Keyboard0x36 соответствует правой Shift в scan-code naming; фактический
reader объединяет0x2a и0x36 и проверяет обе Shift. Поэтому для пользовательской
подсказки корректно «Shift», а не искусственное ограничение только правой.
В ветке отсутствия третьей кнопки действие Around Mouse получает keyboard
code0x0b, соответствующий0 в этой scan-code карте, вместо mouse-code2.
Эту fallback-ветку на настоящей двухкнопочной мыши не проверяли.

Evidence: STATIC-A/B/C, LABELS-A. Системная смена кнопок для левши и реальные
переназначения пользователя в работающем original не исследованы.

Профиль может заменить defaults: загрузка сперва устанавливает defaults,
затем читает тройку пользовательских значений key/modifier/mouse для каждого
действия. В этой installed Profiles файлов нет. Поэтому выше **default схема
проверенного exe**, не сертификат любой пользовательской настройки.

## Rotate/Pitch и обе основные кнопки

Обычная ПКМ — Action. Привязывать к ней одновременно постоянный rotate/pitch
означает создавать конфликт с исходным взятием/сбором/применением предметов.
Default Around Mouse имеет отдельный MMB binding, а Tilt/Rotate — Shift.

Legacy camera update показывает: Around Mouse читает движение мыши и меняет
heading/pitch. Нажатие обеих основных кнопок включает zoom-landscape: движение
вверх/вниз меняет zoom, горизонтальное движение после порога может давать
поворот. Исходная подсказка NEW_INTERFACE_05 отдельно описывает zoom обеими
кнопками. Это **legacy camera observation + original text**, а не утверждение,
что весь camera update уже сверён с этим executable/реальным вводом.

Для текущего ремейка полезный подтверждённый минимум — MMB rotate/pitch,
LMB Move, RMB Action. Полный chord/Shift/edge-tilt behavior требует отдельного
контракта и теста; нельзя переименовать собственную простую схему в полную
копию source camera. Исходные LOOK_AT_SKY подсказки также используют Move у
границы экрана для изменения угла; это отдельное camera behavior.

## Вход в храм

Исходная подсказка CITADEL_GUIDE_03 говорит применить **Action к входу**.
Она не требует double-click. Проверенный entrance tap entry:

- работает с entrance, связанным со своим храмом;
- проверяет владение и локальный interface/player;
- вызывает переход в интерьер;
- не содержит собственного double-click counter/condition.

Это подтверждает «tap/action на вход» как правильный semantic API. В сочетании
с подсказкой достаточно оснований использовать один Action click для входа
в ремейке и не требовать двойного Move click. Точная временная граница tap
(press/release, длительность и приоритет held-object) во всём original
dispatcher этим bounded-проходом **не установлена**. Отсутствие double-click
в entrance callback не является доказательством отсутствия такой проверки
в любой внешней ветке движка.

Evidence: STATIC-A/C, TEXT-A. Реальное нажатие в original и визуальный тест
положения door-hit ещё нужны для полного поведенческого сравнения.

## Fixtures для следующей реализации/проверки

Это предлагаемые проверки source-compatible bindings, не выполненные tests:

- Пустая рука: LMB drag двигает камеру, не поднимая предмет и не активируя свиток.
- RMB tap по свитку вызывает Action; LMB tap не дублирует это действие.
- RMB hold по resource pile начинает/продолжает сбор; отпускание прекращает
  сбор, оставляя реальный запас в руке.
- Single RMB click по входу своего готового храма вызывает вход один раз.
- MMB drag меняет yaw/pitch; одиночный RMB без MMB не поворачивает камеру.
- Camera chord, если подключён, получает приоритет и не должен оставлять
  отложенный случайный Action/throw при отпускании одной кнопки.
- Проверить tutorial ограничение интерфейса: его camera learning inputs
  должны использовать исправленные bindings и не зависнуть на старом RMB rotate.
- Проверить переназначенную/леворукую схему отдельно, если port начнёт читать
  original profile settings; текущий факт defaults этого не реализует.

Подтверждены defaults и ограниченная entrance tap логика. Полный original
input dispatcher, camera solver, chord priority и manual original play пока
не заявляются восстановленными.
