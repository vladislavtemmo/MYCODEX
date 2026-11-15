# MYCODEX 8.3B2B — адаптер NEPacketTunnelFlow (без подключения OpenVPN Core)

**Дата:** 2026-11-15. **Исходная ветка:** `feat/apple-core-integration`, коммит `c04ead9`.

## Реализовано

- `Sources/MYCODEX/MYCODEXPacketFlowCoordinator.swift` — переносимый слой управления партиями IP-пакетов между входящим потоком и существующим C++ `MYCODEXPacketBridge`. Проверяет соответствие IP версии и AF_INET/AF_INET6, ограничивает размер очереди, удерживает непринятые пакеты при backpressure.
- `Sources/MYCODEX/MYCODEXApplePacketFlowAdapter.swift` — условно компилируемый `#if canImport(NetworkExtension)` адаптер Apple. Вызывает `NEPacketTunnelFlow.readPackets` и `writePackets`. Методы изолированы `MainActor`; callback передаёт на него только Sendable-массивы `Data` и `Int32`.
- Указатель `MYCODEXPacketBridge.maximumQueueBytes` помогает отклонить пакет, заведомо превышающий размер очереди, вместо бесконечного ожидания.
- Swift `dequeue` выделяет сначала 2048 байт и увеличивает размер по `actual_length` из C ABI для более крупных пакетов. Это снижает размер временного выделения на обычном пакете, но **ещё не является измеренной оптимизацией throughput**.

## Жизненный цикл

1. Подписанный `NEPacketTunnelProvider` должен сначала получить проверенные сетевые настройки из OpenVPN Core и успешно вызвать `setTunnelNetworkSettings`.
2. Только после этого создать `MYCODEXApplePacketFlowAdapter(flow:bridge:onFailure:)` и вызвать `beginReading()`.
3. При чтении TUN пакеты помещаются в очередь `.toCore`. Если она полна, адаптер удерживает остаток batch и **не** делает новый `readPackets`, пока потребитель не вызовет `ingressQueueDidDrain()`.
4. Когда будущий Core передаст IP-пакеты в `.toSystem`, вызывающая сторона должна вызвать `flushCoreToSystem()`. При `false` от `writePackets` batch остаётся в памяти для повторной попытки, но Apple API не гарантирует exactly-once delivery: этот сценарий требует device тестов.
5. `stop()` прекращает постановку новых чтений и закрывает очереди. Удерживаемые ранее данные очищаются. Отложенные системные callback'и игнорируются.
6. При ошибке адаптер закрывается и вызывает `onFailure`; владелец-Provider должен завершить или безопасно отменить VPN-сессию.

## Ограничения и известные риски

- **НЕТ связки с OpenVPN TunBuilderBase / ExternalTun::Factory / TUN C++ packet engine.** Никакой реальный encrypted tunnel не создаётся; `mycodex_client_start()` по-прежнему обязан возвращать `tunnelUnavailable`.
- Нет реализации `NEPacketTunnelProvider`, entitlement, настройки приложения/extension, пользовательского разрешения, socket bypass, а также гарантированной работы IPv6 и DNS.
- Нет автоматической подписки на событие опустошения очереди Core. Будущая Core-часть должна вызывать `ingressQueueDidDrain` при освобождении места и `flushCoreToSystem` после появления исходящих пакетов. До её подключения `beginReading()` **не использовать в рабочем VPN** — очередь может заполниться.
- Ограничение памяти нативного C++ моста задаётся в байтах и количестве пакетов **на каждое направление**; дополнительно Apple может единовременно вернуть произвольный batch. Его фактический предел необходимо измерить в расширении.
- Типы `MYCODEXPacketBridge` и `MYCODEXPacketFlowCoordinator` не Sendable. Уничтожение нельзя совмещать с native вызовами в других потоках; Apple-адаптер изолирован MainActor.
- Содержимое VPN-пакетов и секреты не выводятся в логи.
- Переносимые XCTest на Linux проверяют backpressure, порядок, размеры и retry. Компиляцию реального `NetworkExtension`, выполнение callback'ов, device-тесты и CPU/throughput нужно провести на Mac/iPhone; локальная проверка типов с тестовой заглушкой Apple API не доказывает совместимость с реальным SDK.

## Проверка

```bash
swift test
swift build -c release
bash scripts/test-macos-packet-bridge.sh
```

После успешной проверки на Mac — коммитить изменения в `feat/apple-core-integration`. Следующий самостоятельный этап: реализация ExternalTun/`TunBuilderBase` с подтверждением сетевых настроек Provider и реальным worker lifetime.
