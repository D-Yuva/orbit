import Foundation

public enum ReminderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case water, stretch, eyes, meal, rest, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .water: return "Drink some water"
        case .stretch: return "A little stretch"
        case .eyes: return "Rest your eyes"
        case .meal: return "Time for a bite"
        case .rest: return "Take a quiet moment"
        case .custom: return "A little reminder"
        }
    }

    public var symbolName: String {
        switch self {
        case .water: return "drop.fill"
        case .stretch: return "figure.flexibility"
        case .eyes: return "eye.fill"
        case .meal: return "fork.knife"
        case .rest: return "leaf.fill"
        case .custom: return "heart.fill"
        }
    }
}

public enum CompanionLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english, tamil, hindi, telugu

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .english: return "English"
        case .tamil: return "Tamil"
        case .hindi: return "Hindi"
        case .telugu: return "Telugu"
        }
    }

    public var nativeLabel: String {
        switch self {
        case .english: return "English"
        case .tamil: return "தமிழ்"
        case .hindi: return "हिन्दी"
        case .telugu: return "తెలుగు"
        }
    }
}

public enum CompanionStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic, rose, sage

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .classic: return "Natural"
        case .rose: return "Soft"
        case .sage: return "Mono"
        }
    }
}

public enum ReminderSchedule: String, CaseIterable, Codable, Identifiable, Sendable {
    case interval, daily

    public var id: String { rawValue }
}

public struct ReminderRule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: ReminderKind
    public var title: String
    /// Leave empty to use the selected language's built-in message.
    public var message: String
    public var intervalMinutes: Int
    public var schedule: ReminderSchedule
    public var hour: Int
    public var minute: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        kind: ReminderKind,
        title: String? = nil,
        message: String = "",
        intervalMinutes: Int = 45,
        schedule: ReminderSchedule = .interval,
        hour: Int = 9,
        minute: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.message = message
        self.intervalMinutes = Self.validInterval(intervalMinutes)
        self.schedule = schedule
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.isEnabled = isEnabled
    }

    public static var defaults: [ReminderRule] {
        [
            ReminderRule(kind: .water, intervalMinutes: 45),
            ReminderRule(kind: .stretch, intervalMinutes: 60),
            ReminderRule(kind: .eyes, intervalMinutes: 20),
            ReminderRule(kind: .meal, intervalMinutes: 180)
        ]
    }

    static func validInterval(_ minutes: Int) -> Int {
        min(max(minutes, 1), 1_440)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, message, intervalMinutes, schedule, hour, minute, isEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? values.decode(ReminderKind.self, forKey: .kind)) ?? .custom
        self.init(
            id: (try? values.decode(UUID.self, forKey: .id)) ?? UUID(),
            kind: kind,
            title: (try? values.decode(String.self, forKey: .title)) ?? kind.title,
            message: (try? values.decode(String.self, forKey: .message)) ?? "",
            intervalMinutes: (try? values.decode(Int.self, forKey: .intervalMinutes)) ?? 45,
            schedule: (try? values.decode(ReminderSchedule.self, forKey: .schedule)) ?? .interval,
            hour: (try? values.decode(Int.self, forKey: .hour)) ?? 9,
            minute: (try? values.decode(Int.self, forKey: .minute)) ?? 0,
            isEnabled: (try? values.decode(Bool.self, forKey: .isEnabled)) ?? true
        )
    }
}

public struct ReminderEvent: Identifiable, Codable, Equatable, Sendable {
    public enum Outcome: String, CaseIterable, Codable, Sendable {
        case delivered, completed, snoozed, dismissed
    }

    public var id: UUID
    public var ruleID: UUID
    public var kind: ReminderKind
    public var title: String
    public var message: String
    public var date: Date
    public var outcome: Outcome

    public init(
        id: UUID = UUID(),
        ruleID: UUID,
        kind: ReminderKind,
        title: String,
        message: String,
        date: Date = Date(),
        outcome: Outcome = .delivered
    ) {
        self.id = id
        self.ruleID = ruleID
        self.kind = kind
        self.title = title
        self.message = message
        self.date = date
        self.outcome = outcome
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var language: CompanionLanguage
    public var appearance: CompanionStyle
    public var quietHoursEnabled: Bool
    public var quietStartHour: Int
    public var quietEndHour: Int
    public var soundEnabled: Bool
    public var stretchSoundEnabled: Bool
    public var focusSoundEnabled: Bool
    public var pauseRemindersDuringFocus: Bool
    public var stretchTone: AlertTone
    public var focusTone: AlertTone
    public var reminderTone: AlertTone
    public var focusDurationMinutes: Int
    public var showTranslation: Bool
    public var reminderDurationSeconds: Int
    public var rules: [ReminderRule]

    public init(
        language: CompanionLanguage = .english,
        appearance: CompanionStyle = .classic,
        quietHoursEnabled: Bool = true,
        quietStartHour: Int = 22,
        quietEndHour: Int = 8,
        soundEnabled: Bool = false,
        stretchSoundEnabled: Bool = true,
        focusSoundEnabled: Bool = true,
        pauseRemindersDuringFocus: Bool = true,
        stretchTone: AlertTone = .pop,
        focusTone: AlertTone = .glass,
        reminderTone: AlertTone = .tink,
        focusDurationMinutes: Int = 25,
        showTranslation: Bool = true,
        reminderDurationSeconds: Int = 12,
        rules: [ReminderRule] = ReminderRule.defaults
    ) {
        self.language = language
        self.appearance = appearance
        self.quietHoursEnabled = quietHoursEnabled
        self.quietStartHour = min(max(quietStartHour, 0), 23)
        self.quietEndHour = min(max(quietEndHour, 0), 23)
        self.soundEnabled = soundEnabled
        self.stretchSoundEnabled = stretchSoundEnabled
        self.focusSoundEnabled = focusSoundEnabled
        self.pauseRemindersDuringFocus = pauseRemindersDuringFocus
        self.stretchTone = stretchTone
        self.focusTone = focusTone
        self.reminderTone = reminderTone
        self.focusDurationMinutes = min(max(focusDurationMinutes, 1), 180)
        self.showTranslation = showTranslation
        self.reminderDurationSeconds = min(max(reminderDurationSeconds, 5), 60)
        var seen = Set<UUID>()
        self.rules = rules.filter { seen.insert($0.id).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case language, appearance, quietHoursEnabled, quietStartHour, quietEndHour
        case soundEnabled, stretchSoundEnabled, focusSoundEnabled, focusDurationMinutes
        case pauseRemindersDuringFocus, stretchTone, focusTone, reminderTone
        case showTranslation, reminderDurationSeconds, rules
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            language: (try? values.decode(CompanionLanguage.self, forKey: .language)) ?? .english,
            appearance: (try? values.decode(CompanionStyle.self, forKey: .appearance)) ?? .classic,
            quietHoursEnabled: (try? values.decode(Bool.self, forKey: .quietHoursEnabled)) ?? true,
            quietStartHour: (try? values.decode(Int.self, forKey: .quietStartHour)) ?? 22,
            quietEndHour: (try? values.decode(Int.self, forKey: .quietEndHour)) ?? 8,
            soundEnabled: (try? values.decode(Bool.self, forKey: .soundEnabled)) ?? false,
            stretchSoundEnabled: (try? values.decode(Bool.self, forKey: .stretchSoundEnabled)) ?? true,
            focusSoundEnabled: (try? values.decode(Bool.self, forKey: .focusSoundEnabled)) ?? true,
            pauseRemindersDuringFocus: (try? values.decode(Bool.self, forKey: .pauseRemindersDuringFocus)) ?? true,
            stretchTone: (try? values.decode(AlertTone.self, forKey: .stretchTone)) ?? .pop,
            focusTone: (try? values.decode(AlertTone.self, forKey: .focusTone)) ?? .glass,
            reminderTone: (try? values.decode(AlertTone.self, forKey: .reminderTone)) ?? .tink,
            focusDurationMinutes: (try? values.decode(Int.self, forKey: .focusDurationMinutes)) ?? 25,
            showTranslation: (try? values.decode(Bool.self, forKey: .showTranslation)) ?? true,
            reminderDurationSeconds: (try? values.decode(Int.self, forKey: .reminderDurationSeconds)) ?? 12,
            rules: (try? values.decode([ReminderRule].self, forKey: .rules)) ?? ReminderRule.defaults
        )
    }
}

public enum ReminderCopy {
    public static func message(for kind: ReminderKind, language: CompanionLanguage) -> String {
        switch language {
        case .english:
            return translation(for: kind)
        case .tamil:
            switch kind {
            case .water: return "தண்ணீர் இடைவேளை. கொஞ்சம் குடிக்கலாமா?"
            case .stretch: return "கொஞ்சம் அசையலாம். கை கால்களை நீட்டலாமா?"
            case .eyes: return "திரையிலிருந்து பார்வையை விலக்கு. கண்களுக்கு 20 நொடிகள் ஓய்வு."
            case .meal: return "அடுத்த வேலை: சாப்பிட ஏதாவது."
            case .rest: return "ஒரு நிமிடம் ஓய்வெடு. இது உனக்கான நேரம்."
            case .custom: return "ஒரு சிறிய நினைவூட்டல். சரியான நேரத்தில்."
            }
        case .hindi:
            switch kind {
            case .water: return "पानी का ब्रेक। दो घूँट हो जाएँ?"
            case .stretch: return "थोड़ा हिलें-डुलें। एक छोटा सा स्ट्रेच?"
            case .eyes: return "स्क्रीन से नज़र हटाओ। आँखों को 20 सेकंड दो।"
            case .meal: return "अगला काम: कुछ खाना।"
            case .rest: return "एक पल रुको। ब्रेक तो बनता है।"
            case .custom: return "एक छोटा सा रिमाइंडर, सही समय पर।"
            }
        case .telugu:
            switch kind {
            case .water: return "నీళ్ల విరామం. రెండు గుటకలు తాగుదామా?"
            case .stretch: return "కాస్త కదులుదాం. ఒళ్లు విరుచుకుందామా?"
            case .eyes: return "స్క్రీన్ నుంచి చూపు తిప్పు. కళ్లకు 20 సెకన్లు ఇవ్వు."
            case .meal: return "తర్వాతి పని: ఏదైనా తినడం."
            case .rest: return "కాసేపు ఆగు. ఈ విరామం నీ కోసమే."
            case .custom: return "సరైన సమయానికి ఒక చిన్న రిమైండర్."
            }
        }
    }

    public static func translation(for kind: ReminderKind) -> String {
        switch kind {
        case .water: return "Time for a sip of water."
        case .stretch: return "Take a moment to stretch."
        case .eyes: return "Rest your eyes for 20 seconds."
        case .meal: return "Take a break for something to eat."
        case .rest: return "You’ve earned a little break."
        case .custom: return "Here’s your reminder."
        }
    }
}
