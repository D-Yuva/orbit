import AppKit
import Combine
import QuartzCore
import SwiftUI
import OrbitCore

/// A keyable panel exists only after an explicit click or menu command. Closing
/// this view never changes the timer session, which belongs to AppStore.
@MainActor
final class FocusTimerPanelController: NSObject {
    private let model = FocusPanelModel()
    private var panel: FocusControlPanel?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var trackedMenus: Set<ObjectIdentifier> = []
    private var anchor = NSRect.zero
    var onClose: (() -> Void)?
    var isVisible: Bool { panel?.isVisible == true }

    func show(store: AppStore, anchor: NSRect) {
        self.anchor = anchor
        model.showsAudio = false
        if let panel, panel.isVisible {
            reposition()
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = FocusControlPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.onEscape = { [weak self] in self?.close() }
        panel.setAccessibilityLabel("Focus timer")
        let view = FocusHostingView(rootView: FocusTimerPanelView(store: store, model: model,
            onClose: { [weak self] in self?.close() },
            onAudio: { [weak self] in self?.showAudioSettings() },
            onTimer: { [weak self] in self?.showTimer() }))
        view.safeAreaRegions = []
        view.sizingOptions = []
        panel.contentView = view
        panel.setContentSize(NSSize(width: FocusPanelLayout.width, height: FocusPanelLayout.timerHeight))
        self.panel = panel
        reposition()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        installDismissalObservers()
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        removeDismissalObservers()
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        onClose?()
    }

    func showAudioSettings() {
        guard isVisible else { return }
        model.showsAudio = true
        reposition(animated: true)
    }

    func showTimer() {
        guard isVisible else { return }
        model.showsAudio = false
        reposition(animated: true)
    }

    /// Captures this app's view only, without screen-recording permission.
    func snapshot(to file: URL) throws {
        guard let view = panel?.contentView, view.bounds.width > 0 else {
            throw NSError(domain: "OrbitFocusSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Open the focus timer before taking its snapshot."])
        }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "OrbitFocusSnapshot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate the focus timer snapshot."])
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "OrbitFocusSnapshot", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to encode the focus timer snapshot."])
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    private func reposition(animated: Bool = false) {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let size = NSSize(width: FocusPanelLayout.width, height: model.showsAudio ? FocusPanelLayout.audioHeight : FocusPanelLayout.timerHeight)
        let proposedX = anchor.maxX + 12
        let x = min(max(bounds.minX, proposedX), max(bounds.minX, bounds.maxX - size.width))
        let top = min(bounds.maxY, screen.frame.maxY - screen.safeAreaInsets.top - 34)
        let y = max(bounds.minY, top - size.height)
        let frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func installDismissalObservers() {
        removeDismissalObservers()
        guard let installedPanel = panel else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel, self.trackedMenus.isEmpty { self.close() }
            return event
        }
        // Native tone pickers track their menus in another AppKit window. Their
        // selection clicks belong to these controls, not to the desktop outside.
        menuObservers = [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self, weak installedPanel] notification in
                MainActor.assumeIsolated {
                    guard let self, let installedPanel, self.panel === installedPanel, let menu = notification.object as? NSMenu else { return }
                    if name == NSMenu.didBeginTrackingNotification {
                        self.trackedMenus.insert(ObjectIdentifier(menu))
                    } else {
                        self.trackedMenus.remove(ObjectIdentifier(menu))
                    }
                }
            }
        }
        // Mouse events outside this application require no accessibility access.
        // Keyboard events are handled solely by the focus panel itself.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self, weak installedPanel] _ in
            Task { @MainActor [weak self, weak installedPanel] in
                guard let self, let installedPanel, self.panel === installedPanel else { return }
                self.close()
            }
        }
        deactivateObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self, weak installedPanel] _ in
            Task { @MainActor [weak self, weak installedPanel] in
                guard let self, let installedPanel, self.panel === installedPanel else { return }
                self.close()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reposition() }
        }
    }

    private func removeDismissalObservers() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers.removeAll()
        trackedMenus.removeAll()
        localMouseMonitor = nil
        globalMouseMonitor = nil
        deactivateObserver = nil
        screenObserver = nil
    }

    deinit {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        menuObservers.forEach(NotificationCenter.default.removeObserver)
    }
}

private final class FocusControlPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

private final class FocusHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private enum FocusPanelLayout {
    static let width: CGFloat = 280
    static let timerHeight: CGFloat = 360
    static let audioHeight: CGFloat = 416
}

@MainActor
private final class FocusPanelModel: ObservableObject {
    @Published var showsAudio = false
}

private struct FocusTimerPanelView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: FocusPanelModel
    let onClose: () -> Void
    let onAudio: () -> Void
    let onTimer: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if model.showsAudio {
                    Button(action: onTimer) {
                        Label("Sounds", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to focus timer")
                } else {
                    Label("Focus", systemImage: "timer")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                Spacer()
                if !model.showsAudio {
                    Button {
                        onAudio()
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose reminder sounds")
                    .help("Sounds")
                }
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close focus timer")
                .help("Close (Esc). Your timer keeps running.")
            }
            .padding(.bottom, 16)

            if model.showsAudio {
                ScrollView(.vertical) {
                    AudioSettingsView(store: store, compact: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FocusTimerControls(store: store)
            }
        }
        .padding(18)
        .frame(width: FocusPanelLayout.width, height: model.showsAudio ? FocusPanelLayout.audioHeight : FocusPanelLayout.timerHeight)
        .foregroundStyle(.primary)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(.regularMaterial)
                    .overlay { shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.2)) }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.09), lineWidth: 0.5)
        }
        .onExitCommand(perform: onClose)
    }

}

/// Shared by the main app and the optional Batman shortcut panel.
struct FocusTimerControls: View {
    @ObservedObject var store: AppStore
    @State private var durationText = "25"
    @State private var showTimerActions = false
    @FocusState private var editingDuration: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var editable: Bool { store.focusTimer.state == .idle || store.focusTimer.state == .completed }
    private var countdown: String {
        let seconds = max(0, store.focusRemainingSeconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private var status: String {
        switch store.focusTimer.state {
        case .idle: return "Ready when you are"
        case .running: return "Time to focus"
        case .paused: return "Paused"
        case .completed: return "Session complete"
        }
    }
    private var primaryTitle: String {
        switch store.focusTimer.state {
        case .idle: return "Start focus"
        case .running: return "Pause"
        case .paused: return "Resume"
        case .completed: return "Start again"
        }
    }
    private var duration: Binding<Int> {
        Binding(get: { store.focusDurationMinutes }, set: {
            durationText = String($0)
            store.focusDurationMinutes = $0
        })
    }

    var body: some View {
        timerContent
            .onAppear { durationText = String(store.focusDurationMinutes) }
            .onChange(of: store.focusDurationMinutes) { _, value in durationText = String(value) }
            .onChange(of: editingDuration) { _, focused in if !focused { commitDuration() } }
            .onDisappear { commitDuration() }
            .onChange(of: store.focusTimer.state) { old, new in
                if new == .idle || new == .completed || (new == .running && old != .paused) {
                    showTimerActions = false
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.focusTimer.state)
    }

    private var timerContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                if editable {
                    countdownText
                } else {
                    Button { showTimerActions = true } label: {
                        countdownText.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show timer controls")
                    .accessibilityIdentifier("focus-countdown")
                    .help("Click to pause or cancel this timer.")
                }
                Text(status).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)

            GeometryReader { geometry in
                Capsule().fill(.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color(nsColor: .systemBlue))
                            .frame(width: geometry.size.width * min(1, max(0, store.focusProgress)))
                    }
            }
            .frame(height: 3)
            .accessibilityLabel("Focus progress")
            .accessibilityValue("\(Int(store.focusProgress * 100)) percent")
            .padding(.bottom, 18)

            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text("Duration").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                    Spacer()
                    TextField("Minutes", text: $durationText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 43)
                        .focused($editingDuration)
                        .onSubmit(commitDuration)
                        .accessibilityLabel("Focus duration in minutes")
                    Text("min").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                    Stepper("Duration", value: duration, in: 1...180)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityLabel("Adjust focus duration")
                }
                HStack(spacing: 6) {
                    ForEach([15, 25, 45, 60], id: \.self) { minutes in
                        Button {
                            durationText = String(minutes)
                            editingDuration = false
                            store.focusDurationMinutes = minutes
                        } label: {
                            Text("\(minutes)m")
                                .font(.system(size: 11, weight: store.focusDurationMinutes == minutes ? .medium : .regular, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .foregroundStyle(store.focusDurationMinutes == minutes ? Color(nsColor: .systemBlue) : Color.primary.opacity(0.68))
                                .background(store.focusDurationMinutes == minutes ? Color.blue.opacity(0.12) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(minutes) minutes")
                        .accessibilityAddTraits(store.focusDurationMinutes == minutes ? .isSelected : [])
                    }
                }
            }
            .disabled(!editable)
            .opacity(editable ? 1 : 0.55)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Pause reminders", isOn: $store.preferences.pauseRemindersDuringFocus)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 12, design: .rounded))
                    .tint(Color(nsColor: .systemBlue))
                Text("Keep nudges quiet until your session ends.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 18)

            if editable || showTimerActions {
                HStack(spacing: 10) {
                    if !editable {
                        Button("Cancel") { editingDuration = false; store.cancelFocus() }
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .accessibilityLabel("Cancel focus timer")
                            .accessibilityIdentifier("cancel-focus")
                    } else if store.focusTimer.state == .completed {
                        Button("Reset") { editingDuration = false; store.resetFocus() }
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    Button(action: performPrimaryAction) {
                        Text(primaryTitle).font(.system(size: 12, weight: .medium, design: .rounded)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(nsColor: .systemBlue))
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("focus-primary-action")
                }
            } else {
                Text("Click the time to pause or cancel")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
        }
    }

    private var countdownText: some View {
        Text(countdown)
            .font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
            .tracking(-1.5)
            .contentTransition(.numericText(countsDown: true))
            .accessibilityLabel("Time remaining")
            .accessibilityValue("\(store.focusRemainingSeconds / 60) minutes, \(store.focusRemainingSeconds % 60) seconds")
    }

    private func commitDuration() {
        guard editable else { return }
        if let value = Int(durationText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            store.focusDurationMinutes = min(180, max(1, value))
        }
        durationText = String(store.focusDurationMinutes)
    }

    private func performPrimaryAction() {
        commitDuration()
        editingDuration = false
        switch store.focusTimer.state {
        case .idle, .completed: store.startFocus()
        case .running: store.pauseFocus()
        case .paused: store.resumeFocus()
        }
    }
}
