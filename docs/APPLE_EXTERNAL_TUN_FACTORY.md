# MYCODEX 8.3B2D2A — OpenVPN 3 ExternalTun::Factory (без пакетов)

Дата: 2026-11-15. Основа: `feat/apple-core-integration@1f9024a`.

## Что реализовано

- Режим отдельной **нативной** сборки `OPENVPN_EXTERNAL_TUN_FACTORY`, без `OPENVPN_FORCE_TUN_NULL`.
- `MYCODEXNativeClient::new_tun_factory` возвращает upstream `TunBuilderClient::ClientConfig`, то есть Core может выбрать собственный TUN-адаптер через `ExternalTun::Factory`, **а не системный macOS TunMac или TunNull**.
- Воспроизводимо передаются `TunProp::Config`, Core `Frame`, `SessionStats` и указатель на существующие `TunBuilderBase` callbacks. Установлены `tun_prefix=false` (сырые IP-пакеты), `retain_sd=false` (один владелец FD), `n_parallel=8`.
- Режим persistent TUN пока отклоняется, потому что сохранение FD во время reconnect/stop не проверено.
- `mycodex_external_tun_factory_compiled()` сообщает, выбран ли соответствующий **путь сборки**, а не установлено ли VPN-соединение.
- Только для изолированного теста существует `mycodex_external_tun_factory_test_fixture()`, создающий фабрику и проверяющий контракт. В production test fixture не включён.

## Особенности реализации

`OpenVPNClient::connect_setup` передаёт `this` как `ExternalTun::Factory`, когда Core компилируется с `OPENVPN_EXTERNAL_TUN_FACTORY`. Далее `ClientOptions` запрашивает новый `TunClientFactory` и использует `TunBuilderClient::ClientConfig`; при реальном `tun_start` он будет вызывать `TunBuilderBase::tun_builder_new`, `TunProp::configure_builder` и `tun_builder_establish`.

**Текущий `tun_builder_establish()` всегда возвращает `-1`**. Нет реального дескриптора, механизма ожидания асинхронного `setTunnelNetworkSettings` и связки `NEPacketTunnelFlow` с Core. Не существует действительного VPN-подключения. Даже если включить диагностический флаг фабрики, `start()` должен возвращать `tunnelUnavailable` (`-6`), поскольку отдельный production-guard `MYCODEX_PRODUCTION_TUN_TRANSPORT_VERIFIED` по умолчанию выключен.

## Почему нельзя сразу вызывать connect()

- OpenVPN Core ожидает файловый дескриптор для `TunBuilderClient`, а Apple даёт `NEPacketTunnelFlow`, **не FD**.
- Для моста нужен канал raw-IP-пакетов с двусторонним обменом, правильной границей пакета, backpressure и завершением потоков без UAF.
- Core вызывает TUN setup *после* начала соединения и серверного PUSH; `setTunnelNetworkSettings` необходимо подтвердить асинхронно до `tun_connected()`. Синхронный вызов на main actor недопустим.
- Сокеты транспорта самого OpenVPN должны обходить туннель; это требует отдельного socket/routing тестирования.

## Проверки

- `swift test`, `swift build -c release` — fallback regression, не OpenVPN Core.
- `bash scripts/test-macos-external-tun-factory.sh` — полная существующая регрессия и отдельная сборка pinned OpenVPN 3 Core с `OPENVPN_EXTERNAL_TUN_FACTORY`, проверка factory test fixture и запрета `connect()`.
- Нативная новая сборка должна быть проверена **на Intel Mac**, а затем отдельно на Apple Silicon/iOS при переходе к production.

## Следующий шаг 8.3B2D2B

Добавить безопасный Unix socketpair/FD транспорт, связать его с bounded packet queues и дать `NEPacketTunnelProvider` асинхронное подтверждение `setTunnelNetworkSettings` в нужной фазе. До успешного end-to-end тестирования не включать `MYCODEX_HAS_APPLE_TUN_ADAPTER` и `MYCODEX_PRODUCTION_TUN_TRANSPORT_VERIFIED`.
