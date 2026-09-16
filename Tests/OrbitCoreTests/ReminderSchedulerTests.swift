import Foundation
import XCTest
@testable import OrbitCore

final class ReminderSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(hour: Int, minute: Int = 0, day: Int = 16) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private var activePreferences: AppPreferences {
        AppPreferences(quietHoursEnabled: false)
    }

    func testFirstDeliveryWaitsFullIntervalAndRestartsFromDeliveryTime() {
        let rule = ReminderRule(kind: .water, intervalMinutes: 45)
        let start = date(hour: 10)
        var scheduler = ReminderScheduler(rules: [rule], now: start, calendar: calendar)

        XCTAssertNil(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 10, minute: 44)))
        XCTAssertEqual(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 10, minute: 46))?.id, rule.id)
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 11, minute: 31))
        XCTAssertNil(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 10, minute: 46)))
    }

    func testCountdownSurvivesPresentationChanges() {
        var rule = ReminderRule(kind: .water, intervalMinutes: 45)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 10), calendar: calendar)
        rule.title = "A quick sip"
        rule.message = "Your water is waiting."
        scheduler.reconcile(rules: [rule], now: date(hour: 10, minute: 30))

        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 10, minute: 45))
    }

    func testCadenceChangeRestartsCountdown() {
        var rule = ReminderRule(kind: .water, intervalMinutes: 45)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 10), calendar: calendar)
        rule.intervalMinutes = 20
        scheduler.reconcile(rules: [rule], now: date(hour: 10, minute: 30))

        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 10, minute: 50))
    }

    func testDisablingAndDeletingRulesRemovesTheirSchedule() {
        var water = ReminderRule(kind: .water, intervalMinutes: 45)
        let eyes = ReminderRule(kind: .eyes, intervalMinutes: 20)
        var scheduler = ReminderScheduler(rules: [water, eyes], now: date(hour: 10), calendar: calendar)
        water.isEnabled = false
        scheduler.reconcile(rules: [water], now: date(hour: 10, minute: 30))

        XCTAssertTrue(scheduler.dueDates.isEmpty)
        XCTAssertNil(scheduler.nextDue(rules: [water], preferences: activePreferences, now: date(hour: 12)))

        water.isEnabled = true
        scheduler.reconcile(rules: [water], now: date(hour: 12))
        XCTAssertEqual(scheduler.dueDates[water.id], date(hour: 12, minute: 45))
    }

    func testWakeFromSleepCoalescesOverdueRemindersWithoutBurst() {
        let water = ReminderRule(kind: .water, intervalMinutes: 45)
        let eyes = ReminderRule(kind: .eyes, intervalMinutes: 20)
        let stretch = ReminderRule(kind: .stretch, intervalMinutes: 60)
        let rules = [water, eyes, stretch]
        var scheduler = ReminderScheduler(rules: rules, now: date(hour: 10), calendar: calendar)
        let wake = date(hour: 15)

        XCTAssertEqual(scheduler.nextDue(rules: rules, preferences: activePreferences, now: wake)?.id, eyes.id)
        XCTAssertNil(scheduler.nextDue(rules: rules, preferences: activePreferences, now: wake.addingTimeInterval(1)))
        XCTAssertEqual(scheduler.dueDates[water.id], date(hour: 15, minute: 5))
        XCTAssertEqual(scheduler.dueDates[eyes.id], date(hour: 15, minute: 20))
        XCTAssertEqual(scheduler.dueDates[stretch.id], date(hour: 15, minute: 10))
        XCTAssertEqual(scheduler.nextDue(rules: rules, preferences: activePreferences, now: date(hour: 15, minute: 5))?.id, water.id)
        XCTAssertEqual(scheduler.nextDue(rules: rules, preferences: activePreferences, now: date(hour: 15, minute: 10))?.id, stretch.id)
    }

    func testEqualDeadlinesUseRuleOrder() {
        let water = ReminderRule(kind: .water, intervalMinutes: 20)
        let eyes = ReminderRule(kind: .eyes, intervalMinutes: 20)
        let rules = [water, eyes]
        var scheduler = ReminderScheduler(rules: rules, now: date(hour: 10), calendar: calendar)

        XCTAssertEqual(scheduler.nextDue(rules: rules, preferences: activePreferences, now: date(hour: 10, minute: 20))?.id, water.id)
        XCTAssertNil(scheduler.nextDue(rules: rules, preferences: activePreferences, now: date(hour: 10, minute: 20)))
    }

    func testRepeatedCadenceCollisionsDoNotStarveAnyReminder() {
        let rules = [
            ReminderRule(kind: .eyes, intervalMinutes: 1),
            ReminderRule(kind: .stretch, intervalMinutes: 5)
        ]
        let start = date(hour: 10)
        var scheduler = ReminderScheduler(rules: rules, now: start, calendar: calendar)
        var deliveries: [ReminderKind: Int] = [:]
        for minute in 1...30 {
            if let next = scheduler.nextDue(rules: rules, preferences: activePreferences, now: start.addingTimeInterval(Double(minute * 60))) {
                deliveries[next.kind, default: 0] += 1
            }
        }
        XCTAssertGreaterThan(deliveries[.eyes, default: 0], 0)
        XCTAssertGreaterThan(deliveries[.stretch, default: 0], 0)
    }

    func testSnoozeSurvivesReconciliationAndFiresAtSnoozedDeadline() {
        let rule = ReminderRule(kind: .water, intervalMinutes: 45)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 10), calendar: calendar)
        _ = scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 10, minute: 45))
        scheduler.snooze(ruleID: rule.id, minutes: 5, now: date(hour: 10, minute: 46))

        XCTAssertNil(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 10, minute: 50)))
        XCTAssertEqual(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 10, minute: 51))?.id, rule.id)
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 11, minute: 36))
    }

    func testSnoozeOrResetCannotReviveRemovedReminder() {
        let rule = ReminderRule(kind: .water)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 10), calendar: calendar)
        scheduler.reconcile(rules: [], now: date(hour: 11))
        scheduler.snooze(ruleID: rule.id, minutes: 5, now: date(hour: 11))
        scheduler.reset(ruleID: rule.id, intervalMinutes: 20, now: date(hour: 11))

        XCTAssertTrue(scheduler.dueDates.isEmpty)
    }

    func testOvernightQuietHoursIncludeStartAndExcludeEnd() {
        let preferences = AppPreferences()
        XCTAssertFalse(isQuiet(preferences, hour: 21, minute: 59))
        XCTAssertTrue(isQuiet(preferences, hour: 22))
        XCTAssertTrue(isQuiet(preferences, hour: 0))
        XCTAssertTrue(isQuiet(preferences, hour: 7, minute: 59))
        XCTAssertFalse(isQuiet(preferences, hour: 8))
    }

    func testWithinDayQuietHoursAndEqualBoundaries() {
        var preferences = AppPreferences(quietStartHour: 13, quietEndHour: 15)
        XCTAssertFalse(isQuiet(preferences, hour: 12, minute: 59))
        XCTAssertTrue(isQuiet(preferences, hour: 13))
        XCTAssertTrue(isQuiet(preferences, hour: 14, minute: 59))
        XCTAssertFalse(isQuiet(preferences, hour: 15))

        preferences.quietEndHour = 13
        XCTAssertFalse(isQuiet(preferences, hour: 13))
        preferences.quietStartHour = 22
        preferences.quietEndHour = 8
        preferences.quietHoursEnabled = false
        XCTAssertFalse(isQuiet(preferences, hour: 23))
    }

    func testQuietHoursSuppressDeliveryAndReleaseOnlyOneAtEnd() {
        let rules = [
            ReminderRule(kind: .water, intervalMinutes: 45),
            ReminderRule(kind: .eyes, intervalMinutes: 20)
        ]
        let preferences = AppPreferences()
        var scheduler = ReminderScheduler(rules: rules, now: date(hour: 21, minute: 50), calendar: calendar)

        XCTAssertNil(scheduler.nextDue(rules: rules, preferences: preferences, now: date(hour: 22, minute: 40)))
        XCTAssertNil(scheduler.nextDue(rules: rules, preferences: preferences, now: date(hour: 7, minute: 59, day: 17)))
        XCTAssertEqual(scheduler.nextDue(rules: rules, preferences: preferences, now: date(hour: 8, day: 17))?.kind, .eyes)
        XCTAssertNil(scheduler.nextDue(rules: rules, preferences: preferences, now: date(hour: 8, minute: 1, day: 17)))
    }

    func testMutatedInvalidIntervalAndSnoozeAreClamped() {
        var rule = ReminderRule(kind: .water)
        rule.intervalMinutes = Int.min
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 10), calendar: calendar)
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 10, minute: 1))

        scheduler.snooze(ruleID: rule.id, minutes: Int.max, now: date(hour: 11))
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 11, day: 17))
    }

    func testDailyReminderStartsAtNextFutureLocalTime() {
        let rule = ReminderRule(kind: .custom, schedule: .daily, hour: 9, minute: 30)
        for (start, expected) in [
            (date(hour: 8), date(hour: 9, minute: 30)),
            (date(hour: 9, minute: 30), date(hour: 9, minute: 30, day: 17)),
            (date(hour: 10), date(hour: 9, minute: 30, day: 17))
        ] {
            let scheduler = ReminderScheduler(rules: [rule], now: start, calendar: calendar)
            XCTAssertEqual(scheduler.dueDates[rule.id], expected)
        }
    }

    func testDailyDeliveryReturnsToChosenTimeInsteadOfInterval() {
        let rule = ReminderRule(kind: .custom, intervalMinutes: 45, schedule: .daily, hour: 9, minute: 30)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 8), calendar: calendar)

        XCTAssertNil(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 9, minute: 29)))
        XCTAssertEqual(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 9, minute: 30))?.id, rule.id)
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 9, minute: 30, day: 17))
        XCTAssertNil(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 10, minute: 15)))
    }

    func testDailyMidnightScheduleMovesToNextCalendarDay() {
        let rule = ReminderRule(kind: .custom, schedule: .daily, hour: 0, minute: 0)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 23, minute: 59), calendar: calendar)

        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 0, day: 17))
        XCTAssertEqual(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 0, day: 17))?.id, rule.id)
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 0, day: 18))
    }

    func testChangingScheduleOrDailyTimeRecalculatesDeadline() {
        var rule = ReminderRule(kind: .custom, intervalMinutes: 45)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 8), calendar: calendar)
        rule.schedule = .daily
        scheduler.reconcile(rules: [rule], now: date(hour: 8, minute: 10))
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 9))

        rule.hour = 10
        rule.minute = 15
        scheduler.reconcile(rules: [rule], now: date(hour: 8, minute: 20))
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 10, minute: 15))

        rule.schedule = .interval
        scheduler.reconcile(rules: [rule], now: date(hour: 8, minute: 30))
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 9, minute: 15))
    }

    func testDailySnoozeSurvivesTextAndInactiveIntervalEdits() {
        var rule = ReminderRule(kind: .custom, schedule: .daily, hour: 9)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 8), calendar: calendar)
        XCTAssertEqual(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 9))?.id, rule.id)
        scheduler.snooze(ruleID: rule.id, minutes: 5, now: date(hour: 9, minute: 1))

        rule.title = "An updated note"
        rule.intervalMinutes = 180
        scheduler.reconcile(rules: [rule], now: date(hour: 9, minute: 2))
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 9, minute: 6))
        XCTAssertEqual(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: date(hour: 9, minute: 6))?.id, rule.id)
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 9, day: 17))
    }

    func testDailyResetHonorsItsScheduleThroughBothAPIs() {
        var rule = ReminderRule(kind: .custom, schedule: .daily, hour: 9)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 8), calendar: calendar)
        scheduler.reset(ruleID: rule.id, intervalMinutes: 5, now: date(hour: 10))
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 9, day: 17))

        rule.hour = 11
        scheduler.reset(rule: rule, now: date(hour: 10))
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 11))
    }

    func testDailyQuietOccurrenceIsSkippedDuringAndAfterQuietHours() {
        let rule = ReminderRule(kind: .custom, schedule: .daily, hour: 7)
        for tick in [date(hour: 7), date(hour: 8)] {
            var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 6), calendar: calendar)

            XCTAssertNil(scheduler.nextDue(rules: [rule], preferences: AppPreferences(), now: tick))
            XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 7, day: 17))
        }
    }

    func testQuietHoursSkipDailyReminderButRetainOverdueIntervalReminder() {
        let daily = ReminderRule(kind: .custom, schedule: .daily, hour: 7)
        let interval = ReminderRule(kind: .water, intervalMinutes: 60)
        let rules = [daily, interval]
        var scheduler = ReminderScheduler(rules: rules, now: date(hour: 6), calendar: calendar)

        XCTAssertEqual(scheduler.nextDue(rules: rules, preferences: AppPreferences(), now: date(hour: 8))?.id, interval.id)
        XCTAssertEqual(scheduler.dueDates[daily.id], date(hour: 7, day: 17))
        XCTAssertEqual(scheduler.dueDates[interval.id], date(hour: 9))
    }

    func testDailyCollisionDelayAppliesOnceThenReturnsToDailyTime() {
        let first = ReminderRule(kind: .custom, title: "First", schedule: .daily, hour: 9)
        let second = ReminderRule(kind: .custom, title: "Second", schedule: .daily, hour: 9)
        let rules = [first, second]
        var scheduler = ReminderScheduler(rules: rules, now: date(hour: 8), calendar: calendar)

        XCTAssertEqual(scheduler.nextDue(rules: rules, preferences: activePreferences, now: date(hour: 9))?.id, first.id)
        XCTAssertNil(scheduler.nextDue(rules: rules, preferences: activePreferences, now: date(hour: 9, minute: 1)))
        XCTAssertEqual(scheduler.dueDates[second.id], date(hour: 9, minute: 5))
        XCTAssertEqual(scheduler.nextDue(rules: rules, preferences: activePreferences, now: date(hour: 9, minute: 5))?.id, second.id)
        XCTAssertEqual(scheduler.dueDates[first.id], date(hour: 9, day: 17))
        XCTAssertEqual(scheduler.dueDates[second.id], date(hour: 9, day: 17))
    }

    func testDailyRuleDisableDeleteAndReenableUseNextOccurrence() {
        var rule = ReminderRule(kind: .custom, schedule: .daily, hour: 9)
        var scheduler = ReminderScheduler(rules: [rule], now: date(hour: 8), calendar: calendar)
        rule.isEnabled = false
        scheduler.reconcile(rules: [rule], now: date(hour: 8, minute: 30))
        XCTAssertNil(scheduler.dueDates[rule.id])

        rule.isEnabled = true
        scheduler.reconcile(rules: [rule], now: date(hour: 10))
        XCTAssertEqual(scheduler.dueDates[rule.id], date(hour: 9, day: 17))

        scheduler.reconcile(rules: [], now: date(hour: 11))
        scheduler.reset(rule: rule, now: date(hour: 11))
        XCTAssertNil(scheduler.dueDates[rule.id])
    }

    func testDailyScheduleKeepsWallClockTimeAcrossDaylightSaving() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let before = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 7)))
        let due = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 8)))
        let nextDay = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 8)))
        let rule = ReminderRule(kind: .custom, schedule: .daily, hour: 8)
        var scheduler = ReminderScheduler(rules: [rule], now: before, calendar: local)

        XCTAssertEqual(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: due)?.id, rule.id)
        XCTAssertEqual(scheduler.dueDates[rule.id], nextDay)
        XCTAssertEqual(nextDay.timeIntervalSince(due), 23 * 60 * 60)
    }

    func testNonexistentDailyClockTimeUsesNextValidTime() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let before = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0)))
        let due = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3)))
        let nextDay = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 2, minute: 30)))
        let rule = ReminderRule(kind: .custom, schedule: .daily, hour: 2, minute: 30)
        var scheduler = ReminderScheduler(rules: [rule], now: before, calendar: local)

        XCTAssertEqual(scheduler.dueDates[rule.id], due)
        XCTAssertEqual(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: due)?.id, rule.id)
        XCTAssertEqual(scheduler.dueDates[rule.id], nextDay)
    }

    func testRepeatedDailyClockTimeIsDeliveredOnlyOnce() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let before = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0)))
        let nextDay = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 1, minute: 30)))
        let rule = ReminderRule(kind: .custom, schedule: .daily, hour: 1, minute: 30)
        var scheduler = ReminderScheduler(rules: [rule], now: before, calendar: local)
        let firstOccurrence = try XCTUnwrap(scheduler.dueDates[rule.id])

        XCTAssertEqual(firstOccurrence.timeIntervalSince(before), 90 * 60)
        XCTAssertEqual(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: firstOccurrence)?.id, rule.id)
        XCTAssertEqual(scheduler.dueDates[rule.id], nextDay)
        XCTAssertNil(scheduler.nextDue(rules: [rule], preferences: activePreferences, now: firstOccurrence.addingTimeInterval(60 * 60)))
    }

    private func isQuiet(_ preferences: AppPreferences, hour: Int, minute: Int = 0) -> Bool {
        ReminderScheduler.isWithinQuietHours(preferences: preferences, now: date(hour: hour, minute: minute), calendar: calendar)
    }
}
