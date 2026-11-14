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