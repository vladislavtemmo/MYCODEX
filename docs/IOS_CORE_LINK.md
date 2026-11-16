# OpenVPN 3 Core в iOS PacketTunnelExtension

## Сборка

Из корня репозитория на MacBook с Xcode и XcodeGen:

```bash
MYCODEX_IOS_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro' \
  bash scripts/test-ios-extension-core-link.sh
```

Для другого доступного симулятора замените `MYCODEX_IOS_TEST_DESTINATION`. Скрипт собирает исходный Core по SHA из `Dependencies/openvpn3.lock`, проверяет контрольные суммы четырёх архивов из `Dependencies/ios-core-sources.lock`, создаёт статические срезы iOS arm64 и iOS Simulator x86_64/arm64, затем собирает HostApp и PacketTunnelExtension в Debug и Release для обеих платформ. Зависимости не берутся из macOS Homebrew `.dylib`.

Генерируемый Swift package находится в `.external/ios-core-package`. Его `COpenVPNBridge` — только бинарный XCFramework из статического Core; Swift-исходники `MYCODEX` копируются из текущего дерева. Xcode-проект `Examples/AppleExtension` ссылается именно на этот package. Стандартный корневой `Package.swift` продолжает обслуживать переносимые тесты с fallback-мостом, но в extension не подключается. Это исключает повторное определение C ABI.

## Проверки

`CoreLinkTests` запускает настоящий `OpenVPNClient`, передаёт безсекретный `.ovpn` в Core, проверяет флаги linked/External TUN и отказ `start()` без готового транспорта. Дополнительно скрипт проверяет один экземпляр ключевых C ABI-символов в каждой архитектуре фактических Debug/Release `.appex`, платформу Mach-O, отсутствие ссылок на macOS/Homebrew библиотеки и отсутствие `OPENVPN_FORCE_TUN_NULL` / `MYCODEX_PRODUCTION_TUN_TRANSPORT_VERIFIED` в флагах Core.

Это проверка линковки и конфигурации Core. В Provider пока нет полного запуска worker, подтверждения настроек и двустороннего PacketFlow; статус Connected и передача VPN-трафика не проверяются. Для установки на устройство нужны подпись, Network Extension entitlement и provisioning. Исследовательский pin OpenVPN3 ещё требует решения по выпуску и лицензиям зависимостей.
