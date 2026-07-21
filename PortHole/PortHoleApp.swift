import SwiftUI

@main
struct PortHoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var settings: SettingsStore { SettingsStore.shared }
    /// Owned by the app delegate so the MenuBarExtra panel, the Settings
    /// window, and the global-hotkey panel all drive one instance.
    private var viewModel: PortListViewModel { appDelegate.viewModel }

    var body: some Scene {
        MenuBarExtra {
            PortListView(viewModel: viewModel, settings: settings)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(settings.accentTint.color)
        } label: {
            MenuBarLabel(viewModel: viewModel, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, viewModel: viewModel)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(settings.accentTint.color)
        }
    }
}
