# MYCODEX — публичный API и направление развития

## Уже реализовано и проверено в переносимой сборке

- `OpenVPNTransport`: `udp`, `tcp`.
- `OpenVPNEndpoint`: структурно проверяемый hostname и ненулевой порт.
- `OpenVPNConnectionState`: набор будущих состояний.
- `OpenVPNProfile`: хранение текста `.ovpn` с редакцией при `description`/`debugDescription` и ограничением размера.
- `OpenVPNProfileInspector.remoteEndpoints(in:)`: ограниченное извлечение `remote`, `proto` и `<connection>`; не полноценный parser и не проверка безопасности.
- `OpenVPNNativeBridge`: версия ABI, имя нативного backend и `isOpenVPNCoreLinked == false` до интеграции ядра.

### Пример работы только с профилем

```swift
import MYCODEX
import MYCODEXConfiguration

let profile = try OpenVPNProfile(ovpnText: """
client
proto udp
remote vpn.example.org 1194
""")
let endpoints = try OpenVPNProfileInspector.remoteEndpoints(in: profile)
print(endpoints.map(\.hostname))
print(OpenVPNNativeBridge.isOpenVPNCoreLinked) // Сейчас false
```

## Проектируется, но не реализовано

- `OpenVPNClient` с `async/await`-операциями `start`, `stop`, `cancel`.
- Поток событий соединения `AsyncSequence`.
- `OpenVPNConnectionOptions`, ограничения таймаута и политики reconnect.
- Ошибки с явными причинами (`invalidProfile`, `authenticationFailed`, `transportError`, `permissionDenied`, `cancelled`).
- Секреты через Keychain references и отдельный безопасный слой.
- Отдельные API хост-приложения и `NEPacketTunnelProvider` без смешивания ответственностей.
- Совместимый переход с устаревшего OpenVPNAdapter после изучения потребительских сценариев.

**Важное ограничение:** будущие имена и сигнатуры не утверждены окончательно. Не разрабатывать потребительское приложение, исходя из существования этих классов до их появления в репозитории.
