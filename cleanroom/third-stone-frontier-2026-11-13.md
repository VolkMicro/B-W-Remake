# Скульптор: следующий реальный блокер

Координаторская запись, не approved packet для независимого реализатора.
13 ноября 2026. Рабочая игровая сборка — Preview9.5; дальнейшее прохождение
по-прежнему останавливается в SetupSculptor/native51/address34914/line35.
Эта запись не означает, что третий камень реализован.

## Продолжение 17 ноября 2026

Историческая граница выше устранена в кандидате Preview9.6. Исходный
TheSculptor проходит до физической доставки subtype51: bits7, три видимых
камня, source flags91/92/93=1. Полный ускоренный rendered input-only маршрут
с начала игры проходит на исходниках и exact exported pack; это не ручное
прохождение. CreaturesInGlade начинается и остаётся pending на native27,
address39763, line735: CREATE(type12, subtype1, позиция marker171).
Ни выбор существа, ни полное открытие ворот пока не заявляются готовыми.
На момент этой записи fresh Git export и активация обычного launcher ещё
предстоят; нормальная проверенная сборка остаётся9.5.

- TS-51-ADAPTER: стабильный handle для каждого объекта; исключение учитывает
  настоящие OBJECT values в globals и locals/stacks живых задач. Завершённая
  диагностическая история не владеет объектами, suspended задачи сохраняют
  ссылки. Это bounded адаптер порта, не доказанная копия original refcount.
- TS-321-FLAG: флаг восприимчивости к огню действительно меняется; зажигание,
  чудеса и расчёт fire damage не реализованы этой командой и остаются отдельной
  границей. Огнестойкость скульптора не выдаётся за готовую систему огня.
- TS-TURNS: проверенные Ghidra quarter-turn commands16/17 и свойства
  heading/pitch/roll в градусах подключены к mirrored Godot transforms.
  CREATE_WITH_ANGLE_SCALE также принимает исходный угол в градусах.
- TS-MUSIC57: подключён установленный Script01.sad из исходной music table.
- TS-BIRDS: native109 получает count20, object type6, subtype12, а не
  type20/subtype6/count12 из ошибочного первого Claude research ответа.
  В установке это mesh5, animation8, clip M_dove_flap с5 bones. Создаются
  все20 настоящих rigs; ID_SIZE считает их, disband освобождает контейнер.
  Радиус14 и angular speed0.35 — явно новая визуальная политика порта;
  обычный animal AI и точная траектория оригинальной стаи не восстановлены.
- TS-CRAFT: quarry50 теперь переносимый rock; source принимает его рядом с
  живым скульптором, блокирует перенос на время работы, ждёт60s, удаляет blank
  rock и создаёт51. Получение награды не засчитывает доставку на пьедестал.

Новый OrbitActors получен неизменённым по approved v3 packet от отдельной
tool-less remote-модели; review/implementation manifests лежат рядом с packet.
Standalone2778 и installed birds18 headless/20 rendered checks PASS.
Native/VM/factory/animation adapters остаются coordinator/legacy работой.
Новые Ghidra references/scene/properties passes завершились exit0/save.
Raw exports, ошибочные первые probes, ответы и hashes остаются вне Git.

Приватные source listings, Ghidra exports и manifest —
`%LOCALAPPDATA%/BW-Restoration/Research/ThirdStone`. Проверен тот же установленный
exe SHA256 525a6a31ba208ebace5365a10f6afc76c7a76f138722e132b838a2c2c71f1054.
Ghidra12.1.4/JDK21: native-pass и typed query-pass завершились exit0 с save.
Ниже TS-* — локальные observation IDs, не evidence IDs Craft Anything.

- TS-ROUTE: SetupSculptor повторяет CALL_NEAR для rocks33/subtype5000,
  radius30, exclude-scripted=true и запускает KeepRockScripted для каждого
  результата. Без корректного владения объектами нельзя просто разрешить true:
  цикл может бесконечно возвращать один и тот же камень.
- TS-51: registry подтверждает native51:7 аргументов/1 результат. Wrapper
  выбирает разные predicate callbacks по последнему boolean. Exclusion callback
  отклоняет объект при ненулевом результате его virtual method; обычный callback
  вызывает дополнительный фильтр и проверку расстояния. Для query types8 и33 используется
  общий поисковый callback. Это статические наблюдения, не запуск оригинала.
- TS-HANDLES: оригинальная выдача script handle проверяет уже существующую
  связь объекта и пытается вернуть прежний handle. Текущий register_object
  порта всегда выдаёт новый ID, а каталог кандидатов заранее содержит объекты
  сцены. Нельзя считать весь этот каталог «занятым сценарием».
- TS-OWNERSHIP-OPEN: точный жизненный цикл scripted references ещё не проверен.
  Возможный adapter — учитывать реальные OBJECT refs в globals/live tasks и
  отдельно хранить каталог кандидатов. Это **проектное предположение**, не
  утверждённая реализация или доказанная полная копия original reference count.
- TS-321: registry321:2 аргумента/0 результатов; wrapper меняет флаг объекта.
  Реальные fire damage paths и применимость к actor types ещё не исследованы.
  Нельзя выдать пустое ok=true за поддержку огня.322/323 в текущих выбранных
  CHL listings маршрута не встречаются; изученные wrappers не требуют их порта.

Ожидаемые следующие зависимости по исходному CHL: показ scroll20, анимации
скульптора, исходный quarry rock50, видимый progress object58, доставка камня
к скульптору, source timer60s, превращение в subtype51, физическая доставка
третьего ключа. Порт ещё не поддерживает весь этот маршрут. Blank rock50 в
текущем spawn использует scenery category; его реальную переносимость и
source gating необходимо проверить, прежде чем заявлять готовность.

Claude помог с исследовательской картой по явным raw CHL listings. Первая
readonly сессия исчерпала16 turns без отчёта; затем свежий tools0/MCP0 запрос
вернул отчёт (broker run35c23b12aee64c29a668ddd8c5a3da0a, observed calls0).
Роль — researcher/coordinator, без clean implementation claim. Его выводы
проверяются: например, native320 уже привязан, вопреки предположению отчёта;
порядок аргументов нельзя переносить без сверки с текущим VM CALL_SCRIPT.
Вводы/ответы не передаются независимому реализатору и не включаются в Git.
