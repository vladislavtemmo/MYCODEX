import Foundation
import XCTest
@testable import MYCODEX

final class MYCODEXPacketBridgeTests: XCTestCase {
    private func ipv4() throws -> MYCODEXPacket {
        try MYCODEXPacket(data: Data([0x45] + Array(repeating: 0, count: 19)))
    }

    private func ipv6() throws -> MYCODEXPacket {
        try MYCODEXPacket(data: Data([0x60] + Array(repeating: 0, count: 39)))
    }

    func testIndependentDirectionsAndOrder() throws {
        let bridge = try MYCODEXPacketBridge(maxPackets: 2, maxBytes: 1024)
        let first = try ipv4()
        let second = try ipv6()
        XCTAssertTrue(try bridge.enqueue(first, direction: .toCore))
        XCTAssertTrue(try bridge.enqueue(second, direction: .toCore))
        XCTAssertTrue(try bridge.enqueue(first, direction: .toSystem))
        XCTAssertEqual(try bridge.statistics(direction: .toCore),
                       MYCODEXPacketQueueStats(packets: 2, bytes: 60))
        XCTAssertEqual(try bridge.statistics(direction: .toSystem).packets, 1)
        XCTAssertEqual(try bridge.dequeue(direction: .toCore), first)
        XCTAssertEqual(try bridge.dequeue(direction: .toCore), second)
        XCTAssertNil(try bridge.dequeue(direction: .toCore))
        XCTAssertEqual(try bridge.dequeue(direction: .toSystem), first)
    }

    func testFullQueueReturnsBackpressureWithoutDropping() throws {
        let bridge = try MYCODEXPacketBridge(maxPackets: 1, maxBytes: 1024)
        let packet = try ipv4()
        XCTAssertTrue(try bridge.enqueue(packet, direction: .toCore))
        XCTAssertFalse(try bridge.enqueue(packet, direction: .toCore))
        XCTAssertEqual(try bridge.dequeue(direction: .toCore), packet)
        XCTAssertTrue(try bridge.enqueue(packet, direction: .toCore))
    }

    func testByteBoundAndIdempotentClose() throws {
        let bridge = try MYCODEXPacketBridge(maxPackets: 64, maxBytes: 1024)
        let packet = try MYCODEXPacket(data: Data([0x60] + Array(repeating: 0, count: 599)))
        XCTAssertTrue(try bridge.enqueue(packet, direction: .toSystem))
        XCTAssertFalse(try bridge.enqueue(packet, direction: .toSystem))
        try bridge.close()
        try bridge.close()
        XCTAssertThrowsError(try bridge.enqueue(packet, direction: .toCore)) {
            XCTAssertEqual($0 as? MYCODEXPacketBridgeError, .closed)
        }
        XCTAssertEqual(try bridge.dequeue(direction: .toSystem), packet)
        XCTAssertThrowsError(try bridge.dequeue(direction: .toSystem)) {
            XCTAssertEqual($0 as? MYCODEXPacketBridgeError, .closed)
        }
    }

    func testInvalidPacketsAndQuotas() throws {
        XCTAssertThrowsError(try MYCODEXPacket(data: Data()))
        XCTAssertThrowsError(try MYCODEXPacket(data: Data([0x45, 0x00])))
        XCTAssertThrowsError(try MYCODEXPacket(data: Data([0x55] + Array(repeating: 0, count: 39))))
        XCTAssertThrowsError(try MYCODEXPacketBridge(maxPackets: 0))
        XCTAssertThrowsError(try MYCODEXPacketBridge(maxPackets: 1025))
        XCTAssertThrowsError(try MYCODEXPacketBridge(maxBytes: 100))
        XCTAssertThrowsError(try MYCODEXPacketBridge(maxBytes: 9 * 1_048_576))
    }
}
