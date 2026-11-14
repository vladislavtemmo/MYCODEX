# MYCODEX — результаты Windows-интеграции

Дата: 2026-11-15.

- OpenVPN 3 Core SHA: 0c1ce172fe918b05463d71e682a0c2f2d8fe7899.
- Visual Studio 2022 / MSVC, Windows x64.
- OpenVPN 3 Core Release ovpncli.exe собран успешно.
- После настройки OPENSSL_MODULES набор CoreTests прошёл (CTest 1/1).
- Реальный C ABI проверен: CORE_LINKED=1, VALID_RESULT=0, INVALID_RESULT=1, EMPTY_RESULT=-1.
- Резервная сборка без ядра проверена: CORE_LINKED=0, PROFILE_RESULT=-2, EMPTY_RESULT=-1.
- Реальный VPN-туннель и SwiftPM-сборка с подключённым ядром ещё не проверены.
- Apple NetworkExtension, Xcode и устройства Apple ещё не проверены.
- Движок не копируется в репозиторий; используется отдельная зафиксированная ревизия.
- Следующий этап: Swift-оболочка для C ABI, тесты Swift и Apple NetworkExtension.
## 2026-11-15 — Windows: Swift -> C ABI -> OpenVPN 3 Core
- Собрана динамическая библиотека mycodex_core.dll с настоящим OpenVPN 3 Core.
- Swift 6.4.2 успешно вызвал OpenVPNNativeBridge.validateProfile через C ABI.
- Результаты: SWIFT_CORE_LINKED=1, SWIFT_VALID=1, SWIFT_INVALID_REJECTED=1, SWIFT_TO_OPENVPN3_PASSED.
- Интеграционная сборка находится в tools/windows-swift-core-probe.
- Обычный SwiftPM пока использует резервный мост без ядра.
- Реальное VPN-подключение, Apple NetworkExtension и Xcode пока не проверены.
