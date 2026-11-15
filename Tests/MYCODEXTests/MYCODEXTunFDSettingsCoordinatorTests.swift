import Foundation
import XCTest
@testable import MYCODEX

@MainActor
private final class DummyTunFDClient: MYCODEXTunFDSettingsClient {
    var configuration: MYCODEXTunnelNetworkConfiguration?
    var acknowledgements: [(UInt64, Bool)] = []
    var cancellations = 0
    var rejectAcknowledgement = false

    func capturedTunnelConfiguration() throws -> MYCODEXTunnelNetworkConfiguration {
        guard let configuration else { throw MYCODEXTunFDSettingsError.snapshotUnavailable }
        return configuration
    }
    func acknowledgeTunSettings(generation: UInt64, applied: Bool) throws {
        if rejectAcknowledgement { throw MYCODEXTunFDAcknowledgementError.invalidState }
        acknowledgements.append((generation, applied))
    }
    func cancelTunHandoff() throws { cancellations += 1 }
}

final class MYCODEXTunFDSettingsCoordinatorTests: XCTestCase {
    private func config() throws -> MYCODEXTunnelNetworkConfiguration {
        try MYCODEXTunnelNetworkConfiguration(
            remoteAddress: "198.51.100.9",
            ipv4Addresses: [.init(address: "10.9.0.2", subnetMask: "255.255.255.0")],
            dnsServers: ["1.1.1.1"])
    }

    func testNativeAcknowledgementOnlyAfterAppleConfirms() async throws {
        let value = try config()
        await MainActor.run {
            let fake = DummyTunFDClient()
            fake.configuration = value
            let coordinator = MYCODEXTunFDSettingsCoordinator(native: fake)
            var appleCompletion: (@MainActor (Bool) -> Void)?
            var callbackResults: [Result<Void, MYCODEXTunFDSettingsError>] = []
            coordinator.begin(generation: 11, apply: { config, finish in
                XCTAssertEqual(config, value)
                appleCompletion = finish
            }, completion: { callbackResults.append($0) })
            XCTAssertTrue(fake.acknowledgements.isEmpty)
            XCTAssertEqual(coordinator.state, .applying(generation: 11))
            appleCompletion?(true)
            XCTAssertEqual(fake.acknowledgements.count, 1)
            XCTAssertEqual(fake.acknowledgements.first?.0, 11)
            XCTAssertEqual(fake.acknowledgements.first?.1, true)
            XCTAssertEqual(coordinator.state, .acknowledged)
            XCTAssertEqual(callbackResults.count, 1)
            appleCompletion?(true) // duplicate cannot ACK twice
            XCTAssertEqual(fake.acknowledgements.count, 1)
        }
    }

    func testRejectedSettingsNeverApprove() async throws {
        let value = try config()
        await MainActor.run {
            let fake = DummyTunFDClient()
            fake.configuration = value
            let coordinator = MYCODEXTunFDSettingsCoordinator(native: fake)
            var result: Result<Void, MYCODEXTunFDSettingsError>?
            coordinator.begin(generation: 12, apply: { _, finish in finish(false) },
                              completion: { result = $0 })
            XCTAssertEqual(fake.acknowledgements.first?.1, false)
            XCTAssertEqual(coordinator.state, .rejected)
            if case .failure(.networkSettingsRejected)? = result {} else { XCTFail("Wrong rejection") }
        }
    }

    func testCancelIgnoresLateCallback() async throws {
        let value = try config()
        await MainActor.run {
            let fake = DummyTunFDClient()
            fake.configuration = value
            let coordinator = MYCODEXTunFDSettingsCoordinator(native: fake)
            var finish: (@MainActor (Bool) -> Void)?
            var delivered = 0
            coordinator.begin(generation: 15, apply: { _, callback in finish = callback },
                              completion: { _ in delivered += 1 })
            coordinator.cancel()
            finish?(true)
            XCTAssertEqual(delivered, 1)
            XCTAssertEqual(fake.cancellations, 1)
            XCTAssertTrue(fake.acknowledgements.isEmpty)
            XCTAssertEqual(coordinator.state, .cancelled)
        }
    }

    func testMissingCaptureRejectsNativePending() async {
        await MainActor.run {
            let fake = DummyTunFDClient()
            let coordinator = MYCODEXTunFDSettingsCoordinator(native: fake)
            var applied = false
            var result: Result<Void, MYCODEXTunFDSettingsError>?
            coordinator.begin(generation: 21, apply: { _, _ in applied = true },
                              completion: { result = $0 })
            XCTAssertFalse(applied)
            XCTAssertEqual(fake.acknowledgements.count, 1)
            XCTAssertEqual(fake.acknowledgements.first?.1, false)
            if case .failure(.snapshotUnavailable)? = result {} else { XCTFail("Missing failure") }
        }
    }

    func testNativeAckFailureCancelsAndRejects() async throws {
        let value = try config()
        await MainActor.run {
            let fake = DummyTunFDClient()
            fake.configuration = value
            fake.rejectAcknowledgement = true
            let coordinator = MYCODEXTunFDSettingsCoordinator(native: fake)
            var result: Result<Void, MYCODEXTunFDSettingsError>?
            coordinator.begin(generation: 22, apply: { _, finish in finish(true) },
                              completion: { result = $0 })
            XCTAssertEqual(fake.cancellations, 1)
            XCTAssertEqual(coordinator.state, .rejected)
            if case .failure(.nativeAcknowledgementFailed)? = result {} else { XCTFail("Wrong ack failure") }
        }
    }

    func testInvalidGenerationAndDuplicateBegin() async throws {
        let value = try config()
        await MainActor.run {
            let fake = DummyTunFDClient()
            fake.configuration = value
            let coordinator = MYCODEXTunFDSettingsCoordinator(native: fake)
            var callbacks: [MYCODEXTunFDSettingsError] = []
            coordinator.begin(generation: 0, apply: { _, _ in XCTFail("Zero generation") },
                              completion: { if case .failure(let error) = $0 { callbacks.append(error) } })
            XCTAssertEqual(callbacks, [.invalidGeneration])
            var finish: (@MainActor (Bool) -> Void)?
            coordinator.begin(generation: 90, apply: { _, completion in finish = completion },
                              completion: { _ in })
            coordinator.begin(generation: 91, apply: { _, _ in XCTFail("Duplicate begin") },
                              completion: { if case .failure(let error) = $0 { callbacks.append(error) } })
            XCTAssertEqual(callbacks, [.invalidGeneration, .invalidState])
            finish?(true)
            XCTAssertEqual(fake.acknowledgements.count, 1)
        }
    }
}
