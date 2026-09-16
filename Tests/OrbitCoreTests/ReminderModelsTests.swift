import Foundation
import XCTest
@testable import OrbitCore

final class ReminderModelsTests: XCTestCase {
    func testMissingPreferencesUseSafeDefaults() throws {
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(preferences.language, .english)
        XCTAssertEqual(preferences.appearance, .classic)
        XCTAssertTrue(preferences.quietHoursEnabled)
        XCTAssertFalse(preferences.soundEnabled)
        XCTAssertTrue(preferences.stretchSoundEnabled)
        XCTAssertTrue(preferences.focusSoundEnabled)
        XCTAssertTrue(preferences.pauseRemindersDuringFocus)
        XCTAssertEqual(preferences.stretchTone, .pop)
        XCTAssertEqual(preferences.focusTone, .glass)
        XCTAssertEqual(preferences.reminderTone, .tink)
        XCTAssertEqual(preferences.focusDurationMinutes, 25)
        XCTAssertEqual(preferences.reminderDurationSeconds, 12)
        XCTAssertEqual(preferences.rules.map(\.kind), [.water, .stretch, .eyes, .meal])
        XCTAssertEqual(preferences.rules.map(\.intervalMinutes), [45, 60, 20, 180])
        XCTAssertTrue(preferences.rules.allSatisfy { $0.schedule == .interval })
    }

    func testMalformedPreferenceFieldsFallbackAndNumbersClamp() throws {
        let json = #"{"language":"future-language","appearance":false,"quietStartHour":-5,"quietEndHour":38,"reminderDurationSeconds":0,"soundEnabled":"yes","rules":[]}"#
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
        XCTAssertEqual(preferences.language, .english)
        XCTAssertEqual(preferences.appearance, .classic)
        XCTAssertEqual(preferences.quietStartHour, 0)
        XCTAssertEqual(preferences.quietEndHour, 23)
        XCTAssertEqual(preferences.reminderDurationSeconds, 5)
        XCTAssertFalse(preferences.soundEnabled)
        XCTAssertTrue(preferences.rules.isEmpty)
    }

    func testRuleDecodingPreservesTextAndClampsCadence() throws {
        let json = #"{"kind":"custom","title":"Call home","message":"A little hello goes a long way.","intervalMinutes":999999}"#
        let rule = try JSONDecoder().decode(ReminderRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.kind, .custom)
        XCTAssertEqual(rule.title, "Call home")
        XCTAssertEqual(rule.message, "A little hello goes a long way.")
        XCTAssertEqual(rule.intervalMinutes, 1_440)
        XCTAssertTrue(rule.isEnabled)
    }

    func testExistingReminderMigratesToIntervalWithoutLosingIdentityOrContent() throws {
        let original = ReminderRule(
            kind: .custom, title: "Walk outside", message: "Try the longer route today.",
            intervalMinutes: 90, isEnabled: false
        )
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["schedule", "hour", "minute"] { legacy.removeValue(forKey: key) }

        let decoded = try JSONDecoder().decode(ReminderRule.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schedule, .interval)
        XCTAssertEqual(decoded.hour, 9)
        XCTAssertEqual(decoded.minute, 0)
    }

    func testDailyReminderRoundTripPreservesTimeAndInactiveIntervalChoice() throws {
        let rule = ReminderRule(
            kind: .custom, title: "Lunch", message: "Step away from the desk.",
            intervalMinutes: 120, schedule: .daily, hour: 12, minute: 45, isEnabled: false
        )
        let preferences = AppPreferences(language: .tamil, soundEnabled: false, rules: [rule])
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))

        XCTAssertEqual(decoded, preferences)
        XCTAssertEqual(decoded.rules.first?.id, rule.id)
        XCTAssertEqual(decoded.rules.first?.intervalMinutes, 120)
    }

    func testInvalidSavedScheduleFallsBackAndTimeFieldsClamp() throws {
        let malformed = Data(#"{"schedule":"future-schedule","hour":"nine","minute":null,"intervalMinutes":30}"#.utf8)
        let decoded = try JSONDecoder().decode(ReminderRule.self, from: malformed)
        XCTAssertEqual(decoded.schedule, .interval)
        XCTAssertEqual(decoded.hour, 9)
        XCTAssertEqual(decoded.minute, 0)
        XCTAssertEqual(decoded.intervalMinutes, 30)

        for (hour, minute, expectedHour, expectedMinute) in [(Int.min, Int.max, 0, 59), (Int.max, Int.min, 23, 0)] {
            let data = Data("{\"schedule\":\"daily\",\"hour\":\(hour),\"minute\":\(minute)}".utf8)
            let clamped = try JSONDecoder().decode(ReminderRule.self, from: data)
            XCTAssertEqual(clamped.schedule, .daily)
            XCTAssertEqual(clamped.hour, expectedHour)
            XCTAssertEqual(clamped.minute, expectedMinute)
        }
    }

    func testFocusPreferencesMigrateWithoutChangingExistingReminders() throws {
        let original = AppPreferences(language: .tamil, appearance: .rose, soundEnabled: false,
                                      rules: [ReminderRule(kind: .stretch, intervalMinutes: 60)])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["stretchSoundEnabled", "focusSoundEnabled", "focusDurationMinutes"] { legacy.removeValue(forKey: key) }
        let migrated = try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated, original)
        var chosen = migrated
        chosen.stretchSoundEnabled = false
        chosen.focusSoundEnabled = false
        chosen.focusDurationMinutes = 45
        XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(chosen)), chosen)
    }

    func testFocusDurationClampsInvalidSavedValues() throws {
        for (input, expected) in [(-10, 1), (0, 1), (181, 180), (Int.max, 180)] {
            let data = Data("{\"focusDurationMinutes\":\(input)}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: data).focusDurationMinutes, expected)
        }
    }

    func testAlertPreferencesMigrateWithoutChangingExistingChoices() throws {
        let original = AppPreferences(
            language: .telugu, appearance: .sage, quietHoursEnabled: false,
            quietStartHour: 20, quietEndHour: 7, soundEnabled: true,
            stretchSoundEnabled: false, focusSoundEnabled: false,
            focusDurationMinutes: 45, showTranslation: false, reminderDurationSeconds: 20,
            rules: [ReminderRule(kind: .custom, title: "Walk outside", intervalMinutes: 90, isEnabled: false)]
        )
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["pauseRemindersDuringFocus", "stretchTone", "focusTone", "reminderTone"] {
            legacy.removeValue(forKey: key)
        }

        let migrated = try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated, original)
    }

    func testMalformedAlertPreferencesUseDefaultsWithoutDiscardingValidFields() throws {
        let invalidValues: [Any] = ["future-tone", 123, false, NSNull(), ["pop"], ["name": "pop"]]
        for invalid in invalidValues {
            let data = try JSONSerialization.data(withJSONObject: [
                "stretchTone": invalid,
                "focusTone": invalid,
                "reminderTone": invalid,
                "pauseRemindersDuringFocus": "yes",
                "focusDurationMinutes": 40,
                "focusSoundEnabled": false,
                "rules": []
            ])
            let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)

            XCTAssertEqual(preferences.stretchTone, .pop)
            XCTAssertEqual(preferences.focusTone, .glass)
            XCTAssertEqual(preferences.reminderTone, .tink)
            XCTAssertTrue(preferences.pauseRemindersDuringFocus)
            XCTAssertEqual(preferences.focusDurationMinutes, 40)
            XCTAssertFalse(preferences.focusSoundEnabled)
            XCTAssertTrue(preferences.rules.isEmpty)
        }

        let mixedData = Data(#"{"stretchTone":"missing","focusTone":"ping","reminderTone":"pop","pauseRemindersDuringFocus":false}"#.utf8)
        let mixed = try JSONDecoder().decode(AppPreferences.self, from: mixedData)
        XCTAssertEqual(mixed.stretchTone, .pop)
        XCTAssertEqual(mixed.focusTone, .ping)
        XCTAssertEqual(mixed.reminderTone, .pop)
        XCTAssertFalse(mixed.pauseRemindersDuringFocus)
    }

    func testToneSelectionsPersistWhileAllSoundsAndFocusSuppressionAreDisabled() throws {
        for tone in AlertTone.allCases {
            let original = AppPreferences(
                soundEnabled: false, stretchSoundEnabled: false, focusSoundEnabled: false,
                pauseRemindersDuringFocus: false,
                stretchTone: tone, focusTone: tone, reminderTone: tone
            )
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)

            XCTAssertEqual(decoded, original)
            XCTAssertFalse(decoded.pauseRemindersDuringFocus)
            XCTAssertFalse(decoded.soundEnabled)
            XCTAssertFalse(decoded.stretchSoundEnabled)
            XCTAssertFalse(decoded.focusSoundEnabled)
        }
    }

    func testPreferenceRoundTripPreservesRuleIdentityAndUnicode() throws {
        let rule = ReminderRule(kind: .custom, title: "இடைவேளை", message: "Take a break", intervalMinutes: 120)
        let original = AppPreferences(language: .tamil, appearance: .rose, rules: [rule])
        let encoded = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: encoded), original)
    }

    func testDuplicateRuleIDsAreDeduplicatedWithoutDroppingOtherRules() {
        let rule = ReminderRule(kind: .water)
        let other = ReminderRule(kind: .stretch)
        let preferences = AppPreferences(rules: [rule, rule, other])
        XCTAssertEqual(preferences.rules, [rule, other])
    }

    func testEveryLanguageAndReminderHasCopy() {
        for kind in ReminderKind.allCases {
            XCTAssertFalse(ReminderCopy.translation(for: kind).isEmpty)
            for language in CompanionLanguage.allCases {
                XCTAssertFalse(ReminderCopy.message(for: kind, language: language).isEmpty)
            }
        }
    }

    func testHistoryEventRoundTripPreservesOutcome() throws {
        let event = ReminderEvent(
            ruleID: UUID(), kind: .water, title: "A little water", message: "Take a sip.",
            date: Date(timeIntervalSince1970: 1_700_000_000), outcome: .snoozed
        )
        let encoded = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(ReminderEvent.self, from: encoded), event)
    }
}
