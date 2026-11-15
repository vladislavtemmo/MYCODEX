# MYCODEX 8.3B2D — контролируемая подготовка Packet Tunnel Provider

Дата: 2026-11-15. Основа: `feat/apple-core-integration@4a298a4`.

## Реализовано

- `MYCODEXPacketTunnelPreparation`: переносимая машина состояний `idle → applyingSettings → settingsApplied → coreTransportReady`, с остановкой и отклонением запоздалых callbacks по токену поколения. `settingsApplied` не означает VPN `CONNECTED`.
- `MYCODEXAppleTunnelSettingsApplier`: Apple-only MainActor-обёртка, асинхронно вызывает настоящий `NEPacketTunnelProvider.setTunnelNetworkSettings(...)` и уведомляет об успехе/ошибке ровно один раз. Поздний ответ после `cancel()` игнорируется. Внешняя ошибка Apple не логируется с сетевыми параметрами.
- `Examples/PacketTunnelProvider/PacketTunnelProvider.swift`: пример реального класса `NEPacketTunnelProvider` для будущего Xcode extension target. Пока **намеренно всегда отказывает в `startTunnel`**, а не возвращает ложный успех. Для включения в расширение необходимы Xcode target, Bundle ID, capabilities, entitlement, подпись, пользовательское разрешение, настоящая интеграция native TUN и device tests.
- `MYCODEXApplePacketFlowAdapter` здесь ещё **не запускается**, потому что Core не подключён к пакетной очереди и неизвестно, как будет подтверждаться готовность TUN FD/ExternalTun.

## Гарантии и ограничения

1. Реальный OpenVPN 3 Core и `TunBuilderBase` в текущей macOS-интеграции используют `OPENVPN_FORCE_TUN_NULL`; `tun_builder_establish()` не выдаёт работающий TUN. Флаг `MYCODEX_HAS_APPLE_TUN_ADAPTER` **не включать**.
2. Успешный callback `setTunnelNetworkSettings` — **только** подтверждение сетевой конфигурации. Запуск VPN разрешён исключительно после готовности native packet transport и фактической Core-сессии; `runState.running` не означает `CONNECTED`.
3. `MYCODEXAppleTunnelSettingsApplier` должен жить у владельца-Provider до окончания callback. `cancel()` вызывается при остановке/тайм-ауте. Временная защита по токену исключает повторное завершение из позднего callback.
4. Продолжают требоваться fail-safe обработка отмены, ограниченная очередь пакетов, завершение C++ worker до уничтожения bridge, корректные socket routing/bypass и реальные испытания IPv4/IPv6/DNS/MTU.
5. Код примера не включён в SwiftPM target намеренно: `NEPacketTunnelProvider` — класс системного extension, который должен быть частью подписанного приложения. `swift test` проверяет машину состояний; Apple-код компилируется только на Apple-хосте. Один лишь синтаксический разбор файла примера не гарантирует корректность Xcode target.

## Тестирование

```bash
swift test
swift build -c release
bash scripts/test-macos-provider-preparation.sh
```

После рабочего VPN transport потребуется подписанный extension target и end-to-end проверка с сервером. До этого проект остаётся SDK-подготовкой, а не подключающим VPN-клиентом.
