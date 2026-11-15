# MYCODEX 8.3B2D2D2 — событийное управление пакетным транспортом

**Основа:** `feat/apple-core-integration@5cee693` (репозиторий переименован в `OpenVPNAdapte-for-Apple`). **Дата:** 2026-11-15.

## Реализовано

- В C ABI добавлен `mycodex_tun_socket_dup_monitor_fd`: владение отдельным `dup()` pump-конца `socketpair`. Дескриптор предназначен **только для наблюдения** (`poll`/`DispatchSource`); `recv/send` на нём опасны, поскольку будут конкурировать с `mycodex_tun_socket_pump`.
- `mycodex_tun_socket_core_write_pending` проверяет, удерживает ли насос пакет после `EAGAIN`; очередь `.toCore` проверяется отдельно.
- `MYCODEXApplePacketTransportDriver` управляет `DispatchSourceRead`/`DispatchSourceWrite` на главной очереди. Пробуждение при пакетах от Core; наблюдение writable включается **только** при существующих исходящих данных — нет постоянного busy poll.
- Каждая итерация ограничена максимум 32 пакетами на направление. `MYCODEXApplePacketFlowAdapter.onIngressStaged` инициирует перенос новых системных пакетов в Core; после освобождения входящей очереди `ingressQueueDidDrain()` возобновляет ранее приостановленную обработку.
- При `writePackets == false` сохранённый batch не удаляется; чтение из Core приостанавливается до вызова `retryOutput()` владельцем.
- При отмене GCD-источников их независимые monitor FD закрываются в cancel handlers, а при остановке остановленные/suspended источники сначала resume, чтобы избежать утечек.
- Windows C ABI получил явные -2 заглушки; SwiftPM fallback по-прежнему не включает реальный VPN.

## Важные требования к владельцу

1. **Не запускайте драйвер на неподписанном тестовом Provider** и не вызывайте `beginReading` до подтверждения `setTunnelNetworkSettings`. Сам факт ACK не означает успешное VPN-соединение.
2. Сначала должен стартовать настоящий OpenVPN Core worker с настоящими настройками, иметь подключённый `MYCODEXTunSocketTransport`, и пройти native FD handoff. Только после этого допустимо включить пакетный монитор. **Этот этап ещё не подключает worker к Provider автоматически.**
3. При остановке: остановить и дождаться завершения native Core worker, вызвать `driver.stopMonitoring()` (не даёт запоздалым callback продолжать работу), затем закрыть `MYCODEXTunSocketTransport` и освободить очередь/клиент. Уничтожение native handle одновременно с pump запрещено.
4. `retryOutput()` — явный сигнал возобновления после отказа системного writer. Автоматическая сигнализация готовности `NEPacketTunnelFlow.writePackets` отсутствует; требуется end-to-end тест на устройстве.
5. Новые `DispatchSource` только следят за готовностью дескриптора. Они **не** обеспечивают TLS, маршрутизацию, DNS leak protection или обработку CONNECTED.
6. Драйвер использует `MainActor` и не предназначен для бесконтрольного throughput. Перед реальным релизом необходимо профилировать нагрузку и, при необходимости, перенести bounded pump на выделенную serial queue при сохранении последовательности жизни объектов.
7. Нет production `NEPacketTunnelProvider` с жизненным циклом Core и entitlement; пример Provider всё ещё возвращает ошибку. `mycodex_client_start()` обязан оставаться заблокированным (`-6`).

## Проверки

- `swift test` — переносимые XCTest, включая наблюдение FD без поглощения датаграммы и независимое владение monitor FD.
- `swift build -c release` — сохранение резервного режима SwiftPM.
- `bash scripts/test-macos-packet-wakeup.sh` — вся предыдущая регрессия OpenVPN 3 Core + новая проверка на macOS, в том числе link/export C ABI.
- Реальная Apple-ветка должна компилироваться Swift 6 / Xcode; подписанный extension и реальные сетевые потоки **не проверены**.

**Следующий этап:** отдельный `NEPacketTunnelProvider` target + управление настоящим Core worker и запуском session; затем сквозное испытание и только тогда разрешение нативного `start()`.
