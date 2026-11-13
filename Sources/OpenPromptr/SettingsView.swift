import OpenPromptrCore
import SwiftUI

/// Preferences window (⌘,): everything that is set once and rarely touched,
/// kept out of the control window so that stays about the output itself.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            presenceSection
            startupSection
            remoteControlSection
        }
        .padding(16)
        .frame(width: 520)
    }

    private var presenceSection: some View {
        ControlSection(title: "Presence", systemImage: "menubar.dock.rectangle") {
            VStack(alignment: .leading, spacing: 6) {
                Picker(
                    "Presence",
                    selection: Binding(
                        get: { model.presence },
                        set: { model.setPresence($0) }
                    )
                ) {
                    ForEach(AppPresence.allCases, id: \.rawValue) { presence in
                        Text(presence.localizedName).tag(presence)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Text(model.presence.localizedExplanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !model.presence.showsMenuBarItem {
                    Text(
                        "Output still starts and stops from the control window or the local HTTP API while hidden this way."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var startupSection: some View {
        ControlSection(title: "Startup and recovery", systemImage: "power") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "Start output automatically when the app launches",
                    isOn: Binding(
                        get: { model.autoStartOutput },
                        set: { model.setAutoStartOutput($0) }
                    )
                )

                Toggle(
                    "Automatically resume output after an interruption",
                    isOn: Binding(
                        get: { model.autoResumeOutput },
                        set: { model.setAutoResumeOutput($0) }
                    )
                )
                Text("Retries after 2, 5 and 15 seconds. Stop always cancels automatic recovery.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack {
                    Toggle(
                        "Launch at login",
                        isOn: Binding(
                            get: { model.loginItemEnabled },
                            set: { model.setLoginItemEnabled($0) }
                        )
                    )
                    .disabled(model.loginItemBusy)
                    if model.loginItemBusy {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    if model.loginItemNeedsApproval {
                        Button("Open System Settings") {
                            model.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                }

                Label {
                    Text(model.loginItemStatusText)
                        .font(.caption2)
                        .foregroundStyle(
                            model.loginItemStatusIsError ? .red : .secondary
                        )
                } icon: {
                    Image(
                        systemName: model.loginItemStatusIsError
                            ? "exclamationmark.circle.fill"
                            : "info.circle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(model.loginItemStatusIsError ? .red : .secondary)
                }

                if !model.appIsInApplicationsFolder {
                    Text(
                        "For a reliable launch at login, move the signed app to /Applications and register it there."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private var remoteControlSection: some View {
        ControlSection(title: "Remote control", systemImage: "network") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "Enable local HTTP API",
                    isOn: Binding(
                        get: { model.enableLocalAPI },
                        set: { model.setEnableLocalAPI($0) }
                    )
                )
                .toggleStyle(.checkbox)

                Text(
                    "Lets a script or a Stream Deck plugin start/stop output and read status. Listens on 127.0.0.1 only and requires a token; never reachable from the network."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                if model.enableLocalAPI {
                    Button("Reveal Connection Info in Finder") {
                        LocalAPICredentials.revealInFinder()
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
