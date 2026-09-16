import AppKit
import SwiftUI
import OrbitCore

@main
enum OrbitMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = OrbitAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class OrbitAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: AppStore!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var stateItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        OrbitMenu.installEditingCommands()
        let args = ProcessInfo.processInfo.arguments
        let snapshotIndex = args.firstIndex(of: "--snapshot")
        store = AppStore(isPreview: snapshotIndex != nil)
        // One-time local upgrade action, requested when restoring the uploaded colors.
        if snapshotIndex == nil, args.contains("--natural-avatar") { store.preferences.appearance = .classic }
        makeWindow()
        if let index = snapshotIndex, args.count > index + 1 {
            let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { fail("Snapshot directory: \(error)") }
            let artworkModes = Dictionary(uniqueKeysWithValues: ReminderKind.allCases.map {
                ($0.rawValue, CompanionArtwork.currentArtworkMode(for: $0).rawValue)
            })
            do {
                let data = try JSONSerialization.data(withJSONObject: artworkModes, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("artwork-modes.json"))
            } catch { fail("Artwork manifest: \(error)") }
            snapshotAvatarVariations(directory: directory)
            snapshotAppIcon(directory: directory)
            snapshotPages(directory: directory, pages: Array(AppPage.allCases))
        } else {
            makeMenu()
            store.startIsland(onOpenSettings: { [weak self] in self?.showWindow() })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.store.greet() }
        }
    }

    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 670),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Orbit"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(OrbitTheme.background)
        window.appearance = nil
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OrbitControlsView(store: store))
        window.center()
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: "Orbit")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Orbit · your little reminder island"
        }
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "Orbit", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        stateItem = NSMenuItem(title: store.status, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        addMenuItem("Reminders & settings…", action: #selector(openReminders), key: ",", to: menu)
        addMenuItem("Focus timer…", action: #selector(openFocus), key: "f", to: menu)
        addMenuItem("Audio settings…", action: #selector(openAudio), key: "", to: menu)
        pauseItem = addMenuItem("Pause for one hour", action: #selector(togglePause), key: "p", to: menu)
        menu.addItem(.separator())
        addMenuItem("Quit Orbit", action: #selector(quit), key: "q", to: menu)
        statusItem.menu = menu
    }

    @discardableResult
    private func addMenuItem(_ title: String, action: Selector, key: String, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }
    func menuWillOpen(_ menu: NSMenu) {
        stateItem.title = store.status
        pauseItem.title = store.isPaused ? "Resume reminders" : "Pause for one hour"
    }
    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    @objc private func openReminders() { store.selectedPage = .reminders; showWindow() }
    @objc private func openFocus() { store.selectedPage = .focus; showWindow() }
    @objc private func openAudio() { store.selectedPage = .audio; showWindow() }
    @objc private func togglePause() { store.togglePause() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        store.focusPanel.close()
        store.notch.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }

    private func snapshotAvatarVariations(directory: URL) {
        let avatars = directory.appendingPathComponent("avatars", isDirectory: true)
        do { try FileManager.default.createDirectory(at: avatars, withIntermediateDirectories: true) }
        catch { fail("Avatar preview directory: \(error)") }
        for kind in ReminderKind.allCases {
            let renderer = ImageRenderer(content: CompanionView(style: .classic, size: 512, kind: kind))
            renderer.scale = 2
            guard let cgImage = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                fail("Unable to render \(kind.rawValue) expression")
            }
            do { try png.write(to: avatars.appendingPathComponent("batman-\(kind.rawValue).png")) }
            catch { fail("Expression preview: \(error)") }
        }
    }

    private func snapshotAppIcon(directory: URL) {
        let renderer = ImageRenderer(content:
            ZStack {
                Color(red: 0.035, green: 0.055, blue: 0.11)
                CompanionView(style: .classic, size: 490)
            }
            .frame(width: 512, height: 512)
            .clipShape(RoundedRectangle(cornerRadius: 112, style: .continuous))
        )
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            fail("Unable to render avatar app icon")
        }
        do { try png.write(to: directory.appendingPathComponent("app-icon.png")) }
        catch { fail("App icon snapshot: \(error)") }
    }

    private func snapshotPages(directory: URL, pages: [AppPage]) {
        guard let page = pages.first else {
            snapshotExpressionSheet(directory: directory)
            return
        }
        store.selectedPage = page
        window.setContentSize(NSSize(width: 480, height: 670))
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            guard let view = window.contentView else { fail("No content view") }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fail("No bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("No PNG") }
            do { try png.write(to: directory.appendingPathComponent("controls-\(page.rawValue.lowercased()).png")) }
            catch { fail("Snapshot write: \(error)") }
            snapshotPages(directory: directory, pages: Array(pages.dropFirst()))
        }
    }

    private func snapshotIsland(directory: URL) {
        store.startIsland(onOpenSettings: {})
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in
            captureIsland(directory)
            store.notch.previewExpanded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in
                captureIsland(directory)
                store.notch.revealMessageActions()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                    captureIsland(directory.appendingPathComponent("message-actions"))
                    store.preview()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                        captureIsland(directory)
                        store.preferences.language = .tamil
                        store.previewKind = .eyes
                        store.preview()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                            captureIsland(directory.appendingPathComponent("regional"))
                            store.preferences.language = .english
                            snapshotReminders(directory: directory, kinds: ReminderKind.allCases)
                        }
                    }
                }
            }
        }
    }

    private func snapshotExpressionSheet(directory: URL) {
        window.contentView = NSHostingView(rootView: ExpressionSheetView())
        window.setContentSize(NSSize(width: 980, height: 690))
        window.center()
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fail("No expression sheet bitmap") }
            view.layoutSubtreeIfNeeded()
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("No expression sheet PNG") }
            do { try png.write(to: directory.appendingPathComponent("batman-reminders.png")) }
            catch { fail("Expression sheet: \(error)") }
            window.orderOut(nil)
            snapshotIsland(directory: directory)
        }
    }

    private func snapshotReminders(directory: URL, kinds: [ReminderKind]) {
        guard let kind = kinds.first else {
            store.notch.previewReminderActions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                captureIsland(directory.appendingPathComponent("actions"))
                store.preview(rule: ReminderRule(kind: .custom, title: "Long message", message: String(repeating: "Take a moment to step away and enjoy a little break. ", count: 40)))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                    captureIsland(directory.appendingPathComponent("long-message"))
                    snapshotFocus(directory: directory)
                }
            }
            return
        }
        store.previewKind = kind
        store.preview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            captureIsland(directory.appendingPathComponent("expressions/\(kind.rawValue)"))
            snapshotReminders(directory: directory, kinds: Array(kinds.dropFirst()))
        }
    }

    private func captureIsland(_ directory: URL) {
        do { try store.notch.snapshot(to: directory) }
        catch { fail("Island snapshot: \(error)") }
    }

    private func snapshotFocus(directory: URL) {
        store.notch.dismiss()
        store.openFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            captureFocus(directory, name: "focus-setup")
            store.focusPanel.showAudioSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                captureFocus(directory, name: "focus-audio")
                store.focusPanel.showTimer()
                snapshotRunningFocus(directory: directory)
            }
        }
    }

    private func snapshotRunningFocus(directory: URL) {
        store.startFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            captureFocus(directory, name: "focus-running")
            store.pauseFocus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                captureFocus(directory, name: "focus-paused")
                store.resumeFocus()
                if let deadline = store.focusTimer.deadline { store.advanceFocus(to: deadline) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                    captureFocus(directory, name: "focus-complete")
                    store.focusPanel.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                        captureIsland(directory.appendingPathComponent("focus-finished"))
                        print("Rendered controls, rounded callouts, audio settings, and focus timer states to \(directory.path)")
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
    }

    private func captureFocus(_ directory: URL, name: String) {
        do { try store.focusPanel.snapshot(to: directory.appendingPathComponent(name + ".png")) }
        catch { fail("Focus snapshot: \(error)") }
    }
    private func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
}

private struct ExpressionSheetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Batman, on reminder duty.").font(.system(size: 23, weight: .semibold))
                Spacer()
                Text("Orbit").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                ForEach(ReminderKind.allCases) { kind in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(kind.displayName).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        NotchPreviewView(style: .classic, message: ReminderCopy.translation(for: kind), translation: "", kind: kind)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(32)
        .frame(width: 980, height: 690, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.light)
    }
}
