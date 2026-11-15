# MYCODEX — журнал разработки и передачи задач

## Актуальный статус

- **Фаза:** 1 — SwiftPM и подготовка воспроизводимой сборки OpenVPN 3 Core.
- **Опубликовано в GitHub (main):** C++20 мост и SwiftPM, коммит `3e0630d288c56d9930e49f041114086b32467c6a`.
- **Подготовлено локально, НЕ опубликовано:** инкремент v0.3 (фиксированная ревизия ядра, скрипты для macOS, расширение инспектора и документация).
- **Реальный OpenVPN 3 Core:** не подключён к Swift SDK.
- **Реальный Apple VPN-туннель:** не реализован.
- **Apple/Xcode сборка:** не проводилась.

## 2026-11-14 — первичная документация проекта

**Цель:** создать общий источник контекста для ChatGPT и Codex.

**Подтверждено в GitHub:** загружены `README.md`, `AGENTS.md`, `memory.md`, `skills.md`, `PROGRESS.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, коммит `5066088c43326f06d6654c1dc52dd211945bdcb2`. На первом этапе это была только документация без работающего VPN.

**Блокер:** GitHub-коннектор ChatGPT отклонил запись (403). Загрузка выполнена через GitHub пользователем.

## 2026-11-14 — публикация первого Swift Package

**Цель:** перейти от документации к исходному коду и переносимым тестам.

**Подтверждено в GitHub:** пользователь загрузил `Package.swift`, `Sources/MYCODEX`, `Sources/MYCODEXConfiguration`, тесты и документы в ветку `main`, коммит `34941e91a94560162ece10479334753e189635b9`.

**Содержимое:** модели адресов/транспорта/состояний, безопасный контейнер `.ovpn`, ограниченный инспектор профиля. Предыдущий локальный тест Swift 6.2.1 Linux: 8 тестов прошли; Apple-тестов нет.

## 2026-11-14 — нативный мост и русская документация

**Цель:** подготовить интерфейс для будущего OpenVPN 3 Core и улучшить извлечение серверов из `.ovpn` без ложных обещаний о рабочем туннеле.

**Локальные изменения:**

- `Package.swift`: C++20 target `COpenVPNBridge`, зависимость из `MYCODEX`.
- `Sources/COpenVPNBridge/include/MYCODEXBridge.h` и `MYCODEXBridge.cpp`: компилируемый C ABI с версией и честным признаком отсутствия OpenVPN 3 Core.
- `Sources/MYCODEX/OpenVPNNativeBridge.swift`: Swift-доступ к ABI и диагностике ядра.
- `Sources/MYCODEXConfiguration/OpenVPNProfileInspector.swift`: `<connection>`, директивы `proto`, `remote host tcp-client`, исключение inline-содержимого и ошибки незакрытых блоков.
- `Tests/...`: проверки C ABI, удалённых адресов и ошибок профиля.
- Все README/инструкции/исследование/архитектура/API/дорожная карта переведены на русский и актуализированы.
- `docs/CORE_INTEGRATION.md`: конкретная последовательность подключения OpenVPN 3 Core.

**Проверки:** Linux x86_64, Swift 6.2.1: `swift test --parallel` — 13 тестов без ошибок; `swift test` — 13 тестов, 0 ошибок (вывод XCTest); `swift build -c release` — успешно; `swift package describe` — успешно. C++20 target действительно компилируется. Xcode/Apple не проверялись.

**Не сделано:** интеграция настоящего OpenVPN 3 Core, сетевой стек и Packet Tunnel Provider, системные подписанные расширения, Apple device-сборка.

**Публикация:** на момент подготовки этого документа новые локальные изменения **не подтверждены в GitHub**. Предыдущие попытки записи через коннектор вернули 403. Если запись снова закрыта, приложить архив/патч, но не помечать коммит выполненным.

**Следующий шаг:** выбрать и зафиксировать upstream OpenVPN 3 Core SHA после проверки C++20 build+license/dependency inventory; реализовать настоящую связку OpenVPNClient и TunBuilderBase, проверить на macOS через Xcode.

## 2026-11-14 — исследовательская подготовка OpenVPN 3 Core (v0.3)

**Цель:** закрепить проверяемую upstream-ревизию, дать воспроизводимый способ получить и собрать ядро на Mac; исправить обработку `.ovpn` аргументов в кавычках.

**Подтверждённый статус GitHub:** версия v0.2 уже опубликована пользователем, `main` = `3e0630d288c56d9930e49f041114086b32467c6a`.

**Подготовленные локальные изменения:**

- `Dependencies/openvpn3.lock` — исследовательский SHA `0c1ce172fe918b05463d71e682a0c2f2d8fe7899` (НЕ production pin).
- `scripts/fetch-openvpn3.sh` — точный SHA, проверка Git origin, запрет перезаписи локальных правок.
- `scripts/build-openvpn3-macos.sh` — проверка Homebrew/Xcode/CMake, сборка upstream без root и без скрытой установки зависимостей.
- `.gitignore` — исключение `.external/`; `.github/workflows/swift-package.yml` — заготовка матрицы macOS/Linux, прежде не подтверждённая на GitHub.
- `.ovpn`-инспектор — токенизатор с учётом кавычек, экранирования, комментариев и ошибочных закрывающих блоков; отдельная ошибка `malformedDirective(line:)`.
- Пять новых модульных тестов; документы `docs/OPENVPN3_BUILD.md`, `docs/APPLE_PLATFORM_MATRIX.md`, `docs/DEPENDENCY_AUDIT.md`.

**Фактически проверено:** Swift 6.2.1 Linux x86_64: `swift test` — 18/18 без ошибок; `swift build -c release` — успешно; `swift package describe` — успешно; `bash -n` обоих скриптов — успешно. Сборка OpenVPN 3 Core на Mac, Xcode, entitlement и настоящие VPN-соединения **не проверены**. В контейнере отсутствует DNS-доступ к github.com — внешнее ядро не скачивалось.

**Возможности:** подготовлена схема получения, но OpenVPN 3 Core по-прежнему не добавлен в бинарь MYCODEX; лицензии и зависимости не прошли полный аудит.

**Публикация:** новые файлы v0.3 ещё не подтверждены в GitHub. Предыдущая попытка создания ветки через ChatGPT GitHub — HTTP 403. Перед объявлением коммита выполненным необходима проверка GitHub.

**Следующий шаг:** на macOS выполнить `scripts/build-openvpn3-macos.sh`, зафиксировать результаты и на их основании реализовать настоящий bridge к OpenVPNClient и TunBuilderBase.

## Шаблон следующей записи

### ГГГГ-ММ-ДД — название задачи
- Цель:
- Ветка, коммит/PR:
- Файлы:
- Изменения:
- Запущенные тесты и фактические результаты:
- Непроверенные области:
- Технические решения/риски:
- Следующий шаг:

Старые записи не удалять — дописывать новые и актуализировать только статус наверху.


## 2026-11-15 — Windows: реальный C ABI OpenVPN 3 Core
- Ветка: feat/windows-core-probe.
- Зафиксированная ревизия ядра: 0c1ce172fe918b05463d71e682a0c2f2d8fe7899.
- C ABI с флагом MYCODEX_WITH_OPENVPN3 компилируется и вызывает OpenVPNClientHelper::eval_config.
- Проверены принятие тестового профиля, отклонение профиля без remote и некорректные аргументы.
- Это только предварительная проверка конфигурации, не VPN-соединение.
- Xcode, iOS/macOS, NetworkExtension и реальный VPN-туннель не проверены.
- Изменения локальные, коммит и публикация ещё не подтверждены.


### 2026-11-15 — Windows: проверка режима без ядра
- Успешно собран резервный C ABI без MYCODEX_WITH_OPENVPN3.
- Проверено: ABI=1, CORE_LINKED=0, PROFILE_RESULT=-2, EMPTY_RESULT=-1.
- Подробности: docs/WINDOWS_CORE_VALIDATION.md.
- Swift/Xcode/реальный VPN-туннель не проверены.


### 2026-11-15 — Windows: проверка режима без ядра
- Успешно собран резервный C ABI без MYCODEX_WITH_OPENVPN3.
- Проверено: ABI=1, CORE_LINKED=0, PROFILE_RESULT=-2, EMPTY_RESULT=-1.
- Подробности: docs/WINDOWS_CORE_VALIDATION.md.
- Swift/Xcode/реальный VPN-туннель не проверены.

## 2026-11-15 — Swift API валидации OpenVPN
- Создан OpenVPNProfileValidation.swift с публичным OpenVPNNativeBridge.validateProfile().
- Добавлены 2 теста резервного режима без ядра.
- Windows 11 / Swift 6.4.2: swift test — 20/20 успешно.
- Windows Release: swift build -c release — успешно.
- Реальная цепочка Swift -> C ABI -> OpenVPN 3 Core ещё не проверена.
- Apple NetworkExtension и VPN-туннель не реализованы.

## 2026-11-15 — Windows: Swift -> C ABI -> OpenVPN 3 Core
- Собрана динамическая библиотека mycodex_core.dll с настоящим OpenVPN 3 Core.
- Swift 6.4.2 успешно вызвал OpenVPNNativeBridge.validateProfile через C ABI.
- Результаты: SWIFT_CORE_LINKED=1, SWIFT_VALID=1, SWIFT_INVALID_REJECTED=1, SWIFT_TO_OPENVPN3_PASSED.
- Интеграционная сборка находится в tools/windows-swift-core-probe.
- Обычный SwiftPM пока использует резервный мост без ядра.
- Реальное VPN-подключение, Apple NetworkExtension и Xcode пока не проверены.

## 2026-11-15 — автоматизация Windows-интеграции
- Создан scripts/test-windows-swift-core.ps1 с кодировкой UTF-8 BOM для Windows PowerShell 5.1.
- Автоматизированная сборка mycodex_core.dll и Swift integration probe завершилась успешно.
- Проверено: SWIFT_CORE_LINKED=1, SWIFT_VALID=1, SWIFT_INVALID_REJECTED=1, SWIFT_TO_OPENVPN3_PASSED.
- Основная сборка SwiftPM пока использует мост без ядра; VPN-туннель не реализован.

## 2026-11-15 — macOS Intel x86_64: проверка ядра и Swift Bridge
- macOS 15.8.2, Xcode 26.3, Swift 6.2.4, AppleClang 17.
- SwiftPM: 20/20 tests PASS; Release build PASS.
- OpenVPN 3 Core: pinned revision 0c1ce172fe918b05463d71e682a0c2f2d8fe7899; CMake Release build PASS; CTest CoreTests 1/1 PASS.
- OpenSSL 3.5.9 обнаружен через PKG_CONFIG_PATH.
- macOS native bridge: libmycodex_core.dylib собрана; Swift integration PASS: SWIFT_CORE_LINKED=1, SWIFT_VALID=1, SWIFT_INVALID_REJECTED=1, SWIFT_TO_OPENVPN3_PASSED.
- Ограничения: проверка выполнена отдельным исследовательским тестом; SwiftPM пока без реального Core; VPN-сессия и NetworkExtension не реализованы.
- Следующий шаг: автоматизация macOS integration probe, подключение OpenVPNClient и тесты туннеля.

## 2026-11-15 — macOS: автоматизация Swift/OpenVPN 3 Core integration
- Добавлен scripts/test-macos-swift-core.sh.
- Проверяется pinned SHA OpenVPN 3 Core, C ABI, OpenSSL, сборка native bridge и Swift integration.
- Фактический результат: SWIFT_CORE_LINKED=1, SWIFT_VALID=1, SWIFT_INVALID_REJECTED=1, SWIFT_TO_OPENVPN3_PASSED.
- Повторная сборка C++: ninja no work to do; Swift integration test PASS.
- Ограничения: реальная VPN-сессия и NetworkExtension ещё не реализованы.
- Следующий этап: OpenVPNClient и управление жизненным циклом соединения.

## 2026-11-15 — OpenVPNClient 8.2: credentials + ограниченная очередь событий

- Ветка для интеграции: feat/apple-core-integration (после 6d5d547).
- C ABI: `mycodex_client_provide_credentials()` с проверкой аргументов,
  обязательной успешной конфигурацией и очисткой временной C++ копии пароля.
- `MYCODEXNativeClient::event()` хранит только тип, флаги error/fatal,
  не записывает `Event.info` и логи; очередь до 64 событий, mutex для polling.
- Swift: `provideCredentials(username:password:)`, `pollEvent()`,
  `OpenVPNClientEvent`, типизированная ошибка `credentialsRejected`.
- Обновлены macOS probe и Windows DLL exports; исходные C ABI функции сохраняются.
- Эта запись описывает реализацию до фактической macOS/Windows проверки;
  **реальные события, соединение, TLS, NetworkExtension не проверены**.
- Перед публикацией выполнить `swift test`, `swift build -c release`,
  `bash scripts/test-macos-swift-client.sh` на Mac Intel, затем Windows regression.

## 2026-11-15 — этап 8.3A: lifecycle API, до реализации Apple TUN
- Ветка: feat/apple-core-integration; база: 60f229e.
- Подготовлены C++ worker, функции start/stop/pause/resume/reconnect/wait,
  ограниченный Swift API и тестирование отказа запуска без TUN.
- `start()` возвращает `tunnelUnavailable` до реальной интеграции NetworkExtension.
- `runState.running` не является подтверждением VPN CONNECTED.
- Linux Swift 6.2.1: swift test — 21/21 PASS, swift build -c release — PASS.
- macOS и Windows необходимо проверить отдельно.
- Не проверено: реальная VPN-сессия, сетевые гонки, Apple NetworkExtension, Windows.

## 2026-11-15 — Apple 8.3B1: сетевые настройки Packet Tunnel (только подготовка)
- База: feat/apple-core-integration, 2508fb3.
- Добавлена валидация IPv4/IPv6 адресов, маршрутов, DNS и MTU.
- Для Apple доступно создание NEPacketTunnelNetworkSettings на основе строго проверенной модели.
- Добавлена классификация IPv4/IPv6 пакетов без копирования payload.
- Добавлены XCTest-тесты; Linux Swift 6.2.1: 25/25 PASS и Release PASS (до проверки Mac).
- macOS тесты и сборка NetworkExtension требуют отдельной проверки на Mac.
- Не реализовано: реальный TunBuilderBase/NEPacketTunnelFlow, туннель, VPN CONNECTED.
- Следующий шаг: capture pushed options из OpenVPN 3 Core и TUN packet bridge.

## 2026-11-15 — этап 8.3B2A: двусторонняя staging-очередь пакетов
- Основа: feat/apple-core-integration@60685cd.
- Добавлен C++20 пакетный мост с C ABI create/push/pop/stats/close/destroy, отдельные очереди и пределы памяти по направлениям.
- Переполнение возвращает явный backpressure и не удаляет уже принятые пакеты.
- Swift MYCODEXPacketBridge, MYCODEXPacket, тесты IPv4/IPv6, порядка, переполнения и закрытия.
- Linux Swift 6.2.1: swift test — 29/29 PASS; swift build -c release — PASS.
- Требуется macOS native Core test и Windows DLL regression после внесения изменений.
- НЕ реализовано: соединение с OpenVPN TunBuilderBase, NEPacketTunnelFlow, Apple entitlement, рабочий VPN.
- Следующий этап: Apple TunBuilderBase + подтверждение setTunnelNetworkSettings и связывание реального пакетного транспорта.

## 2026-11-15 — Apple 8.3B2B: адаптер PacketFlow и backpressure (без VPN)
- Основа: feat/apple-core-integration@c04ead9.
- Добавлены переносимый MYCODEXPacketFlowCoordinator и Apple-only MYCODEXApplePacketFlowAdapter для readPackets/writePackets.
- При переполнении удерживается остаток входящей партии без следующего read; выходящая партия удерживается, если системная запись не принята.
- Исправлено чрезмерное выделение памяти при dequeue: буфер 2048 байт с увеличением по длине из C ABI.
- Linux Swift 6.2.1: swift test 35/35 PASS, swift build -c release PASS; Apple-часть прошла только static typecheck с заглушкой NEPacketTunnelFlow.
- Требуется проверка macOS SwiftPM/NetworkExtension SDK и нативного Core, затем iOS entitlement/device тесты.
- Не подключены: OpenVPN TunBuilderBase/ExternalTun, реальный NEPacketTunnelProvider и зашифрованный сетевой канал.

## 2026-11-15 — этап 8.3B2C: захват настроек OpenVPN TunBuilderBase
- База: feat/apple-core-integration@1eebcda.
- Подготовлены callbacks TunBuilderBase в реальном OpenVPNClient, которые фиксируют remote, IPv4/IPv6, маршруты, DNS и MTU в C++.
- Снимок передаётся через C ABI и преобразуется в валидируемую Swift-модель сетевых настроек; `tun_builder_establish()` по-прежнему возвращает -1, а `start()` заблокирован без реального TUN.
- Добавлены переносимые XCTest и отдельный macOS test-only Core callback probe.
- В контейнере Linux Swift 6.2.1: `swift test` — 40/40 PASS; `swift build -c release` — PASS.
- Нативная компиляция с OpenVPN3 на macOS, тестовые callbacks и Apple SDK ещё НЕ подтверждены — выполнить `bash scripts/test-macos-tun-capture.sh`.
- Не реализовано: OpenVPN encrypted packet path, NEPacketTunnelProvider, setTunnelNetworkSettings, реальное VPN-соединение, безопасная передача пакетов в Core.
- Важно: существующая macOS Core-сборка с `OPENVPN_FORCE_TUN_NULL` не вызывает TunBuilder callbacks автоматически; отдельный тест вызывает их напрямую. Для production потребуется режим `USE_TUN_BUILDER` или `OPENVPN_EXTERNAL_TUN_FACTORY` с настоящим транспортом.
