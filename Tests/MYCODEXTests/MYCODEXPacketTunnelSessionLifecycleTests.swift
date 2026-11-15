import XCTest
@testable import MYCODEX

final class MYCODEXPacketTunnelSessionLifecycleTests: XCTestCase {
    func testStartRequiresAllThreeSignals() async {
        await MainActor.run {
            let lifecycle = MYCODEXPacketTunnelSessionLifecycle()
            var results: [Result<Void, MYCODEXPacketTunnelSessionError>] = []
            let generation = lifecycle.begin(completion: { results.append($0) }, onDisconnection: { _ in })!
            XCTAssertEqual(lifecycle.phase, .awaitingNetworkSettings(generation))
            XCTAssertTrue(results.isEmpty)
            XCTAssertTrue(lifecycle.networkSettingsDidComplete(generation: generation, accepted: true))
            XCTAssertEqual(lifecycle.phase, .awaitingPacketTransport(generation))
            XCTAssertTrue(results.isEmpty)
            XCTAssertTrue(lifecycle.packetTransportDidStart(generation: generation))
            XCTAssertEqual(lifecycle.phase, .awaitingCoreConnection(generation))
            XCTAssertTrue(results.isEmpty)
            XCTAssertTrue(lifecycle.receiveCoreEvent(event("CONNECTED"), generation: generation))
            XCTAssertEqual(lifecycle.phase, .connected(generation))
            XCTAssertEqual(results.count, 1)
            if case .success = results[0] { /* exactly-once success */ } else { XCTFail("start was not successful") }
            XCTAssertFalse(lifecycle.receiveCoreEvent(event("CONNECTED"), generation: generation))
            XCTAssertEqual(results.count, 1)
        }
    }

    func testEarlyConnectedFailsClosed() async {
        await MainActor.run {
            let lifecycle = MYCODEXPacketTunnelSessionLifecycle()
            var result: MYCODEXPacketTunnelSessionError?
            let gen = lifecycle.begin(completion: { if case .failure(let error) = $0 { result = error } }, onDisconnection: { _ in })!
            XCTAssertTrue(lifecycle.receiveCoreEvent(event("CONNECTED"), generation: gen))
            XCTAssertEqual(result, .invalidState)
            XCTAssertEqual(lifecycle.phase, .failed)
        }
    }

    func testNetworkSettingsRejected() async {
        await MainActor.run {
            let lifecycle = MYCODEXPacketTunnelSessionLifecycle()
            var result: MYCODEXPacketTunnelSessionError?
            let gen = lifecycle.begin(completion: { if case .failure(let error) = $0 { result = error } }, onDisconnection: { _ in })!
            XCTAssertTrue(lifecycle.networkSettingsDidComplete(generation: gen, accepted: false))
            XCTAssertEqual(result, .networkSettingsRejected)
            XCTAssertEqual(lifecycle.phase, .failed)
            XCTAssertFalse(lifecycle.packetTransportDidStart(generation: gen))
        }
    }

    func testFatalCoreEventBeforeConnection() async {
        await MainActor.run {
            let lifecycle = MYCODEXPacketTunnelSessionLifecycle()
            var result: MYCODEXPacketTunnelSessionError?
            let gen = lifecycle.begin(completion: { if case .failure(let error) = $0 { result = error } }, onDisconnection: { _ in })!
            XCTAssertTrue(lifecycle.networkSettingsDidComplete(generation: gen, accepted: true))
            XCTAssertTrue(lifecycle.receiveCoreEvent(event("AUTH_FAILED", error: true), generation: gen))
            XCTAssertEqual(result, .coreConnectionFailed)
            XCTAssertEqual(lifecycle.phase, .failed)
        }
    }

    func testStopCancelsPendingStartAndRequiresJoinThenRelease() async {
        await MainActor.run {
            let lifecycle = MYCODEXPacketTunnelSessionLifecycle()
            var cancelled: MYCODEXPacketTunnelSessionError?
            var stopped = 0
            let gen = lifecycle.begin(completion: { if case .failure(let error) = $0 { cancelled = error } }, onDisconnection: { _ in })!
            let stop = lifecycle.requestStop { stopped += 1 }!
            XCTAssertEqual(cancelled, .cancelled)
            XCTAssertEqual(lifecycle.phase, .stopping(stop))
            XCTAssertEqual(stopped, 0)
            XCTAssertFalse(lifecycle.resourcesDidRelease(stopToken: stop))
            XCTAssertFalse(lifecycle.networkSettingsDidComplete(generation: gen, accepted: true))
            XCTAssertFalse(lifecycle.receiveCoreEvent(event("CONNECTED"), generation: gen))
            XCTAssertTrue(lifecycle.coreWorkerDidJoin(stopToken: stop))
            XCTAssertEqual(lifecycle.phase, .releasingResources(stop))
            XCTAssertEqual(stopped, 0)
            XCTAssertTrue(lifecycle.resourcesDidRelease(stopToken: stop))
            XCTAssertEqual(stopped, 1)
            XCTAssertEqual(lifecycle.phase, .stopped)
        }
    }

    func testDuplicateStopHasSingleCleanupAndAllCallbacks() async {
        await MainActor.run {
            let lifecycle = MYCODEXPacketTunnelSessionLifecycle()
            var completions = 0
            _ = lifecycle.begin(completion: { _ in }, onDisconnection: { _ in })
            let stop = lifecycle.requestStop { completions += 1 }!
            XCTAssertNil(lifecycle.requestStop { completions += 1 })
            XCTAssertEqual(completions, 0)
            XCTAssertFalse(lifecycle.coreWorkerDidJoin(stopToken: stop + 1))
            XCTAssertTrue(lifecycle.coreWorkerDidJoin(stopToken: stop))
            XCTAssertTrue(lifecycle.resourcesDidRelease(stopToken: stop))
            XCTAssertEqual(completions, 2)
            XCTAssertFalse(lifecycle.resourcesDidRelease(stopToken: stop))
            XCTAssertEqual(completions, 2)
            XCTAssertNil(lifecycle.requestStop { completions += 1 })
            XCTAssertEqual(completions, 3)
        }
    }

    func testRetryRejectsPreviousGeneration() async {
        await MainActor.run {
            let lifecycle = MYCODEXPacketTunnelSessionLifecycle()
            let old = lifecycle.begin(completion: { _ in }, onDisconnection: { _ in })!
            let stop = lifecycle.requestStop {}!
            XCTAssertTrue(lifecycle.coreWorkerDidJoin(stopToken: stop))
            XCTAssertTrue(lifecycle.resourcesDidRelease(stopToken: stop))
            var current = 0
            let next = lifecycle.begin(completion: { _ in current += 1 }, onDisconnection: { _ in })!
            XCTAssertNotEqual(old, next)
            XCTAssertFalse(lifecycle.networkSettingsDidComplete(generation: old, accepted: true))
            XCTAssertFalse(lifecycle.receiveCoreEvent(event("CONNECTED"), generation: old))
            XCTAssertEqual(current, 0)
            XCTAssertEqual(lifecycle.phase, .awaitingNetworkSettings(next))
        }
    }

    func testUnexpectedDisconnectAfterConnectedUsesTerminationCallback() async {
        await MainActor.run {
            let lifecycle = MYCODEXPacketTunnelSessionLifecycle()
            var success = 0
            var disconnected: [MYCODEXPacketTunnelSessionError] = []
            let gen = lifecycle.begin(completion: { if case .success = $0 { success += 1 } }, onDisconnection: { disconnected.append($0) })!
            XCTAssertTrue(lifecycle.networkSettingsDidComplete(generation: gen, accepted: true))
            XCTAssertTrue(lifecycle.packetTransportDidStart(generation: gen))
            XCTAssertTrue(lifecycle.receiveCoreEvent(event("CONNECTED"), generation: gen))
            XCTAssertEqual(success, 1)
            XCTAssertTrue(lifecycle.receiveCoreEvent(event("DISCONNECTED"), generation: gen))
            XCTAssertEqual(disconnected, [.coreDisconnected])
            XCTAssertEqual(lifecycle.phase, .failed)
            XCTAssertFalse(lifecycle.receiveCoreEvent(event("DISCONNECTED"), generation: gen))
            XCTAssertEqual(success, 1)
        }
    }

    func testInvalidStartWhileActiveDoesNotSupersedeSession() async {
        await MainActor.run {
            let lifecycle = MYCODEXPacketTunnelSessionLifecycle()
            let gen = lifecycle.begin(completion: { _ in }, onDisconnection: { _ in })!
            var failure: MYCODEXPacketTunnelSessionError?
            XCTAssertNil(lifecycle.begin(completion: { if case .failure(let err) = $0 { failure = err } }, onDisconnection: { _ in }))
            XCTAssertEqual(failure, .invalidState)
            XCTAssertEqual(lifecycle.phase, .awaitingNetworkSettings(gen))
        }
    }
}

private func event(_ name: String, error: Bool = false, fatal: Bool = false) -> OpenVPNClientEvent {
    OpenVPNClientEvent(name: name, isError: error, isFatal: fatal)
}
