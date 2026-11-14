# MYCODEX — исследование исходных решений и ограничений

**Проверено:** 2026-11-14. Источники не заменяют проверку реальной сборки Apple.

## 1. Устаревший OpenVPNAdapter

- Источник: https://github.com/ss-abramchuk/OpenVPNAdapter
- Репозиторий архивирован, в README автор прямо сообщил о прекращении поддержки.
- Исходный `Package.swift`: Swift Tools 5.1, минимумы iOS 9 и macOS 10.11, C++14 и targets OpenVPNClient, mbedTLS, LZ4.
- Реализация содержит Objective-C-адаптер, делегаты, `NetworkExtension` и старые vendored зависимости.
- Использовать как справочник совместимости, а не копировать без проверки AGPLv3.

## 2. Актуальный OpenVPN 3 Core

- Репозиторий: https://github.com/OpenVPN/openvpn3
- Руководство: https://openvpn.github.io/openvpn3/
- API: `client/ovpncli.hpp`, класс `openvpn::ClientAPI::OpenVPNClient`.
- TUN-абстракция: `openvpn::TunBuilderBase`.
- Это **клиентская** библиотека OpenVPN 3, не VPN-сервер; содержит транспорт UDP и TCP.
- Требует современных инструментов C++20. Обсуждаемый срез: commit `0c1ce172fe918b05463d71e682a0c2f2d8fe7899`; пока не принят как production pin.
- `LICENSE.md`: https://github.com/OpenVPN/openvpn3/blob/master/LICENSE.md — выбор AGPLv3 или MPL 2.0. Остальные включённые зависимости и обязательства ещё не утверждены.
- Для Apple обязательно отдельное доказательство сборки/линковки и интеграции с `NetworkExtension`.

## 3. Apple NetworkExtension

- Документация: https://developer.apple.com/documentation/networkextension
- Развёртывание расширений: https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment
- На iOS/macOS VPN реализуется через разрешённый системный механизм; `NEPacketTunnelProvider` обслуживает пакеты и настройки интерфейса.
- Платформы tvOS и visionOS рассматриваются отдельно по версии SDK/entitlement. На watchOS локальный packet tunnel **не обещается**.
- Факт наличия framework не доказывает возможность подписать приложение, выдать entitlement или успешно подключить VPN.

## 4. Проверенная переносимая часть MYCODEX

- SwiftPM target `COpenVPNBridge` с C ABI и C++20 создан без подключения upstream кода.
- Swift-модели и `.ovpn`-инспектор не выполняют шифрование, не проверяют сертификаты и не управляют сокетами.
- Проверка SwiftPM под Linux не означает проверку iOS, macOS или tvOS.

## 5. Незакрытые вопросы

1. Лицензирование и список зависимостей OpenVPN 3 Core, стратегия бинарной/исходной доставки.
2. Проверка сборки на актуальном Xcode и выбор минимальных Apple OS.
3. Реальный транспорт OpenVPN 3 Core ↔ Apple `NEPacketTunnelFlow`.
4. Keychain/App Group, entitlement и жизненный цикл VPN extension.
5. Таблица совместимости `.ovpn`, UDP/TCP и SoftEther на устройствах.
