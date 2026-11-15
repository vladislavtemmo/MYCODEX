# MYCODEX 8.3B2C — захват TunBuilderBase (без реального TUN)

Дата: 2026-11-15. Исходная ветка: `feat/apple-core-integration`, базовый коммит `1eebcda`.

## Реализация

- `Sources/COpenVPNBridge/MYCODEXBridge.cpp`: C++ наследник настоящего `openvpn::ClientAPI::OpenVPNClient` переопределяет обработчики `TunBuilderBase` для записи remote address, IPv4/IPv6, включённых/исключённых маршрутов, перенаправления шлюза, DNS и MTU.
- `Sources/COpenVPNBridge/MYCODEXTunCapture.hpp` описывает внутренние виды записей. До вызова `tun_builder_establish()` снимок не выдаётся. Снимок — отдельная копия значений, освобождаемая через C ABI.
- C ABI: `mycodex_client_tun_snapshot_create`, `mycodex_tun_snapshot_count`, `mycodex_tun_snapshot_get`, `mycodex_tun_snapshot_destroy`. Старые символы остаются неизменными.
- `Sources/MYCODEX/MYCODEXTunSettingsCapture.swift`: переносимый преобразователь записей в валидируемую модель `MYCODEXTunnelNetworkConfiguration`, поддерживающую IPv4, IPv6, DNS, маршруты и MTU.
- Тестовый символ `mycodex_client_tun_test_fixture` компилируется **только** с `MYCODEX_TUN_CAPTURE_TESTING` и вызывает настоящие виртуальные методы C++ на фиктивных адресах из диапазонов документации. Production dylib и обычный SwiftPM этот символ не содержат.

## Граница безопасности

1. `tun_builder_establish()` **всегда возвращает -1**. Реального системного TUN-дескриптора, `NEPacketTunnelProvider` и защищённого пакетного транспорта нет. `mycodex_client_start()` продолжает возвращать `tunnelUnavailable`; **не включать** `MYCODEX_HAS_APPLE_TUN_ADAPTER`.
2. Снимок **не подтверждает** применение сетевых параметров через `setTunnelNetworkSettings` и не означает OpenVPN `CONNECTED`. Текущая macOS-сборка использует `OPENVPN_FORCE_TUN_NULL`, поэтому Core сам эти callbacks не вызывает. Они проверяются только прямым тестовым fixture. Для будущего рабочего провайдера потребуются корректная ветка `USE_TUN_BUILDER` либо `OPENVPN_EXTERNAL_TUN_FACTORY` и действительно реализованный транспорт пакетов.
3. Захват отвергает net30, нестандартные порты DNS, DoH/DoT/DNSSEC, split DNS/search domains и неподдерживаемые запреты IP-family/local DNS, вместо того чтобы молча игнорировать их. Для поддержки этих режимов понадобится отдельное проектирование.
4. Снимок не содержит паролей, ключей, логов Core, IP-пакетов или `Event.info`. DNS-серверы/сетевые адреса всё равно могут быть персональными сетевыми данными: не выводить их автоматически в production-логи.
5. Одновременно использовать клиентский C ABI и уничтожать клиент нельзя. Снимок после создания владеет независимой копией и может жить после уничтожения исходного клиента.
6. Существующий пакетный мост и Apple PacketFlow не связаны с OpenVPN C++ обработчиком данных, поэтому ускорение, TLS, DNS leak protection и реальная VPN-сессия не подтверждены.

## Тестирование

- `swift test` — portable тесты преобразования и ошибок, не вызывает реальные Core callbacks.
- `swift build -c release` — SwiftPM fallback, без линковки OpenVPN Core.
- `bash scripts/test-macos-tun-capture.sh` — существующая интеграционная регрессия + специальная тестовая macOS dylib с pinned OpenVPN3 и прямыми вызовами `TunBuilderBase`, затем Swift snapshot + сборка Apple-модели.

**Следующий рубеж:** нативный packet transport/factory вместо file descriptor, создание подписанного `NEPacketTunnelProvider`, асинхронный `setTunnelNetworkSettings` с подтверждением и безопасная остановка. Только после этого можно разрешать `connect()` и проверять реальный VPN.
