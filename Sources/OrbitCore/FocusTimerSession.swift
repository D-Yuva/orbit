import Foundation

/// A focus timer driven by absolute deadlines rather than a count of timer ticks.
public struct FocusTimerSession: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle, running, paused, completed
    }

    public private(set) var state: State = .idle
    public private(set) var durationSeconds: TimeInterval = 25 * 60
    public private(set) var deadline: Date?

    private var pausedRemainingSeconds: TimeInterval = 25 * 60

    public init() {}

    public mutating func start(minutes: Int, now: Date) {
        durationSeconds = TimeInterval(min(max(minutes, 1), 180)) * 60
        pausedRemainingSeconds = durationSeconds
        deadline = now.addingTimeInterval(durationSeconds)
        state = .running
    }

    public mutating func pause(now: Date) {
        guard state == .running else { return }
        let remaining = remainingTime(at: now)
        // Leave an expired session running so `advance` can report its completion.
        guard remaining > 0 else { return }
        pausedRemainingSeconds = remaining
        deadline = nil
        state = .paused
    }

    public mutating func resume(now: Date) {
        guard state == .paused else { return }
        deadline = now.addingTimeInterval(pausedRemainingSeconds)
        state = .running
    }

    /// Returns to idle while preserving the selected session length.
    public mutating func reset() {
        state = .idle
        deadline = nil
        pausedRemainingSeconds = durationSeconds
    }

    public func remainingSeconds(at now: Date) -> Int {
        Int(ceil(remainingTime(at: now)))
    }

    public func progress(at now: Date) -> Double {
        min(max(1 - remainingTime(at: now) / durationSeconds, 0), 1)
    }

    /// Returns true exactly once for each session that reaches its deadline.
    @discardableResult
    public mutating func advance(now: Date) -> Bool {
        guard state == .running, let deadline, now >= deadline else { return false }
        state = .completed
        self.deadline = nil
        pausedRemainingSeconds = 0
        return true
    }

    private func remainingTime(at now: Date) -> TimeInterval {
        switch state {
        case .idle:
            return durationSeconds
        case .running:
            guard let deadline else { return 0 }
            return min(max(deadline.timeIntervalSince(now), 0), durationSeconds)
        case .paused:
            return pausedRemainingSeconds
        case .completed:
            return 0
        }
    }
}
