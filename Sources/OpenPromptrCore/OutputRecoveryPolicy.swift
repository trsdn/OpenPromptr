/// A bounded retry budget shared across short-lived capture sessions.
/// Times must come from a monotonic clock, not wall-clock dates.
public struct OutputRecoveryPolicy: Sendable {
    public static let retryDelays = [2, 5, 15]
    public static let stableInterval: Double = 30

    public private(set) var attemptCount = 0
    private var firstFrameUptime: Double?

    public init() {}

    public var nextDelay: Int? {
        Self.retryDelays.indices.contains(attemptCount)
            ? Self.retryDelays[attemptCount] : nil
    }

    /// Only consume a retry when its delay has elapsed and capture can start.
    @discardableResult
    public mutating func beginAttempt() -> Bool {
        guard nextDelay != nil else {
            return false
        }
        attemptCount += 1
        return true
    }

    public mutating func didRender(at uptime: Double) {
        if firstFrameUptime == nil {
            firstFrameUptime = uptime
        }
    }

    public mutating func didStop(at uptime: Double) {
        if let firstFrameUptime,
           uptime - firstFrameUptime >= Self.stableInterval {
            attemptCount = 0
        }
        firstFrameUptime = nil
    }

    public mutating func reset() {
        self = Self()
    }
}
