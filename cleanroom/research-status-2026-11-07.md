# Research status — 7 ноября 2026

**Draft, не approved packet. Роль: исследователь.** Новая независимая
реализация не создавалась; продуктовый код в этом исследовательском шаге
не менялся. Доступ этой сессии к legacy checkout/research сохраняется.

## Выполнено: portable toolchain и настоящий Ghidra import

- Ghidra **12.2**, официальный release `Ghidra_12.2_build`, архив
  `ghidra_12.2_PUBLIC_20261016.zip`.
- SHA256 скачанного архива совпал с официальным release digest:
  `2c2cd776db3c1f6a097ba418922378ac3649cadd5e844a6f5f088ae628a7be67`.
- Eclipse Adoptium Temurin JDK **25.0.5+8 LTS**, Windows x64 portable ZIP.
  SHA256 совпал с официальным API:
  `636bdc13dc649ddc7d5921c5c7d23cca6e44fd19d662b45cc9c02135a6c96c42`.
- Версия JDK реально запущена через `java -version`; Getting Started именно
  release 12.2 требует Java 25 x64. `JAVA_HOME` и `PATH` заданы только
  для запуска процесса, системные настройки не изменены.
- Установка находится в `%LOCALAPPDATA%/BW-Restoration/Tools`, исследование —
  в `%LOCALAPPDATA%/BW-Restoration/Research`. Архивы, project database,
  исследовательские скрипты и raw logs не входят в Git.

Официальные источники: [Ghidra release](https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.2_build),
[Getting Started 12.2](https://github.com/NationalSecurityAgency/ghidra/blob/Ghidra_12.2_build/GhidraDocs/GettingStarted.md),
[headless README 12.2](https://github.com/NationalSecurityAgency/ghidra/blob/Ghidra_12.2_build/Ghidra/RuntimeScripts/support/analyzeHeadlessREADME.md),
[Adoptium API JDK 25](https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse).

## Импортированная установка

Actual EXE найден перечислением файлов установленной игры:
`C:/Games/Black and White Complete Collection/runblack.exe`, 8 663 040 байт.
SHA256:
`525a6a31ba208ebace5365a10f6afc76c7a76f138722e132b838a2c2c71f1054`.

Headless import выполнен с `-noanalysis` и проверочным post-script;
**exit code 0**, import и сохранение project завершились успешно.
Ghidra сообщила:

- loader: Portable Executable (PE);
- language: `x86:LE:32:default`, compiler spec: `windows`;
- pointer size: 4 байта, image base: `00400000`;
- default calling convention модели: `__stdcall`.

Последний пункт не утверждает ABI каждой C++ функции. PE VersionInfo содержит
`1, 0, 0, 1`; конкретная версия игрового патча этим не доказана. Общая
автоматическая аналитика всего EXE не запускалась. Импортёр читал exports
зависимых DLL, но не сохранял их в project (`Loaded 0 additional files`).

Есть нефатальные сообщения о debug/export directory и отдельных WEVT-ресурсах
системных DLL. Они сохранены в локальных logs; успешный exit не означает,
что этих сообщений не было.

Локальное доказательство `BW001-IMPORT-20261107-A`:

- `Research/toolchain-manifest.json`;
- `Research/original-executable-manifest.json`;
- `Research/import-result.json`;
- `Research/import-evidence-sha256.json`;
- `Research/import-analysis.log`, `import-scripts.log`, `import-console.log`;
- `Research/projects/BW_525a6a31ba20.gpr`.

## Границы результата и следующий шаг

Установка Ghidra и import выполнены. BW-001 этим **не закрыт**. Численные
предположения прежнего legacy research не становятся approved спецификацией
после одного импорта.

Дополнительно выполнен ограниченный `-process runblack.exe -noanalysis`:
девять candidate функций склада/куч и позиционного helper, exit code 0.
Legacy-подсказки использовались для выбора входов после проверки SHA256;
имена кандидатов назначены исследователем. Автоматически восстановленные
типы/сигнатуры местами неоднозначны, поэтому pseudocode не принят за
достоверную функциональную спецификацию.

Статические наблюдения, **ещё не проверенное игровое поведение**:

- Создаются одна пищевая куча и пять древесных куч.
- В прочитанном `Info` соответствуют grain mesh 225 с номиналом 15 000 и
  wood meshes 230–234 с номиналом 5 000 каждая.
- У обоих исследованных storage meshes есть 18 ExtraMetrics; обычная
  ExtraPos-таблица содержит только две точки и не является шестью слотами куч.

**UNKNOWN:** полный callback/transform для точек куч и поправка на terrain;
поведение при overflow/приёме ресурса сверх номинала; вид исходной игры при
0/частичном/полном запасе. Начальные script stocks больше номиналов, поэтому
эти номиналы нельзя без дальнейшего исследования превращать в жёсткие лимиты.

Локальные evidence IDs: `BW001-STATIC-20261107-A`, `BW001-DATA-20261107-A`.
Raw excerpts и численные таблицы находятся только в
`Research/raw/BW001-static-A`; результаты и hashes —
`storage-research-result.json`, `storage-evidence-sha256.json`.

Повторение ограниченного прохода использует приватный исследовательский
скрипт: `analyzeHeadless.bat <Research>/projects BW_525a6a31ba20 -process
runblack.exe -noanalysis -scriptPath <Research>/scripts -postScript
BwStorageEvidence.java <Research>/raw/BW001-static-A`. Скрипт содержит
адресные legacy-подсказки и остаётся вне Git. Публичные generic Ghidra helpers
в этом шаге не добавлялись.

Следующий шаг — завершить именно эти UNKNOWN, проверить исходную игру и
подготовить behavioral draft с opaque evidence IDs для отдельного review.
Реализатору этот checkout, project и raw evidence не передавать. Подтаск
исследователя завершён; файлы заморожены, независимых модулей/approved packets
не создано. Этот результат не заявляет готовность Preview 10.
