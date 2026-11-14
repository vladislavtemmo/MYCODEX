# MYCODEX — проверка возможности Packet Tunnel на платформах Apple

**Состояние:** сведения о доступности Apple API подтверждены документацией; сборка MYCODEX и entitlement на устройствах не подтверждены.

| Платформа | Документированный тип поставки Packet Tunnel | Статус MYCODEX |
| --- | --- | --- |
| iOS / iPadOS | App Extension | Целевая, НЕ проверено в Xcode |
| macOS | App Extension (с ограничением App Store) или System Extension | Целевая, НЕ проверено в Xcode |
| tvOS 17+ | App Extension; per-app VPN не поддерживается | Исследовать |
| visionOS | App Extension с ограничениями per-app режима | Исследовать |
| watchOS | Нет подтверждения Packet Tunnel Provider | Не обещать локальный VPN-туннель |

Минимальные версии Swift Package MYCODEX — iOS 16 и macOS 13 — предварительный продуктовый выбор, не минимумы NetworkExtension.

`NEPacketTunnelProvider` управляет параметрами виртуального сетевого интерфейса и пакетным потоком `packetFlow`, а entitlement `com.apple.developer.networking.networkextension` является обязательным. Наличие поддержки API **не означает**, что SDK автоматически получит доступ к нему без подписи, разрешений и настройки App ID.

Тестировать отдельно: наличие entitlement, подписание host app и extension, сохранение конфигурации VPN, пользовательское разрешение, соединение, настройки DNS/routes/MTU и завершение туннеля.

Источники:
- https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment
- https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
