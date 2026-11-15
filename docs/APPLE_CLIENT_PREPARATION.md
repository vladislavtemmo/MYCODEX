# MYCODEX — первый инкремент OpenVPNClient

- C++ создаёт реальный `openvpn::ClientAPI::OpenVPNClient` через opaque handle.
- C ABI: `mycodex_client_create`, `mycodex_client_configure`, `mycodex_client_destroy`.
- Swift `OpenVPNClient` владеет opaque handle, проверяет `.ovpn` и освобождает объект в `deinit`.
- НЕТ `connect`, `stop`, credentials, callbacks, NetworkExtension, VPN-туннеля и реальной статистики.
- Операции с одним экземпляром выполняются последовательно; объект не `Sendable`.
- `swift test` проверяет честное отсутствие движка в обычном SwiftPM.
- `bash scripts/test-macos-swift-client.sh` требует настоящий локальный OpenVPN 3 Core.
- Это технический инкремент, не готовая VPN-библиотека.
