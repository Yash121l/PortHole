import AppKit
import SwiftUI

/// A floating panel that can take keyboard focus (plain panel/borderless
/// windows refuse key status by default, which would break the search field
/// and the ⏎/⌫ row shortcuts).
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Single source of truth for the port list, shared by the MenuBarExtra
    /// panel, the Settings window, and the hotkey panel below.
    let viewModel = PortListViewModel(scanner: LsofPortScanner(),
                                      terminator: ProcessController(),
                                      settings: .shared)

    private var hotKey: HotKeyManager?
    private var panel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist ships LSUIElement = YES (menu-bar-only agent). The user
        // can opt into a Dock icon in Settings; apply their choice at launch.
        NSApp.setActivationPolicy(SettingsStore.shared.showDockIcon ? .regular : .accessory)

        // Global ⌥⌘P opens the panel from anywhere — even over a fullscreen app
        // or when the menu-bar icon is hidden behind the notch. The MenuBarExtra
        // panel is anchored to that icon and can't be shown when it's hidden, so
        // this floating panel is the app's reliable way in.
        hotKey = HotKeyManager(keyCode: HotKeyManager.keyP,
                               modifiers: HotKeyManager.optionKey | HotKeyManager.cmdKey) { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - Hotkey panel

    func togglePanel() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        // Activate so the panel holds key focus (the search field and ⏎/⌫
        // shortcuts need it) and only auto-closes when the user clicks away.
        // We're an accessory app whose only window is a .fullScreenAuxiliary
        // panel, so activating overlays the current space — including a
        // frontmost fullscreen app — without switching out of it.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> FloatingPanel {
        let settings = SettingsStore.shared
        let root = PortListView(viewModel: viewModel, settings: settings)
            .preferredColorScheme(settings.appearance.colorScheme)
            .tint(settings.accentTint.color)
            // The window is clear (for rounded corners), so the content must
            // carry its own background — otherwise whatever is behind the panel
            // shows straight through. Frosted material matches the native
            // menu-bar panel's look.
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        // .canJoinAllSpaces + .fullScreenAuxiliary lets the panel float over the
        // current space, including a frontmost fullscreen app. (These two are
        // mutually exclusive with .moveToActiveSpace — don't add it.)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let hosting = NSHostingController(rootView: root)
        panel.contentViewController = hosting
        // Assigning a contentViewController resizes the window to the hosting
        // view's (initially zero) fitting size, so pin the size explicitly.
        panel.setContentSize(NSSize(width: 400, height: 500))

        // Transient: close when it loses focus, like the menu-bar panel does.
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey(_:)),
            name: NSWindow.didResignKeyNotification, object: panel)
        return panel
    }

    @objc private func panelResignedKey(_ note: Notification) {
        (note.object as? NSWindow)?.orderOut(nil)
    }

    /// Top-right of the screen under the pointer, just below the menu bar —
    /// where a menu-bar app's window naturally belongs.
    private func position(_ panel: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: visible.maxX - size.width - 12,
                             y: visible.maxY - size.height - 12)
        panel.setFrameOrigin(origin)
    }
}
