# Следующая граница: автономное желание существа

Роль — coordinator/integrator с доступом к legacy и raw research. Это отчёт
исследования, **не approved packet** для независимого реализатора.
Оригинальная установка и приватные Ghidra exports в Git не включены.

Новый rendered input-only маршрут на hint candidate снова прошёл три настоящих
камня, два Action по корове и исходную home cinema с fade0. Команда
CreatureDevSeeHome/native188/address6441/line512 остаётся pending:
SET_CREATURE_ONLY_DESIRE(selected,27,86400.0). Полный run завершился exit1;
это подтверждение реального frontier, а не PASS оставшейся кампании.

## Что уточнено статически

- Вспомогательная операция имеет два stack arguments и RET8. Исправление ABI
  убрало ошибку декомпилятора, который путал duration и mode.
- Override и development mask — разные состояния. Установка выбирает один
  индекс из40 и сбрасывает счётчик; отключение использует sentinel40.
- Подавляются не все остальные желания: есть исключения и отдельный mode.
  Подавление сохраняет максимум существующего и нового срока.
- Найден участок счёта времени: целые turns переводятся через текущий
  turn duration, сравнение срока строгое `>`. Не объявлять его непрерывным
  секундным таймером без проверки tick gates и countdown.
- Найден кандидат селектора, читающий enabled flags, suppression counters
  и scores. Это ещё не восстановленный выбор действия в Godot.
- В установленной последовательности40 описаний индекс27 подписан Sadness,
  отдельно есть действие BeSad. Их точная связь с runtime tables/dispatch
  ещё не доказана. Строки описаний сами по себе не разрешают выбрать анимацию.

Raw instructions и таблицы исследованы Ghidra12.1.4/JDK21 в read-only проекте
на прежнем exe SHA525a6a31…f1054. Craft ledger содержит реальные evidence IDs
для ограниченных byte/disassembly проверок; внешние exports учитываются
собственным приватным hash manifest и не выдаются за Craft evidence.

## Проверка Claude и ошибки, которые нельзя переносить в реализацию

Шестой tools0/MCP0 запрос завершился как research reviewer с raw observations,
без продуктового кода. Ответ остаётся NOT APPROVED. Capability manifest
сохранён в development/claude-desire-followup-2026-11-17.json.

Рецензент ошибочно назвал одну запись конструктора начальным selected40:
сырые смещения указывают другое поле. Декомпиляция следующего helper всё ещё
теряет pointer receiver; raw имеет приоритет. Гипотеза о расположении
action table непосредственно перед найденными описаниями дала нулевой ряд
и отвергнута как основание для поведения.

Нужна ограниченная цепочка forced desire → выбор действия → наблюдаемое
поведение после release, а не полный AI перед любым следующим шагом.
Пока нет проверенной цепочки, native188 не связывается с пустой записью,
песочничным help/scare, произвольной грустной позой или искусственным PLAYED.

Следующие пробы: выровнять file/runtime record layout и table loader;
проследить источник желания и action dispatch; уточнить release/PLAYED и
условия ticking. Адресные детали и rejected hypotheses остаются в приватном
Research/CreatureHomeDesire и актуальном Craft handoff.
