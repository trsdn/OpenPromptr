import Testing

@testable import OpenPromptrCore

private let everyLifecycle: [OutputLifecycle] = [
    .idle, .waiting, .recovering, .starting(1), .running, .stopping, .blocked,
]

// MARK: - Lifecycle and controls

@Test("Only running counts as running, and only starting or stopping as busy")
func lifecycleProjections() {
    for lifecycle in everyLifecycle {
        #expect(lifecycle.isRunning == (lifecycle == .running))
    }
    let busy = everyLifecycle.filter(\.isBusy)
    #expect(busy == [.starting(1), .stopping])
}

@Test("Stop is shown while there is output to stop, and not while merely waiting or idle")
func stopIsShownOnlyForOutputThatExists() {
    let shown = everyLifecycle.filter(\.showsStop)
    #expect(shown == [.recovering, .starting(1), .running, .stopping])
    #expect(!OutputLifecycle.idle.showsStop)
    #expect(!OutputLifecycle.waiting.showsStop)
    #expect(!OutputLifecycle.blocked.showsStop)
}

@Test("Start is offered only when nothing runs or changes and target and source are set")
func startNeedsAQuietStateAndASetup() {
    for lifecycle in everyLifecycle {
        let quiet = !lifecycle.isRunning && !lifecycle.isBusy
        #expect(
            OutputControls.canStart(lifecycle: lifecycle, hasTarget: true, sourceIsComplete: true)
                == quiet
        )
        #expect(
            !OutputControls.canStart(lifecycle: lifecycle, hasTarget: false, sourceIsComplete: true)
        )
        #expect(
            !OutputControls.canStart(lifecycle: lifecycle, hasTarget: true, sourceIsComplete: false)
        )
    }
}

@Test("Stop is accepted for wanted, running and changing output, so an update cannot slip in")
func stopCoversWantedOutput() {
    #expect(OutputControls.canStop(desiredOutput: true, lifecycle: .waiting))
    #expect(OutputControls.canStop(desiredOutput: false, lifecycle: .running))
    #expect(OutputControls.canStop(desiredOutput: false, lifecycle: .starting(3)))
    #expect(OutputControls.canStop(desiredOutput: false, lifecycle: .stopping))
    #expect(!OutputControls.canStop(desiredOutput: false, lifecycle: .idle))
    #expect(!OutputControls.canStop(desiredOutput: false, lifecycle: .blocked))
    #expect(!OutputControls.canStop(desiredOutput: false, lifecycle: .waiting))
}

// MARK: - After a failed start

@Test("Displays and windows that are not there yet are transient; real failures are not")
func transientStartFailures() {
    let transient: [StartFailureKind] = [
        .virtualSourceUnavailable, .sourceDisplayUnavailable, .sourceWindowUnavailable,
        .targetDisplayUnavailable, .configurationChanged,
    ]
    let permanent: [StartFailureKind] = [.sourceIsTarget, .screenCaptureSourceUnavailable, .other]
    #expect(transient.allSatisfy { $0.isTransient })
    #expect(permanent.allSatisfy { !$0.isTransient })
}

@Test(
    "Only a ScreenCaptureKit-side miss on the cached ID asks for the virtual source to be recreated"
)
func onlyScreenCaptureSourceUnavailableRequiresRecreation() {
    let needsRecreation: [StartFailureKind] = [.screenCaptureSourceUnavailable]
    let doesNotNeedRecreation: [StartFailureKind] = [
        .virtualSourceUnavailable, .sourceDisplayUnavailable, .sourceWindowUnavailable,
        .targetDisplayUnavailable, .configurationChanged, .sourceIsTarget, .other,
    ]
    #expect(needsRecreation.allSatisfy { $0.requiresVirtualSourceRecreation })
    #expect(doesNotNeedRecreation.allSatisfy { !$0.requiresVirtualSourceRecreation })
}

@Test("A missing monitor is waited out quietly, never reported as a failed start")
func missingMonitorWaitsQuietly() {
    // Even when the target still looks resolved by the time the error is handled.
    for resolved in [true, false] {
        let response = StartFailureResponse.decide(
            .targetDisplayUnavailable,
            targetIsResolved: resolved,
            hasPendingRecovery: false
        )
        #expect(response.outcome == .waitQuietly)
        #expect(!response.schedulesRecovery)
        #expect(!response.clearsRecoveryFailure)
    }
}

@Test("A transient failure resumes recovery only when a recovery was already pending")
func transientFailureResumesPendingRecovery() {
    let pending = StartFailureResponse.decide(
        .configurationChanged,
        targetIsResolved: true,
        hasPendingRecovery: true
    )
    let fresh = StartFailureResponse.decide(
        .configurationChanged,
        targetIsResolved: true,
        hasPendingRecovery: false
    )
    #expect(pending.outcome == .waitQuietly && pending.schedulesRecovery)
    #expect(fresh.outcome == .waitQuietly && !fresh.schedulesRecovery)
}

@Test("A real failure with the monitor present is reported and retried")
func realFailureBlocksAndRetries() {
    for kind in [StartFailureKind.screenCaptureSourceUnavailable, .other] {
        let response = StartFailureResponse.decide(
            kind,
            targetIsResolved: true,
            hasPendingRecovery: false
        )
        #expect(response.outcome == .blockWithError)
        #expect(response.schedulesRecovery)
        #expect(!response.clearsRecoveryFailure)
    }
}

@Test("Source equal to target is reported and never retried, because a retry cannot fix it")
func sourceIsTargetIsNotRetried() {
    let response = StartFailureResponse.decide(
        .sourceIsTarget,
        targetIsResolved: true,
        hasPendingRecovery: true
    )
    #expect(response.outcome == .blockWithError)
    #expect(!response.schedulesRecovery)
    #expect(response.clearsRecoveryFailure)
}

@Test("An unexpected failure with no monitor connected is not an error either")
func failureWithoutMonitorWaits() {
    for kind in [StartFailureKind.other, .screenCaptureSourceUnavailable, .sourceIsTarget] {
        let response = StartFailureResponse.decide(
            kind,
            targetIsResolved: false,
            hasPendingRecovery: true
        )
        #expect(response.outcome == .waitQuietly)
        #expect(!response.schedulesRecovery)
    }
}

// MARK: - When a display goes away

@Test("A start in flight is discarded, running output is stopped, and otherwise the app waits")
func displayGoneResponse() {
    #expect(
        DisplaysUnavailableResponse.decide(lifecycle: .starting(2), hasCaptureSession: false)
            == .discardStartAndWait
    )
    #expect(
        DisplaysUnavailableResponse.decide(lifecycle: .starting(2), hasCaptureSession: true)
            == .discardStartAndWait
    )
    #expect(
        DisplaysUnavailableResponse.decide(lifecycle: .running, hasCaptureSession: true)
            == .stopAndWait
    )
    #expect(
        DisplaysUnavailableResponse.decide(lifecycle: .recovering, hasCaptureSession: true)
            == .stopAndWait
    )
    #expect(
        DisplaysUnavailableResponse.decide(lifecycle: .stopping, hasCaptureSession: false)
            == .leaveAlone
    )
    for lifecycle in [OutputLifecycle.idle, .waiting, .blocked, .recovering] {
        #expect(
            DisplaysUnavailableResponse.decide(lifecycle: lifecycle, hasCaptureSession: false)
                == .wait
        )
    }
}

@Test("A retry in progress is cancelled when the display goes away")
func displayGoneCancelsRecovery() {
    for lifecycle in everyLifecycle {
        #expect(
            DisplaysUnavailableResponse.cancelsRecovery(lifecycle: lifecycle)
                == (lifecycle == .recovering)
        )
    }
}

// MARK: - Recovery

@Test("Missing permission wins over everything else, then missing displays, then the budget")
func recoveryDecisionOrder() {
    #expect(
        RecoveryDecision.decide(permissionGranted: false, displaysAvailable: false, nextDelay: nil)
            == .blockForPermission
    )
    #expect(
        RecoveryDecision.decide(permissionGranted: true, displaysAvailable: false, nextDelay: nil)
            == .waitForDisplays
    )
    #expect(
        RecoveryDecision.decide(permissionGranted: true, displaysAvailable: true, nextDelay: nil)
            == .exhausted
    )
    #expect(
        RecoveryDecision.decide(permissionGranted: true, displaysAvailable: true, nextDelay: 5)
            == .retry(afterSeconds: 5)
    )
}

@Test("Driven by the retry budget, recovery retries after 2, 5 and 15 seconds and then gives up")
func recoveryFollowsTheBudget() {
    var policy = OutputRecoveryPolicy()
    var decisions: [RecoveryDecision] = []
    for index in 0..<4 {
        decisions.append(
            RecoveryDecision.decide(
                permissionGranted: true,
                displaysAvailable: true,
                nextDelay: policy.nextDelay
            )
        )
        _ = policy.beginAttempt()
        policy.didStop(at: Double(index))
    }
    #expect(
        decisions == [
            .retry(afterSeconds: 2), .retry(afterSeconds: 5), .retry(afterSeconds: 15), .exhausted,
        ]
    )
}

@Test("A stream that ends by itself is recovered when both displays are there, else waited out")
func captureEndedResponse() {
    #expect(CaptureEndedResponse.decide(displaysAvailable: true) == .recover)
    #expect(CaptureEndedResponse.decide(displaysAvailable: false) == .stopAndWait)
}
