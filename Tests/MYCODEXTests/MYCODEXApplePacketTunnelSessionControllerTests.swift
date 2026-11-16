#if canImport(NetworkExtension) && canImport(Darwin)
import XCTest
@testable import MYCODEX

@MainActor
private final class MockTunnelRuntime: MYCODEXAppleTunnelSessionRuntime {
    var startError: Error?
    var ack = true
    var pending: UInt64? = 11
    var events: [OpenVPNClientEvent] = []
    var state: OpenVPNClientRunState = .running
    var started = 0
    var acked = 0
    var transportStarted = 0
    var stopRequested = 0
    var joined = 0
    var released = 0
    var holdJoin = false
    var joinContinuation: CheckedContinuation<Void, Never>?

    func start() throws {
        started += 1
        if let startError { throw startError }
    }
    func waitForPendingTunSettings() async throws -> UInt64? {
        if let pending {
            self.pending = nil
            return pending
        }
        try await Task.sleep(for: .milliseconds(10))
        return nil
    }
    func applyPendingTunSettings(generation: UInt64) async -> Bool {
        acked += 1
        return ack
    }
    func startPacketTransport() throws { transportStarted += 1 }
    func pollEvent() throws -> OpenVPNClientEvent? {
        events.isEmpty ? nil : events.removeFirst()
    }
    func workerState() throws -> OpenVPNClientRunState { state }
    func requestStop() throws { stopRequested += 1 }
    func joinWorker() async throws {
        if holdJoin {
            await withCheckedContinuation { joinContinuation = $0 }
        }
        joined += 1
    }
    func releaseResources() async { released += 1 }
    func finishJoin() { joinContinuation?.resume(); joinContinuation = nil }
}

@MainActor
private final class FactoryProbe {
    var calls = 0
    var profile: String?
    var credentials: MYCODEXAppleTunnelCredentials?
    var continuation: CheckedContinuation<any MYCODEXAppleTunnelSessionRuntime, Error>?
}

final class MYCODEXApplePacketTunnelSessionControllerTests: XCTestCase {
    private let profile = "client\nremote example.invalid 1194\nproto udp\n"

    @MainActor private func controller(_ runtime: MockTunnelRuntime) -> MYCODEXApplePacketTunnelSessionController {
        MYCODEXApplePacketTunnelSessionController(makeRuntime: { _, _, _ in runtime }, onDisconnection: { _ in })
    }

    @MainActor private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for session transition")
    }

    @MainActor func testRealEventRequiredAfterACKAndTransport() async throws {
        let runtime = MockTunnelRuntime()
        let session = controller(runtime)
        var results: [Result<Void, MYCODEXPacketTunnelSessionError>] = []
        session.start(profileText: profile, credentials: nil) { results.append($0) }
        try await eventually { runtime.transportStarted == 1 }
        XCTAssertEqual(runtime.acked, 1)
        XCTAssertTrue(results.isEmpty)
        runtime.events.append(OpenVPNClientEvent(name: "CONNECTED", isError: false, isFatal: false))
        try await eventually { results.count == 1 }
        XCTAssertEqual(session.phase, .connected(1))
        if case .success = results[0] {} else { XCTFail("CONNECTED was not delivered") }
        session.stop {}
        try await eventually { session.phase == .stopped }
        XCTAssertEqual(runtime.released, 1)
    }

    @MainActor func testValidatedProfileAndCredentialsReachFactory() async throws {
        let runtime = MockTunnelRuntime()
        let probe = FactoryProbe()
        let session = MYCODEXApplePacketTunnelSessionController(
            makeRuntime: { profile, credentials, _ in
                probe.calls += 1
                probe.profile = profile.withRawConfiguration { $0 }
                probe.credentials = credentials
                return runtime
            }, onDisconnection: { _ in }
        )
        session.start(profileText: "", credentials: nil) { _ in }
        try await eventually { session.phase == .stopped }
        XCTAssertEqual(probe.calls, 0)
        session.start(profileText: profile,
                      credentials: MYCODEXAppleTunnelCredentials(username: "user", password: "secret")) { _ in }
        try await eventually { runtime.started == 1 }
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(probe.profile, profile)
        XCTAssertEqual(probe.credentials?.username, "user")
        XCTAssertEqual(probe.credentials?.password, "secret")
        session.stop {}
        try await eventually { session.phase == .stopped }
    }

    @MainActor func testNativeStartRefusalFailsAndReleases() async throws {
        let runtime = MockTunnelRuntime()
        runtime.startError = OpenVPNClientError.tunnelUnavailable
        let session = controller(runtime)
        var errors: [MYCODEXPacketTunnelSessionError] = []
        session.start(profileText: profile, credentials: nil) {
            if case .failure(let error) = $0 { errors.append(error) }
        }
        try await eventually { session.phase == .stopped }
        XCTAssertEqual(errors, [.nativeTunnelUnavailable])
        XCTAssertEqual(runtime.started, 1)
        XCTAssertEqual(runtime.joined, 1)
        XCTAssertEqual(runtime.released, 1)
    }

    @MainActor func testRejectedACKNeverStartsTransport() async throws {
        let runtime = MockTunnelRuntime()
        runtime.ack = false
        let session = controller(runtime)
        var error: MYCODEXPacketTunnelSessionError?
        session.start(profileText: profile, credentials: nil) {
            if case .failure(let reason) = $0 { error = reason }
        }
        try await eventually { session.phase == .stopped }
        XCTAssertEqual(error, .networkSettingsRejected)
        XCTAssertEqual(runtime.transportStarted, 0)
        XCTAssertEqual(runtime.released, 1)
    }

    @MainActor func testDuplicateStopWaitsForJoinAndIgnoresLateEvent() async throws {
        let runtime = MockTunnelRuntime()
        runtime.holdJoin = true
        let session = controller(runtime)
        var starts: [Result<Void, MYCODEXPacketTunnelSessionError>] = []
        var stops = 0
        session.start(profileText: profile, credentials: nil) { starts.append($0) }
        try await eventually { runtime.started == 1 }
        session.stop { stops += 1 }
        session.stop { stops += 1 }
        runtime.events.append(OpenVPNClientEvent(name: "CONNECTED", isError: false, isFatal: false))
        try await eventually { runtime.joinContinuation != nil }
        XCTAssertEqual(runtime.released, 0)
        XCTAssertEqual(stops, 0)
        XCTAssertEqual(starts.count, 1)
        runtime.finishJoin()
        try await eventually { stops == 2 }
        XCTAssertEqual(runtime.released, 1)
        XCTAssertEqual(session.phase, .stopped)
        if case .failure(.cancelled) = starts[0] {} else { XCTFail("Start was not cancelled") }
    }

    @MainActor func testRestartAfterStopUsesNewGeneration() async throws {
        let first = MockTunnelRuntime()
        let second = MockTunnelRuntime()
        var factories = [first, second]
        let session = MYCODEXApplePacketTunnelSessionController(
            makeRuntime: { _, _, _ in factories.removeFirst() }, onDisconnection: { _ in }
        )
        session.start(profileText: profile, credentials: nil) { _ in }
        try await eventually { first.started == 1 }
        session.stop {}
        try await eventually { session.phase == .stopped }
        session.start(profileText: profile, credentials: nil) { _ in }
        try await eventually { second.started == 1 }
        XCTAssertEqual(session.phase, .awaitingCoreConnection(3))
        session.transportDidFail(generation: 1)
        XCTAssertEqual(session.phase, .awaitingCoreConnection(3))
        session.stop {}
        try await eventually { session.phase == .stopped }
        XCTAssertEqual(first.released, 1)
        XCTAssertEqual(second.released, 1)
    }

    @MainActor func testStopDuringPreparationReleasesLateRuntimeWithoutStartingIt() async throws {
        let runtime = MockTunnelRuntime()
        let probe = FactoryProbe()
        let session = MYCODEXApplePacketTunnelSessionController(
            makeRuntime: { _, _, _ in
                try await withCheckedThrowingContinuation { probe.continuation = $0 }
            }, onDisconnection: { _ in }
        )
        var result: MYCODEXPacketTunnelSessionError?
        var stopped = 0
        session.start(profileText: profile, credentials: nil) {
            if case .failure(let reason) = $0 { result = reason }
        }
        try await eventually { probe.continuation != nil }
        session.stop { stopped += 1 }
        XCTAssertEqual(result, .cancelled)
        probe.continuation?.resume(returning: runtime)
        probe.continuation = nil
        try await eventually { stopped == 1 }
        XCTAssertEqual(runtime.started, 0)
        XCTAssertEqual(runtime.joined, 1)
        XCTAssertEqual(runtime.released, 1)
    }
}
#endif
