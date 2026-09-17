import AppKit

/// Shared "Check for Updates…" / "Install and Restart" flow, used identically by the
/// status-item menu and the app's Update command menu so there is one place that decides
/// whether an install may proceed.
@MainActor
enum UpdateFlow {
    static func checkForUpdates(updates: UpdateManager, model: AppModel) {
        Task {
            await updates.check(userInitiated: true)
            switch updates.state {
            case .upToDate:
                presentResult(
                    title: "OpenPromptr is up to date",
                    message: "You are running the newest release."
                )
            case .failed(let message):
                presentResult(title: "Update check failed", message: message)
            case .readyToInstall(let version):
                offerInstall(version: version, updates: updates, model: model)
            default:
                break
            }
        }
    }

    /// Only ever called from an explicit menu action — never automatically, and never
    /// while `model.canStop` (a session is running, desired, or in the middle of starting,
    /// stopping, or automatic recovery), so a teleprompter session is never interrupted
    /// mid-talk. `isRunning` alone is not enough: it goes false the instant a capture
    /// failure starts an automatic-recovery retry, even though that retry is still trying
    /// to restore the same session.
    static func installUpdate(updates: UpdateManager, model: AppModel) {
        guard !model.canStop else {
            presentResult(
                title: "Stop output before installing",
                message:
                    "OpenPromptr restarts to install the update. Stop the current output first."
            )
            return
        }
        Task {
            if await !updates.installAndRelaunch() {
                if case .failed(let message) = updates.state {
                    presentResult(title: "Update could not be installed", message: message)
                }
            }
        }
    }

    /// Discards a downloaded update without installing it. The next check finds it again.
    static func dismissUpdate(updates: UpdateManager) {
        Task {
            await updates.dismiss()
        }
    }

    private static func offerInstall(version: String, updates: UpdateManager, model: AppModel) {
        NSApp.activate(ignoringOtherApps: true)
        let sessionActive = model.canStop
        let alert = NSAlert()
        alert.messageText = "OpenPromptr \(version) is ready to install"
        alert.informativeText =
            sessionActive
            ? "OpenPromptr quits and reopens to install this update, so it can't be installed while output is running. Stop output first, then install from the menu."
            : "OpenPromptr quits, updates itself, and opens again."
        alert.addButton(withTitle: sessionActive ? "OK" : "Install and Restart")
        if !sessionActive {
            alert.addButton(withTitle: "Later")
        }
        switch alert.runModal() {
        case .alertFirstButtonReturn where !sessionActive:
            installUpdate(updates: updates, model: model)
        case .alertSecondButtonReturn where !sessionActive:
            dismissUpdate(updates: updates)
        default:
            break
        }
    }

    private static func presentResult(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
