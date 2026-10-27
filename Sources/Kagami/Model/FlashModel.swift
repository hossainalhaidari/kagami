import Darwin
import Foundation
import Observation

@MainActor
@Observable
final class FlashModel {
    enum State: Equatable {
        case idle
        case busy(String)
        case running(FlashProgress.Phase, fraction: Double)
        case finished(verified: Bool)
        case failed(String)
    }

    let monitor = DriveMonitor()

    private(set) var imageURL: URL?
    private(set) var imageInfo: ImageInfo?
    var selectedDriveID: Drive.ID?
    private(set) var state: State = .idle
    private(set) var statusDetail = ""
    /// Message shown when the chosen file can't be used.
    var imageError: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var phaseStart = Date()
    @ObservationIgnored private var acceptingProgress = false
    /// Called whenever a flash ends, however it ends.
    @ObservationIgnored var onFinish: (() -> Void)?

    var drives: [Drive] { monitor.drives }
    var selectedDrive: Drive? { drives.first { $0.id == selectedDriveID } }

    var isWorking: Bool {
        switch state {
        case .busy, .running: return true
        default: return false
        }
    }

    var canFlash: Bool {
        guard !isWorking, imageURL != nil, selectedDrive != nil else { return false }
        return !imageTooLarge
    }

    /// Why the Flash button is disabled, if it isn't obvious.
    var blocker: String? {
        imageTooLarge ? "The image is larger than the selected drive." : nil
    }

    /// Only known up front when the format records the decompressed size;
    /// otherwise the writer stops with an error once the drive is full.
    private var imageTooLarge: Bool {
        guard let drive = selectedDrive, let size = imageInfo?.imageSize else { return false }
        return size > drive.size
    }

    func selectImage(_ url: URL) {
        guard !isWorking else { return }
        imageError = nil
        do {
            let info = try ImageSources.inspect(url)
            guard info.fileSize > 0 else { throw ImageWriterError.emptyImage }
            imageURL = url
            imageInfo = info
        } catch {
            imageError = "“\(url.lastPathComponent)”: \(error.localizedDescription)"
            return
        }
        if case .finished = state { state = .idle }
        if case .failed = state { state = .idle }
    }

    func flash() {
        guard canFlash, let image = imageURL, let drive = selectedDrive else { return }
        task = Task { await run(image: image, drive: drive) }
    }

    func cancel() {
        task?.cancel()
    }

    var isVerifying: Bool {
        if case .running(.verifying, _) = state { return true }
        return false
    }

    /// Cancelling the flash task during verification makes the writer stop
    /// checking and report the (already complete) image as unverified.
    func skipVerification() {
        guard isVerifying else { return }
        task?.cancel()
    }

    func reset() {
        guard !isWorking else { return }
        state = .idle
        statusDetail = ""
    }

    private func run(image: URL, drive: Drive) async {
        var startedWriting = false
        do {
            state = .busy("Unmounting \(drive.name)…")
            try await DiskOperations.unmountAll(drive.bsdName)

            state = .busy("Waiting for administrator authorization…")
            let device = try await Self.openDevice(drive.rawDevicePath)
            try Task.checkCancellation()

            startedWriting = true
            phaseStart = Date()
            acceptingProgress = true
            defer { acceptingProgress = false }
            let outcome = try await Self.write(image: image, to: device) { [weak self] progress in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.apply(progress) }
                }
            }
            acceptingProgress = false

            state = .busy("Ejecting…")
            let ejected = await ejectWithRetry(drive.bsdName)
            let verified = outcome == .verified
            state = .finished(verified: verified)
            statusDetail = "\(image.lastPathComponent) was written to \(drive.name)"
                + (verified ? ". " : " but not verified. ")
                + (ejected ? "You can remove the drive." : "Eject it in Finder before removing it.")
        } catch is CancellationError {
            state = .failed("Cancelled.")
            statusDetail = startedWriting ? "The drive was only partially written and won't boot." : ""
            if !startedWriting { try? await DiskOperations.mountAll(drive.bsdName) }
        } catch AuthOpenError.cancelled {
            state = .idle
            statusDetail = ""
            try? await DiskOperations.mountAll(drive.bsdName)
        } catch {
            state = .failed(error.localizedDescription)
            statusDetail = ""
        }
        task = nil
        onFinish?()
    }

    private func apply(_ progress: FlashProgress) {
        guard acceptingProgress else { return }
        if case .running(let phase, _) = state, phase != progress.phase { phaseStart = Date() }
        state = .running(progress.phase, fraction: progress.fraction)

        let elapsed = Date().timeIntervalSince(phaseStart)
        guard elapsed > 1, progress.bytesDone > 0 else { statusDetail = ""; return }
        let speed = Double(progress.bytesDone) / elapsed
        let remaining = progress.fraction > 0 ? elapsed * (1 - progress.fraction) / progress.fraction : 0
        let speedText = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
        let etaFormatter = DateComponentsFormatter()
        etaFormatter.unitsStyle = .abbreviated
        etaFormatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : [.minute, .second]
        statusDetail = "\(speedText) · \(etaFormatter.string(from: remaining) ?? "") left"
    }

    /// After writing, macOS may auto-mount the new partitions; retry so eject wins the race.
    private func ejectWithRetry(_ bsdName: String) async -> Bool {
        for attempt in 1...4 {
            do {
                try await DiskOperations.eject(bsdName)
                return true
            } catch {
                if attempt < 4 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        return false
    }

    // MARK: - Blocking work, kept off the main actor

    @concurrent
    private nonisolated static func openDevice(_ path: String) async throws -> Int32 {
        try AuthOpen.open(path)
    }

    @concurrent
    private nonisolated static func write(
        image: URL,
        to device: Int32,
        progress: @escaping @Sendable (FlashProgress) -> Void
    ) async throws -> FlashOutcome {
        defer { close(device) }
        // Forward at most ~10 updates per second, but always the first and last of each phase.
        var lastSent = Date.distantPast
        return try ImageWriter.flash(image: image, to: device) { update in
            let now = Date()
            if update.fraction == 0 || update.fraction >= 1 || now.timeIntervalSince(lastSent) >= 0.1 {
                lastSent = now
                progress(update)
            }
        }
    }
}
