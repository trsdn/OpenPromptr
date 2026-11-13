import Testing

@testable import OpenPromptrCore

@Test("Recovery allows exactly three attempts after 2, 5 and 15 seconds")
func recoveryBudgetIsBounded() {
    var policy = OutputRecoveryPolicy()
    for (index, delay) in [2, 5, 15].enumerated() {
        #expect(policy.attemptCount == index)
        #expect(policy.nextDelay == delay)
        let started = policy.beginAttempt()
        #expect(started)
        policy.didStop(at: Double(index))
    }
    #expect(policy.nextDelay == nil)
    let extraAttempt = policy.beginAttempt()
    #expect(!extraAttempt)
    #expect(policy.attemptCount == 3)
}

@Test("Waiting without starting does not consume a retry")
func recoveryWaitingPreservesBudget() {
    var policy = OutputRecoveryPolicy()
    #expect(policy.nextDelay == 2)
    #expect(policy.nextDelay == 2)
    let started = policy.beginAttempt()
    #expect(started)
    policy.didStop(at: 1)
    #expect(policy.nextDelay == 5)
    #expect(policy.nextDelay == 5)
    #expect(policy.attemptCount == 1)
}

@Test("A brief successful output does not replenish retries")
func recoveryShortSuccessKeepsBudget() {
    var policy = OutputRecoveryPolicy()
    for index in 0..<3 {
        let started = policy.beginAttempt()
        #expect(started)
        let start = Double(index * 100)
        policy.didRender(at: start)
        policy.didStop(at: start + 29.99)
    }
    #expect(policy.nextDelay == nil)
}

@Test("Thirty seconds after the first rendered frame replenish retries")
func recoveryStableOutputResetsBudget() {
    var policy = OutputRecoveryPolicy()
    let first = policy.beginAttempt()
    let second = policy.beginAttempt()
    #expect(first && second)
    policy.didRender(at: 100)
    // A renderer fallback must not move the first-frame timestamp forward.
    policy.didRender(at: 120)
    policy.didStop(at: 130)
    #expect(policy.attemptCount == 0)
    #expect(policy.nextDelay == 2)
}

@Test("An empty source does not count as a stable rendered output")
func recoveryNoFrameKeepsBudget() {
    var policy = OutputRecoveryPolicy()
    let started = policy.beginAttempt()
    #expect(started)
    policy.didStop(at: 100_000)
    #expect(policy.attemptCount == 1)
}

@Test("Explicit restart resets retries and the old frame timestamp")
func recoveryExplicitResetClearsSession() {
    var policy = OutputRecoveryPolicy()
    let first = policy.beginAttempt()
    #expect(first)
    policy.didRender(at: 1)
    policy.reset()
    #expect(policy.attemptCount == 0)
    let restarted = policy.beginAttempt()
    #expect(restarted)
    policy.didStop(at: 100)
    #expect(policy.attemptCount == 1)
}

@Test("Stable time does not span separate capture sessions")
func recoveryStabilityDoesNotSpanSessions() {
    var policy = OutputRecoveryPolicy()
    let first = policy.beginAttempt()
    #expect(first)
    policy.didRender(at: 1)
    policy.didStop(at: 10)
    let second = policy.beginAttempt()
    #expect(second)
    policy.didStop(at: 100)
    #expect(policy.attemptCount == 2)
}
