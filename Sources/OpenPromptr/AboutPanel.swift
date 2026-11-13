import AppKit

/// Shows the standard macOS About panel, enriched with the build number and
/// links back to the repository and issue tracker (I04: the running product
/// shows its version and links to the repository and issue tracker).
///
/// This reuses `NSApp.orderFrontStandardAboutPanel` rather than a custom
/// window, so title, icon, and copyright keep coming from `Info.plist` the
/// way every other macOS app's About panel does; only the credits area is
/// extended.
enum AboutPanel {
    @MainActor
    static func show() {
        let info = Bundle.main.infoDictionary
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let repositoryURL = info?["OPRRepositoryURL"] as? String
        let issueTrackerURL = info?["OPRIssueTrackerURL"] as? String

        let credits = NSMutableAttributedString(
            string: "Build \(build)\n\n",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
        if let repositoryURL, let url = URL(string: repositoryURL) {
            credits.append(link(title: "Source repository", url: url))
            credits.append(NSAttributedString(string: "\n"))
        }
        if let issueTrackerURL, let url = URL(string: issueTrackerURL) {
            credits.append(link(title: "Report an issue", url: url))
        }

        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func link(title: String, url: URL) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .link: url,
                .foregroundColor: NSColor.linkColor,
            ]
        )
    }
}
