import AppUpdater
import Foundation

/// Checks GitHub Releases for a newer OpenPromptr and installs it in place.
///
/// Backed by [AppUpdater](https://github.com/mxcl/AppUpdater). It only accepts a release
/// asset named exactly `OpenPromptr-<semver>.dmg`, and only if the app inside carries the
/// same Developer ID Team ID, signing identifier and bundle identifier as this one.
///
/// GitHub artifact attestation (`GitHubAttestationPolicy`) is deliberately not required:
/// the notarization broker builds the release in its own repository, so there is no
/// provenance from `trsdn/OpenPromptr` for AppUpdater to check against. Requiring it would
/// reject every genuine release.
@MainActor
public final class UpdateManager: ObservableObject {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(version: String)
        case readyToInstall(version: String)
        case installing
        case failed(String)
    }

    public enum Key {
        public static let automaticChecks = "checkForUpdatesAutomatically"
    }

    @Published public private(set) var state: State = .idle

    @Published public var automaticChecksEnabled: Bool {
        didSet {
            guard automaticChecksEnabled != oldValue else { return }
            defaults.set(automaticChecksEnabled, forKey: Key.automaticChecks)
            if automaticChecksEnabled { startAutomaticChecks() } else { stopAutomaticChecks() }
        }
    }

    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private let updater = AppUpdater(owner: "trsdn", repo: "OpenPromptr")
    private let defaults: UserDefaults
    private var preparedUpdate: PreparedUpdate?
    private var lastAutomaticCheck: Date?
    private var automaticCheckTask: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticChecksEnabled = defaults.object(forKey: Key.automaticChecks) as? Bool ?? true
    }

    public var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    public var hasPreparedUpdate: Bool { preparedUpdate != nil }

    // MARK: - Automatic checks

    public func startAutomaticChecks() {
        automaticCheckTask?.cancel()
        guard automaticChecksEnabled else { return }
        // Wakes hourly but checks at most once a day: a Mac that sleeps through the night
        // would otherwise miss a plain 24-hour timer indefinitely.
        automaticCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.isAutomaticCheckDue {
                    await self.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    public func stopAutomaticChecks() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
    }

    private var isAutomaticCheckDue: Bool {
        guard let lastAutomaticCheck else { return true }
        return Date().timeIntervalSince(lastAutomaticCheck) >= Self.automaticCheckInterval
    }

    // MARK: - Check, install, dismiss

    /// Looks for a newer release and, if there is one, downloads and validates it so that
    /// installing is a single click. Downloading never interrupts a running teleprompter
    /// session; only the actual install (which relaunches the app) has to wait for one.
    ///
    /// A failed background check is only logged: being offline is not worth an alert. A
    /// check the user asked for always answers.
    public func check(userInitiated: Bool) async {
        guard !isBusy, preparedUpdate == nil else { return }
        if userInitiated {
            state = .checking
        } else {
            lastAutomaticCheck = Date()
        }

        do {
            guard let update = try await updater.check() else {
                state = userInitiated ? .upToDate : .idle
                return
            }
            NSLog("OpenPromptr: update available: \(update.version)")
            state = .downloading(version: update.version)
            preparedUpdate = try await update.prepareInstallation()
            state = .readyToInstall(version: update.version)
        } catch is CancellationError {
            state = .idle
        } catch {
            NSLog("OpenPromptr: update check failed: \(error.localizedDescription)")
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    /// Replaces the app and relaunches it. On success this never returns. Returns `false`
    /// if installation failed, so the caller can resume whatever it stopped beforehand.
    ///
    /// Callers must not invoke this while a display is being mirrored — a teleprompter must
    /// not restart mid-session. `UpdateManager` itself has no notion of mirroring state, so
    /// the UI layer is responsible for only offering this while `AppModel.isRunning` is
    /// false, and never triggering it automatically.
    @discardableResult
    public func installAndRelaunch() async -> Bool {
        guard let prepared = preparedUpdate else { return false }
        preparedUpdate = nil
        state = .installing
        stopAutomaticChecks()

        do {
            try await prepared.installAndRelaunch()
            return true
        } catch {
            NSLog("OpenPromptr: update install failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            startAutomaticChecks()
            return false
        }
    }

    /// Throws the downloaded update away. The next automatic check finds it again.
    public func dismiss() async {
        if let prepared = preparedUpdate {
            preparedUpdate = nil
            await prepared.discard()
        }
        state = .idle
    }
}
