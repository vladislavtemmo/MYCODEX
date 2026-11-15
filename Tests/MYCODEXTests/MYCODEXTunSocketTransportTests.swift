import Foundation
import XCTest
import COpenVPNBridge
@testable import MYCODEX

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class MYCODEXTunSocketTransportTests: XCTestCase {
    private func ipv4(_ byte: UInt8 = 1) throws -> MYCODEXPacket {
        try MYCODEXPacket(data: Data([0x45] + Array(repeating: byte, count: 19)))
    }

    #if os(Windows)
    func testWindowsRejectsPosixSocketTransport() throws {
        let queue = try MYCODEXPacketBridge()
        XCTAssertThrowsError(try MYCODEXTunSocketTransport(bridge: queue))
    }
    #else
    func testBidirectionalPacketDeliveryAndIdlePump() throws {
        let queue = try MYCODEXPacketBridge(maxPackets: 2, maxBytes: 1024)
        let transport = try MYCODEXTunSocketTransport(bridge: queue)
        let fd = try transport.duplicateCoreFileDescriptor()
        defer { _ = close(fd) }
        let packet = try ipv4(0x22)
        XCTAssertTrue(try queue.enqueue(packet, direction: .toCore))
        let ingress = try transport.pump()
        XCTAssertEqual(ingress.intoCore, 1)
        XCTAssertEqual(ingress.intoSystem, 0)
        var bytes = [UInt8](repeating: 0, count: 128)
        let received = bytes.withUnsafeMutableBufferPointer {
            recv(fd, $0.baseAddress, $0.count, Int32(MSG_DONTWAIT))
        }
        XCTAssertEqual(received, packet.data.count)
        XCTAssertEqual(Data(bytes.prefix(max(0, received))), packet.data)

        let sent = packet.data.withUnsafeBytes {
            send(fd, $0.baseAddress, $0.count, Int32(MSG_DONTWAIT))
        }
        XCTAssertEqual(sent, packet.data.count)
        let egress = try transport.pump()
        XCTAssertEqual(egress.intoSystem, 1)
        XCTAssertEqual(try queue.dequeue(direction: .toSystem), packet)
        XCTAssertEqual(try transport.pump(), MYCODEXTunSocketProgress(intoCore: 0, intoSystem: 0))
    }

    func testReadinessDescriptorObservesPacketsWithoutConsumingThem() throws {
        let queue = try MYCODEXPacketBridge(maxPackets: 2, maxBytes: 1024)
        let transport = try MYCODEXTunSocketTransport(bridge: queue)
        let coreFD = try transport.duplicateCoreFileDescriptor()
        let monitorFD = try transport.duplicateMonitorFileDescriptor()
        defer { _ = close(monitorFD); _ = close(coreFD) }
        XCTAssertFalse(try transport.hasPendingCoreWrite())
        var event = pollfd(fd: monitorFD, events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&event, 1, 0), 0)

        let packet = try ipv4(0x44)
        let sent = packet.data.withUnsafeBytes {
            send(coreFD, $0.baseAddress, $0.count, Int32(MSG_DONTWAIT))
        }
        XCTAssertEqual(sent, packet.data.count)
        XCTAssertEqual(poll(&event, 1, 100), 1)
        XCTAssertNotEqual(event.revents & Int16(POLLIN), 0)
        XCTAssertEqual(try transport.pump().intoSystem, 1)
        XCTAssertEqual(try queue.dequeue(direction: .toSystem), packet)
        XCTAssertEqual(poll(&event, 1, 0), 0)
    }

    func testMonitorDescriptorIsOwnedIndependently() throws {
        let queue = try MYCODEXPacketBridge()
        let transport = try MYCODEXTunSocketTransport(bridge: queue)
        let monitorFD = try transport.duplicateMonitorFileDescriptor()
        XCTAssertGreaterThanOrEqual(monitorFD, 0)
        _ = close(monitorFD)
        let coreFD = try transport.duplicateCoreFileDescriptor()
        _ = close(coreFD)
        XCTAssertFalse(try transport.hasPendingCoreWrite())
        try transport.close()
        XCTAssertThrowsError(try transport.duplicateMonitorFileDescriptor()) {
            XCTAssertEqual($0 as? MYCODEXTunSocketError, .closed)
        }
        XCTAssertThrowsError(try transport.hasPendingCoreWrite()) {
            XCTAssertEqual($0 as? MYCODEXTunSocketError, .closed)
        }
    }

    func testFullEgressQueueRetainsPendingDatagram() throws {
        let queue = try MYCODEXPacketBridge(maxPackets: 1, maxBytes: 1024)
        let transport = try MYCODEXTunSocketTransport(bridge: queue)
        let fd = try transport.duplicateCoreFileDescriptor()
        defer { _ = close(fd) }
        let first = try ipv4(0x31)
        let second = try ipv4(0x32)
        for packet in [first, second] {
            let count = packet.data.withUnsafeBytes {
                send(fd, $0.baseAddress, $0.count, Int32(MSG_DONTWAIT))
            }
            XCTAssertEqual(count, packet.data.count)
        }
        XCTAssertEqual(try transport.pump(maxPerDirection: 8).intoSystem, 1)
        XCTAssertEqual(try queue.dequeue(direction: .toSystem), first)
        XCTAssertEqual(try transport.pump(maxPerDirection: 8).intoSystem, 1)
        XCTAssertEqual(try queue.dequeue(direction: .toSystem), second)
    }

    func testCloseAndInvalidArgumentsAreExplicit() throws {
        let queue = try MYCODEXPacketBridge()
        let transport = try MYCODEXTunSocketTransport(bridge: queue)
        XCTAssertThrowsError(try transport.pump(maxPerDirection: 0)) {
            XCTAssertEqual($0 as? MYCODEXTunSocketError, .invalidArgument)
        }
        try transport.close()
        try transport.close()
        XCTAssertThrowsError(try transport.duplicateCoreFileDescriptor()) {
            XCTAssertEqual($0 as? MYCODEXTunSocketError, .closed)
        }
        XCTAssertThrowsError(try transport.pump()) {
            XCTAssertEqual($0 as? MYCODEXTunSocketError, .closed)
        }
    }

    func testInvalidDatagramIsRejected() throws {
        let queue = try MYCODEXPacketBridge()
        let transport = try MYCODEXTunSocketTransport(bridge: queue)
        let fd = try transport.duplicateCoreFileDescriptor()
        defer { _ = close(fd) }
        let invalid = [UInt8](repeating: 0x22, count: 20)
        let sent = invalid.withUnsafeBytes {
            send(fd, $0.baseAddress, $0.count, Int32(MSG_DONTWAIT))
        }
        XCTAssertEqual(sent, invalid.count)
        XCTAssertThrowsError(try transport.pump()) {
            XCTAssertEqual($0 as? MYCODEXTunSocketError, .invalidPacket)
        }
    }
    #endif
}
