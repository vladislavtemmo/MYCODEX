# MYCODEX — архитектура

**Статус:** есть переносимое Swift-ядро и C++-точка ABI; интеграция OpenVPN 3 Core и Apple NetworkExtension только проектируется.

## Целевые слои

```text
Приложение (SwiftUI / UIKit / AppKit)
  |
  +-- Хост-менеджер NETunnelProviderManager [НЕ РЕАЛИЗОВАН]
  |      \-- Сохранённая VPN-конфигурация / запуск расширения
  |
  +-- MYCODEX — типобезопасные модели, состояния, публичный Swift API
  |      \-- OpenVPNNativeBridge (сборка C++ ABI работает)
  |             \-- COpenVPNBridge (OpenVPN 3 Core пока НЕ подключён)
  |                    \-- openvpn::ClientAPI::OpenVPNClient [НЕ РЕАЛИЗОВАН]
  |
  +-- MYCODEXConfiguration — ограниченный анализ .ovpn

NEPacketTunnelProvider (отдельное расширение, НЕ РЕАЛИЗОВАНО)
  +-- setTunnelNetworkSettings + NEPacketTunnelFlow
  +-- Адаптер TunBuilderBase <-> NEPacketTunnelFlow [НЕ РЕАЛИЗОВАН]
  \-- Поток событий и диагностика
```

Нативный OpenVPN 3 Core подключается только после проверки лицензирования, выбранного SHA и воспроизводимой Apple-сборки. Swift Package не должен получать прямую зависимость на UIKit/SwiftUI.

## Реальная структура пакета

```text
Package.swift
Sources/
  MYCODEX/                    # Публичные Swift-модели и диагностика моста
  MYCODEXConfiguration/       # Инспектор .ovpn (не полный парсер)
  COpenVPNBridge/             # C++20 и публичный C ABI — скелет
    include/MYCODEXBridge.h
Tests/
  MYCODEXTests/
  MYCODEXConfigurationTests/
.github/workflows/            # Предложение CI, требует запуска на GitHub
scripts/test.sh
```

## Инварианты интерфейса C/C++

- Открытый C ABI содержит функции `mycodex_bridge_abi_version`, `mycodex_bridge_core_linked`, `mycodex_bridge_backend_name`.
- При отсутствии движка `mycodex_bridge_core_linked() == 0`. Никакие функции не утверждают, что происходит VPN-подключение.
- C++-объекты не пересекают ABI как Swift-объекты; будущие opaque handles имеют явные функции create/destroy.
- Буферы, передаваемые между Swift, OpenVPN и packet flow, должны иметь документированное владение и жизненный цикл.
- Все события и результаты операций должны проходить явные состояния, ошибки и отмену.

## Отличие `.ovpn`-инспектора от OpenVPN-парсера

`OpenVPNProfileInspector` извлекает только адреса и транспорт, поддерживая директивы `remote`, `proto` и блоки `<connection>`. Он не реализует всю грамматику OpenVPN, не проверяет криптографию, сертификаты, `pull-filter`, `route`, директивы внешних файлов и фактическую поддержку профиля в core. В будущем валидность определяет реальный OpenVPN 3 Core.

## Требования Apple

- Хост-приложение управляет системным VPN-профилем и пользовательским разрешением через `NETunnelProviderManager`.
- Подписанное расширение `NEPacketTunnelProvider` отвечает за пакеты, сетевые параметры, MTU, DNS и маршруты в рамках возможностей API.
- Проверка entitlement, App Group/Keychain Access Group и расширения должна проходить отдельно для каждой платформы.
- Результаты Linux SwiftPM-тестов не подтверждают совместимость с Apple.

Подробности следующего шага: [CORE_INTEGRATION.md](CORE_INTEGRATION.md).

## Apple extension example (2026-11-16)

`Examples/AppleExtension` содержит Xcode targets PacketTunnelExtension и HostApp. Для extension скрипт генерирует отдельный Swift package с бинарным iOS XCFramework настоящего OpenVPN3 Core; стандартный SwiftPM fallback в него не входит. Provider пока намеренно завершает start ошибкой, потому что transport worker/PacketFlow не подключён. Нативный `start()` требует staged TUN FD перед запуском worker. Production статус Connected остаётся запрещённым до реального события Core. Схема сборки и проверки: [IOS_CORE_LINK.md](IOS_CORE_LINK.md).
