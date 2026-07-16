import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist ships LSUIElement = YES (menu-bar-only agent). The user
        // can opt into a Dock icon in Settings; apply their choice at launch.
        NSApp.setActivationPolicy(SettingsStore.shared.showDockIcon ? .regular : .accessory)
    }
}
