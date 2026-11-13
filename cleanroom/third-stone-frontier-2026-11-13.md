# Скульптор: следующий реальный блокер

Координаторская запись, не approved packet для независимого реализатора.
13 ноября 2026. Рабочая игровая сборка — Preview9.5; дальнейшее прохождение
по-прежнему останавливается в SetupSculptor/native51/address34914/line35.
Эта запись не означает, что третий камень реализован.

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
