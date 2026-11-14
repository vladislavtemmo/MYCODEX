# MYCODEX — воспроизводимая исследовательская сборка OpenVPN 3 Core

**Статус на 2026-11-14:** инструменты подготовлены; сборка OpenVPN 3 Core на macOS **ещё не запускалась**. Это не интегрированный VPN SDK.

## Зафиксированная ревизия

- Git: https://github.com/OpenVPN/openvpn3.git
- SHA: `0c1ce172fe918b05463d71e682a0c2f2d8fe7899` — проверенный commit от 2026-11-04.
- Файл с ревизией: `Dependencies/openvpn3.lock`.
- Статус фиксации: **только integration spike**. Для релиза ревизию и список CVE/зависимостей пересмотреть.
- Upstream API: `client/ovpncli.hpp`; официальный протокольный движок C++20.

Исходный код OpenVPN 3 Core не включён в MYCODEX. Его получение производится отдельно по SHA, с проверкой точного результата и наличия ключевых файлов. Никакого автоматического обновления до `master`.

## Подготовка Mac

Использовать учётную запись без прав root. Требуются Xcode с Command Line Tools, Git, CMake, Ninja и Homebrew.

```bash
brew install asio cmake fmt jsoncpp lz4 openssl@3 pkg-config xxhash ninja
```

Поддержка Intel и Apple Silicon требует реального теста, а не только применения этих команд.

## Запуск

```bash
bash scripts/fetch-openvpn3.sh
bash scripts/build-openvpn3-macos.sh
```

Опционально запустить тесты upstream после компиляции:

```bash
MYCODEX_RUN_CORE_TESTS=1 bash scripts/build-openvpn3-macos.sh
```

`fetch-openvpn3.sh` не перезаписывает пользовательские изменения в checkout, проверяет происхождение `origin`, точный SHA и ключевые исходные файлы. Сборка проходит в `.external/`, который исключён из Git. Скрипт не устанавливает зависимости сам и не требует root.

При ошибке сохранять вывод `cmake`/`ctest` без секретов. Нельзя ставить статус «готово», пока фактическая сборка на macOS и тесты не подтверждены.

## После первой успешной сборки

1. Записать Xcode/Swift/CMake/Clang версии, CPU-архитектуру, SHA, список библиотек и итог `ctest`.
2. Проверить фактические зависимости и лицензии (MPL-2.0/AGPL-3.0 + отдельные third-party licenses).
3. Сформировать линковку MYCODEX `COpenVPNBridge` с ядром в Packet Tunnel Extension.
4. Реализовать адаптер `TunBuilderBase` и двусторонний обмен пакетами через `NEPacketTunnelFlow`.
5. Проверять каждую Apple-платформу отдельно.

## Источники

- https://github.com/OpenVPN/openvpn3
- https://github.com/OpenVPN/openvpn3/blob/master/README.md
- https://github.com/OpenVPN/openvpn3/blob/master/LICENSE.md
- https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
