# MYCODEX 8.3B2D2D3 — контроль запуска и остановки Packet Tunnel

**Основа:** `feat/apple-core-integration@a360530` (`vladislavtemmo/OpenVPNAdapte-for-Apple`). Дата: 2026-11-16.

## Реализовано

Добавлена переносимая `@MainActor`-машина состояний `MYCODEXPacketTunnelSessionLifecycle`. Она **не запускает VPN** и не принимает события из сети самостоятельно. Её будущий владелец — подписанный `NEPacketTunnelProvider`.

Порядок **разрешения успешного completion**: получение настоящего Core TunBuilder generation, подтверждение `setTunnelNetworkSettings` **вместе с native FD ACK** → `MYCODEXApplePacketTransportDriver.startMonitoring()` → фактическое `OpenVPNClientEvent(name: "CONNECTED")` от Core. Пропуск любой фазы или ранний `CONNECTED` приводит к отказу, а не к ложному успеху. `runState.running` недостаточно.

Состояния: `idle → awaitingNetworkSettings → awaitingPacketTransport → awaitingCoreConnection → connected`. Ошибки переходят в `failed`; остановка переходит `stopping → releasingResources → stopped`.

- Для каждой попытки используется монотонный `generation`; запоздалые callbacks старой попытки отклоняются.
- `startTunnel`-completion срабатывает один раз: только после `CONNECTED`, при ошибке или при отмене. После установленного соединения ошибки передаются через отдельный `onDisconnection`.
- `stopTunnel`-completion допускается лишь после **подтверждённого join Core worker** и освобождения транспорта. Двойные вызовы `stop` объединяются в одну процедуру завершения.
- Apple-пример `Examples/PacketTunnelProvider/PacketTunnelProvider.swift` использует эту модель и **по-прежнему отвечает ошибкой на старт**. В примере нет Core worker и пакетного канала; поэтому только там фазы join/release подтверждаются синхронно, как пустые операции.
- Значения ошибки не содержат .ovpn, логины, пароли или IP-пакеты.

## Как интегрировать в настоящий Provider (следующий этап)

1. Подписанное расширение получает конфигурацию и секреты разрешённым способом; создаёт `OpenVPNClient`, `MYCODEXPacketBridge`, `MYCODEXTunSocketTransport`.
2. Перед `connect()` вызывает `attachTunSocket` и запускает Core worker в отдельном контексте. Пока `OpenVPNClient.start()` возвращает `-6`, **дальше нельзя проходить**; флаги `MYCODEX_HAS_APPLE_TUN_ADAPTER` и `MYCODEX_PRODUCTION_TUN_TRANSPORT_VERIFIED` не включать без device-проверки.
3. В отдельном рабочем контексте (не MainActor) выполняет `waitForPendingTunSettings`; на MainActor вызывает `MYCODEXAppleTunFDSettingsHandoff.applyPending`. Успех на Apple должен быть подтверждён нативным ACK того же generation.
4. При успехе готовит `MYCODEXApplePacketFlowAdapter` и `MYCODEXApplePacketTransportDriver`, запускает монитор и вызывает `packetTransportDidStart`.
5. Core events, **считанные из `pollEvent()`**, передаются в `receiveCoreEvent`; только `CONNECTED` после пунктов 3–4 разрешает вызывать `startTunnel completionHandler(nil)`.
6. При остановке: `cancelTunHandoff` → `requestStop` → `waitForWorker` вне MainActor → `coreWorkerDidJoin` → `driver.stopMonitoring` → закрытие транспорта и очереди → `resourcesDidRelease` → `stopTunnel completionHandler()`.
7. Перед включением флагов нужен подписанный Xcode extension, entitlement, фактическая проверка UDP/TCP, IPv4/IPv6, DNS, MTU, потоков на устройствах и отсутствие утечек.

## Реальные проверки

- Linux Swift 6.2.1, отдельный SwiftPM стенд с реальным новым исходником и моделью `OpenVPNClientEvent`: **9/9 XCTest**, Release **PASS**. Это не проверка полного репозитория или macOS.
- Swift 6.2.1: проверка типов изменённого примера Provider **со stub NetworkExtension**, PASS. Это не Apple SDK и не подписанная сборка.
- `bash scripts/test-macos-provider-lifecycle.sh`: полная регрессия на MacBook, дополнительные 9 тестов и синтаксический разбор примера; **запустить на MacBook**.

**Ограничение:** пример Provider всё ещё fail-closed. Нативный Core не запускается, `NEPacketTunnelFlow` не подаёт реальные пакеты. В этой стадии готова только последовательность этапов и callback/stop-модель, а не VPN-сессия.
