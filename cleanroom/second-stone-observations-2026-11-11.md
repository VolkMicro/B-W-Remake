# Второй камень: границы исследования и реализации

Координаторская запись, 11 ноября 2026. Это не packet для изолированного
реализатора и не сертификация legacy-кода. Источник — установленный runblack.exe
SHA256 525a6a31ba208ebace5365a10f6afc76c7a76f138722e132b838a2c2c71f1054,
исходный CHL и редакторские данные. Ghidra12.1.4/JDK21 выполняла статический
анализ; оригинальная игра для сравнения кадров не запускалась.

Приватные доказательства и hash manifest остаются вне Git в
`%LOCALAPPDATA%/BW-Restoration/Research/SecondStone`. Обозначения ниже —
локальные observation IDs, не evidence IDs Craft Anything.

- SS-ROUTE: первый тигриный камень имеет subtype52/bit2; награда LostBrother —
  уже существующий subtype49/bit1. Scroll19 запускает спасение живого брата,
  воссоединение и GiveReward. Только физическая доставка награды даёт bits3,
  два камня на пьедестале и journal55=0.5. Quarry50 и sculpted51 не заменяют её.
- SS-ACTOR: health property1, drowning6, flying5, held9. Indestructible298
  игнорирует здоровье <=float32(.01), сохраняя прежнее значение. State200
  использует animation/repeats из native20; брату задан animation253/-1.
  State199 использует центр/radius и интервалы ожидания из18/19/20.
- SS-NULL: GetProperty21 возвращает numeric0 для NULL до проверки свойства;
  Attach37 при отсутствующем actor/container возвращает OBJECT0, Release159
  допускает NULL. Это требуется при исходной очистке HeadingHome.
- SS-DELETE: delete48 mode0 удаляет сразу, mode1 сразу инвалидирует script handle
  и запрашивает видимое исчезновение. Применённый fade2s — новая политика порта;
  modes2/3 остаются неподдержанными.
- WZ-20261111-A: registry/typed decompilation подтверждают порядок weather123,
  проценты rain/snow/overcast*100, lifetime125 и clouds126. Отдельный сохранённый
  weather-time-pass подтверждает age+=dt и симметричную fade/plateau/fade форму;
  исходные единицы dt не установлены. Для120/40 веса в0/20/40/60/80/100/120:
  0/.5/1/1/1/.5/0. Первоначального текстового вывода агента без этого экспорта
  было недостаточно; повторный анализ закрыл пробел доказательств.
- SS-MEDIA: cue59 разрешается PE-таблицей в Script03.sad. Track39 содержит
  отдельные eye/focus каналы; их длительности5470/760ms прочитаны из установки.

Новый WeatherZone получен свежим tool-less Claude запросом по reviewed v3 packet;
packet SHA, review, результат и граница доступа — в specs/*WEATHER-ZONE-001*.
Сам модуль скопирован без изменений. Отложен старт его теста до входа в дерево,
поскольку исходный test fixture нарушал явное условие API. Headless279 и
rendered284 checks проверяют разные возможности rendering server.

Main/native/actor/camera/highlight/influence adapters — coordinator/legacy.
Wander использует прежний provisional solver; здоровье поддерживается0..1,
не произвольный исходный диапазон. Camera track интерполируется линейно,
исходная Bezier-траектория не сертифицирована. Погода, wind, spatial falloff,
освещение и частицы — явно новая визуализация. Ненулевая молния блокируется.
Внешний вид и feel не подтверждены покадровым сравнением с оригиналом.

Focused LostBrother fixture задаёт камеру и исходные post-keeper preconditions,
включая настоящий ProtectGateKey1. Полный opening harness отдельно проходит
через реальные обработчики ввода; quest flags и позиции актёров он не пишет.
Оба ускорены и пропускают медиа: они не являются ручным прохождением.
После второго камня SetupSculptor сохраняет pending native51; третий камень,
ворота и выбор существа остаются следующей задачей.
