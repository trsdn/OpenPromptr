import AppKit
import Foundation
import OSLog
import Security

/// Generates and publishes the port/token a script or Stream Deck plugin
/// needs to reach the local API, and removes them again on shutdown so a
/// stale file never claims a port nothing is listening on.
enum LocalAPICredentials {
    private static let logger = Logger(
        subsystem: "com.github.trsdn.OpenPromptr",
        category: "local-api"
    )

    private static var directory: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.github.trsdn.OpenPromptr"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    private static var fileURL: URL {
        directory.appendingPathComponent("local-api.json")
    }

    /// 32 random bytes, hex-encoded. Regenerated on every launch: a fresh
    /// token each run limits how long a leaked one stays useful, and the
    /// discovery file is rewritten on every launch anyway.
    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Writes `{"port": ..., "token": ...}` to the discovery file, creating
    /// the app's Application Support directory if this is the first thing
    /// ever written there. Sets 0600 permissions so another local user
    /// account on a shared Mac can't read the token even though the app
    /// itself isn't sandboxed.
    static func publish(port: Int, token: String) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let payload = ["port": port, "token": token] as [String: Any]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            logger.error("Could not publish local API credentials: \(error.localizedDescription)")
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Reveals the discovery file so a Deck/script author can read its port
    /// and token without hand-typing an Application Support path.
    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
