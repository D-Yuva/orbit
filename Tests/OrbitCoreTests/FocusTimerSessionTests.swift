import Foundation
import XCTest
@testable import OrbitCore

final class FocusTimerSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testNewSessionIsIdleAndCannotComplete() {
        var session = FocusTimerSession()

        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.deadline)
        XCTAssertEqual(session.durationSeconds, 25 * 60)
        XCTAssertEqual(session.remainingSeconds(at: start), 25 * 60)
        XCTAssertEqual(session.progress(at: start), 0)
        XCTAssertFalse(session.advance(now: start.addingTimeInterval(24 * 60 * 60)))
    }

    func testRunningSessionUsesElapsedTimeAndRoundsRemainingUp() {
        var session = FocusTimerSession()
        session.start(minutes: 1, now: start)

        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.deadline, start.addingTimeInterval(60))
        XCTAssertEqual(session.remainingSeconds(at: start.addingTimeInterval(0.25)), 60)
        XCTAssertEqual(session.remainingSeconds(at: start.addingTimeInterval(30)), 30)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(30)), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(session.remainingSeconds(at: start.addingTimeInterval(59.75)), 1)
        XCTAssertFalse(session.advance(now: start.addingTimeInterval(59.75)))
    }

    func testPauseFreezesFractionalTimeAndResumeRestoresItWithoutDrift() {
        var session = FocusTimerSession()
        session.start(minutes: 1, now: start)
        session.pause(now: start.addingTimeInterval(12.25))
        let muchLater = start.addingTimeInterval(12 * 60 * 60)

        XCTAssertEqual(session.state, .paused)
        XCTAssertNil(session.deadline)
        XCTAssertEqual(session.remainingSeconds(at: muchLater), 48)
        XCTAssertEqual(session.progress(at: muchLater), 12.25 / 60, accuracy: 0.000_001)
        XCTAssertFalse(session.advance(now: muchLater))

        session.resume(now: muchLater)
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.deadline, muchLater.addingTimeInterval(47.75))
        XCTAssertEqual(session.remainingSeconds(at: muchLater), 48)
        XCTAssertFalse(session.advance(now: muchLater.addingTimeInterval(47.5)))
        XCTAssertTrue(session.advance(now: muchLater.addingTimeInterval(47.75)))
    }

    func testDelayedTickAfterSleepCompletesImmediatelyAndOnlyOnce() {
        var session = FocusTimerSession()
        session.start(minutes: 25, now: start)
        let wake = start.addingTimeInterval(8 * 60 * 60)

        XCTAssertEqual(session.remainingSeconds(at: wake), 0)
        XCTAssertEqual(session.progress(at: wake), 1)
        XCTAssertTrue(session.advance(now: wake))
        XCTAssertEqual(session.state, .completed)
        XCTAssertNil(session.deadline)
        XCTAssertFalse(session.advance(now: wake))
        XCTAssertFalse(session.advance(now: wake.addingTimeInterval(1)))
    }

    func testCompletionAtExactDeadlineIsReportedOnce() {
        var session = FocusTimerSession()
        session.start(minutes: 1, now: start)
        let deadline = start.addingTimeInterval(60)

        XCTAssertTrue(session.advance(now: deadline))
        XCTAssertFalse(session.advance(now: deadline))
        XCTAssertEqual(session.remainingSeconds(at: deadline), 0)
        XCTAssertEqual(session.progress(at: deadline), 1)
    }

    func testPauseAtOrAfterDeadlineDoesNotConsumeCompletion() {
        for elapsed in [60.0, 600.0] {
            var session = FocusTimerSession()
            session.start(minutes: 1, now: start)
            let now = start.addingTimeInterval(elapsed)
            session.pause(now: now)

            XCTAssertEqual(session.state, .running)
            XCTAssertEqual(session.deadline, start.addingTimeInterval(60))
            XCTAssertTrue(session.advance(now: now))
            XCTAssertFalse(session.advance(now: now))
        }
    }

    func testResetCancelsSessionAndPreservesChosenDuration() {
        var session = FocusTimerSession()
        session.start(minutes: 10, now: start)
        session.pause(now: start.addingTimeInterval(90))
        session.reset()

        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.deadline)
        XCTAssertEqual(session.durationSeconds, 600)
        XCTAssertEqual(session.remainingSeconds(at: start.addingTimeInterval(1_000)), 600)
        XCTAssertEqual(session.progress(at: start), 0)
        XCTAssertFalse(session.advance(now: start.addingTimeInterval(1_000)))
    }

    func testRestartReplacesOldDeadlineAndRearmsCompletion() {
        var session = FocusTimerSession()
        session.start(minutes: 1, now: start)
        let restart = start.addingTimeInterval(50)
        session.start(minutes: 2, now: restart)

        XCTAssertEqual(session.durationSeconds, 120)
        XCTAssertEqual(session.deadline, restart.addingTimeInterval(120))
        XCTAssertFalse(session.advance(now: start.addingTimeInterval(60)))
        XCTAssertTrue(session.advance(now: restart.addingTimeInterval(120)))

        let secondStart = restart.addingTimeInterval(121)
        session.start(minutes: 1, now: secondStart)
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.progress(at: secondStart), 0)
        XCTAssertTrue(session.advance(now: secondStart.addingTimeInterval(60)))
        XCTAssertFalse(session.advance(now: secondStart.addingTimeInterval(61)))
    }

    func testMinuteBoundsClampBeforeMultiplication() {
        for (minutes, expectedSeconds) in [(Int.min, 60), (0, 60), (1, 60), (180, 10_800), (181, 10_800), (Int.max, 10_800)] {
            var session = FocusTimerSession()
            session.start(minutes: minutes, now: start)

            XCTAssertEqual(session.durationSeconds, TimeInterval(expectedSeconds))
            XCTAssertEqual(session.remainingSeconds(at: start), expectedSeconds)
            XCTAssertEqual(session.deadline, start.addingTimeInterval(TimeInterval(expectedSeconds)))
        }
    }

    func testBackwardClockJumpKeepsProgressAndRemainingWithinBounds() {
        var session = FocusTimerSession()
        session.start(minutes: 1, now: start)
        let beforeStart = start.addingTimeInterval(-3_600)

        XCTAssertEqual(session.remainingSeconds(at: beforeStart), 60)
        XCTAssertEqual(session.progress(at: beforeStart), 0)
        XCTAssertFalse(session.advance(now: beforeStart))
        XCTAssertTrue(session.advance(now: start.addingTimeInterval(60)))
        XCTAssertEqual(session.progress(at: beforeStart), 1)
        XCTAssertEqual(session.remainingSeconds(at: beforeStart), 0)
    }

    func testInvalidTransitionsDoNotChangeTheSession() {
        var session = FocusTimerSession()
        let idle = session
        session.pause(now: start)
        session.resume(now: start)
        XCTAssertEqual(session, idle)

        session.start(minutes: 1, now: start)
        let running = session
        session.resume(now: start.addingTimeInterval(30))
        XCTAssertEqual(session, running)

        session.pause(now: start.addingTimeInterval(30))
        let paused = session
        session.pause(now: start.addingTimeInterval(100))
        XCTAssertEqual(session, paused)

        session.resume(now: start.addingTimeInterval(100))
        XCTAssertTrue(session.advance(now: start.addingTimeInterval(130)))
        let completed = session
        session.pause(now: start.addingTimeInterval(140))
        session.resume(now: start.addingTimeInterval(140))
        XCTAssertEqual(session, completed)
    }
}
