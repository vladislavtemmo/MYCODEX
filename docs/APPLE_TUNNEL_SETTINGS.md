# MYCODEX 8.3B1 — подготовка настроек Packet Tunnel Provider

Дата: 2026-11-15. Статус: модель сетевых настроек и фабрика NetworkExtension; реального VPN-подключения пока нет.

## Новый исходный код

- `Sources/MYCODEX/AppleTunnelNetworkSettings.swift`: валидируемые модели IPv4/IPv6-адресов, маршрутов, MTU, DNS; `MYCODEXIPPacketKind.detect()` для классификации IP-пакетов.
- `MYCODEXAppleTunnelSettings.make(from:)` доступна только на Apple-платформах с `NetworkExtension`, создаёт `NEPacketTunnelNetworkSettings`. Метод **не** вызывает `setTunnelNetworkSettings` и не соединяется с сетью.
- `Tests/MYCODEXTests/AppleTunnelNetworkSettingsTests.swift`: ошибки входных данных, маршруты IPv4/IPv6, классификация, а на macOS ещё свойства полученных `NEPacketTunnelNetworkSettings`.

## Границы безопасности

1. `remoteAddress` должен быть числовым IPv4/IPv6; его нельзя автоматически брать из произвольного пользовательского текста.
2. Адреса, маршруты, DNS и MTU должны поступать из проверенного результата конфигурации реального OpenVPN 3 Core. Тестовые `10.8.0.2` и `198.51.100.10` — только фикстуры.
3. Никаких фиктивных событий `CONNECTED` и включения `MYCODEX_HAS_APPLE_TUN_ADAPTER`: реализации `TunBuilderBase` и `NEPacketTunnelFlow` пока нет.
4. `routeAllDNS` требует заданного списка DNS серверов. Полная защита от DNS/IP-утечек, split tunnel и bypass VPN-сокета должны быть отдельно проверены на устройствах.
5. Ни одна функция не меняет системные сетевые настройки вне `NEPacketTunnelProvider`.

## Следующие задачи

1. Реализовать capture и валидацию pushed settings в C++ `TunBuilderBase` (routes, DNS, IPv4/IPv6, MTU) без запуска `connect` до готовности TUN.
2. Организовать асинхронный `setTunnelNetworkSettings` с явными подтверждением/ошибкой.
3. Реализовать двусторонний пакетный транспорт между `NEPacketTunnelFlow` и Core, bounded backpressure, отмену/teardown.
4. Проверить реальный Apple extension и entitlement на устройствах; только после этого разрешать connect.
5. Измерить производительность и расход памяти на одинаковых профилях против OpenVPNAdapter.

## Команды проверки

`swift test` и `swift build -c release` — переносимые Swift модели. На macOS тесты также проверят создание объектов `NetworkExtension`. `bash scripts/test-macos-swift-client.sh` — регрессия нативной цепочки, не подтверждение реального VPN-туннеля.
