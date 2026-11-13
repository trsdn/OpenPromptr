import Foundation

/// Where the output is in its life. The app's model holds one of these and every
/// decision below is a pure function of it, so the rules can be tested without a
/// display, ScreenCaptureKit or a Screen Recording grant.
public enum OutputLifecycle: Equatable, Sendable {
    case idle
    case waiting
    case recovering
    case starting(UInt64)
    case running
    case stopping
    case blocked

    public var isRunning: Bool {
        self == .running
    }

    /// A start or a stop is under way.
    public var isBusy: Bool {
        switch self {
        case .starting, .stopping:
            return true
        case .idle, .waiting, .recovering, .running, .blocked:
            return false
        }
    }

    /// Whether there is output to stop, as the control window shows it: running,
    /// starting or stopping, or retrying after a failure. Deliberately narrower
    /// than `OutputControls.canStop`, which also covers output that is merely
    /// wanted (waiting for a display).
    public var showsStop: Bool {
        isRunning || isBusy || self == .recovering
    }
}

public enum OutputControls {
    /// Start is offered when nothing runs or is changing and there is a target
    /// and a complete source to start with.
    public static func canStart(
        lifecycle: OutputLifecycle,
        hasTarget: Bool,
        sourceIsComplete: Bool
    ) -> Bool {
        !lifecycle.isRunning && !lifecycle.isBusy && hasTarget && sourceIsComplete
    }

    /// Stop is accepted while output is wanted, running or changing. This is
    /// also what keeps an update from installing under a session.
    public static func canStop(desiredOutput: Bool, lifecycle: OutputLifecycle) -> Bool {
        desiredOutput || lifecycle.isRunning || lifecycle.isBusy
    }
}

/// The ways a start can fail, as far as the response to it is concerned. The app
/// maps its own errors onto these.
public enum StartFailureKind: Equatable, Sendable {
    case virtualSourceUnavailable
    case sourceDisplayUnavailable
    case sourceWindowUnavailable
    case targetDisplayUnavailable
    case configurationChanged
    case sourceIsTarget
    case screenCaptureSourceUnavailable
    case other

    /// A display or window that is not there right now and may come back. These
    /// are waited out quietly rather than reported as a failure.
    public var isTransient: Bool {
        switch self {
        case .virtualSourceUnavailable,
            .sourceDisplayUnavailable,
            .sourceWindowUnavailable,
            .targetDisplayUnavailable,
            .configurationChanged:
            return true
        case .sourceIsTarget, .screenCaptureSourceUnavailable, .other:
            return false
        }
    }

    /// Whether recovering from this failure needs to discard the cached
    /// virtual source display and create a new one, rather than simply
    /// retrying with the same `CGDirectDisplayID`. True only for
    /// `screenCaptureSourceUnavailable`: the case observed after the Mac
    /// wakes from sleep, where the private CGVirtualDisplay silently drops
    /// out of ScreenCaptureKit's shareable content while its ID still reads
    /// back as "online" at the CoreGraphics level, so a same-ID retry fails
    /// identically every time.
    public var requiresVirtualSourceRecreation: Bool {
        self == .screenCaptureSourceUnavailable
    }
}

/// What to do after a start failed.
public struct StartFailureResponse: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Wait for a display; not an error and no failure message.
        case waitQuietly
        /// Stop and say so; the person can start again.
        case blockWithError
    }

    public var outcome: Outcome
    /// Hand the failure to automatic recovery.
    public var schedulesRecovery: Bool
    /// Forget a remembered failure so that recovery does not retry it: a retry
    /// cannot fix a source that is the target.
    public var clearsRecoveryFailure: Bool

    public static func decide(
        _ kind: StartFailureKind,
        targetIsResolved: Bool,
        hasPendingRecovery: Bool
    ) -> StartFailureResponse {
        if kind.isTransient {
            return StartFailureResponse(
                outcome: .waitQuietly,
                schedulesRecovery: hasPendingRecovery,
                clearsRecoveryFailure: false
            )
        }
        if targetIsResolved {
            let hopeless = kind == .sourceIsTarget
            return StartFailureResponse(
                outcome: .blockWithError,
                schedulesRecovery: !hopeless,
                clearsRecoveryFailure: hopeless
            )
        }
        // The monitor is not there, so there is nothing to have failed against.
        return StartFailureResponse(
            outcome: .waitQuietly,
            schedulesRecovery: false,
            clearsRecoveryFailure: false
        )
    }
}

/// What to do when the target display or the source is no longer available.
public enum DisplaysUnavailableResponse: Equatable, Sendable {
    /// A start is in flight: discard it and wait.
    case discardStartAndWait
    /// Output is up: stop it, then wait.
    case stopAndWait
    /// Nothing is up: just wait.
    case wait
    /// A stop is already under way; leave it.
    case leaveAlone

    public static func decide(
        lifecycle: OutputLifecycle,
        hasCaptureSession: Bool
    ) -> DisplaysUnavailableResponse {
        if case .starting = lifecycle {
            return .discardStartAndWait
        }
        if lifecycle == .running || hasCaptureSession {
            return .stopAndWait
        }
        if lifecycle == .stopping {
            return .leaveAlone
        }
        return .wait
    }

    /// A retry in progress no longer makes sense once the display is gone; it
    /// starts over when the display is back.
    public static func cancelsRecovery(lifecycle: OutputLifecycle) -> Bool {
        lifecycle == .recovering
    }
}

/// What to do after capture failed and automatic recovery is asked to step in.
public enum RecoveryDecision: Equatable, Sendable {
    case blockForPermission
    case waitForDisplays
    /// Three attempts have been spent.
    case exhausted
    case retry(afterSeconds: Int)

    public static func decide(
        permissionGranted: Bool,
        displaysAvailable: Bool,
        nextDelay: Int?
    ) -> RecoveryDecision {
        guard permissionGranted else {
            return .blockForPermission
        }
        guard displaysAvailable else {
            return .waitForDisplays
        }
        guard let nextDelay else {
            return .exhausted
        }
        return .retry(afterSeconds: nextDelay)
    }
}

/// What to do when a running capture stream ends by itself.
public enum CaptureEndedResponse: Equatable, Sendable {
    /// Both displays are there, so something else went wrong: try to recover.
    case recover
    /// A display went away: stop and wait for it, without an error.
    case stopAndWait

    public static func decide(displaysAvailable: Bool) -> CaptureEndedResponse {
        displaysAvailable ? .recover : .stopAndWait
    }
}
