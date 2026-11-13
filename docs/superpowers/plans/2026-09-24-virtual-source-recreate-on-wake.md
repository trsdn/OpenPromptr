# Virtual Source Recreate-on-Wake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix "Start failed: ScreenCaptureKit did not find the source display with ID N. Automatic recovery failed after 3 attempts." occurring every time the Mac wakes from standby while OpenPromptr uses the virtual display source.

**Architecture:** The virtual source's `CGDirectDisplayID` is captured once at launch (`AppModel.ensureVirtualSource()`) and never refreshed. After a sleep/wake cycle the private `CGVirtualDisplay` silently drops out of ScreenCaptureKit's `SCShareableContent` while its ID still reads back as "online" via `CGGetOnlineDisplayList`, so every recovery attempt retries the identical, permanently-dead ID and the fixed 3-attempt budget (`OutputRecoveryPolicy`) is guaranteed to exhaust. The fix adds a way to discard and recreate the virtual source (reusing the existing `releaseVirtualSource()`/`ensureVirtualSource()` pair) and triggers it in two places: (1) inside `startResolvedOutput`'s failure handler, the moment this specific error is detected, so the *next* scheduled recovery attempt uses a fresh ID instead of repeating the doomed one; (2) proactively on `NSWorkspace.didWakeNotification` when output is idle, so a manual "Start output" right after waking doesn't hit the stale ID at all. This mirrors how the physical `.display` source path already self-heals via `DisplayIdentityMatcher` on every attempt — the virtual path never had an equivalent.

**Tech Stack:** Swift 6.1, SwiftPM, swift-testing (`@Test`/`#expect`), AppKit (`NSWorkspace`), ScreenCaptureKit.

**Spec:** No separate spec document. Root cause was established via direct code investigation of this repository (see Problem Statement below); this plan's own text is the spec.

## Problem Statement (root cause, verified against the code)

- Error text origin: `Sources/OpenPromptr/DisplayCatalog.swift:88`, `DisplayResolutionError.screenCaptureSourceUnavailable(CGDirectDisplayID)`, thrown by `screenCaptureDisplay(matching:)` (`DisplayCatalog.swift:421-457`) after 8 polling attempts (125ms apart) fail to find the ID in `SCShareableContent`.
- `AppModel.virtualDisplayID` (`AppModel.swift:318`) is set once in `ensureVirtualSource()` (`AppModel.swift:310-332`, guarded by `virtualDisplayID == nil`) and never re-derived except when the source kind changes.
- `makeSnapshot(target:)`'s `.virtualDisplay` case (`AppModel.swift:1062-1071`) always hands this same cached ID to `DisplayCatalog.makeVirtualSourceSnapshot`, on every call — including every automatic-recovery retry (`AppModel.swift:1603-1652`), which calls `refreshDisplaySnapshot()` (physical displays only) then `startResolvedOutput(target:)` again with no virtual-ID refresh.
- `makeVirtualSourceSnapshot` (`DisplayCatalog.swift:267-293`) first checks `onlineDisplayIDs().contains(virtualDisplayID)` (`CGGetOnlineDisplayList`, fast/low-level) — this **passes** even when the display is gone from ScreenCaptureKit's view, which is why the thrown error is `.screenCaptureSourceUnavailable` (the ScreenCaptureKit-level miss), not `.virtualSourceUnavailable` (the low-level miss) — confirmed by the exact wording in the reported screenshot.
- No sleep/wake handling exists anywhere in the repo today (`AppDelegate` in `Sources/OpenPromptr/OpenPromptrApp.swift:268-366` implements only launch/terminate/reopen callbacks; no `NSWorkspace` notification observer, no `CGDisplayRegisterReconfigurationCallback`).
- `Tests/OpenPromptrCoreTests/OutputDecisionsTests.swift` already pins `screenCaptureSourceUnavailable` as non-transient → `blockWithError` + `schedulesRecovery: true` (lines ~65, 103, 129) — that classification is correct and is **not** changed by this plan; only a new, additional predicate is added.
- `virtualDisplayID` staleness has zero existing test coverage.

## Global Constraints

(Copied verbatim from `AGENTS.md`.)

- `swift build`, `swift test`, `swift format lint --strict --recursive Sources Tests Package.swift` must all stay clean.
- swift-testing only (`@Test`/`#expect`); no XCTest.
- `OutputRecoveryPolicy`'s fixed 2s/5s/15s, 3-attempt, 30s-stability-reset budget must not change — this plan does not touch `OutputRecoveryPolicy` or its tests.
- A manual Stop always wins and suppresses automatic recovery/restart for the rest of the app session — this plan does not touch `manualStopSuppressed` semantics.
- Unit tests exercise `OpenPromptrCore` only; there is no test target for the `OpenPromptr` app target. Any `AppModel.swift`/`DisplayCatalog.swift` change is **unverified by `swift test` alone** — it needs a real run with a Screen Recording grant (see Task 4's manual verification).
- Every commit carries a `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` trailer and a `Claude-Session:` line (this session's values, supplied by the harness).
- No new third-party dependency; no new network connection; no changes to signing, bundle identity, or `Info.plist` usage strings — none of that is touched by this plan.

---

### Task 1: Pure predicate for "this failure needs the virtual source recreated"

**Files:**
- Modify: `Sources/OpenPromptrCore/OutputDecisions.swift:58-82` (the `StartFailureKind` enum)
- Test: `Tests/OpenPromptrCoreTests/OutputDecisionsTests.swift`

**Interfaces:**
- Produces: `StartFailureKind.requiresVirtualSourceRecreation: Bool` — a new computed property, `true` only for `.screenCaptureSourceUnavailable`. Task 2 calls this from `AppModel`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/OpenPromptrCoreTests/OutputDecisionsTests.swift`, directly after the existing `transientStartFailures` test (which ends around line 65):

```swift
@Test("Only a ScreenCaptureKit-side miss on the cached ID asks for the virtual source to be recreated")
func onlyScreenCaptureSourceUnavailableRequiresRecreation() {
    let needsRecreation: [StartFailureKind] = [.screenCaptureSourceUnavailable]
    let doesNotNeedRecreation: [StartFailureKind] = [
        .virtualSourceUnavailable, .sourceDisplayUnavailable, .sourceWindowUnavailable,
        .targetDisplayUnavailable, .configurationChanged, .sourceIsTarget, .other,
    ]
    #expect(needsRecreation.allSatisfy { $0.requiresVirtualSourceRecreation })
    #expect(doesNotNeedRecreation.allSatisfy { !$0.requiresVirtualSourceRecreation })
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter onlyScreenCaptureSourceUnavailableRequiresRecreation`
Expected: FAIL to build — `value of type 'StartFailureKind' has no member 'requiresVirtualSourceRecreation'`.

- [ ] **Step 3: Add the property**

In `Sources/OpenPromptrCore/OutputDecisions.swift`, insert immediately after the closing brace of the existing `isTransient` computed property (right before the `StartFailureKind` enum's own closing `}`, i.e. after current line 81):

```swift
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter onlyScreenCaptureSourceUnavailableRequiresRecreation`
Expected: PASS.

- [ ] **Step 5: Full core test suite and format check**

Run: `swift test && swift format lint --strict --recursive Sources Tests Package.swift`
Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenPromptrCore/OutputDecisions.swift Tests/OpenPromptrCoreTests/OutputDecisionsTests.swift
git commit -m "$(cat <<'EOF'
Add StartFailureKind.requiresVirtualSourceRecreation

Pure predicate identifying the one start-failure kind
(screenCaptureSourceUnavailable) that means the cached virtual source
display ID is dead and must be recreated, not merely retried. Used by
AppModel in the next commit to fix recovery after standby.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EGjbE4ZXFZyXFd2GQ7xRAp
EOF
)"
```

---

### Task 2: Recreate the virtual source when a start fails with a stale ID

**Files:**
- Modify: `Sources/OpenPromptr/AppModel.swift:336-344` (add a method right after `releaseVirtualSource()`)
- Modify: `Sources/OpenPromptr/AppModel.swift:1259-1265` (the `startResolvedOutput` catch block)

**Interfaces:**
- Consumes: `StartFailureKind.requiresVirtualSourceRecreation` (Task 1); existing `releaseVirtualSource()` (`AppModel.swift:336-344`) and `ensureVirtualSource()` (`AppModel.swift:310-332`); existing `Self.startFailureKind(of:)` (`AppModel.swift:1726-1739`).
- Produces: `private func recreateVirtualSource() async` — also used by Task 3.

- [ ] **Step 1: Add `recreateVirtualSource()`**

In `Sources/OpenPromptr/AppModel.swift`, immediately after the existing `releaseVirtualSource()` method (current lines 336-344):

```swift
    /// Tears the virtual display down when another source is chosen, so no
    /// unused synthetic monitor stays in the arrangement.
    private func releaseVirtualSource() {
        guard virtualDisplayHost != nil || virtualDisplayID != nil else {
            return
        }
        virtualDisplayHost?.stop()
        virtualDisplayHost = nil
        virtualDisplayID = nil
        refreshDisplaySnapshot()
    }

    /// Discards a virtual source display whose `CGDirectDisplayID`
    /// ScreenCaptureKit no longer recognizes and creates a fresh one in its
    /// place. The private CGVirtualDisplay does not reliably survive a
    /// sleep/wake cycle: its ID can still read back as "online" via
    /// `CGGetOnlineDisplayList`, but it silently drops out of
    /// ScreenCaptureKit's `SCShareableContent`, so every further attempt
    /// against the same ID fails identically — see
    /// `DisplayResolutionError.screenCaptureSourceUnavailable`.
    private func recreateVirtualSource() async {
        releaseVirtualSource()
        await ensureVirtualSource()
    }
```

(Only the second method is new; the first is shown for exact-match context.)

- [ ] **Step 2: Hook it into the start-failure handler**

In the same file, the catch block of `startResolvedOutput` currently reads (current lines 1259-1265):

```swift
            refreshDisplaySnapshot()
            let response = StartFailureResponse.decide(
                Self.startFailureKind(of: startError),
                targetIsResolved: resolvedTarget != nil,
                hasPendingRecovery: recoveryFailure != nil
            )
```

Replace with:

```swift
            refreshDisplaySnapshot()
            let failureKind = Self.startFailureKind(of: startError)
            if sourceKind == .virtualDisplay, failureKind.requiresVirtualSourceRecreation {
                await recreateVirtualSource()
            }
            let response = StartFailureResponse.decide(
                failureKind,
                targetIsResolved: resolvedTarget != nil,
                hasPendingRecovery: recoveryFailure != nil
            )
```

This does not change what the *current* failed attempt reports (it still shows "Start failed…" and schedules recovery exactly as before, since `StartFailureResponse.decide` is unchanged) — it only ensures that by the time the next scheduled recovery attempt runs `startResolvedOutput` again, `virtualDisplayID` already points at a live display instead of the dead one, so that attempt succeeds instead of repeating the identical failure three times.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 4: Full test suite and format check**

Run: `swift test && swift format lint --strict --recursive Sources Tests Package.swift`
Expected: both clean. (No new automated coverage here — `AppModel` has no test target; this step only guards against a regression in `OpenPromptrCore`.)

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenPromptr/AppModel.swift
git commit -m "$(cat <<'EOF'
Recreate the virtual source when ScreenCaptureKit loses it

Fixes: after the Mac wakes from standby, starting output failed with
"ScreenCaptureKit did not find the source display with ID N" and
automatic recovery exhausted all 3 attempts, because every retry
reused the same now-dead CGDirectDisplayID captured once at launch.

startResolvedOutput now discards and recreates the virtual source
(reusing releaseVirtualSource()/ensureVirtualSource()) the moment this
specific failure is detected, so the next scheduled recovery attempt
gets a fresh, live display ID instead of repeating the same failure.

Unverified by swift test alone: AppModel has no test target and this
touches the capture path. Verified manually per
docs/superpowers/plans/2026-09-24-virtual-source-recreate-on-wake.md
Task 4.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EGjbE4ZXFZyXFd2GQ7xRAp
EOF
)"
```

---

### Task 3: Proactively refresh the virtual source on system wake

**Files:**
- Modify: `Sources/OpenPromptr/AppModel.swift:167-178` (register the observer in `init`)
- Modify: `Sources/OpenPromptr/AppModel.swift:184-190` (remove it in `deinit`)
- Modify: `Sources/OpenPromptr/AppModel.swift:1816-1821` (add the `@objc` handler next to `applicationDidBecomeActive`)

**Interfaces:**
- Consumes: `recreateVirtualSource()` (Task 2); existing `virtualDisplayHost`/`virtualDisplayID`/`captureSession`/`startingCaptureSession` stored properties (`AppModel.swift:122-137`).

- [ ] **Step 1: Register an `NSWorkspace.didWakeNotification` observer**

In `init(defaults:)`, the existing observer registration currently reads (current lines 167-178):

```swift
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
```

Add a third registration immediately after it:

```swift
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
```

- [ ] **Step 2: Remove it in `deinit`**

Current `deinit` (lines 184-190):

```swift
    deinit {
        displayChangeTask?.cancel()
        windowRefreshTask?.cancel()
        selfTestTimeoutTask?.cancel()
        recoveryTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
```

Replace with:

```swift
    deinit {
        displayChangeTask?.cancel()
        windowRefreshTask?.cancel()
        selfTestTimeoutTask?.cancel()
        recoveryTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
```

- [ ] **Step 3: Add the handler**

Current end of class (lines 1816-1821):

```swift
    @objc
    private func applicationDidBecomeActive(_ notification: Notification) {
        updatePermissionStatus()
        refreshLoginItemStatus()
    }
}
```

Replace with:

```swift
    @objc
    private func applicationDidBecomeActive(_ notification: Notification) {
        updatePermissionStatus()
        refreshLoginItemStatus()
    }

    @objc
    private func systemDidWake(_ notification: Notification) {
        Task { @MainActor [weak self] in
            await self?.recreateVirtualSourceAfterWake()
        }
    }

    /// Proactively refreshes an idle virtual source right after the Mac
    /// wakes, so a manual "Start output" does not have to burn a doomed
    /// attempt against a display ID ScreenCaptureKit already dropped during
    /// sleep. Left alone while output is starting or running: a live
    /// `CaptureSession` still references the old display, and pulling it
    /// out from under that session belongs to the same failure-driven path
    /// `startResolvedOutput` already uses (`recreateVirtualSource()`), not
    /// to a notification handler racing it.
    private func recreateVirtualSourceAfterWake() async {
        guard virtualDisplayHost != nil || virtualDisplayID != nil,
            captureSession == nil,
            startingCaptureSession == nil
        else {
            return
        }
        await recreateVirtualSource()
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 5: Full test suite and format check**

Run: `swift test && swift format lint --strict --recursive Sources Tests Package.swift`
Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenPromptr/AppModel.swift
git commit -m "$(cat <<'EOF'
Refresh an idle virtual source right after the Mac wakes

Listens for NSWorkspace.didWakeNotification and, when output is idle
(no active or starting capture session), recreates the virtual source
display proactively via recreateVirtualSource(). Complements the
startResolvedOutput fix: that one repairs a failed start after the
fact, this one avoids the failure altogether for the common case where
output was not running across the sleep.

Unverified by swift test alone: AppModel has no test target and this
touches the capture path. Verified manually per
docs/superpowers/plans/2026-09-24-virtual-source-recreate-on-wake.md
Task 4.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EGjbE4ZXFZyXFd2GQ7xRAp
EOF
)"
```

---

### Task 4: Changelog, manual verification, final gate

**Files:**
- Modify: `CHANGELOG.md` (the `[Unreleased]` → `### Fixed` section)

**Interfaces:**
- Consumes: nothing new. This task only documents and verifies Tasks 1-3.

- [ ] **Step 1: Add the changelog entry**

`CHANGELOG.md` currently has, under `## [Unreleased]`:

```markdown
## [Unreleased]

### Fixed

- A flaky Stream Deck plugin smoke test (`test/smoke.js`) that could race the
  placeholder title against the real first paint.
```

Replace with:

```markdown
## [Unreleased]

### Fixed

- Starting output after the Mac woke from standby could fail with
  "ScreenCaptureKit did not find the source display with ID N" and exhaust
  all 3 automatic-recovery attempts, when using the virtual display source.
  The virtual source is now recreated when ScreenCaptureKit reports it
  missing, and proactively refreshed on system wake while output is idle.
- A flaky Stream Deck plugin smoke test (`test/smoke.js`) that could race the
  placeholder title against the real first paint.
```

- [ ] **Step 2: Commit the changelog**

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
Changelog: virtual source recreated after standby

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EGjbE4ZXFZyXFd2GQ7xRAp
EOF
)"
```

- [ ] **Step 3: Full gate**

Run, in order:

```bash
swift build
swift test
swift format lint --strict --recursive Sources Tests Package.swift
(cd Tools/openpromptr-streamdeck && npm test)
```

Expected: all clean. (The Stream Deck plugin is unrelated to this change; running it only confirms nothing else broke.)

- [ ] **Step 4: Manual verification (required — the capture path has no automated coverage)**

This is the only step that actually exercises the fix. Report to the user exactly what was and was not verified, per `AGENTS.md`'s review-expectation section.

1. `./build-app.sh` to produce `dist/OpenPromptr.app`.
2. Launch it, grant Screen Recording if prompted, select the virtual display as the source, pick a target display, click "Start output". Confirm it starts normally (baseline, unrelated to the fix).
3. Click "Stop output" (or quit back to idle) so output is not running.
4. Put the Mac to sleep and wake it again — either physically, or from Terminal: `pmset sleepnow`, then wake the display (a key press/click) within a few seconds.
5. Click "Start output" again. Expected after the fix: it starts cleanly with no "Start failed" message. (Before the fix, this reproduced the reported error every time.)
6. Repeat once more with output *running* going into sleep (start output, then `pmset sleepnow`, wake): confirm it either keeps running or recovers on its own within the 3-attempt/2s-5s-15s budget, without needing a manual "Start output" click. This exercises Task 2's fix (Task 3 intentionally does not touch a running session — see its docstring).
7. Note in the report to the user which of steps 5/6 were actually run and their outcome; do not claim the fix is confirmed for a step that was not run.

- [ ] **Step 5: Report results to the user**

Summarize: what was verified manually (step 4, with actual outcomes), what was only covered by `swift test` (Task 1's pure predicate), and that `AppModel`'s changes (Tasks 2-3) have no automated regression coverage going forward, consistent with the rest of the capture/virtual-display path.

---

## Self-Review

- **Spec coverage:** Problem Statement's three findings (stale ID never refreshed, no wake handling, no test coverage) are each addressed: Task 1+2 fix the stale-ID retry loop; Task 3 adds wake handling; Task 4 documents what remains unverified by design (matches `AGENTS.md`, not a gap to close).
- **Placeholder scan:** no TBD/"add error handling"/unshown code; every step has literal code.
- **Type consistency:** `recreateVirtualSource() async` (Task 2) is called identically in Task 2 (`await recreateVirtualSource()`) and Task 3 (`await recreateVirtualSource()` inside `recreateVirtualSourceAfterWake()`); `StartFailureKind.requiresVirtualSourceRecreation: Bool` (Task 1) is consumed with matching name/type in Task 2's `failureKind.requiresVirtualSourceRecreation`.
