import Foundation
import XCTest
@testable import MYCODEX

final class MYCODEXPacketFlowCoordinatorTests: XCTestCase {
    private func packet(_ version: Int = 4, length: Int = 20) throws -> MYCODEXPacket {
        try MYCODEXPacket(data: Data([version == 4 ? 0x45 : 0x60] +
                                          Array(repeating: 0, count: max(length - 1, 0))))
    }

    func testClassifyRejectsFamilyMismatchAndInvalidBatch() throws {
        let v4 = try packet()
        XCTAssertEqual(try MYCODEXPacketFlowCoordinator.classify([v4.data],
                                             protocolFamilies: [v4.kind.protocolFamily]), [v4])
        XCTAssertThrowsError(try MYCODEXPacketFlowCoordinator.classify([v4.data], protocolFamilies: [])) {
            XCTAssertEqual($0 as? MYCODEXPacketFlowError, .invalidReadBatch)
        }
        XCTAssertThrowsError(try MYCODEXPacketFlowCoordinator.classify([v4.data],
                           protocolFamilies: [MYCODEXIPPacketKind.ipv6.protocolFamily])) {
            XCTAssertEqual($0 as? MYCODEXPacketFlowError, .protocolFamilyMismatch)
        }
    }

    func testIngressWaitsForCoreDrainWithoutLossOrReordering() throws {
        let bridge = try MYCODEXPacketBridge(maxPackets: 1, maxBytes: 1024)
        let coordinator = MYCODEXPacketFlowCoordinator(bridge: bridge)
        let v4 = try packet()
        let v6 = try packet(6, length: 40)
        XCTAssertFalse(try coordinator.stageIncoming([v4, v6]))
        XCTAssertTrue(coordinator.hasPendingIngress)
        XCTAssertThrowsError(try coordinator.stageIncoming([v4])) {
            XCTAssertEqual($0 as? MYCODEXPacketFlowError, .pendingReadBatch)
        }
        XCTAssertEqual(try bridge.dequeue(direction: .toCore), v4)
        XCTAssertTrue(try coordinator.resumeIncoming())
        XCTAssertFalse(coordinator.hasPendingIngress)
        XCTAssertEqual(try bridge.dequeue(direction: .toCore), v6)
        XCTAssertNil(try bridge.dequeue(direction: .toCore))
    }

    func testOversizedIngressCannotHangOnBackpressure() throws {
        let bridge = try MYCODEXPacketBridge(maxPackets: 2, maxBytes: 1024)
        let coordinator = MYCODEXPacketFlowCoordinator(bridge: bridge)
        let huge = try packet(6, length: 1500)
        XCTAssertThrowsError(try coordinator.stageIncoming([huge])) {
            XCTAssertEqual($0 as? MYCODEXPacketFlowError, .packetExceedsQueueCapacity)
        }
        XCTAssertFalse(coordinator.hasPendingIngress)
    }

    func testFailedSystemWriteKeepsBatchForRetry() throws {
        let bridge = try MYCODEXPacketBridge(maxPackets: 4, maxBytes: 1024)
        let coordinator = MYCODEXPacketFlowCoordinator(bridge: bridge)
        let v4 = try packet()
        let v6 = try packet(6, length: 40)
        XCTAssertTrue(try bridge.enqueue(v4, direction: .toSystem))
        XCTAssertTrue(try bridge.enqueue(v6, direction: .toSystem))
        var attempted: [MYCODEXPacket] = []
        XCTAssertFalse(try coordinator.flushOutgoing { packets in
            attempted = packets
            return false
        })
        XCTAssertEqual(attempted, [v4, v6])
        XCTAssertTrue(coordinator.hasPendingEgress)
        XCTAssertEqual(try bridge.statistics(direction: .toSystem).packets, 0)
        XCTAssertTrue(try coordinator.flushOutgoing { packets in
            XCTAssertEqual(packets, [v4, v6])
            return true
        })
        XCTAssertFalse(coordinator.hasPendingEgress)
    }


    func testLargePacketUsesExactSizeFallback() throws {
        let bridge = try MYCODEXPacketBridge(maxPackets: 2, maxBytes: 8192)
        let jumbo = try packet(6, length: 5000)
        XCTAssertTrue(try bridge.enqueue(jumbo, direction: .toSystem))
        XCTAssertEqual(try bridge.dequeue(direction: .toSystem), jumbo)
    }

    func testBoundedOutgoingFlushAndClose() throws {
        let bridge = try MYCODEXPacketBridge(maxPackets: 4, maxBytes: 1024)
        let coordinator = MYCODEXPacketFlowCoordinator(bridge: bridge)
        let v4 = try packet()
        for _ in 0..<3 { XCTAssertTrue(try bridge.enqueue(v4, direction: .toSystem)) }
        var sent = 0
        XCTAssertTrue(try coordinator.flushOutgoing(maxBatch: 2) { items in
            sent += items.count
            return true
        })
        XCTAssertEqual(sent, 2)
        XCTAssertTrue(try coordinator.flushOutgoing(maxBatch: 2) { items in
            sent += items.count
            return true
        })
        XCTAssertEqual(sent, 3)
        XCTAssertThrowsError(try coordinator.flushOutgoing(maxBatch: 0) { _ in true }) {
            XCTAssertEqual($0 as? MYCODEXPacketFlowError, .invalidBatchLimit)
        }
        try coordinator.close()
        try coordinator.close()
        XCTAssertThrowsError(try coordinator.resumeIncoming()) {
            XCTAssertEqual($0 as? MYCODEXPacketFlowError, .closed)
        }
    }
}
