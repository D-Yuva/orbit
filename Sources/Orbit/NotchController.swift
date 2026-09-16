import AppKit
import Combine
import QuartzCore
import SwiftUI
import OrbitCore

/// The notch grows only downward. Its companion and its speech bubble live in
/// separate nonactivating windows so the desktop between them stays unobstructed.
@MainActor
final class NotchController: ObservableObject {
    private enum Outcome { case complete, snooze, dismiss }
    private enum HoverRegion: Hashable { case notch, bubble }
    private struct Presentation {
        let id: UUID
        let onComplete: () -> Void
        let onSnooze: () -> Void
        let onDismiss: () -> Void
    }

    private let model = NotchModel()
    private var notchPanel: CompanionPanel?
    private var bubblePanel: CompanionPanel?
    private var presentation: Presentation?
    private var expiryTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var bubbleTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var preferredScreenID: NSNumber?
    private var hoveredRegions: Set<HoverRegion> = []
    private var previewHold = false
    private var focusControlsVisible = false
    private var isStarted = false
    private var transitionID = UUID()
    private var bubbleTargetFrame = NSRect.zero
    private var onOpenSettings: () -> Void = {}
    private var onTogglePause: () -> Void = {}
    private var onOpenFocus: (NSRect) -> Void = { _ in }
    private var onToggleFocusPause: () -> Void = {}
    private var onCancelFocus: () -> Void = {}

    init() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reposition(animated: false) }
        }
    }

    deinit {
        expiryTask?.cancel()
        collapseTask?.cancel()
        bubbleTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func start(onOpenSettings: @escaping () -> Void, onTogglePause: @escaping () -> Void,
               onOpenFocus: @escaping (NSRect) -> Void = { _ in },
               onToggleFocusPause: @escaping () -> Void = {}, onCancelFocus: @escaping () -> Void = {}) {
        self.onOpenSettings = onOpenSettings
        self.onTogglePause = onTogglePause
        self.onOpenFocus = onOpenFocus
        self.onToggleFocusPause = onToggleFocusPause
        self.onCancelFocus = onCancelFocus
        guard !isStarted else { return }
        isStarted = true
        installPanelsIfNeeded()
        transition(to: .idle, animated: false)
        notchPanel?.orderFrontRegardless()
    }

    func updateIdle(title: String, subtitle: String, paused: Bool, style: CompanionStyle = .classic,
                    focusState: FocusTimerSession.State = .idle) {
        let wasActive = model.hasActiveFocus
        let isActive = focusState == .running || focusState == .paused
        if wasActive != isActive, model.mode == .idle || model.mode == .hovered { model.showActions = false }
        model.focusState = focusState
        model.idleTitle = title
        model.idleSubtitle = subtitle
        model.paused = paused
        model.style = style
        if model.mode == .hovered { reposition(animated: false) }
    }

    func show(title: String, message: String, translation: String?, kind: ReminderKind, style: CompanionStyle, duration: TimeInterval, allowsSnooze: Bool = true,
              onComplete: @escaping () -> Void, onSnooze: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        expiryTask?.cancel()
        collapseTask?.cancel()
        previewHold = false
        let id = UUID()
        presentation = Presentation(id: id, onComplete: onComplete, onSnooze: onSnooze, onDismiss: onDismiss)
        model.title = title
        model.message = message
        model.translation = translation
        model.kind = kind
        model.style = style
        model.allowsSnooze = allowsSnooze
        let pointer = NSEvent.mouseLocation
        hoveredRegions.removeAll()
        if let notchPanel, notchPanel.isVisible, notchPanel.frame.contains(pointer) { hoveredRegions.insert(.notch) }
        if let bubblePanel, bubblePanel.isVisible, bubblePanel.alphaValue > 0.1, bubblePanel.frame.contains(pointer) { hoveredRegions.insert(.bubble) }
        model.showActions = false
        isStarted = true
        installPanelsIfNeeded()
        transition(to: .reminder)
        notchPanel?.orderFrontRegardless()
        let seconds = duration.isFinite ? max(1, min(duration, 3600)) : 15
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) }
            catch { return }
            let clock = ContinuousClock()
            var outsideSince: ContinuousClock.Instant?
            while self?.shouldHoldExpiredReminder(matching: id) == true {
                if self?.pointerIsInsideCompanion() == true {
                    outsideSince = nil
                } else if let outsideSince {
                    if outsideSince.duration(to: clock.now) >= .milliseconds(450) { break }
                } else {
                    outsideSince = clock.now
                }
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            self?.finish(.dismiss, matching: id)
        }
    }

    func dismiss() {
        previewHold = false
        if let id = presentation?.id {
            finish(.dismiss, matching: id)
        } else {
            collapseTask?.cancel()
            transition(to: .idle)
        }
    }

    func stop() {
        expiryTask?.cancel()
        collapseTask?.cancel()
        bubbleTask?.cancel()
        transitionID = UUID()
        presentation = nil
        hoveredRegions.removeAll()
        previewHold = false
        focusControlsVisible = false
        isStarted = false
        notchPanel?.orderOut(nil)
        bubblePanel?.orderOut(nil)
        model.mode = .idle
        model.showActions = false
    }

    func previewExpanded() {
        guard isStarted, presentation == nil else { return }
        collapseTask?.cancel()
        previewHold = true
        model.showActions = false
        transition(to: .hovered)
    }

    /// A message click reveals its controls; pausing always takes a separate,
    /// deliberate press on the Pause reminders button.
    func revealMessageActions() {
        guard isStarted, !focusControlsVisible, model.mode == .hovered || model.mode == .reminder else { return }
        collapseTask?.cancel()
        guard !model.showActions else { return }
        model.showActions = true
        reposition(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func presentFocusControls() {
        guard isStarted, let notchPanel else { return }
        onOpenFocus(notchPanel.frame)
    }

    /// The timer owns its own window; keep the character visible without laying
    /// the hover callout beneath its controls.
    func setFocusControlsVisible(_ visible: Bool) {
        guard focusControlsVisible != visible else { return }
        focusControlsVisible = visible
        collapseTask?.cancel()
        previewHold = false
        guard isStarted else { return }
        transition(to: presentation == nil ? (visible ? .hovered : .idle) : .reminder)
    }

    /// Exposes reminder controls for app-owned screenshots without invoking an
    /// action or changing the current reminder's expiry time.
    func previewReminderActions() {
        guard isStarted, presentation != nil, model.mode == .reminder else { return }
        revealMessageActions()
        previewHold = true
        reposition(animated: false)
    }

    /// Composites only our two native views, preserving transparent space and
    /// their true relative positions. This never captures another application.
    func snapshot(to directory: URL) throws {
        guard let notchPanel, let notchView = notchPanel.contentView, notchView.bounds.width > 0 else {
            throw snapshotError("The notch does not have a renderable view.")
        }
        var windows = [notchPanel]
        if let bubblePanel, bubblePanel.isVisible, bubblePanel.alphaValue > 0 { windows.append(bubblePanel) }
        let union = windows.reduce(notchPanel.frame) { $0.union($1.frame) }
        let scale = notchPanel.backingScaleFactor
        guard let context = CGContext(data: nil, width: Int(ceil(union.width * scale)), height: Int(ceil(union.height * scale)), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw snapshotError("Unable to allocate the composite snapshot.")
        }
        context.scaleBy(x: scale, y: scale)
        for window in windows {
            guard let view = window.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw snapshotError("Unable to capture a companion view.") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let image = bitmap.cgImage else { throw snapshotError("Unable to read a companion bitmap.") }
            context.draw(image, in: window.frame.offsetBy(dx: -union.minX, dy: -union.minY))
        }
        guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw snapshotError("Unable to encode the composite snapshot.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "island-\(model.mode.rawValue)"
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        // Diagnostic paper backdrop: 24 physical pixels at each side and below,
        // while the notch's top edge remains flush with the image's top.
        if let paper = CGContext(data: nil, width: image.width + 48, height: image.height + 24, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            paper.setFillColor(CGColor(red: 250.0 / 255, green: 250.0 / 255, blue: 248.0 / 255, alpha: 1))
            paper.fill(CGRect(x: 0, y: 0, width: image.width + 48, height: image.height + 24))
            paper.draw(image, in: CGRect(x: 24, y: 24, width: image.width, height: image.height))
            if let paperImage = paper.makeImage(), let paperPNG = NSBitmapImageRep(cgImage: paperImage).representation(using: .png, properties: [:]) {
                try paperPNG.write(to: directory.appendingPathComponent(name + "-on-paper.png"))
            }
        }
        func geometry(_ rect: NSRect) -> [String: Double] {
            ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
        }
        var metadata: [String: Any] = ["mode": model.mode.rawValue, "reminderKind": model.kind.rawValue, "physicalNotchWidth": model.notchWidth,
                                       "safeTop": model.safeTop, "showActions": model.showActions, "scrollContent": model.scrollContent,
                                       "focusControlsVisible": focusControlsVisible, "allowsSnooze": model.allowsSnooze,
                                       "notchHasShadow": notchPanel.hasShadow,
                                       "usesHardwareCutout": model.mode == .idle && model.hasPhysicalNotch,
                                       "bubbleVisible": bubblePanel?.isVisible == true && (bubblePanel?.alphaValue ?? 0) > 0,
                                       "notchFrame": geometry(notchPanel.frame),
                                       "blackNotchHeight": model.mode == .idle ? notchPanel.frame.height : notchPanel.frame.height - 12,
                                       "compositeFrame": geometry(union), "scale": scale]
        let pauseTitle = model.paused ? "Resume reminders" : "Pause reminders"
        let actionTitles: [String]
        if model.showActions, model.mode == .hovered {
            actionTitles = model.hasActiveFocus ? [model.focusState == .paused ? "Resume" : "Pause", "Cancel"] : [pauseTitle, "Settings"]
        } else if model.showActions, model.mode == .reminder {
            actionTitles = [pauseTitle, "Done"] + (model.allowsSnooze ? ["5 min"] : []) + ["Dismiss"]
        } else {
            actionTitles = []
        }
        metadata["actionTitles"] = actionTitles
        metadata["focusState"] = String(describing: model.focusState)
        if windows.count > 1, let bubblePanel {
            metadata["bubbleFrame"] = geometry(bubblePanel.frame)
            metadata["bubbleGap"] = bubblePanel.frame.minX - notchPanel.frame.maxX
            metadata["appearance"] = bubblePanel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "system"
        }
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent(name + ".json"))
    }

    private func snapshotError(_ message: String) -> NSError {
        NSError(domain: "OrbitSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func installPanelsIfNeeded() {
        guard notchPanel == nil else { return }
        let notch = makePanel(label: "Orbit notch companion")
        notch.contentView = hosting(NotchWellView(model: model,
            onHover: { [weak self] inside in self?.handleHover(inside, region: .notch) },
            onOpenFocus: { [weak self] in self?.presentFocusControls() }))
        notchPanel = notch
        let bubble = makePanel(label: "Orbit companion bubble")
        bubble.contentView = hosting(CompanionBubbleView(model: model,
            onHover: { [weak self] inside in self?.handleHover(inside, region: .bubble) },
            onRevealActions: { [weak self] in self?.revealMessageActions() },
            onComplete: { [weak self] in
                guard let self, let id = self.presentation?.id else { return }
                self.finish(.complete, matching: id)
            },
            onSnooze: { [weak self] in
                guard let self, let id = self.presentation?.id else { return }
                self.finish(.snooze, matching: id)
            },
            onDismiss: { [weak self] in self?.dismiss() },
            onSettings: { [weak self] in self?.dismiss(); self?.onOpenSettings() },
            onPause: { [weak self] in self?.onTogglePause() },
            onToggleFocusPause: { [weak self] in
                guard let self, self.model.mode == .hovered, self.model.hasActiveFocus,
                      self.model.showActions, !self.focusControlsVisible else { return }
                self.onToggleFocusPause()
            },
            onCancelFocus: { [weak self] in
                guard let self, self.model.mode == .hovered, self.model.hasActiveFocus,
                      self.model.showActions, !self.focusControlsVisible else { return }
                self.model.showActions = false
                self.onCancelFocus()
                self.reposition(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        ))
        bubblePanel = bubble
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        preferredScreenID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    private func makePanel(label: String) -> CompanionPanel {
        let panel = CompanionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.setAccessibilityLabel(label)
        return panel
    }

    private func hosting<Content: View>(_ content: Content) -> NSHostingView<Content> {
        let view = CompanionHostingView(rootView: content)
        view.sizingOptions = []
        view.safeAreaRegions = []
        return view
    }

    private func handleHover(_ inside: Bool, region: HoverRegion) {
        if inside { hoveredRegions.insert(region) } else { hoveredRegions.remove(region) }
        guard isStarted, !previewHold, !focusControlsVisible else { return }
        if inside {
            if model.mode == .idle || model.mode == .hovered || model.mode == .reminder { collapseTask?.cancel() }
            if model.mode == .idle {
                transition(to: .hovered)
            }
        } else if (model.mode == .hovered || model.mode == .reminder) && hoveredRegions.isEmpty {
            collapseTask?.cancel()
            collapseTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(450)) }
                catch { return }
                guard let self, !self.focusControlsVisible, self.hoveredRegions.isEmpty else { return }
                let pointer = NSEvent.mouseLocation
                let insideNotch = self.notchPanel?.frame.contains(pointer) == true
                let insideBubble = self.bubblePanel?.isVisible == true && self.bubblePanel?.frame.contains(pointer) == true
                guard !insideNotch, !insideBubble else { return }
                if self.model.mode == .hovered {
                    self.transition(to: .idle)
                } else if self.model.mode == .reminder {
                    self.model.showActions = false
                    self.reposition(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                }
            }
        }
    }

    private func finish(_ outcome: Outcome, matching identifier: UUID) {
        guard let current = presentation, current.id == identifier else { return }
        presentation = nil
        previewHold = false
        expiryTask?.cancel()
        expiryTask = nil
        collapseTask?.cancel()
        switch outcome {
        case .complete:
            transition(to: .celebrate)
            collapseTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(1300)) }
                catch { return }
                guard let self, self.presentation == nil, self.model.mode == .celebrate else { return }
                self.transition(to: .idle)
            }
            current.onComplete()
        case .snooze:
            transition(to: .idle)
            current.onSnooze()
        case .dismiss:
            transition(to: .idle)
            current.onDismiss()
        }
    }

    private func shouldHoldExpiredReminder(matching identifier: UUID) -> Bool {
        presentation?.id == identifier && model.showActions && !previewHold
    }

    private func pointerIsInsideCompanion() -> Bool {
        let point = NSEvent.mouseLocation
        let insideNotch = notchPanel?.isVisible == true && notchPanel?.frame.contains(point) == true
        let insideBubble = bubblePanel?.isVisible == true && (bubblePanel?.alphaValue ?? 0) > 0.1 && bubblePanel?.frame.contains(point) == true
        return insideNotch || insideBubble
    }

    private func transition(to mode: NotchMode, animated: Bool = true) {
        let mode = focusControlsVisible && mode == .idle ? NotchMode.hovered : mode
        bubbleTask?.cancel()
        let id = UUID()
        transitionID = id
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if model.mode != mode { model.showActions = false }
        model.mode = mode
        if mode != .idle { model.bubbleMode = mode }
        reposition(animated: animate)
        guard let bubblePanel else { return }
        if mode == .idle || focusControlsVisible {
            hoveredRegions.remove(.bubble)
            if animate, mode != .idle, bubblePanel.isVisible {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    bubblePanel.animator().alphaValue = 0
                }
                bubbleTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .milliseconds(190)) }
                    catch { return }
                    guard let self, self.transitionID == id else { return }
                    self.bubblePanel?.orderOut(nil)
                }
            } else {
                bubblePanel.alphaValue = 0
                bubblePanel.orderOut(nil)
            }
        } else if bubblePanel.isVisible && bubblePanel.alphaValue > 0.1 {
            bubblePanel.alphaValue = 1
        } else {
            bubbleTask = Task { @MainActor [weak self] in
                if animate {
                    do { try await Task.sleep(for: .milliseconds(120)) }
                    catch { return }
                }
                guard let self, self.transitionID == id, self.isStarted, let bubble = self.bubblePanel else { return }
                let target = self.bubbleTargetFrame
                bubble.alphaValue = animate ? 0 : 1
                bubble.setFrame(animate ? target.offsetBy(dx: -4, dy: 0) : target, display: true)
                bubble.orderFrontRegardless()
                if animate {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.22
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        bubble.animator().setFrame(target, display: true)
                        bubble.animator().alphaValue = 1
                    }, completionHandler: nil)
                }
            }
        }
    }

    private func reposition(animated: Bool) {
        guard let notchPanel, let bubblePanel else { return }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == preferredScreenID
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let safeTop = screen.safeAreaInsets.top
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let measuredWidth = (right?.minX ?? 0) - (left?.maxX ?? 0)
        let hasPhysicalNotch = safeTop > 0 && measuredWidth > 0
        let width: CGFloat = hasPhysicalNotch ? measuredWidth : 188
        let center = hasPhysicalNotch ? ((left?.maxX ?? 0) + (right?.minX ?? 0)) / 2 : screen.frame.midX
        model.safeTop = safeTop
        model.hasPhysicalNotch = hasPhysicalNotch
        model.notchWidth = width
        // The resting window must end at the hardware cutout's bottom edge.
        // Keep a small hover target only on displays without a physical notch.
        let height = model.mode == .idle ? (hasPhysicalNotch ? safeTop : 3) : safeTop + 105 + 12
        let needsShadow = model.mode != .idle
        if notchPanel.hasShadow != needsShadow {
            notchPanel.hasShadow = needsShadow
            notchPanel.invalidateShadow()
        }
        let top = screen.frame.maxY
        let frame = NSRect(x: center - width / 2, y: top - height, width: width, height: height)
        let bubbleX = frame.maxX + 12
        let bubbleTop = top - safeTop - 34
        let availableWidth = max(1, screen.visibleFrame.maxX - bubbleX - 12)
        let availableHeight = max(1, bubbleTop - screen.visibleFrame.minY - 12)
        let maximumHeight = min(320, availableHeight)
        var bubbleSize: NSSize
        switch model.bubbleMode {
        case .idle, .hovered:
            bubbleSize = CalloutMetrics.size(
                message: model.idleSubtitle,
                translation: nil,
                showActions: model.showActions,
                minimumWidth: model.showActions ? 220 : 156,
                maximumWidth: min(250, availableWidth)
            )
        case .reminder:
            bubbleSize = CalloutMetrics.size(message: model.message, translation: model.translation,
                                             showActions: model.showActions, actionRows: 2,
                                             minimumWidth: model.showActions ? 220 : 156, maximumWidth: min(270, availableWidth))
        case .celebrate:
            bubbleSize = CalloutMetrics.size(message: "All done.", translation: "A little time, well spent.",
                                             showActions: false, maximumWidth: min(270, availableWidth))
        }
        model.scrollContent = bubbleSize.height > maximumHeight
        bubbleSize.height = min(bubbleSize.height, maximumHeight)
        bubbleTargetFrame = NSRect(x: bubbleX, y: bubbleTop - bubbleSize.height,
                                   width: bubbleSize.width, height: bubbleSize.height)
        if animated, notchPanel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                notchPanel.animator().setFrame(frame, display: true)
                if bubblePanel.isVisible { bubblePanel.animator().setFrame(bubbleTargetFrame, display: true) }
            }
        } else {
            notchPanel.setFrame(frame, display: true)
            bubblePanel.setFrame(bubbleTargetFrame, display: true)
        }
    }


}

private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CompanionHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private enum NotchMode: String { case idle, hovered, reminder, celebrate }

@MainActor
private final class NotchModel: ObservableObject {
    @Published var mode: NotchMode = .idle
    @Published var bubbleMode: NotchMode = .hovered
    @Published var idleTitle = "Your next little break"
    @Published var idleSubtitle = "Take a moment for yourself"
    @Published var paused = false
    @Published var focusState: FocusTimerSession.State = .idle
    @Published var showActions = false
    @Published var allowsSnooze = true
    @Published var scrollContent = false
    @Published var title = "Hydrate"
    @Published var message = "A sip of water. A fresh start."
    @Published var translation: String?
    @Published var kind: ReminderKind = .water
    @Published var style: CompanionStyle = .classic
    @Published var safeTop: CGFloat = 0
    @Published var hasPhysicalNotch = false
    @Published var notchWidth: CGFloat = 188

    var hasActiveFocus: Bool { focusState == .running || focusState == .paused }
}

private struct NotchWellView: View {
    @ObservedObject var model: NotchModel
    let onHover: (Bool) -> Void
    let onOpenFocus: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let expanded = model.mode != .idle
            ZStack(alignment: .bottom) {
                Color.clear
                if expanded || !model.hasPhysicalNotch {
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 0)
                        .fill(.black)
                        .frame(height: max(0, geometry.size.height - (expanded ? 12 : 0)))
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                if expanded {
                    PeekingCompanionView(style: model.style, width: 126, height: 110, kind: model.kind)
                        .padding(.bottom, 12)
                        .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onOpenFocus)
        .animation(reduceMotion || model.mode == .idle ? .none : .easeInOut(duration: 0.28), value: model.mode)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Orbit companion. \(model.paused ? "Paused" : model.idleTitle).")
        .accessibilityHint("Click to open the focus timer.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpenFocus() }
    }
}

/// Measurement and rendering share the same fonts and insets so regional copy
/// can wrap naturally without forcing every callout to the maximum width.
private enum CalloutMetrics {
    static let horizontalInset: CGFloat = 13
    static let verticalInset: CGFloat = 10
    static let secondarySpacing: CGFloat = 4
    static let actionHeight: CGFloat = 28

    static func size(message: String, translation: String?, showActions: Bool, actionRows: Int = 1,
                     minimumWidth: CGFloat = 156, maximumWidth: CGFloat = 270) -> NSSize {
        let mainFont = roundedFont(size: 13)
        let secondaryFont = roundedFont(size: 11)
        let secondary = translation.flatMap { $0.isEmpty ? nil : $0 }
        let mainWidth = naturalWidth(message, font: mainFont)
        let secondaryWidth = secondary.map { naturalWidth($0, font: secondaryFont) } ?? 0
        let width = min(maximumWidth, max(min(minimumWidth, maximumWidth), ceil(max(mainWidth, secondaryWidth)) + horizontalInset * 2))
        let contentWidth = max(1, width - horizontalInset * 2)
        let mainHeight = height(message, width: contentWidth, font: mainFont)
        let secondaryHeight = secondary.map { height($0, width: contentWidth, font: secondaryFont) + secondarySpacing } ?? 0
        let totalHeight = max(40, mainHeight + secondaryHeight + verticalInset * 2) + (showActions ? actionHeight * CGFloat(actionRows) : 0)
        return NSSize(width: width, height: totalHeight)
    }

    private static func naturalWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func roundedFont(size: CGFloat) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: .regular)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    private static func height(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        ceil((text as NSString).boundingRect(with: NSSize(width: width, height: 10_000),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                                            attributes: [.font: font]).height)
    }
}

private struct CompanionBubbleView: View {
    @ObservedObject var model: NotchModel
    let onHover: (Bool) -> Void
    let onRevealActions: () -> Void
    let onComplete: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void
    let onSettings: () -> Void
    let onPause: () -> Void
    let onToggleFocusPause: () -> Void
    let onCancelFocus: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFocusCountdown: Bool {
        model.hasActiveFocus && (model.bubbleMode == .idle || model.bubbleMode == .hovered)
    }
    private var focusPauseTitle: String { model.focusState == .paused ? "Resume" : "Pause" }

    var body: some View {
        CalloutOverflow(scrolls: model.scrollContent && model.bubbleMode != .reminder) {
            switch model.bubbleMode {
            case .idle, .hovered:
                VStack(alignment: .leading, spacing: CalloutMetrics.secondarySpacing) {
                    CalloutMessage(message: model.idleSubtitle, action: onRevealActions, isFocusCountdown: isFocusCountdown) {
                        Text(model.idleSubtitle)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.showActions {
                        HStack(spacing: 10) {
                            if isFocusCountdown {
                                CalloutAction(title: focusPauseTitle, accented: true, action: onToggleFocusPause)
                                    .accessibilityLabel("\(focusPauseTitle) focus timer")
                                    .help("\(focusPauseTitle) this focus session.")
                                CalloutSeparator()
                                CalloutAction(title: "Cancel", action: onCancelFocus)
                                    .accessibilityLabel("Cancel focus timer")
                                    .help("Cancel this focus session and reset its timer.")
                                Spacer(minLength: 4)
                            } else {
                                CalloutPauseAction(paused: model.paused, action: onPause)
                                Spacer(minLength: 4)
                                Button(action: onSettings) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open Orbit settings")
                                .help("Settings")
                            }
                        }
                        .frame(height: 20)
                        .padding(.top, 4)
                    }
                }
            case .reminder:
                CalloutReminderContent(message: model.message, translation: model.translation,
                                       showActions: model.showActions, scrolls: model.scrollContent, allowsSnooze: model.allowsSnooze,
                                       onRevealActions: onRevealActions, paused: model.paused, onPause: onPause, onComplete: onComplete,
                                       onSnooze: onSnooze, onDismiss: onDismiss)
            case .celebrate:
                VStack(alignment: .leading, spacing: CalloutMetrics.secondarySpacing) {
                    Text("All done.").font(.system(size: 13, weight: .regular, design: .rounded))
                    Text("A little time, well spent.").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, CalloutMetrics.horizontalInset)
        .padding(.vertical, CalloutMetrics.verticalInset)
        .foregroundStyle(.primary)
        .background(CalloutSurface())
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover(perform: onHover)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: model.showActions)
        .contextMenu {
            if model.bubbleMode == .hovered || model.bubbleMode == .reminder {
                if model.showActions {
                    if isFocusCountdown {
                        Button("\(focusPauseTitle) focus timer", action: onToggleFocusPause)
                        Button("Cancel focus timer", action: onCancelFocus)
                    } else {
                        Button(model.paused ? "Resume reminders" : "Pause reminders for one hour", action: onPause)
                        if model.bubbleMode == .reminder {
                            Button("Done", action: onComplete)
                            if model.allowsSnooze { Button("Remind me in 5 minutes", action: onSnooze) }
                            Button("Dismiss", action: onDismiss)
                        }
                    }
                } else {
                    Button(isFocusCountdown ? "Show focus timer controls" : "Show reminder controls", action: onRevealActions)
                }
            }
        }
        .accessibilityActions {
            if model.bubbleMode == .hovered || model.bubbleMode == .reminder {
                if model.showActions {
                    if isFocusCountdown {
                        Button("\(focusPauseTitle) focus timer", action: onToggleFocusPause)
                        Button("Cancel focus timer", action: onCancelFocus)
                    } else {
                        Button(model.paused ? "Resume reminders" : "Pause reminders for one hour", action: onPause)
                        if model.bubbleMode == .reminder {
                            Button("Mark reminder complete", action: onComplete)
                            if model.allowsSnooze { Button("Snooze for five minutes", action: onSnooze) }
                        }
                    }
                } else {
                    Button(isFocusCountdown ? "Show focus timer controls" : "Show reminder controls", action: onRevealActions)
                }
            }
        }
    }
}

private struct CalloutReminderContent: View {
    let message: String
    let translation: String?
    var showActions = false
    var scrolls = false
    var allowsSnooze = true
    var onRevealActions: (() -> Void)? = nil
    var paused = false
    var onPause: (() -> Void)? = nil
    let onComplete: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CalloutMetrics.secondarySpacing) {
            CalloutOverflow(scrolls: scrolls) {
                CalloutMessage(message: [message, translation ?? ""].filter { !$0.isEmpty }.joined(separator: ". "), action: onRevealActions) {
                    VStack(alignment: .leading, spacing: CalloutMetrics.secondarySpacing) {
                        Text(message)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let translation, !translation.isEmpty {
                            Text(translation)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if showActions {
                if let onPause {
                    HStack {
                        CalloutPauseAction(paused: paused, action: onPause)
                        Spacer(minLength: 4)
                    }
                    .frame(height: 20)
                    .padding(.top, 4)
                    .transition(.opacity)
                }
                HStack(spacing: 10) {
                    CalloutAction(title: "Done", action: onComplete)
                        .accessibilityLabel("Mark reminder complete")
                    if allowsSnooze {
                        CalloutSeparator()
                        CalloutAction(title: "5 min", action: onSnooze)
                            .accessibilityLabel("Snooze reminder for five minutes")
                    }
                    Spacer(minLength: 4)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss reminder")
                }
                .frame(height: 20)
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
    }
}

/// The clickable region is just the message, so pressing any revealed control
/// cannot accidentally invoke the message's reveal action a second time.
private struct CalloutMessage<Content: View>: View {
    let message: String
    let action: (() -> Void)?
    let isFocusCountdown: Bool
    let content: Content

    init(message: String, action: (() -> Void)?, isFocusCountdown: Bool = false, @ViewBuilder content: () -> Content) {
        self.message = message
        self.action = action
        self.isFocusCountdown = isFocusCountdown
        self.content = content()
    }

    var body: some View {
        if let action {
            Button(action: action) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFocusCountdown ? "Show focus timer controls" : "Show reminder controls")
            .accessibilityValue(message)
            .accessibilityHint(isFocusCountdown ? "Reveals Pause or Resume and Cancel for this focus session. Clicking the countdown does not change your session." : "Reveals Pause or Resume reminders. Clicking the message does not pause them.")
            .help(isFocusCountdown ? "Click to show focus timer controls" : "Click to show reminder controls")
        } else {
            content
        }
    }
}

private struct CalloutPauseAction: View {
    let paused: Bool
    let action: () -> Void

    private var explanation: String {
        paused ? "Resume reminders now." : "Pause reminders for one hour. Your focus timer keeps running."
    }

    var body: some View {
        CalloutAction(title: paused ? "Resume reminders" : "Pause reminders", accented: true, action: action)
            .accessibilityHint(explanation)
            .help(explanation)
    }
}

/// Long copy scrolls inside the popover; reminder controls remain in the
/// enclosing stack so Done and Snooze never disappear below the display.
private struct CalloutOverflow<Content: View>: View {
    let scrolls: Bool
    let content: Content

    init(scrolls: Bool, @ViewBuilder content: () -> Content) {
        self.scrolls = scrolls
        self.content = content()
    }

    var body: some View {
        if scrolls {
            ScrollView(.vertical) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 5)
            }
            .scrollIndicators(.visible)
        } else {
            content
        }
    }
}

private struct CalloutAction: View {
    let title: String
    var accented = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: accented ? .medium : .regular, design: .rounded))
                .foregroundStyle(accented ? Color(nsColor: .systemBlue) : Color.primary.opacity(0.62))
                .frame(height: 20)
                .contentShape(Rectangle())
                .opacity(hovered ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct CalloutSeparator: View {
    var body: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 0.5, height: 10)
            .accessibilityHidden(true)
    }
}

/// The system material follows the window appearance. A small adaptive tint
/// improves legibility while leaving the desktop visible through the frost.
private struct CalloutSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(.regularMaterial)
                    .overlay {
                        shape.fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.20 : 0.12))
                    }
            }
        }
        .overlay {
            shape.strokeBorder(colorScheme == .dark ? .white.opacity(0.13) : .black.opacity(0.09), lineWidth: 0.5)
        }
        .overlay {
            shape.inset(by: 0.5).strokeBorder(.white.opacity(colorScheme == .dark ? 0.06 : 0.48), lineWidth: 0.5)
        }
    }
}

struct NotchPreviewView: View {
    let style: CompanionStyle
    let message: String
    let translation: String
    var kind: ReminderKind = .water

    var body: some View {
        let secondary: String? = translation.isEmpty ? nil : translation
        let size = CalloutMetrics.size(message: message, translation: secondary, showActions: false)
        let visibleHeight = min(320, size.height)
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottom) {
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 0)
                    .fill(.black).frame(width: 188, height: 143).padding(.bottom, 12)
                PeekingCompanionView(style: style, width: 126, height: 110, kind: kind).padding(.bottom, 12)
            }
            .frame(width: 188, height: 155)
            CalloutReminderContent(message: message, translation: secondary, scrolls: size.height > visibleHeight, onComplete: {}, onSnooze: {}, onDismiss: {})
                .padding(.horizontal, CalloutMetrics.horizontalInset)
                .padding(.vertical, CalloutMetrics.verticalInset)
                .frame(width: size.width, height: visibleHeight, alignment: .leading)
                .background(CalloutSurface())
                .padding(.top, 72)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Orbit reminder preview. \(message). \(translation)")
    }
}
