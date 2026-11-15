#if canImport(NetworkExtension) && canImport(Darwin)
import Darwin
import Dispatch
import Foundation
import NetworkExtension

/// Event-driven packet movement between the staging queues and a POSIX
/// datagram socketpair. No OpenVPN authentication, TLS, or CONNECTED signal.
///
/// Only instantiate inside an actual, signed NEPacketTunnelProvider after
/// setTunnelNetworkSettings has succeeded. Its owner MUST stop/join the native
/// Core worker before releasing the client, socket transport, or bridge.
/// All operations are MainActor isolated and each pump is bounded (32 packets
/// per direction); DispatchSource events only provide readiness wakeups.
@MainActor
public final class MYCODEXApplePacketTransportDriver {
    private let bridge: MYCODEXPacketBridge
    private let transport: MYCODEXTunSocketTransport
    private let packetFlow: MYCODEXApplePacketFlowAdapter
    private let onFailure: @MainActor (any Error) -> Void
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var readSuspended = true
    private var writeSuspended = true
    private var active = false
    private var pumping = false
    private var outputBlocked = false

    public init(bridge: MYCODEXPacketBridge,
                transport: MYCODEXTunSocketTransport,
                packetFlow: MYCODEXApplePacketFlowAdapter,
                onFailure: @escaping @MainActor (any Error) -> Void) throws {
        self.bridge = bridge
        self.transport = transport
        self.packetFlow = packetFlow
        self.onFailure = onFailure

        let readFD = try transport.duplicateMonitorFileDescriptor()
        let writeFD: Int32
        do {
            writeFD = try transport.duplicateMonitorFileDescriptor()
        } catch {
            _ = Darwin.close(readFD)
            throw error
        }

        // Separate owned duplicates: each source closes its own descriptor
        // only AFTER its cancellation handler executes.
        let reader = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: .main)
        let writer = DispatchSource.makeWriteSource(fileDescriptor: writeFD, queue: .main)
        reader.setCancelHandler { _ = Darwin.close(readFD) }
        writer.setCancelHandler { _ = Darwin.close(writeFD) }
        self.readSource = reader
        self.writeSource = writer

        // The handlers execute on DispatchQueue.main, which is the main actor's
        // executor. Avoid enqueuing unbounded Tasks on a continuously-ready FD.
        reader.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readable() }
        }
        writer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.writable() }
        }
    }

    deinit {
        // Defensive last-resort cancellation if the owner violated the explicit
        // stop-before-release contract. Never drop a suspended dispatch source.
        if let reader = readSource {
            if readSuspended { reader.resume() }
            reader.cancel()
        }
        if let writer = writeSource {
            if writeSuspended { writer.resume() }
            writer.cancel()
        }
    }

    /// Begin only after NetworkExtension accepted real Core-pushed settings.
    /// Starting this driver does NOT signal that the VPN is connected.
    public func startMonitoring() {
        guard !active else { return }
        active = true
        packetFlow.onIngressStaged = { [weak self] in self?.ingressAvailable() }
        packetFlow.beginReading()
        refreshSources()
    }

    /// Explicit notification for newly staged system packets. The Apple flow
    /// adapter invokes this automatically through onIngressStaged.
    public func ingressAvailable() {
        guard active else { return }
        driveOnce()
    }

    /// Apple writePackets may return false. The owner needs to call this when
    /// the system is ready to retry; it never silently drops the failed batch.
    public func retryOutput() {
        guard active else { return }
        outputBlocked = false
        driveOnce()
    }

    /// Stops all readiness subscriptions and packetFlow reading. Call ONLY
    /// after the Core worker was stopped and joined. Does not destroy the
    /// socket transport: the owner closes it after stopMonitoring().
    public func stopMonitoring() {
        guard readSource != nil || writeSource != nil else { return }
        active = false
        packetFlow.onIngressStaged = nil
        packetFlow.stop()

        // A cancelled suspended GCD source must be resumed once before it can
        // deliver its cancel handler and release its owned monitor descriptor.
        if let reader = readSource {
            if readSuspended { reader.resume(); readSuspended = false }
            reader.cancel()
        }
        if let writer = writeSource {
            if writeSuspended { writer.resume(); writeSuspended = false }
            writer.cancel()
        }
        readSource = nil
        writeSource = nil
    }

    private func readable() {
        guard active else { return }
        setReadEnabled(false)
        driveOnce()
    }

    private func writable() {
        guard active else { return }
        setWriteEnabled(false)
        driveOnce()
    }

    private func driveOnce() {
        guard active, !pumping else { return }
        pumping = true
        defer {
            pumping = false
            if active { refreshSources() }
        }
        do {
            let progress = try transport.pump(maxPerDirection: 32)
            // Every successful system->Core pump frees queue capacity and may
            // permit the PacketFlow adapter to resume a held read batch.
            if progress.intoCore > 0 { packetFlow.ingressQueueDidDrain() }

            // Always attempt a flush, including after a previous failed write.
            // The coordinator retains an unaccepted egress batch for retry.
            outputBlocked = try !packetFlow.flushCoreToSystem(maxBatch: 32)
        } catch {
            stopMonitoring()
            onFailure(error)
        }
    }

    private func refreshSources() {
        guard active else { return }
        // Do not read further Core datagrams when the OS refused the previous
        // write batch. External retryOutput() is required to rearm the source.
        setReadEnabled(!outputBlocked)
        do {
            let queued = try bridge.statistics(direction: .toCore).packets > 0
            let pending = try transport.hasPendingCoreWrite()
            // POLLOUT is level-triggered: never arm it without queued output,
            // otherwise the source would spin continuously on a writable FD.
            setWriteEnabled(queued || pending)
        } catch {
            stopMonitoring()
            onFailure(error)
        }
    }

    private func setReadEnabled(_ enabled: Bool) {
        guard let reader = readSource else { return }
        if enabled && readSuspended { reader.resume(); readSuspended = false }
        if !enabled && !readSuspended { reader.suspend(); readSuspended = true }
    }

    private func setWriteEnabled(_ enabled: Bool) {
        guard let writer = writeSource else { return }
        if enabled && writeSuspended { writer.resume(); writeSuspended = false }
        if !enabled && !writeSuspended { writer.suspend(); writeSuspended = true }
    }
}
#endif
