import Foundation

/// A clock-driven scheduler with no timers or UI dependencies.
/// The app can call `nextDue` on its own timer and present the returned reminder.
public struct ReminderScheduler: Sendable {
    public private(set) var dueDates: [UUID: Date] = [:]
    private var cadences: [UUID: Cadence] = [:]
    private var lastDelivered: [UUID: Date] = [:]
    private let calendar: Calendar

    private enum Cadence: Equatable, Sendable {
        case interval(minutes: Int)
        case daily(hour: Int, minute: Int)

        init(rule: ReminderRule) {
            switch rule.schedule {
            case .interval:
                self = .interval(minutes: ReminderRule.validInterval(rule.intervalMinutes))
            case .daily:
                self = .daily(hour: min(max(rule.hour, 0), 23), minute: min(max(rule.minute, 0), 59))
            }
        }
    }

    public init(rules: [ReminderRule], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        reconcile(rules: rules, now: now)
    }

    /// Keeps an existing countdown when text or other presentation settings change.
    /// Changing its cadence starts a new countdown; disabling removes it immediately.
    public mutating func reconcile(rules: [ReminderRule], now: Date = Date()) {
        let enabledIDs = Set(rules.filter(\.isEnabled).map(\.id))
        dueDates = dueDates.filter { enabledIDs.contains($0.key) }
        cadences = cadences.filter { enabledIDs.contains($0.key) }
        lastDelivered = lastDelivered.filter { enabledIDs.contains($0.key) }

        var seen = Set<UUID>()
        for rule in rules where rule.isEnabled && seen.insert(rule.id).inserted {
            let cadence = Cadence(rule: rule)
            if dueDates[rule.id] == nil || cadences[rule.id] != cadence {
                dueDates[rule.id] = nextDate(for: cadence, after: now)
            }
            cadences[rule.id] = cadence
        }
    }

    /// Delivers at most one reminder per tick, without replaying missed occurrences.
    /// Other already-due reminders are spaced five minutes apart after a wake or collision.
    public mutating func nextDue(
        rules: [ReminderRule],
        preferences: AppPreferences,
        now: Date = Date()
    ) -> ReminderRule? {
        reconcile(rules: rules, now: now)
        // Daily reminders scheduled during quiet hours are skipped, even if the
        // app's first tick arrives after quiet hours have ended.
        for rule in rules where rule.isEnabled && rule.schedule == .daily {
            guard let due = dueDates[rule.id], due <= now,
                  Self.isWithinQuietHours(preferences: preferences, now: due, calendar: calendar) else { continue }
            dueDates[rule.id] = nextDate(for: Cadence(rule: rule), after: now)
        }
        guard !Self.isWithinQuietHours(preferences: preferences, now: now, calendar: calendar) else {
            return nil
        }

        let overdue = rules.enumerated().filter { _, rule in
            guard rule.isEnabled, let due = dueDates[rule.id] else { return false }
            return due <= now
        }.sorted { lhs, rhs in
            let leftDue = dueDates[lhs.element.id, default: .distantFuture]
            let rightDue = dueDates[rhs.element.id, default: .distantFuture]
            if leftDue != rightDue { return leftDue < rightDue }
            // Favor the least recently delivered reminder when cadences line up.
            let leftLast = lastDelivered[lhs.element.id, default: .distantPast]
            let rightLast = lastDelivered[rhs.element.id, default: .distantPast]
            if leftLast != rightLast { return leftLast < rightLast }
            return lhs.offset < rhs.offset
        }.map { $0.element }
        guard let next = overdue.first else {
            return nil
        }

        reset(rule: next, now: now)
        lastDelivered[next.id] = now
        for (offset, rule) in overdue.dropFirst().enumerated() {
            dueDates[rule.id] = now.addingTimeInterval(TimeInterval(offset + 1) * 5 * 60)
        }
        return next
    }

    public mutating func snooze(ruleID: UUID, minutes: Int, now: Date = Date()) {
        guard dueDates[ruleID] != nil else { return }
        dueDates[ruleID] = now.addingTimeInterval(TimeInterval(ReminderRule.validInterval(minutes)) * 60)
    }

    public mutating func reset(ruleID: UUID, intervalMinutes: Int, now: Date = Date()) {
        guard dueDates[ruleID] != nil, let existing = cadences[ruleID] else { return }
        let cadence: Cadence
        switch existing {
        case .interval:
            cadence = .interval(minutes: ReminderRule.validInterval(intervalMinutes))
        case .daily:
            cadence = existing
        }
        cadences[ruleID] = cadence
        dueDates[ruleID] = nextDate(for: cadence, after: now)
    }

    public mutating func reset(rule: ReminderRule, now: Date = Date()) {
        guard rule.isEnabled, dueDates[rule.id] != nil else { return }
        let cadence = Cadence(rule: rule)
        cadences[rule.id] = cadence
        dueDates[rule.id] = nextDate(for: cadence, after: now)
    }

    private func nextDate(for cadence: Cadence, after now: Date) -> Date {
        switch cadence {
        case .interval(let minutes):
            return now.addingTimeInterval(TimeInterval(minutes) * 60)
        case .daily(let hour, let minute):
            let components = DateComponents(hour: hour, minute: minute, second: 0)
            let startOfDay = calendar.startOfDay(for: now)
            // Resolve the first occurrence of a repeated clock time. If a clock
            // time does not exist during a spring change, use the next valid time.
            let today = calendar.nextDate(
                after: startOfDay.addingTimeInterval(-1), matching: components,
                matchingPolicy: .nextTime, repeatedTimePolicy: .first
            )
            if let today, today > now { return today }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay)
                ?? startOfDay.addingTimeInterval(24 * 60 * 60)
            return calendar.nextDate(
                after: tomorrow.addingTimeInterval(-1), matching: components,
                matchingPolicy: .nextTime, repeatedTimePolicy: .first
            ) ?? tomorrow
        }
    }

    public static func isWithinQuietHours(
        preferences: AppPreferences,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard preferences.quietHoursEnabled else { return false }
        let start = min(max(preferences.quietStartHour, 0), 23)
        let end = min(max(preferences.quietEndHour, 0), 23)
        guard start != end else { return false }
        let hour = calendar.component(.hour, from: now)
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }
}
