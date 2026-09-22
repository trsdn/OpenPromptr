import AppKit
import Combine
import OpenPromptrCore
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
    private let laterUpdateItem: NSMenuItem

    /// The Dock icon's own "T over a mirror line" mark, generated alongside
    /// it by `Scripts/make-icon.swift` (`Resources/MenuBarIcon.png`) so the
    /// menu bar item is recognizably the same app rather than an unrelated
    /// SF Symbol. `isTemplate` lets macOS recolor it for light mode, dark
    /// mode and the highlighted state.
    private static func menuBarIcon() -> NSImage {
        guard
            let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else {
            // The bare executable from `swift build` (no app bundle, no
            // Resources) has nothing to load; the packaged app always does.
            let fallback =
                NSImage(
                    systemSymbolName: "rectangle.on.rectangle.angled",
                    accessibilityDescription: "OpenPromptr"
                ) ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }
        let aspectRatio = image.size.width / image.size.height
        image.size = NSSize(width: 18 * aspectRatio, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "OpenPromptr"
        return image
    }

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
        laterUpdateItem = NSMenuItem(
            title: "Later",
            action: #selector(dismissUpdate),
            keyEquivalent: ""
        )
        super.init()

        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.toolTip = "OpenPromptr"

        startItem.target = self
        stopItem.target = self
        stopItem.keyEquivalentModifierMask = [.command]

        let menu = NSMenu()
        menu.delegate = self
        // The icon alone does not say which app this is, so the menu opens with
        // a small title row.
        menu.addItem(Self.titleItem())
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

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

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
        laterUpdateItem.target = self
        laterUpdateItem.isHidden = true
        menu.addItem(laterUpdateItem)
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

    /// "OpenPromptr 1.3.1" as the first row: a section header where the system
    /// has one (macOS 14), otherwise a disabled item.
    private static func titleItem() -> NSMenuItem {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let title = version.map { "OpenPromptr \($0)" } ?? "OpenPromptr"
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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
        checkForUpdatesItem.isEnabled =
            updates?.isBusy != true && updates?.hasPreparedUpdate != true

        if case .readyToInstall(let version)? = updates?.state {
            installUpdateItem.title = "Install Update \(version) and Restart…"
            installUpdateItem.isHidden = false
            laterUpdateItem.isHidden = false
        } else {
            installUpdateItem.isHidden = true
            laterUpdateItem.isHidden = true
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
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI's Settings scene answers to a selector that changed name in
        // macOS 14.
        let selector =
            if #available(macOS 14.0, *) {
                Selector(("showSettingsWindow:"))
            } else {
                Selector(("showPreferencesWindow:"))
            }
        NSApp.sendAction(selector, to: nil, from: nil)
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
    private func dismissUpdate() {
        guard let updates else { return }
        UpdateFlow.dismissUpdate(updates: updates)
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    deinit {
        // Explicit removal rather than relying on dealloc: this instance is
        // discarded whenever presence changes to a mode without a menu bar
        // item, and a status item left behind would sit in the menu bar with
        // nothing behind it. The type is @MainActor, but `deinit` itself is
        // not implicitly isolated.
        MainActor.assumeIsolated {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private weak var updates: UpdateManager?
    private var terminationPending = false
    /// Present only while the current presence includes a menu bar item;
    /// recreated whenever that becomes true again, since a removed
    /// `NSStatusItem` cannot be brought back.
    private var statusItemController: AppStatusItemController?
    private var showControlsHandler: (() -> Void)?
    private var presenceSubscription: AnyCancellable?

    func configure(
        model: AppModel,
        updates: UpdateManager,
        showControls: @escaping () -> Void
    ) {
        self.model = model
        self.updates = updates
        showControlsHandler = showControls
        // Fires immediately with the current value, so the persisted choice
        // takes effect as soon as the model exists, then again on every
        // change made in Settings.
        presenceSubscription = model.$presence.sink { [weak self] presence in
            self?.apply(presence)
        }
    }

    private func apply(_ presence: AppPresence) {
        NSApplication.shared.setActivationPolicy(
            presence.showsDockIcon ? .regular : .accessory
        )

        if presence.showsMenuBarItem {
            guard statusItemController == nil else {
                return
            }
            let controller = AppStatusItemController()
            if let model, let updates, let showControlsHandler {
                controller.configure(
                    model: model,
                    updates: updates,
                    showControls: showControlsHandler
                )
            }
            statusItemController = controller
        } else {
            statusItemController = nil
        }
    }

    func showControls() {
        showControlsHandler?()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Corrected to the persisted choice moments later, once `configure`
        // runs with the model; a regular app with no Dock icon flash yet is
        // the safer default for that brief window than the reverse.
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
                    Button("Later") {
                        UpdateFlow.dismissUpdate(updates: updates)
                    }
                }

                Button("Check for Updates…") {
                    UpdateFlow.checkForUpdates(updates: updates, model: model)
                }
                .disabled(updates.isBusy || updates.hasPreparedUpdate)

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

        Settings {
            SettingsView(model: model)
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
