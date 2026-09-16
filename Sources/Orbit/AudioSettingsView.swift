import SwiftUI
import OrbitCore

/// Shared by the main Audio page and the small panel beside Batman.
struct AudioSettingsView: View {
    @ObservedObject var store: AppStore
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            soundRow("Focus finished", symbol: "timer",
                     enabled: $store.preferences.focusSoundEnabled, tone: $store.preferences.focusTone)
            soundRow("Stretch reminders", symbol: "figure.flexibility",
                     enabled: $store.preferences.stretchSoundEnabled, tone: $store.preferences.stretchTone)
            soundRow("Other reminders", symbol: "bell",
                     enabled: $store.preferences.soundEnabled, tone: $store.preferences.reminderTone)
            Text("A little sound, your way. Tap the speaker to try one.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .font(.system(size: 13, design: .rounded))
        .tint(OrbitTheme.accent)
    }

    private func soundRow(_ title: String, symbol: String, enabled: Binding<Bool>, tone: Binding<AlertTone>) -> some View {
        VStack(spacing: 10) {
            Toggle(isOn: enabled) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .toggleStyle(.switch).controlSize(.small)
            .accessibilityLabel("Sound for \(title.lowercased())")
            HStack(spacing: 10) {
                Picker("Sound for \(title.lowercased())", selection: tone) {
                    ForEach(AlertTone.allCases) { sound in Text(sound.label).tag(sound) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                Button { store.playTonePreview(tone.wrappedValue) } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 25, height: 23)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Try \(tone.wrappedValue.label)")
                .accessibilityLabel("Preview \(tone.wrappedValue.label) for \(title.lowercased())")
            }
        }
        .padding(compact ? 12 : 15)
        .background(OrbitTheme.surface.opacity(compact ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(OrbitTheme.line, lineWidth: 0.5))
    }
}
