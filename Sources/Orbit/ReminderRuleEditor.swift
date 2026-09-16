import SwiftUI
import OrbitCore

/// Edits a local draft; preferences change only when Save is pressed.
struct ReminderRuleEditor: View {
    @State private var rule: ReminderRule
    @State private var intervalText: String
    @State private var intervalUnit: IntervalUnit
    let isNew: Bool
    let save: (ReminderRule) -> Void
    @Environment(\.dismiss) private var dismiss

    init(rule: ReminderRule, isNew: Bool, save: @escaping (ReminderRule) -> Void) {
        _rule = State(initialValue: rule)
        let unit: IntervalUnit = rule.intervalMinutes % 60 == 0 ? .hours : .minutes
        _intervalUnit = State(initialValue: unit)
        _intervalText = State(initialValue: String(rule.intervalMinutes / unit.multiplier))
        self.isNew = isNew
        self.save = save
    }

    private var intervalMinutes: Int? {
        guard let number = Int(intervalText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...(1440 / intervalUnit.multiplier)).contains(number) else { return nil }
        return number * intervalUnit.multiplier
    }

    private var valid: Bool {
        !rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (rule.schedule == .daily || intervalMinutes != nil)
    }

    private var dailyTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                       hour: rule.hour, minute: rule.minute)) ?? Date()
        }, set: {
            let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
            rule.hour = components.hour ?? 9
            rule.minute = components.minute ?? 0
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            VStack(alignment: .leading, spacing: 5) {
                Text(isNew ? "A reminder, your way." : "Make it yours.")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Choose what Batman says and when he shows up.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name").fontWeight(.medium)
                TextField("Water the plants", text: $rule.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Reminder name")
                    .accessibilityIdentifier("reminder-name")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What should Batman say?").fontWeight(.medium)
                TextField("Hey, your plants could use a drink.", text: $rule.message, axis: .vertical)
                    .lineLimit(3...5).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Reminder message")
                    .accessibilityIdentifier("reminder-message")
                Text(rule.kind == .custom ? "Leave this empty to use the reminder name." : "Leave this empty to use Batman’s usual message.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("When").fontWeight(.medium)
                Picker("Reminder schedule", selection: $rule.schedule) {
                    Text("Repeat every").tag(ReminderSchedule.interval)
                    Text("Daily at").tag(ReminderSchedule.daily)
                }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityIdentifier("reminder-schedule")

                if rule.schedule == .interval {
                    HStack(spacing: 10) {
                        TextField("Amount", text: $intervalText)
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                            .accessibilityLabel("Reminder interval")
                            .accessibilityIdentifier("reminder-interval")
                        Picker("Interval unit", selection: $intervalUnit) {
                            ForEach(IntervalUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                        }.labelsHidden().frame(width: 110)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        ForEach([15, 30, 60, 120], id: \.self) { minutes in
                            Button(minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr") {
                                intervalUnit = minutes % 60 == 0 ? .hours : .minutes
                                intervalText = String(minutes / intervalUnit.multiplier)
                            }.buttonStyle(.bordered).controlSize(.small)
                                .accessibilityLabel("Remind every \(minutes) minutes")
                        }
                    }
                    Text(intervalMinutes == nil ? "Choose 1–1,440 minutes or 1–24 hours." : "The next interval starts when you save a new timing.")
                        .font(.system(size: 11))
                        .foregroundStyle(intervalMinutes == nil ? Color.orange : Color.secondary)
                } else {
                    DatePicker("Time", selection: dailyTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .accessibilityLabel("Daily reminder time")
                        .accessibilityIdentifier("reminder-daily-time")
                    Text("Every day, using this Mac’s local time.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Expression").fontWeight(.medium)
                Spacer()
                Picker("Reminder expression", selection: $rule.kind) {
                    ForEach(ReminderKind.allCases) { kind in
                        Text(kind.expressionLabel).tag(kind)
                    }
                }.labelsHidden().frame(width: 170)
            }

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancel-reminder")
                Spacer()
                Button("Save reminder") {
                    if let minutes = intervalMinutes { rule.intervalMinutes = minutes }
                    save(rule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(!valid)
                .accessibilityIdentifier("save-reminder")
            }
        }
        .font(.system(size: 13, design: .rounded)).fontDesign(.rounded)
        .padding(25).frame(width: 440)
        .background(OrbitTheme.background).foregroundStyle(OrbitTheme.text)
        .tint(OrbitTheme.accent)
    }
}

private enum IntervalUnit: String, CaseIterable, Identifiable {
    case minutes = "Minutes", hours = "Hours"
    var id: Self { self }
    var multiplier: Int { self == .hours ? 60 : 1 }
}

private extension ReminderKind {
    var expressionLabel: String {
        switch self {
        case .water: return "Hopeful · Water"
        case .stretch: return "Happy · Stretch"
        case .eyes: return "Peaceful · Eyes"
        case .meal: return "Hungry · Meals"
        case .rest: return "Sleepy · Rest"
        case .custom: return "Surprised · Custom"
        }
    }
}
