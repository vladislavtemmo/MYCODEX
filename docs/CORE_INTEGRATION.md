# MYCODEX — интеграция OpenVPN 3 Core: технический план

**Дата проверки:** 2026-11-14. **Состояние:** исследование выполнено; линковки OpenVPN 3 Core пока нет.

## Подтверждённый upstream

- Исходники: https://github.com/OpenVPN/openvpn3
- API клиента: [`client/ovpncli.hpp`](https://github.com/OpenVPN/openvpn3/blob/master/client/ovpncli.hpp), `openvpn::ClientAPI::OpenVPNClient`.
- Системное TUN-взаимодействие через `openvpn::TunBuilderBase`.
- Опубликованное upstream руководство: https://openvpn.github.io/openvpn3/
- Проверенный срез `master`: `0c1ce172fe918b05463d71e682a0c2f2d8fe7899` (наблюдался 2026-11-14). Это **не зафиксированная зависимость**.
- Лицензия исходников OpenVPN 3 Core: `AGPL-3.0-only` ИЛИ `MPL-2.0` с дополнительными условиями. Конкретную стратегию распространения согласовать до включения зависимостей.

Upstream использует C++20. Старый OpenVPNAdapter включал Swift tools 5.1 и сборочные C++14-настройки; его модель сборки не переносится автоматически.

## Текущий инкремент

Создан отдельный SwiftPM target `COpenVPNBridge` с компилируемым C++20 и заголовком `Sources/COpenVPNBridge/include/MYCODEXBridge.h`. Swift target `MYCODEX` импортирует его через `OpenVPNNativeBridge`. Функция `isOpenVPNCoreLinked` честно возвращает `false`.

Это лишь проверка совместимости SwiftPM → C ABI → C++. **Никакой VPN-трафик не передаётся.**

## Пошаговая интеграция реального ядра

1. Выбрать версию OpenVPN 3 Core и собрать перечень включаемых исходников/зависимостей, CMake-флагов, лицензионных обязательств, OpenSSL и ASIO.
2. На macOS проверить отдельную C++20 сборку клиента OpenVPN 3 Core и подготовить минимальный bridge без `NetworkExtension`.
3. Добавить C ABI для конфигурации, предоставления credentials и жизненного цикла соединения. Ошибки и объекты передавать безопасными типами; секреты исключить из логов.
4. Реализовать `TunBuilderBase` адаптер в Packet Tunnel Provider: настройка `NEPacketTunnelNetworkSettings`, обработка IPv4/IPv6, DNS и MTU, двусторонний обмен пакетами через `NEPacketTunnelFlow`.
5. Скомпоновать правильные Apple-артефакты с явным version pin (XCFramework или исходная сборка после измерений), проверить size/ABI и подписи.
6. Подтвердить iOS/iPadOS/macOS реальные соединения с тестовыми OpenVPN- и SoftEther-серверами, UDP/TCP, reconnect и отсутствие утечек.
7. Добавить CI Apple, тестирование отмены, ошибок профиля и ресурсных ограничений Network Extension.

## Критерии готовности интеграции

- Есть воспроизводимый pinned source + перечень лицензий.
- C ABI имеет documented ownership, nil/error cases и тесты.
- Реальный OpenVPN 3 Core валидирует `.ovpn`; операции подключения/отключения протестированы на устройстве.
- Уточнено, какие платформы реально поддерживаются, и чем подтверждено это утверждение.
- До достижения критериев статус движка — **не реализован**.
