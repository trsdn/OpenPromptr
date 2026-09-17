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
    /// while `model.isRunning`, so a teleprompter session is never interrupted mid-talk.
    static func installUpdate(updates: UpdateManager, model: AppModel) {
        guard !model.isRunning else {
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

    private static func offerInstall(version: String, updates: UpdateManager, model: AppModel) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "OpenPromptr \(version) is ready to install"
        alert.informativeText =
            model.isRunning
            ? "OpenPromptr quits and reopens to install this update, so it can't be installed while output is running. Stop output first, then install from the menu."
            : "OpenPromptr quits, updates itself, and opens again."
        alert.addButton(withTitle: model.isRunning ? "OK" : "Install and Restart")
        if !model.isRunning {
            alert.addButton(withTitle: "Later")
        }
        if alert.runModal() == .alertFirstButtonReturn && !model.isRunning {
            installUpdate(updates: updates, model: model)
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
