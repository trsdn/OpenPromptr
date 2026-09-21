import Foundation
import OpenPromptrCore
import SwiftUI

if CommandLine.arguments.contains("--version") {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
    let build = info?["CFBundleVersion"] as? String ?? "unknown"
    print("OpenPromptr \(VersionInfo.displayString(version: version, build: build))")
    exit(0)
}

if CommandLine.arguments.contains(VirtualDisplayHostProtocol.argument) {
    VirtualDisplayHostMain.run()
} else if CommandLine.arguments.contains("--render-ui-snapshots") {
    MainActor.assumeIsolated {
        UISnapshotRenderer.run(arguments: CommandLine.arguments)
    }
} else {
    OpenPromptrApp.main()
}
