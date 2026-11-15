# MYCODEX 8.3B2D2D1 — согласование Apple settings → native TUN FD handoff

Дата: 2026-11-15. Базовый GitHub commit: `4bcbca3` на `feat/apple-core-integration`.

## Изменения

- `MYCODEXTunFDAcknowledgement.swift`: Swift-оболочка над уже существующими C ABI функциями `mycodex_client_tun_{attach_fd,wait_pending,ack_settings,cancel}`. `attachTunSocket` передаёт **дубликат** локального `SOCK_DGRAM` endpoint и гарантированно закрывает временный FD. `waitForPendingTunSettings` синхронный, **не вызывайте на главном потоке или MainActor**: метод отказывает, если `Thread.isMainThread`.
- `MYCODEXTunFDSettingsCoordinator`: `@MainActor` слой: по native generation читает снимок `TunBuilderBase`, передаёт валидированные настройки операционной системе, отправляет `applied=true` **только** после положительного completion, при отказе отправляет `false`. Дублирующий callback и поздний callback после `cancel()` не подтверждают устаревший generation. При отсутствии снимка — отрицательный ACK; при ошибке ACK — отмена native handoff.
- `MYCODEXAppleTunFDSettingsHandoff.swift`: вызывает существующий `MYCODEXAppleTunnelSettingsApplier` из coordinator и возвращает результат вызвавшему Provider. Успех означает **только применение сетевых настроек Apple**, а не подключение VPN.
- `MYCODEXTunFDSettingsCoordinatorTests.swift`: mock-сценарии положительного и отрицательного ACK, отсутствия snapshot, отмены, повторного callback, повторной попытки и ошибки нативного подтверждения.
- `test-macos-tun-settings-ack.sh`: полный Swift-тест, Release, предыдущие реальные Core/FD регрессии, дополнительный Swift → C ABI → OpenVPN3 probe для защиты от premature / stale ACK.

## Требуемый порядок реального Provider (следующий интеграционный шаг)

1. На отдельном Core worker запустить `connect()` (только после аудита транспорта и снятия compile guard; **здесь guard не снимаем**). До подключения — конфигурация клиента, учетных данных и создание socketpair/очередей.
2. До запуска Core передать endpoint через `client.attachTunSocket(socket)`; это заготовка, пока Core не вызывается.
3. В отдельном **фоновом** контролируемом worker ждать `client.waitForPendingTunSettings(timeoutMilliseconds:)`, не удерживая MainActor. Состояние `OpenVPNClient` и его уничтожение необходимо сериализовать с этим worker, без concurrent deinit.
4. При результате `generation > 0` перейти на MainActor; создать `MYCODEXAppleTunFDSettingsHandoff(provider:nativeClient:)` и вызвать `applyPending(generation:)`.
5. После подтверждения `setTunnelNetworkSettings` координатор отправляет ACK; Core получает FD. При `reject`/timeout/cancel — Core не получает FD. `startTunnel(completionHandler:nil)` **не вызывать** только на основании этого ACK.
6. Отдельно организовать непрерывное пробуждение packet pump при изменении состояния сокета/очередей, привязать `MYCODEXApplePacketFlowAdapter`, протестировать packet bytes через Core, TLS и CONNECTED.
7. На stop: `handoff.cancel()` на MainActor, остановить native Core, прекратить packet flow, дождаться worker, закрыть socket transport **раньше** packet bridge и удалить client **только после** join. Реальные гонки проверять тестами подписанного расширения.

## Ограничения

- Фактический `PacketTunnelProvider.startTunnel()` по-прежнему **отказывает в запуске**. Реальный Core connect запрещён: `mycodex_client_start` возвращает `-6`.
- **Нет** фонового watcher-потока `wait_pending`, Xcode extension target / entitlements, реального сетевого `socket_protect`, TUN packet pump scheduler или реального end-to-end VPN. Swift-координатор доступен для дальнейшего подключения в Provider, но пока не вызывается из `startTunnel()`.
- `setTunnelNetworkSettings` может завершиться позднее 15-секундного native timeout: попытка ACK будет отвергнута, `cancelTunHandoff()` обеспечит fail closed. Для production следует добавить координацию timeout и откат сетевых настроек через Provider на ошибке, без имитации подключения.
- Windows не поддерживает `socketpair`; native stubs остаются неизменными.
- Не записывать в логи IP-пакеты, секреты, DNS/пользовательские адреса и полные конфигурации VPN.

## Тестирование

Portable Linux: `swift test`, `swift build -c release`. Typechecking Apple-кода с **тестовой заглушкой API** не является компиляцией с реальным Apple SDK.

Mac Intel с Xcode: `bash scripts/test-macos-tun-settings-ack.sh`; использует закреплённую ревизию Core и проверяет Swift/ABI для `attach`, `ACK`, `cancel`, при этом VPN остаётся заблокирован.

**Следующий шаг:** полноценная подсистема worker/wakeup + интеграция с подписанным `NEPacketTunnelProvider`, route/stop rollback и socket-protect. Затем end-to-end VPN на реальном Apple устройстве.
