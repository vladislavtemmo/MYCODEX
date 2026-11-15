# OpenVPNAdapte-for-Apple — современная OpenVPN-библиотека для Apple

**Статус: этап 1 — Swift Package и проверяемый C++-мост. VPN-движок ещё не подключён.**

MYCODEX — проект поддерживаемого SDK с публичным Swift API и интеграцией OpenVPN 3 Core в приложения Apple через `NetworkExtension`. Это функциональная замена по назначению, а не копия прекратившего развитие [OpenVPNAdapter](https://github.com/ss-abramchuk/OpenVPNAdapter).

## Целевые платформы

- **Основные:** iOS, iPadOS, macOS.
- **Отдельная проверка:** tvOS, visionOS — в зависимости от SDK, VPN entitlement и результатов сборки на устройствах.
- **watchOS:** локальное VPN-туннелирование не заявляется до подтверждения соответствующего системного API.

В `Package.swift` пока стоят **предварительные**, а не окончательные минимальные версии: iOS 16 и macOS 13.

## Что уже реализовано

- Пакет SwiftPM с двумя библиотеками `MYCODEX` и `MYCODEXConfiguration`.
- Модели адресов, транспорта и состояний VPN-соединения.
- Контейнер `.ovpn`, скрывающий содержимое при обычном выводе/отладке.
- Ограниченный инспектор `.ovpn`: директивы `remote`, `proto`, блоки `<connection>`, пропуск встроенных сертификатов/ключей.
- Отдельный компилируемый C++ target `COpenVPNBridge` с проверяемым C ABI (`OpenVPNNativeBridge`).
- Автоматизированные тесты переносимой части SDK.

**Чего пока нет:** линковки OpenVPN 3 Core, полноценной проверки профилей движком, создания `NEPacketTunnelProvider`, подключения к VPN, шифрованного туннеля и тестов на реальных устройствах Apple. Нативный мост честно возвращает `isOpenVPNCoreLinked == false`.

## Сборка и тесты

На компьютере с Swift 6 и C++20-компилятором:

```bash
swift build
swift test
swift build -c release
```

Успешный Linux-прогон подтверждает только переносимый Swift/C++ код, **не** работоспособность Apple VPN. Для iOS/macOS далее нужны Xcode, подписи и entitlement.

## Документы для разработчиков и AI-агентов

- [AGENTS.md](AGENTS.md) — инструкция на начало и конец каждого сеанса.
- [memory.md](memory.md) — подтверждённые решения и долговременная память проекта.
- [skills.md](skills.md) — инженерные стандарты и определение готовности.
- [PROGRESS.md](PROGRESS.md) — хронологический журнал задач, проверок, проблем.
- [Архитектура](docs/ARCHITECTURE.md) — разделение Swift, C++ и Apple NetworkExtension.
- [Дорожная карта](docs/ROADMAP.md) — планы с критериями готовности.
- [Исследование](docs/RESEARCH.md) — первоисточники и ограничения.
- [Предложение API](docs/API_PROPOSAL.md) — реализованные и проектируемые интерфейсы.
- [Интеграция ядра](docs/CORE_INTEGRATION.md) — следующий этап подключения OpenVPN 3 Core.

## Передача контекста в другой чат

> Открой GitHub-репозиторий `vladislavtemmo/MYCODEX`, прочитай `AGENTS.md`, `memory.md`, `skills.md`, `PROGRESS.md` и документы в `docs/`. Проверь реальные файлы и продолжи первый незавершённый пункт. После работы обнови журнал на русском.

Файлы GitHub — **общий контекст**, но не «автоматическая память»: каждый агент должен перечитывать их. Если интеграции GitHub запрещена запись, подготовить патч/архив, но не утверждать, что изменения опубликованы.

## Лицензии

Оригинальный OpenVPNAdapter имеет лицензию AGPLv3, а OpenVPN 3 Core доступен по AGPLv3 или MPL 2.0. Перед включением исходников ядра, OpenSSL и других зависимостей требуется полная проверка совместимости лицензий и требований распространения. В этом репозитории пока **нет исходников OpenVPN 3 Core**.


## Подготовка OpenVPN 3 Core (v0.3)

В дополнение к SwiftPM-пакету подготовлены **исследовательские** скрипты `scripts/fetch-openvpn3.sh` и `scripts/build-openvpn3-macos.sh`, а также `Dependencies/openvpn3.lock`. Указанный SHA служит только для воспроизводимого эксперимента, не для production.

- [Сборка OpenVPN 3 Core на Mac](docs/OPENVPN3_BUILD.md)
- [Матрица Apple-платформ](docs/APPLE_PLATFORM_MATRIX.md)
- [Аудит зависимостей и лицензий](docs/DEPENDENCY_AUDIT.md)

Пока `OpenVPNNativeBridge.isOpenVPNCoreLinked` возвращает `false`: никакой реальный VPN-трафик не отправляется. Сначала нужно собрать upstream OpenVPN 3 Core на Mac, затем интегрировать C++-клиент и `NEPacketTunnelProvider` с entitlement.
