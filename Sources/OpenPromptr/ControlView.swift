import CoreGraphics
import OpenPromptrCore
import SwiftUI

/// A titled block of related controls. Keeps the window scannable without
/// relying on the heavier platform `GroupBox` chrome.
struct ControlSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            content
        }
        // A named group for VoiceOver, the way a native GroupBox is one; the
        // visible heading is what names it, so it is not read twice.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// Live illustration of what rotation and mirroring do to the source image,
/// so the correct teleprompter orientation can be found without guessing.
private struct OrientationPreview: View {
    let transform: DisplayTransform

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.black)
            Text("Fg")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .scaleEffect(
                    x: transform.mirrorHorizontally ? -1 : 1,
                    y: transform.mirrorVertically ? -1 : 1
                )
                .rotationEffect(.degrees(Double(transform.rotation.rawValue)))
        }
        .frame(width: 74, height: 52)
        .accessibilityLabel("Orientation preview")
    }
}

struct ControlView: View {
    @ObservedObject var model: AppModel
    let onAppear: () -> Void

    private var sourceKindBinding: Binding<CaptureSourceKind> {
        Binding(
            get: { model.sourceKind },
            set: { model.selectSourceKind($0) }
        )
    }

    private var sourceDisplayBinding: Binding<CGDirectDisplayID?> {
        Binding(
            get: { model.selectedSourceDisplayID },
            set: { model.selectSourceDisplay($0) }
        )
    }

    private var sourceWindowBinding: Binding<CGWindowID?> {
        Binding(
            get: { model.selectedSourceWindowID },
            set: { model.selectSourceWindow($0) }
        )
    }

    private var displayBinding: Binding<CGDirectDisplayID?> {
        Binding(
            get: { model.selectedDisplayID },
            set: { model.selectDisplay($0) }
        )
    }

    private var rotationBinding: Binding<DisplayRotation> {
        Binding(
            get: { model.transform.rotation },
            set: { rotation in
                var value = model.transform
                value.rotation = rotation
                model.setTransform(value)
            }
        )
    }

    private var horizontalMirrorBinding: Binding<Bool> {
        Binding(
            get: { model.transform.mirrorHorizontally },
            set: { enabled in
                var value = model.transform
                value.mirrorHorizontally = enabled
                model.setTransform(value)
            }
        )
    }

    private var verticalMirrorBinding: Binding<Bool> {
        Binding(
            get: { model.transform.mirrorVertically },
            set: { enabled in
                var value = model.transform
                value.mirrorVertically = enabled
                model.setTransform(value)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sourceSection
            targetSection
            orientationSection
            statusSection
            actionBar
        }
        .padding(16)
        .frame(width: 560)
        .onAppear(perform: onAppear)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenPromptr")
                    .font(.headline)
                Text("Mirror and rotate a display, a window or a virtual display")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            runningBadge
        }
    }

    @ViewBuilder
    private var runningBadge: some View {
        if model.isRunning {
            // Green marks the state, the text stays in the primary label color:
            // green text on a pale green capsule is too faint in light mode.
            Label {
                Text("Output running")
            } icon: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.green.opacity(0.18)))
        }
    }

    private var sourceSection: some View {
        ControlSection(title: "Source", systemImage: "square.on.square.dashed") {
            Picker("Source", selection: sourceKindBinding) {
                ForEach(CaptureSourceKind.allCases, id: \.rawValue) { kind in
                    Text(kind.localizedName).tag(kind)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Source")
            .pickerStyle(.segmented)
            .disabled(model.isBusy)

            switch model.sourceKind {
            case .virtualDisplay:
                Text(
                    "Creates an invisible display named \"\(model.virtualSourceName)\". Windows have to be moved there blindly; it only becomes visible as the mirrored image on the target display."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                Button {
                    model.openDisplaySettings()
                } label: {
                    Label(
                        "Arrangement in Display Settings…",
                        systemImage: "arrow.up.forward.app"
                    )
                    .font(.caption)
                }
                .buttonStyle(.link)
                .help(
                    "There you can define which edge the invisible display sits on and where the pointer leaves it."
                )
            case .display:
                Picker("Source display", selection: sourceDisplayBinding) {
                    Text("Please select")
                        .tag(nil as CGDirectDisplayID?)
                    ForEach(model.sourceDisplays) { display in
                        Text(display.label)
                            .tag(display.id as CGDirectDisplayID?)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Source display")
                .pickerStyle(.menu)
                .disabled(model.isRunning || model.isBusy)

                Text("Mirrors a visible display. Source and target must not be the same display.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .window:
                HStack {
                    Picker("Source window", selection: sourceWindowBinding) {
                        Text("Please select")
                            .tag(nil as CGWindowID?)
                        ForEach(model.windows) { window in
                            Text(window.label)
                                .tag(window.id as CGWindowID?)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Source window")
                    .pickerStyle(.menu)
                    .disabled(model.isRunning || model.isBusy)

                    Button {
                        model.refreshWindows()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshingWindows)
                    .help("Refresh window list")
                    .accessibilityLabel("Refresh window list")

                    if model.isRefreshingWindows {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                Text(
                    "Mirrors exactly one window, for example the presenter view. Everything stays visible and fully usable."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var targetSection: some View {
        ControlSection(title: "Target display", systemImage: "display") {
            Picker("Target display", selection: displayBinding) {
                Text("Please select")
                    .tag(nil as CGDirectDisplayID?)
                ForEach(model.displays) { display in
                    Text(display.label)
                        .tag(display.id as CGDirectDisplayID?)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Target display")
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.isRunning || model.isBusy)

            if let hint = model.displayConnectionHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let notice = model.singleDisplayNotice {
                Label {
                    Text(notice)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .font(.caption2)
            }
        }
    }

    private var orientationSection: some View {
        ControlSection(
            title: "Orientation",
            systemImage: "arrow.triangle.2.circlepath"
        ) {
            HStack(alignment: .center, spacing: 14) {
                OrientationPreview(transform: model.transform)

                VStack(alignment: .leading, spacing: 8) {
                    Picker("Rotation", selection: rotationBinding) {
                        ForEach(DisplayRotation.allCases, id: \.rawValue) {
                            rotation in
                            Text("\(rotation.rawValue)°").tag(rotation)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Rotation")
                    .pickerStyle(.segmented)

                    HStack(spacing: 16) {
                        Toggle(
                            "Flip horizontally",
                            isOn: horizontalMirrorBinding
                        )
                        Toggle(
                            "Flip vertically",
                            isOn: verticalMirrorBinding
                        )
                        Spacer()
                        Button("Reset") {
                            model.resetTransform()
                        }
                        .controlSize(.small)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(
                    systemName: model.statusIsError
                        ? "exclamationmark.circle.fill"
                        : "info.circle.fill"
                )
                .foregroundStyle(model.statusIsError ? .red : .secondary)
                .accessibilityHidden(true)

                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(
                        model.statusIsError ? .red : .secondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The icon is decorative; a state that only colour and a symbol
            // convey is spoken as text.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                model.statusIsError ? "Error: \(model.statusText)" : model.statusText
            )

            if !model.permissionGranted {
                HStack {
                    Button("Request access") {
                        model.requestPermission()
                    }
                    Button("Open System Settings") {
                        model.openScreenRecordingSettings()
                    }
                    Spacer()
                    Button("Check status") {
                        model.updatePermissionStatus()
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Button {
                model.refreshDisplays()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy)

            Spacer()

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            if model.showsStop {
                // No .cancelAction: Esc means "dismiss", and must not end a
                // running teleprompter. Stop is ⌘. in the Output menu.
                Button("Stop", role: .destructive) {
                    model.requestStop()
                }
            }
            if !model.isRunning && !model.isBusy {
                Button("Start output") {
                    Task { @MainActor in
                        await model.start()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStart)
            }
        }
    }
}
