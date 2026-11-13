# Состояние передачи Claude

## Цель и основа

- Некоммерческий фанатский ремейк на Godot; файлы оригинала допустимы
  и в готовой версии. Цель и этапы — PROJECT_RU.md.
- Проверенная игровая основа — Preview9.5, source commitafb3e9d.
  Second-stone checkpoint9.4 —4d2460d.
  Hand checkpoint9.3 —9c3324e.
  Storage checkpoint9.2 — cf74fad.
  Collision checkpoint9.1 — a061205.
  Исторический checkpoint передачи — dce3b21 (Preview9).
- Первое задание — Preview 10 по TASK_CLAUDE_RU.md.
- Основной checkout/старые исследования — legacy, без заявления
  о доказанном clean-room происхождении.

## Состояние 13 ноября: свитки и DYK

Ремонт main/input/HUD и OriginalDialogue остаётся coordinator/legacy работой.
Новых independent модулей нет. Воспроизведён потерянный Shift release во время
cinematic, блокировавший все три типа свитка. Global release и cleanup после
focus loss/handover не создают броска. DYK текст берётся из уже читаемой
установки; отсутствие voice sample больше не скрывает caption. Новая карточка
не заявляется точной копией renderer оригинала. Исходных текстов в Git нет.
Exact viewport42/rendered43,11 focused396, полный opening до второго камня,
exact startup и fresh Git export/input42/rescue58/startup PASS. Отчёт9.5.
Первая readonly Claude research сессия по ThirdStone исчерпала16 turns без
итогового отчёта; отдельный tools0 research prompt имеет исследовательскую
роль и не является approved implementation packet. Второй review завершён;
Ghidra native/query passes exit0/save. Проверенные границы и несверенные
выводы Claude — third-stone-frontier-2026-11-13.md. Native51 ещё pending.

## Предыдущий checkpoint 11 ноября: второй камень

Исходный LostBrother/GiveReward проходит до физической доставки второй награды,
bits3, journal55=0.5 и возврата камеры. Новый WeatherZone получен от свежего
tool-less Claude по reviewed v3 packet; manifest содержит exact input/result
hashes и observed tool uses0. Модуль не менялся; test fixture перенесён после
входа в SceneTree, как требует API. Headless279/rendered284 checks PASS.
Legacy-native/health/camera/highlight/influence/fade adapters не имеют новой
clean-room сертификации. Routine Claude редактировал тест в legacy checkout;
не смешивать его роль с independent weather worker.

Ghidra static exports и167-file hash manifest остаются вне Git. Проверены
weather setter/lifetime, native NULL/cleanup, property1/6, animation253/state200
и cue59. Публичные границы — second-stone-observations-2026-11-11.md.
Полный exact-pack opening,15 focused982, rendered LostBrother58, exact startup,
fresh Git export/LostBrother58/startup PASS; отчёт development/preview9.4-verification.json.
Это ускоренный тест с пропуском медиа, не manual playthrough. Иногда forced-exit
headless/старые fixtures дают ObjectDB warnings2/4. Следующий настоящий блокер:
SetupSculptor native51; bytecode pending. Третий камень и полная кампания не готовы.

## Предыдущий checkpoint 11 ноября: hand/interaction

Новые packets ResourceHand, HandMomentum, HandSurfaceMotion и HandPointerDynamics
имеют exact-hash review и отдельные implementation manifests. ResourceHand и
ResourceStream прошли353 synthetic checks, Momentum133, Surface124, Pointer74.
Все получены свежими tool-less Claude CLI2.1.311 запросами без tools/MCP,
resume, source checkout или raw research. Проверенный probe7 ноября применим
к тем же CLI/flags; отдельный worker имеет служебную provider envelope с
зафиксированными типами полей. Credentials не копировались. Это ограничение
доступа модели, не изоляция broker/OS и не clean provenance всего репозитория.

Координатор интегрировал source defaults мыши, реальные resource profiles/meshes,
единый stock, потоки, обычный сбор/drop/regather/return и gesture release.
Main/StoryHandPose/HostInfo/StoryResourceInteraction/geometry/adviser adapters
остаются legacy/coordinator. Ghidra follow-up выполнялся portable12.1.4/JDK21
на checked installed exe; reviewed drafts различают ordinary motion, bind span,
cursor lag, frame-based scheduling, linear pose blend и неизвестные ветки.
Проверки static/instruction/numeric — не исполнение оригинала.

Exact9.3 exe прошёл headless/rendered startup, matching-engine exact-pack scenes
resource57/world20/storage25/adviser32 и opening до установленного первого ключа.
Fresh git archive9c3324e export/resource55/startup PASS. Подробности и SHA256 —
development/preview9.3-verification.json. Preview9.2 сохранён. Кампания, полная
приёмка Preview10, aftertouch, special hand/object states и точный BW-003 ещё
не завершены. Переходы частиц и hand-pot presentation остаются remake policy.

Raw evidence новых follow-up и manifests находятся в локальном Research вне Git.
Часть старых private run/cache материалов7 ноября в снимке среды11 ноября
отсутствует; публичные hashes/manifests сохраняются. Это не повод приписывать
старые прогоны текущей сборке: в отчёт9.3 внесены выполненные здесь проверки.
Не клонировать OAuth state и не передавать contaminated checkout реализатору.

## Состояние 7 ноября до Preview9.3 (история)

| Шаг | Состояние | Следующее действие |
| --- | --- | --- |
| Инструкции и критерии | Подготовлены | CLAUDE.md, TASK_CLAUDE_RU.md, CLEAN_ROOM_RU.md |
| Ghidra нового задания | Portable12.2/JDK25; import и bounded storage-проходы 9+14+11 | Static evidence; original manual play не выполнен |
| Граница реализатора | Tool-less remote model; probes/positive control пройдены | runner-probe-2026-11-07.json; это не OS-sandbox |
| Approved packets | ResourceStore v1 и StockPilesView v1 | Exact SHA256 в specs/*.review.json |
| Новые модули | ResourceStore161PASS; StockPilesView149PASS | Manifests в specs; coordinator adapters отдельно |
| BW-001: склад | Вид и единый stock интегрированы;22 actual checks/25 rendered | Ручной сбор/возврат ждёт BW-002; пункт открыт |
| BW-002: перенос ресурсов | Открыт | Критерии — TASK_CLAUDE_RU.md |
| BW-003: коллизия камня | Пять регрессий исправлены в9.1 |12PASS headless/rendered; пользовательский точный эпизод остаётся на проверке |
| BW-004: жест броска | Открыт | Есть прототип автобаллистики; исходного жеста нет |
| Preview 10 | Не собран | Промежуточный9.2 candidate: storage view; BW-002/004 впереди |

## Выполнено 7 ноября

Аудит origin/main и всех удалённых веток не обнаружил новых коммитов после
7c7358f. Три старых headless-теста, зависших 3–4 ноября, остановлены;
пользовательские игровые окна не затрагивались.

Legacy-ремонт9.1: actual-mesh terrain support после вращения, self-sweep
exclusion, контакт с исходными валунами и земля после object contact.
Тот же расширенный probe на исходном7c7358f даёт7PASS/5FAIL, после ремонта12PASS.
Проверены rendered capture, hand18, key24, keeper27, port199, полный rendered
opening, exported startup и свежая Git-source сборка. Отчёт —
development/preview9.1-verification.json. Это не независимый новый модуль.

Исследователь подготовил portable toolchain и Ghidra project по фактическому
exe с проверенным SHA256. Общая autoanalysis не запускалась; после import и
первых9входов исследованы14+11 bounded-входов. Уточнены anchors0..4wood/5food,
overflow, высоты, UV и переходы. Численные проверки и отдельный review выполнены;
это static evidence, не запуск функций оригинала и не visual comparison.
Полный research draft хранит ограничения в specs/storage-observations-draft.md.

ResourceStore v1 и StockPilesView v1 реализованы отдельными свежими фиксированными
запросами Claude без tools/MCP, repo-контекста и прежней сессии.161+149 synthetic
checks PASS в отдельных минимальных Godot-проектах и основном checkout.
После интеграции construction38PASS, workflow10/11PASS, actual storage22PASS
headless/25PASS rendered, hand30/world18, key24, contacts12, scrolls27PASS.
У старых key/scroll fixtures остаются ObjectDB teardown warnings2/4; новых
engine/script errors нет. Кадры actual storage полное/частичное/пустое
проверены локально. Rendered opening на экспортированном9.2 pack прошёл до
первого ключа, temple/door/keeper/key true. Media пропускается, время ускорено.
Exact9.2 exe startup passed headless/rendered. Fresh Git-source cf74fad
собран без build/cache/research; actual storage22 и startup0, engine errors0.
Отчёт — development/preview9.2-verification.json. Normal launcher переключён9.2
после этих проверок;9/9.1 сохранены.
Stock metadata остаётся единственным источником. Manifest и exact spec hash —
specs/SPEC-RESOURCE-STORE-001.implementation.json и
specs/SPEC-STOCK-PILES-VIEW-001.implementation.json. Legacy-adapters в main,
G3dReader, HostInfoReader и construction не получают этой атрибуции.

BW-002: исследователь подготовил39 bounded Ghidra entries; отдельный review
проверил80 hashes и численные fixtures. specs/resource-hand-observations-draft.md
и .review.json одобряют только ограниченные static observations, не новый
implementation packet. Следующий шаг — чистый API сбора/удержания/освобождения
и pose/visual integration; неизвестные масштабы/anchors/PSys не выдавать за факты.

## Формат продолжения

Для выполненного шага: дата, роль/сессия, packet ID/version, commit, команда,
exit code, локальное доказательство и результат. Для незавершённого — следующий
конкретный шаг; для блокера — точная ошибка и независимая доступная работа.

Журнал packets: ID/version, manifest SHA256, исследователь, рецензент, способ
изоляции, сессия реализатора, полученный модуль и tests. Raw disassembly и
прежние адресные подсказки сюда не переносить. Статус задачи и проверенные
новые спецификации не должны незаметно содержать legacy research.
