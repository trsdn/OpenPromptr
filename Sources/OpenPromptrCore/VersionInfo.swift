/// Pure parsing/formatting helpers for the version shown in the About panel and
/// `--version` output. The values themselves come from the built app's
/// `Info.plist`, which `build-app.sh` derives from the git tag at build time.
public enum VersionInfo {
    /// Strips an optional leading "v" from a release tag such as "v1.2.0" and
    /// validates the remainder looks like a three-part numeric version.
    /// Returns `nil` for anything else, including a tag with a
    /// `git describe` commit suffix.
    public static func marketingVersion(fromTag tag: String) -> String? {
        var stripped = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("v") {
            stripped.removeFirst()
        }
        let parts = stripped.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy(isDigits) else {
            return nil
        }
        return stripped
    }

    /// Combines a marketing version with a build identifier for display,
    /// e.g. "1.2.0 (42)".
    public static func displayString(version: String, build: String) -> String {
        "\(version) (\(build))"
    }

    private static func isDigits(_ substring: Substring) -> Bool {
        !substring.isEmpty && substring.allSatisfy(\.isNumber)
    }
}
