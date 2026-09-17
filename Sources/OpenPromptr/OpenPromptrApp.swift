import AppKit
import SwiftUI

@MainActor
final class AppStatusItemController: NSObject, NSMenuDelegate {
    private weak var model: AppModel?
    private weak var updates: UpdateManager?
    private var showControlsHandler: (() -> Void)?
    private let statusItem: NSStatusItem
    private let startItem: NSMenuItem
    private let stopItem: NSMenuItem
    private let checkForUpdatesItem: NSMenuItem
    private let automaticUpdatesItem: NSMenuItem
    private let installUpdateItem: NSMenuItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        startItem = NSMenuItem(
            title: "Start Output",
            action: #selector(startOutput),
            keyEquivalent: ""
        )
        stopItem = NSMenuItem(
            title: "Stop Output",
            action: #selector(stopOutput),
            keyEquivalent: "."
        )
        checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        automaticUpdatesItem = NSMenuItem(
            title: "Check for Updates Automatically",
            action: #selector(toggleAutomaticUpdates),
            keyEquivalent: ""
        )
        installUpdateItem = NSMenuItem(
            title: "Install Update and Restart…",
            action: #selector(installUpdate),
            keyEquivalent: ""
        )
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.on.rectangle.angled",
            accessibilityDescription: "OpenPromptr"
        )
        statusItem.button?.toolTip = "OpenPromptr"

        startItem.target = self
        stopItem.target = self
        stopItem.keyEquivalentModifierMask = [.command]

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(.separator())

        let showItem = NSMenuItem(
            title: "Show Controls",
            action: #selector(showControls),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About OpenPromptr",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        installUpdateItem.target = self
        installUpdateItem.isHidden = true
        menu.addItem(installUpdateItem)
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)
        automaticUpdatesItem.target = self
        menu.addItem(automaticUpdatesItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit OpenPromptr",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func configure(
        model: AppModel,
        updates: UpdateManager,
        showControls: @escaping () -> Void
    ) {
        self.model = model
        self.updates = updates
        showControlsHandler = showControls
    }

    func menuWillOpen(_ menu: NSMenu) {
        startItem.isEnabled = model?.canStart == true
        stopItem.isEnabled = model?.canStop == true

        automaticUpdatesItem.state = updates?.automaticChecksEnabled == true ? .on : .off
        checkForUpdatesItem.isEnabled = updates?.isBusy != true

        if case .readyToInstall(let version)? = updates?.state {
            installUpdateItem.title = "Install Update \(version) and Restart…"
            installUpdateItem.isHidden = false
        } else {
            installUpdateItem.isHidden = true
        }
    }

    @objc
    private func startOutput() {
        Task { @MainActor [weak self] in
            await self?.model?.start()
        }
    }

    @objc
    private func stopOutput() {
        model?.requestStop(message: "Output stopped from the status menu.")
    }

    @objc
    private func showControls() {
        showControlsHandler?()
    }

    @objc
    private func showAbout() {
        AboutPanel.show()
    }

    @objc
    private func checkForUpdates() {
        guard let model, let updates else { return }
        UpdateFlow.checkForUpdates(updates: updates, model: model)
    }

    @objc
    private func toggleAutomaticUpdates() {
        guard let updates else { return }
        updates.automaticChecksEnabled.toggle()
    }

    @objc
    private func installUpdate() {
        guard let model, let updates else { return }
        UpdateFlow.installUpdate(updates: updates, model: model)
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminationPending = false
    private let statusItemController = AppStatusItemController()
    private var showControlsHandler: (() -> Void)?

    func configure(
        model: AppModel,
        updates: UpdateManager,
        showControls: @escaping () -> Void
    ) {
        self.model = model
        showControlsHandler = showControls
        statusItemController.configure(
            model: model,
            updates: updates,
            showControls: showControls
        )
    }

    func showControls() {
        showControlsHandler?()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showControls()
        }
        return true
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if terminationPending {
            return .terminateLater
        }
        guard let model else {
            return .terminateNow
        }
        terminationPending = true
        Task { @MainActor in
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareForTermination()
    }
}

@MainActor
struct OpenPromptrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @StateObject
    private var model = AppModel()

    @StateObject
    private var updates = UpdateManager()

    var body: some Scene {
        Window("OpenPromptr", id: "controls") {
            ControlRootView(
                model: model,
                configure: { showControls in
                    appDelegate.configure(
                        model: model,
                        updates: updates,
                        showControls: showControls
                    )
                    model.appDidLaunch()
                    updates.startAutomaticChecks()
                }
            )
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About OpenPromptr") {
                    AboutPanel.show()
                }
            }

            CommandMenu("Update") {
                if case .readyToInstall(let version) = updates.state {
                    Button("Install Update \(version) and Restart…") {
                        UpdateFlow.installUpdate(updates: updates, model: model)
                    }
                }

                Button("Check for Updates…") {
                    UpdateFlow.checkForUpdates(updates: updates, model: model)
                }
                .disabled(updates.isBusy)

                Toggle(
                    "Check for Updates Automatically",
                    isOn: $updates.automaticChecksEnabled
                )
            }

            CommandMenu("Output") {
                Button("Start Output") {
                    Task { @MainActor in
                        await model.start()
                    }
                }
                .disabled(!model.canStart)

                Button("Stop Output") {
                    model.requestStop()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.canStop)

                Divider()

                Button("Show Controls") {
                    appDelegate.showControls()
                }

                Button("Refresh Displays") {
                    model.refreshDisplays()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isBusy)
            }
        }
    }
}

private struct ControlRootView: View {
    @ObservedObject var model: AppModel
    let configure: (@escaping () -> Void) -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ControlView(model: model) {
            configure {
                openWindow(id: "controls")
                DispatchQueue.main.async {
                    model.showControls()
                }
            }
        }
    }
}
