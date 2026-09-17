import Foundation

/// The `GET /v1/state` response shape for the local control API (issue #4).
public struct LocalAPIState: Codable, Equatable, Sendable {
    public var running: Bool
    public var busy: Bool
    public var status: String
    public var error: Bool
    public var permissionGranted: Bool
    public var source: String
    public var display: LocalAPIDisplay?
    public var transform: LocalAPITransform

    public init(
        running: Bool,
        busy: Bool,
        status: String,
        error: Bool,
        permissionGranted: Bool,
        source: String,
        display: LocalAPIDisplay?,
        transform: LocalAPITransform
    ) {
        self.running = running
        self.busy = busy
        self.status = status
        self.error = error
        self.permissionGranted = permissionGranted
        self.source = source
        self.display = display
        self.transform = transform
    }
}

public struct LocalAPIDisplay: Codable, Equatable, Sendable {
    public var id: UInt32
    public var name: String

    public init(id: UInt32, name: String) {
        self.id = id
        self.name = name
    }
}

public struct LocalAPITransform: Codable, Equatable, Sendable {
    public var rotation: Int
    public var mirrorH: Bool
    public var mirrorV: Bool

    public init(rotation: Int, mirrorH: Bool, mirrorV: Bool) {
        self.rotation = rotation
        self.mirrorH = mirrorH
        self.mirrorV = mirrorV
    }
}

/// A `POST /v1/transform` body: every field is optional, so a caller can
/// change just the rotation, just one mirror axis, or any combination,
/// without first reading the current transform.
public struct TransformPatch: Decodable, Equatable, Sendable {
    public var rotation: Int?
    public var mirrorH: Bool?
    public var mirrorV: Bool?

    public init(rotation: Int? = nil, mirrorH: Bool? = nil, mirrorV: Bool? = nil) {
        self.rotation = rotation
        self.mirrorH = mirrorH
        self.mirrorV = mirrorV
    }

    /// Applies this patch to `transform`, leaving fields the patch doesn't
    /// mention unchanged. An unrecognized `rotation` value (not 0/90/180/270)
    /// is ignored rather than rejecting the whole patch.
    public func apply(to transform: DisplayTransform) -> DisplayTransform {
        var result = transform
        if let rotation, let value = DisplayRotation(rawValue: rotation) {
            result.rotation = value
        }
        if let mirrorH {
            result.mirrorHorizontally = mirrorH
        }
        if let mirrorV {
            result.mirrorVertically = mirrorV
        }
        return result
    }
}

/// A `POST /v1/display` body: selects the target display by its transient
/// `CGDirectDisplayID`.
public struct DisplaySelectionPatch: Decodable, Equatable, Sendable {
    public var id: UInt32

    public init(id: UInt32) {
        self.id = id
    }
}

/// Pure authorization checks for the local API, kept separate from the
/// server so they're unit-testable without a running `HttpServer`.
public enum LocalAPIAuth {
    /// Constant-time comparison: a naive `==` on the token would leak its
    /// length and content one byte at a time through response-time
    /// differences, which matters here specifically because the token is the
    /// only thing standing between "just a localhost app" and full remote
    /// control.
    public static func tokenMatches(provided: String?, expected: String) -> Bool {
        guard let provided else {
            return false
        }
        let providedBytes = Array(provided.utf8)
        let expectedBytes = Array(expected.utf8)
        // A length mismatch returns immediately: the token is always a fixed
        // 64-character hex string, so length was never the secret part, and
        // comparing it first avoids folding two counts (which can each be
        // arbitrarily large, e.g. a long garbage bearer token) into a single
        // `UInt8` — that used to overflow and crash the app instead of just
        // rejecting the request.
        guard providedBytes.count == expectedBytes.count else {
            return false
        }
        var difference: UInt8 = 0
        for index in 0..<expectedBytes.count {
            difference |= providedBytes[index] ^ expectedBytes[index]
        }
        return difference == 0
    }

    /// A request carrying any `Origin` header is rejected outright,
    /// regardless of its value: a legitimate script or Stream Deck plugin
    /// never sets one, only a browser page does — including one attempting
    /// DNS rebinding against 127.0.0.1.
    public static func isOriginRejected(headers: [String: String]) -> Bool {
        headers.keys.contains { $0.caseInsensitiveCompare("Origin") == .orderedSame }
    }

    /// Extracts the bearer token from an `Authorization` header value, or
    /// `nil` if it isn't a bearer token.
    public static func bearerToken(fromAuthorizationHeader value: String?) -> String? {
        guard let value, value.hasPrefix("Bearer ") else {
            return nil
        }
        return String(value.dropFirst("Bearer ".count))
    }
}
