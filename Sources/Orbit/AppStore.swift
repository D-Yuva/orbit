import AppKit
import Combine
import Foundation
import OrbitCore

@MainActor
final class AppStore: ObservableObject {
    @Published var preferences: AppPreferences {
        didSet {
            let wasProtected = oldValue.pauseRemindersDuringFocus && hasActiveFocusSession
            reconcileFocusProtection(wasProtected: wasProtected)
            scheduler.reconcile(rules: preferences.rules, now: now)
            if !isPreview { save() }
            refreshIsland()
        }
    }
    @Published private(set) var history: [ReminderEvent] = []
    @Published var pausedUntil: Date?
    @Published private(set) var now = Date()
    @Published var selectedPage: AppPage = .reminders
    @Published var previewKind: ReminderKind = .water
    @Published var storageError: String?
    @Published private(set) var focusTimer = FocusTimerSession()

    private var scheduler: ReminderScheduler
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var isPresenting = false
    private var pendingFocusCompletion = false
    private var isShowingFocusCompletion = false
    private let soundPlayback: (AlertTone) -> Void
    let notch = NotchController()
    let focusPanel = FocusTimerPanelController()
    private let storageURL: URL
    let isPreview: Bool

    init(isPreview: Bool = false, soundPlayback: ((AlertTone) -> Void)? = nil) {
        self.isPreview = isPreview
        let player = OrbitSoundPlayer()
        self.soundPlayback = soundPlayback ?? { cue in
            if !isPreview { player.play(cue) }
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Orbit", isDirectory: true)
        storageURL = directory.appendingPathComponent("preferences.json")
        let saved = isPreview ? nil : try? Data(contentsOf: storageURL)
        let restored = saved.flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }
        let prefs = restored ?? AppPreferences()
        preferences = prefs
        let launchDate = Date()
        scheduler = ReminderScheduler(rules: prefs.rules, now: launchDate)
        now = launchDate
        if !isPreview {
            let historyURL = directory.appendingPathComponent("history.json")
            if let data = try? Data(contentsOf: historyURL),
               let entries = try? JSONDecoder().decode([ReminderEvent].self, from: data) {
                history = Array(entries.prefix(100))
            }
            let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            timer = ticker
            RunLoop.main.add(ticker, forMode: .common)
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.resetAfterWake() }
            }
            // Persist added defaults alongside a successfully restored settings file.
            if restored != nil { save() }
        }
    }

    var isPaused: Bool { pausedUntil.map { $0 > now } ?? false }
    var enabledCount: Int { preferences.rules.filter(\.isEnabled).count }
    var completedToday: Int {
        history.filter { Calendar.current.isDateInToday($0.date) && $0.outcome == .completed }.count
    }
    var isQuietTime: Bool {
        guard preferences.quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: now)
        let start = preferences.quietStartHour, end = preferences.quietEndHour
        guard start != end else { return false }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }
    var status: String {
        if hasActiveFocusSession { return focusTimer.state == .paused ? "Focus paused" : "Focusing" }
        if isPaused { return "Paused for a bit" }
        if isQuietTime { return "Quiet hours" }
        return enabledCount > 0 ? "Ready" : "Reminders off"
    }
    var nextReminder: (rule: ReminderRule, date: Date)? {
        guard !isPaused && !isQuietTime && !suppressesRemindersForFocus else { return nil }
        return preferences.rules.filter(\.isEnabled).compactMap { rule -> (ReminderRule, Date)? in
            guard let date = scheduler.dueDates[rule.id] else { return nil }
            return (rule, date)
        }.min { $0.1 < $1.1 }
    }
    var previewMessage: String { ReminderCopy.message(for: previewKind, language: preferences.language) }
    var previewTranslation: String {
        preferences.language == .english || !preferences.showTranslation ? "" : ReminderCopy.translation(for: previewKind)
    }

    var focusDurationMinutes: Int {
        get { preferences.focusDurationMinutes }
        set {
            guard focusTimer.state == .idle || focusTimer.state == .completed else { return }
            preferences.focusDurationMinutes = min(max(newValue, 1), 180)
        }
    }
    private var hasActiveFocusSession: Bool {
        focusTimer.state == .running || focusTimer.state == .paused
    }
    var suppressesRemindersForFocus: Bool {
        preferences.pauseRemindersDuringFocus && hasActiveFocusSession
    }
    var focusRemainingSeconds: Int {
        focusTimer.state == .idle ? focusDurationMinutes * 60 : focusTimer.remainingSeconds(at: now)
    }
    var focusProgress: Double { focusTimer.progress(at: now) }
    var focusTimeLabel: String {
        String(format: "%02d:%02d", focusRemainingSeconds / 60, focusRemainingSeconds % 60)
    }

    func openFocus() { notch.presentFocusControls() }

    private func showFocusControls(anchor: NSRect) {
        if focusPanel.isVisible { focusPanel.close(); return }
        notch.dismiss()
        notch.setFocusControlsVisible(true)
        focusPanel.onClose = { [weak self] in
            guard let self else { return }
            self.notch.setFocusControlsVisible(false)
            self.refreshIsland()
            self.presentFocusCompletionIfReady()
        }
        focusPanel.show(store: self, anchor: anchor)
    }

    func startFocus() {
        now = Date()
        let wasProtected = suppressesRemindersForFocus
        clearFocusCompletion()
        focusTimer.start(minutes: focusDurationMinutes, now: now)
        reconcileFocusProtection(wasProtected: wasProtected)
        refreshIsland()
    }

    func pauseFocus() {
        advanceFocus(to: Date())
        focusTimer.pause(now: now)
        refreshIsland()
    }

    func resumeFocus() {
        now = Date()
        let wasProtected = suppressesRemindersForFocus
        focusTimer.resume(now: now)
        reconcileFocusProtection(wasProtected: wasProtected)
        refreshIsland()
    }

    func toggleFocusPause() {
        switch focusTimer.state {
        case .running: pauseFocus()
        case .paused: resumeFocus()
        case .idle, .completed: break
        }
    }

    func cancelFocus() {
        guard hasActiveFocusSession else { return }
        resetFocus()
    }

    func resetFocus() {
        now = Date()
        let wasProtected = suppressesRemindersForFocus
        clearFocusCompletion()
        focusTimer.reset()
        reconcileFocusProtection(wasProtected: wasProtected)
        refreshIsland()
    }

    /// Uses an absolute deadline so focus stays accurate through sleep or delayed ticks.
    func advanceFocus(to date: Date) {
        now = date
        let wasProtected = suppressesRemindersForFocus
        if focusTimer.advance(now: date) {
            reconcileFocusProtection(wasProtected: wasProtected)
            pendingFocusCompletion = true
            if preferences.focusSoundEnabled { playSound(.focus) }
        }
        presentFocusCompletionIfReady()
    }

    func playSound(_ cue: OrbitSound) {
        let tone: AlertTone
        switch cue {
        case .stretch: tone = preferences.stretchTone
        case .focus: tone = preferences.focusTone
        case .reminder: tone = preferences.reminderTone
        }
        soundPlayback(tone)
    }

    func playTonePreview(_ tone: AlertTone) { soundPlayback(tone) }

    private func reconcileFocusProtection(wasProtected: Bool) {
        guard wasProtected != suppressesRemindersForFocus else { return }
        // Missed nudges are discarded, so ending focus never unleashes a backlog.
        scheduler = ReminderScheduler(rules: preferences.rules, now: now)
        if suppressesRemindersForFocus && !isShowingFocusCompletion { notch.dismiss() }
    }

    private func clearFocusCompletion() {
        pendingFocusCompletion = false
        if isShowingFocusCompletion { notch.dismiss() }
    }

    private func presentFocusCompletionIfReady() {
        guard pendingFocusCompletion, !isPresenting, !focusPanel.isVisible else { return }
        pendingFocusCompletion = false
        isShowingFocusCompletion = true
        isPresenting = true
        let finish: () -> Void = { [weak self] in
            self?.isShowingFocusCompletion = false
            self?.isPresenting = false
        }
        notch.show(title: "Focus complete", message: "Focus complete. You’ve earned a break.",
                   translation: nil, kind: .stretch, style: preferences.appearance,
                   duration: TimeInterval(preferences.reminderDurationSeconds), allowsSnooze: false,
                   onComplete: finish, onSnooze: finish, onDismiss: finish)
    }

    func togglePause() {
        if isPaused {
            pausedUntil = nil
            scheduler = ReminderScheduler(rules: preferences.rules, now: now)
        } else {
            pausedUntil = now.addingTimeInterval(60 * 60)
            notch.dismiss()
        }
        refreshIsland()
    }

    func startIsland(onOpenSettings: @escaping () -> Void) {
        notch.start(onOpenSettings: onOpenSettings,
                    onTogglePause: { [weak self] in self?.togglePause() },
                    onOpenFocus: { [weak self] anchor in self?.showFocusControls(anchor: anchor) },
                    onToggleFocusPause: { [weak self] in self?.toggleFocusPause() },
                    onCancelFocus: { [weak self] in self?.cancelFocus() })
        refreshIsland()
    }

    private func refreshIsland() {
        let subtitle: String
        if focusTimer.state == .running { subtitle = "\(focusTimeLabel) left. You’ve got this." }
        else if focusTimer.state == .paused { subtitle = "Take your time. \(focusTimeLabel) to go." }
        else if isPaused { subtitle = "Reminders are taking a little break." }
        else if isQuietTime { subtitle = "Back at \(hourLabel(preferences.quietEndHour))" }
        else if let next = nextReminder {
            let minutes = max(1, Int(ceil(next.date.timeIntervalSince(now) / 60)))
            subtitle = "\(next.rule.title) in \(minutes) min."
        } else { subtitle = "Click Batman for a focus timer" }
        notch.updateIdle(title: status, subtitle: subtitle, paused: isPaused,
                         style: preferences.appearance, focusState: focusTimer.state)
    }

    func greet() {
        guard !focusPanel.isVisible, focusTimer.state == .idle else { return }
        notch.dismiss()
        isPresenting = true
        notch.show(title: "Hello", message: "A little backup for your day.",
                   translation: nil,
                   kind: .stretch, style: preferences.appearance, duration: 10,
                   onComplete: { [weak self] in self?.isPresenting = false },
                   onSnooze: { [weak self] in self?.isPresenting = false },
                   onDismiss: { [weak self] in self?.isPresenting = false })
    }

    /// App-owned visual verification; reminder previews have no user-facing entry point.
    func preview(rule: ReminderRule? = nil) {
        focusPanel.close()
        let kind = rule?.kind ?? previewKind
        let message = rule.map { $0.resolvedMessage(language: preferences.language) } ?? previewMessage
        let translation = (rule.map { $0.usesDefaultMessage } ?? true) && preferences.language != .english && preferences.showTranslation
            ? ReminderCopy.translation(for: kind) : nil
        notch.dismiss()
        isPresenting = true
        notch.show(title: rule?.title ?? kind.displayName, message: message,
                   translation: translation, kind: kind, style: preferences.appearance,
                   duration: TimeInterval(preferences.reminderDurationSeconds),
                   onComplete: { [weak self] in self?.isPresenting = false },
                   onSnooze: { [weak self] in self?.isPresenting = false },
                   onDismiss: { [weak self] in self?.isPresenting = false })
    }

    func updateRule(_ rule: ReminderRule) {
        guard let index = preferences.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        preferences.rules[index] = rule
    }

    func saveRule(_ rule: ReminderRule) {
        var saved = rule
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.message = saved.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saved.title.isEmpty else { return }
        saved.intervalMinutes = min(max(saved.intervalMinutes, 1), 1440)
        saved.hour = min(max(saved.hour, 0), 23)
        saved.minute = min(max(saved.minute, 0), 59)
        if preferences.rules.contains(where: { $0.id == saved.id }) { updateRule(saved) }
        else { preferences.rules.append(saved) }
    }

    func deleteRule(_ rule: ReminderRule) { preferences.rules.removeAll { $0.id == rule.id } }
    func addRule(title: String, message: String, minutes: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        preferences.rules.append(ReminderRule(kind: .custom, title: trimmed,
                                             message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                                             intervalMinutes: max(1, min(minutes, 1440))))
    }
    func clearHistory() { history.removeAll(); saveHistory() }

    func tick(at date: Date = Date()) {
        advanceFocus(to: date)
        if let pausedUntil, pausedUntil <= now {
            self.pausedUntil = nil
            scheduler = ReminderScheduler(rules: preferences.rules, now: now)
        }
        refreshIsland()
        guard !isPaused && !isPresenting && !focusPanel.isVisible && !suppressesRemindersForFocus else { return }
        if let rule = scheduler.nextDue(rules: preferences.rules, preferences: preferences, now: now) {
            deliver(rule)
        }
    }

    private func resetAfterWake() {
        advanceFocus(to: Date())
        scheduler = ReminderScheduler(rules: preferences.rules, now: now)
        refreshIsland()
    }

    private func deliver(_ rule: ReminderRule) {
        isPresenting = true
        let message = rule.resolvedMessage(language: preferences.language)
        let translation = rule.usesDefaultMessage && preferences.language != .english && preferences.showTranslation
            ? ReminderCopy.translation(for: rule.kind) : nil
        let event = ReminderEvent(ruleID: rule.id, kind: rule.kind, title: rule.title,
                                  message: message, date: now, outcome: .delivered)
        history.insert(event, at: 0)
        history = Array(history.prefix(100))
        saveHistory()
        if rule.kind == .stretch {
            if preferences.stretchSoundEnabled { playSound(.stretch) }
        } else if preferences.soundEnabled { playSound(.reminder) }
        notch.show(title: rule.title, message: message, translation: translation,
                   kind: rule.kind, style: preferences.appearance,
                   duration: TimeInterval(preferences.reminderDurationSeconds),
                   onComplete: { [weak self] in self?.finish(event.id, outcome: .completed) },
                   onSnooze: { [weak self] in
                       guard let self else { return }
                       self.scheduler.snooze(ruleID: rule.id, minutes: 5, now: Date())
                       self.finish(event.id, outcome: .snoozed)
                   }, onDismiss: { [weak self] in self?.finish(event.id, outcome: .dismissed) })
    }

    private func finish(_ id: UUID, outcome: ReminderEvent.Outcome) {
        isPresenting = false
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].outcome = outcome
        saveHistory()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: storageURL, options: .atomic)
            storageError = nil
        } catch { storageError = "Orbit couldn’t save your changes. \(error.localizedDescription)" }
    }

    private func saveHistory() {
        guard !isPreview else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: storageURL.deletingLastPathComponent().appendingPathComponent("history.json"), options: .atomic)
        } catch { storageError = "Orbit couldn’t save recent activity. \(error.localizedDescription)" }
    }
}

enum AppPage: String, CaseIterable, Identifiable {
    case reminders = "Reminders", focus = "Focus", companion = "Companion", preferences = "Settings", audio = "Audio"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .reminders: return "bell"
        case .focus: return "timer"
        case .companion: return "sparkle"
        case .preferences: return "slider.horizontal.3"
        case .audio: return "speaker.wave.2"
        }
    }
}

extension ReminderRule {
    var usesDefaultMessage: Bool { message.isEmpty && kind != .custom }

    func resolvedMessage(language: CompanionLanguage) -> String {
        if !message.isEmpty { return message }
        return kind == .custom ? title : ReminderCopy.message(for: kind, language: language)
    }

    var timingLabel: String {
        if schedule == .daily {
            let time = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)) ?? Date()
            return "Daily at \(time.formatted(date: .omitted, time: .shortened))"
        }
        let hours = intervalMinutes / 60, minutes = intervalMinutes % 60
        if hours == 0 { return "Every \(minutes) min" }
        if minutes == 0 { return "Every \(hours) \(hours == 1 ? "hour" : "hours")" }
        return "Every \(hours) hr \(minutes) min"
    }
}

func hourLabel(_ hour: Int) -> String {
    "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "am" : "pm")"
}

extension ReminderKind {
    var displayName: String {
        switch self {
        case .water: return "Drink some water"
        case .stretch: return "Get up & stretch"
        case .eyes: return "Rest your eyes"
        case .meal: return "Make time to eat"
        case .rest: return "Take a little break"
        case .custom: return "A note for you"
        }
    }
    var symbol: String {
        switch self {
        case .water: return "drop"
        case .stretch: return "figure.flexibility"
        case .eyes: return "eye"
        case .meal: return "fork.knife"
        case .rest: return "cup.and.saucer"
        case .custom: return "heart.text.square"
        }
    }
}
