import SwiftUI
import OrbitCore

struct OrbitControlsView: View {
    @ObservedObject var store: AppStore
    @State private var editing: ReminderRule?

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Page", selection: $store.selectedPage) {
                ForEach(AppPage.allCases) { page in Text(page.rawValue).tag(page) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch store.selectedPage {
                    case .reminders: reminders
                    case .focus: focus
                    case .companion: companion
                    case .preferences: settings
                    case .audio:
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Make it sound like you.").font(.system(size: 17, weight: .medium, design: .rounded))
                            AudioSettingsView(store: store)
                        }
                    }
                    if let error = store.storageError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }.padding(22)
            }
            Divider()
            footer
        }
        .font(.system(size: 13, design: .rounded)).fontDesign(.rounded).tint(OrbitTheme.accent)
        .frame(width: 480, height: 670)
        .background(OrbitTheme.background).foregroundStyle(OrbitTheme.text)
        .sheet(item: $editing) { rule in
            ReminderRuleEditor(rule: rule, isNew: !store.preferences.rules.contains(where: { $0.id == rule.id }), save: store.saveRule)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "circle.dotted.circle")
                .font(.system(size: 27, weight: .light)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Orbit").font(.system(size: 18, weight: .semibold))
                Text("Your reminders, gently.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.status).font(.system(size: 11)).foregroundStyle(.secondary)
            Button { store.selectedPage = .audio } label: {
                Image(systemName: "speaker.wave.2").frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Audio settings")
            .accessibilityLabel("Open audio settings")
        }
        .padding(.horizontal, 24).padding(.top, 39).padding(.bottom, 22)
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your reminders").fontWeight(.semibold)
                    Text("Your words, on your schedule.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editing = ReminderRule(kind: .custom, title: "", intervalMinutes: 60)
                } label: {
                    Label("Add reminder", systemImage: "plus")
                }.buttonStyle(.borderedProminent).controlSize(.small)
                    .accessibilityIdentifier("add-reminder")
            }
            if store.preferences.rules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bell")
                        .font(.system(size: 27, weight: .light)).foregroundStyle(.secondary)
                    Text("No reminders yet").fontWeight(.medium)
                    Text("Add a reminder to get started.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 55)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.preferences.rules.enumerated()), id: \.element.id) { index, rule in
                        reminderRow(rule)
                        if index < store.preferences.rules.count - 1 {
                            Divider().padding(.leading, 49)
                        }
                    }
                }.orbitGroup()
            }
            Button { store.selectedPage = .focus } label: {
                HStack(spacing: 12) {
                    Image(systemName: "timer").font(.system(size: 18)).frame(width: 24)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Focus timer").fontWeight(.medium)
                        Text(store.focusTimer.state == .running ? "\(store.focusTimeLabel) remaining" :
                             store.focusTimer.state == .paused ? "Paused · \(store.focusTimeLabel)" : "A little time for one thing.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }.padding(14).contentShape(Rectangle())
            }.buttonStyle(.plain).orbitGroup()
            Label("Add a reminder or choose Edit to change its text and timing.", systemImage: "text.bubble")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A little time for one thing.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
            FocusTimerControls(store: store)
                .padding(22).orbitGroup()
            Text("Your timer keeps going when you close this window.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func reminderRow(_ rule: ReminderRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rule.kind.symbol)
                .font(.system(size: 17, weight: .regular)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(rule.title).fontWeight(.medium).lineLimit(1)
                    .foregroundStyle(rule.isEnabled ? OrbitTheme.text : OrbitTheme.muted)
                Text(rule.resolvedMessage(language: store.preferences.language))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                Text(rule.timingLabel)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Toggle("Enable \(rule.title)", isOn: Binding(get: { rule.isEnabled }, set: { enabled in
                var changed = rule
                changed.isEnabled = enabled
                store.updateRule(changed)
            }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            Button("Edit") { editing = rule }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit \(rule.title)")
                .accessibilityIdentifier("edit-reminder-\(rule.id.uuidString)")
            Menu {
                Button("Edit reminder") { editing = rule }
                Divider()
                Button("Delete", role: .destructive) { store.deleteRule(rule) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 20, height: 24)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            .accessibilityLabel("Options for \(rule.title)")
        }.padding(.horizontal, 14).padding(.vertical, 14)
    }

    private var companion: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 6) {
                CompanionView(style: store.preferences.appearance, size: 142, kind: store.previewKind)
                    .frame(height: 145)
                Text("Batman").font(.system(size: 17, weight: .semibold))
                Text("A different expression for every reminder.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Expression")
                    Spacer()
                    Picker("Expression", selection: $store.previewKind) {
                        ForEach(ReminderKind.allCases) { kind in Text(kind.displayName).tag(kind) }
                    }.labelsHidden().frame(width: 205)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance")
                    Picker("Appearance", selection: $store.preferences.appearance) {
                        ForEach(CompanionStyle.allCases) { style in Text(style.label).tag(style) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                Divider()
                HStack {
                    Text("Language")
                    Spacer()
                    Picker("Language", selection: $store.preferences.language) {
                        ForEach(CompanionLanguage.allCases) { language in Text(language.label).tag(language) }
                    }.labelsHidden().frame(width: 145)
                }
            }.padding(15).orbitGroup()
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            OrbitSection(title: "Reminder preferences") {
                VStack(spacing: 15) {
                    Toggle(isOn: $store.preferences.quietHoursEnabled) {
                        settingLabel("Quiet hours", "Pause scheduled reminders during these hours.")
                    }.toggleStyle(.switch).controlSize(.small)
                    if store.preferences.quietHoursEnabled {
                        HStack(spacing: 9) {
                            Text("From").foregroundStyle(.secondary)
                            hourPicker("Quiet hours start", value: $store.preferences.quietStartHour)
                            Text("to").foregroundStyle(.secondary)
                            hourPicker("Quiet hours end", value: $store.preferences.quietEndHour)
                            Spacer()
                        }.font(.system(size: 11))
                    }
                    Divider()
                    HStack {
                        settingLabel("Time to read", "How long each reminder stays open.")
                        Spacer()
                        Picker("Time to read", selection: $store.preferences.reminderDurationSeconds) {
                            ForEach([8, 12, 20, 30], id: \.self) { value in Text("\(value) sec").tag(value) }
                        }.labelsHidden().frame(width: 95)
                    }
                    Divider()
                    Toggle(isOn: $store.preferences.showTranslation) {
                        settingLabel("English translation", "Show beneath regional language messages.")
                    }.toggleStyle(.switch).controlSize(.small)
                }.padding(15).orbitGroup()
            }
            OrbitSection(title: "During focus") {
                Toggle(isOn: $store.preferences.pauseRemindersDuringFocus) {
                    settingLabel("Pause reminders", "Keep nudges quiet until your focus session ends, even when the timer is paused.")
                }
                .toggleStyle(.switch).controlSize(.small)
                .padding(15).orbitGroup()
            }
            Button { store.selectedPage = .audio } label: {
                Label("Choose your sounds", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            Label {
                Text("Your settings stay on this Mac. No account, analytics, or screen access. Closing this window keeps reminders running.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label("\(store.completedToday) done today", systemImage: "checkmark.circle")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button { store.togglePause() } label: {
                Image(systemName: store.isPaused ? "play" : "pause").frame(width: 16)
            }
            .buttonStyle(.bordered)
            .help(store.isPaused ? "Resume reminders" : "Pause for one hour")
            .accessibilityLabel(store.isPaused ? "Resume reminders" : "Pause for one hour")
        }.padding(.horizontal, 22).padding(.vertical, 15)
    }

    private func settingLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hourPicker(_ label: String, value: Binding<Int>) -> some View {
        Picker(label, selection: value) {
            ForEach(0..<24, id: \.self) { hour in Text(hourLabel(hour)).tag(hour) }
        }.labelsHidden().frame(width: 92)
    }
}

private extension View {
    func orbitGroup() -> some View {
        background(OrbitTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(OrbitTheme.line))
    }
}
