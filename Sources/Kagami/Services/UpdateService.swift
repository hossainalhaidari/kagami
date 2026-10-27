import AppKit
import Observation
import Sparkle

/// Sparkle, reduced to what the rest of the app asks of it: a policy to show and change, and a
/// check to run.
///
/// Only a release build updates itself. `Scripts/build-app.sh` leaves `SUFeedURL` out of any build
/// it was not given a version for, so `make run` never offers to replace itself with the published
/// release — which, with Install Automatically on, it would do the next time it quit. A build with
/// no `SUPublicEDKey` could not verify anything it downloaded, so it is treated the same way. In
/// both cases the updater is never started: started, Sparkle would put up an alert telling the user
/// the app is misconfigured.
@Observable
@MainActor
final class UpdateService: NSObject {
    /// Whether this build has a feed to read and a key to check what it finds against.
    let isAvailable: Bool

    /// Sparkle's two switches, read back rather than remembered, so the update window's own
    /// "Automatically download and install updates" box — which sets one without asking us — shows up
    /// in the settings window.
    private(set) var policy: UpdatePolicy = .manual
    /// False while a check or a background download is already under way.
    private(set) var canCheck = false
    private(set) var lastCheck: Date?

    /// Whether a flash is running. An update must never relaunch the app half-way through writing a
    /// drive, which would leave it unbootable.
    @ObservationIgnored var isBusy: () -> Bool = { false }
    @ObservationIgnored private var postponedRelaunch: (() -> Void)?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation?] = []

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        isAvailable = Self.isConfigured(info)
        super.init()
    }

    nonisolated static func isConfigured(_ info: [String: Any]) -> Bool {
        ["SUFeedURL", "SUPublicEDKey"].allSatisfy { key in
            guard let value = info[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// "0.1.0 (1)": the version a user reads, then the build number Sparkle compares. The second is
    /// what tells two copies of the same version apart when someone reports a problem.
    nonisolated static func version(_ info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Separate from `init` so the scheduler's first check waits for the app to have finished
    /// launching, as Sparkle asks.
    func start() {
        guard isAvailable, controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        // Sparkle's default names the app and its version to whoever serves the feed, and URLSession
        // adds the user's preferred languages. The feed needs none of it to answer — the version is
        // compared here, against the appcast — so every copy sends the same two values instead.
        // Sparkle puts both on the appcast, the release notes and the download alike.
        controller.updater.userAgentString = "Sparkle"
        controller.updater.httpHeaders = ["Accept-Language": "*"]
        controller.startUpdater()
        self.controller = controller

        observations = [
            observe(\.automaticallyChecksForUpdates),
            observe(\.automaticallyDownloadsUpdates),
            observe(\.canCheckForUpdates),
        ]
        refresh()
    }

    func setPolicy(_ newPolicy: UpdatePolicy) {
        guard let updater = controller?.updater else { return }
        // Both switches, every time. One left over from an earlier choice would come back when the
        // other changed: Manual then Ask must not start downloading because Automatic once did.
        updater.automaticallyChecksForUpdates = newPolicy.checksAutomatically
        updater.automaticallyDownloadsUpdates = newPolicy.downloadsAutomatically
        refresh()
    }

    /// Checks now, with Sparkle's progress window and answer.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Lets an update that was held back while a drive was being written relaunch the app now.
    func flashDidFinish() {
        guard let relaunch = postponedRelaunch else { return }
        postponedRelaunch = nil
        relaunch()
    }

    private func observe<Value>(_ keyPath: KeyPath<SPUUpdater, Value>) -> NSKeyValueObservation? {
        controller?.updater.observe(keyPath) { [weak self] _, _ in
            // Sparkle changes these on the main thread only; the handler just cannot say so.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        guard let updater = controller?.updater else { return }
        policy = UpdatePolicy(
            checksAutomatically: updater.automaticallyChecksForUpdates,
            downloadsAutomatically: updater.automaticallyDownloadsUpdates)
        canCheck = updater.canCheckForUpdates
        lastCheck = updater.lastUpdateCheckDate
    }
}

extension UpdateService: SPUUpdaterDelegate {
    /// `lastUpdateCheckDate` is not KVO-compliant, so this is where a finished check is heard about.
    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        refresh()
    }

    /// No system profile, whatever the defaults say. Sparkle sends one only when `SUSendProfileInfo`
    /// is on, which nothing in Kagami sets and `SUEnableSystemProfiling` keeps it from asking for —
    /// but a `defaults write` could still switch it on, and an empty list means it then sends nothing.
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    /// "Install and Relaunch" waits for a running flash to end; `flashDidFinish` lets it go ahead.
    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard isBusy() else { return false }
        postponedRelaunch = installHandler
        return true
    }
}
