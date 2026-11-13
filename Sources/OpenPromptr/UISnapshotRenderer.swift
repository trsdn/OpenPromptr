import AppKit
import SwiftUI

/// Renders the app's own windows offscreen as PNGs, as evidence for a visual
/// review against the Apple Human Interface Guidelines:
///
///     OpenPromptr --render-ui-snapshots <output-directory>
///
/// It draws the production SwiftUI views through an offscreen window at a fixed
/// width and a 2x scale. It does not start output, create a virtual display,
/// request Screen Recording, or open a network connection, and it keeps its
/// preferences in a throwaway defaults suite. What the control window shows still
/// reflects the displays connected to the Mac it runs on.
///
/// Not captured, deliberately: the menu bar menu (it needs a live status item and
/// an offscreen mock would be misleading) and the standard About panel (the
/// system draws it).

enum UISnapshotAppearance: String, CaseIterable {
    case light
    case dark

    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }

    var appKitName: NSAppearance.Name {
        self == .light ? .aqua : .darkAqua
    }
}

enum UISnapshotSurface: String, CaseIterable {
    case control
    case settings

    /// The width the real window uses.
    var width: CGFloat {
        switch self {
        case .control: 560
        case .settings: 520
        }
    }
}

struct UISnapshotPlan: Equatable {
    static let scale = 2

    let surface: UISnapshotSurface
    let appearance: UISnapshotAppearance

    var filename: String {
        "\(surface.rawValue)-\(appearance.rawValue).png"
    }

    /// Every surface in both appearances. There is no larger-text variant:
    /// macOS has no Dynamic Type, so `dynamicTypeSize` changes nothing there and
    /// a picture claiming to show it would be misleading.
    static let all: [UISnapshotPlan] = UISnapshotSurface.allCases.flatMap { surface in
        UISnapshotAppearance.allCases.map { UISnapshotPlan(surface: surface, appearance: $0) }
    }
}

enum UISnapshotRendererError: LocalizedError {
    case missingOutputDirectory
    case cannotCreateBitmap(String)
    case emptyPNG(String)

    var errorDescription: String? {
        switch self {
        case .missingOutputDirectory:
            "usage: OpenPromptr --render-ui-snapshots <output-directory>"
        case .cannotCreateBitmap(let filename):
            "Could not create a bitmap for \(filename)."
        case .emptyPNG(let filename):
            "Rendered PNG is empty: \(filename)."
        }
    }
}

@MainActor
enum UISnapshotRenderer {
    static func run(arguments: [String]) -> Never {
        do {
            guard let flag = arguments.firstIndex(of: "--render-ui-snapshots"),
                arguments.count == flag + 2
            else {
                throw UISnapshotRendererError.missingOutputDirectory
            }
            let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
            try renderAll(to: directory)
            print("Rendered \(UISnapshotPlan.all.count) UI snapshots to \(directory.path)")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("UI snapshot rendering failed: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    static func renderAll(to directory: URL) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A throwaway suite, so nothing the app would persist reaches the
        // person's real preferences.
        let suiteName = "com.github.trsdn.OpenPromptr.ui-snapshots"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(defaults: defaults)

        for plan in UISnapshotPlan.all {
            let data = try render(plan: plan, model: model)
            try data.write(to: directory.appendingPathComponent(plan.filename), options: .atomic)
        }
    }

    private static func content(for plan: UISnapshotPlan, model: AppModel) -> AnyView {
        switch plan.surface {
        case .control:
            AnyView(ControlView(model: model, onAppear: {}))
        case .settings:
            AnyView(SettingsView(model: model))
        }
    }

    private static func render(plan: UISnapshotPlan, model: AppModel) throws -> Data {
        let root = content(for: plan, model: model)
            .environment(\.colorScheme, plan.appearance.colorScheme)
            .environment(\.displayScale, CGFloat(UISnapshotPlan.scale))
            .background(Color(nsColor: .windowBackgroundColor))

        let hosting = NSHostingView(rootView: root)
        let width = plan.surface.width
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        hosting.layoutSubtreeIfNeeded()
        // The real windows size to their content, so measure the same way.
        let height = max(hosting.fittingSize.height, 100).rounded(.up)
        let size = NSSize(width: width, height: height)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: plan.appearance.appKitName)

        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = hosting.appearance
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width) * UISnapshotPlan.scale,
                pixelsHigh: Int(size.height) * UISnapshotPlan.scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            throw UISnapshotRendererError.cannotCreateBitmap(plan.filename)
        }
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.orderOut(nil)

        guard let data = bitmap.representation(using: .png, properties: [:]), !data.isEmpty else {
            throw UISnapshotRendererError.emptyPNG(plan.filename)
        }
        return data
    }
}
