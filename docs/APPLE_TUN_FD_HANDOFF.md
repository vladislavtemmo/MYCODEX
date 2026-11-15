# MYCODEX 8.3B2D2C — подтверждаемый TUN FD handoff

**Основа:** `feat/apple-core-integration` @ `8c5e64e` (2026-11-15).

## Что реально подключено

`OpenVPNClient` в конфигурации `OPENVPN_EXTERNAL_TUN_FACTORY` создаёт `TunBuilderClient::ClientConfig`. Его `TunBuilderBase::tun_builder_establish()` теперь умеет вернуть **настоящий дублированный файловый дескриптор** неблокирующего `AF_UNIX/SOCK_DGRAM` socketpair, но **только после явного ACK** принятия сетевых настроек.

1. Создать `MYCODEXPacketBridge` и `MYCODEXTunSocketTransport` (предыдущий шаг).
2. Получить `duplicateCoreFileDescriptor()`. Вызывающая сторона владеет копией и должна `close` её после `mycodex_client_tun_attach_fd()`: эта функция создаёт свою копию и валидирует сокет.
3. Подготовить OpenVPNClient и (в будущем) запустить Core worker из подписанного `NEPacketTunnelProvider`. **Сейчас `mycodex_client_start` по-прежнему возвращает `-6`; не включать connect в текущей сборке.**
4. После получения PUSH-настроек Core вызывает `tun_builder_new`, остальные `tun_builder_*`, затем `tun_builder_establish`. Последний блокирует *рабочий поток Core*, а не главный поток Apple, не более 15 секунд.
5. Параллельный поток Provider вызывает `mycodex_client_tun_wait_pending(handle, timeout_ms, &generation)`; при `1` получает действительный generation token. Затем снимает snapshot через существующий C ABI, преобразует в `MYCODEXTunnelNetworkConfiguration` и дожидается реального успешного завершения `setTunnelNetworkSettings`.
6. Только при подтверждении Apple: `mycodex_client_tun_ack_settings(handle, generation, 1)`. При ошибке обязательно `..., 0)`. Отрицательный ACK, истечение тайм-аута и отмена всегда возвращают Core `-1` вместо TUN FD.
7. Ранний, запоздалый, повторный ACK или ACK с другим token возвращает `-4`. `mycodex_client_tun_cancel` отменяет ожидание, закрывает внутреннюю копию FD и запрещает его повторное использование. `request_stop` при активном worker и `destroy` также отменяют ожидающий handoff до join.
8. Получив descriptor, Core в будущем сможет использовать его через upstream `TunBuilderClient::Tun`, а внешняя сторона должна независимо качать пакеты через `mycodex_tun_socket_pump` с пробуждением при готовности данных. Автоматический pump и подписанный Provider ещё не соединены.

## Границы реализации

- Фактический тестовый TUN — **локальный Unix datagram socket**, не системный `utun`. Ни байты из Apple `packetFlow`, ни VPN-трафик на сервер в этом шаге не направляются.
- `MYCODEX_HAS_APPLE_TUN_ADAPTER` и `MYCODEX_PRODUCTION_TUN_TRANSPORT_VERIFIED` **не включены**, `tunnel_available=0`, `start=-6`.
- API handoff можно вызвать во время будущего Core worker при условии, что клиент жив. `destroy` **не разрешается** выполнять одновременно с `wait_pending`, `ack`, `attach` и другими вызовами по этому handle. Сначала нужно остановить контроллер и дождаться завершения его операций.
- В C ABI нет защиты от недобросовестного вызывающего кода: ACK `1` должен передаваться только после подтверждения **настоящего** `NEPacketTunnelProvider` (пока не реализовано).
- Требуется отдельная реализация управления изменениями PUSH_UPDATE, reconnect, соответствием DNS и полнотой маршрутов; она будет отдельным этапом.
- Повторное подключение на том же экземпляре FD handoff не поддерживается: после успешного establish дескриптор расходуется, при остановке нужен новый Core client и новый socketpair.
- Каждая проверка работает на тестовых IP и не подключается к внешней сети.

## Тесты

На macOS Intel:

```bash
bash scripts/test-macos-tun-fd-handoff.sh
```

Тест сначала проверяет весь предыдущий стек, затем компилирует header-only state machine и **отдельную** нативную библиотеку `OpenVPN3` с `OPENVPN_EXTERNAL_TUN_FACTORY MYCODEX_TUN_FD_TESTING` (без `OPENVPN_FORCE_TUN_NULL`). Тестовый символ `mycodex_client_tun_fd_test_fixture` вызывает настоящие C++ callbacks, делает ACK с корректным token и проверяет roundtrip по socketpair. Этот символ не входит в обычную production-библиотеку.

На Linux проверены только standalone C++ и SwiftPM fallback. Проверить настоящий OpenVPN 3 Core на MacBook обязательно до git commit.

## Следующий этап

Связать handoff с Swift API `OpenVPNClient` и реальным `setTunnelNetworkSettings` в расширении, добавить пробуждения packet pump и Xcode-signing/entitlement. Только после полной проверки можно безопасно снимать блокировку `connect()`.
