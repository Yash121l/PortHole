import SwiftUI

@main
struct PortHoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var viewModel: PortListViewModel

    private var settings: SettingsStore { SettingsStore.shared }

    init() {
        _viewModel = State(initialValue: PortListViewModel(
            scanner: LsofPortScanner(),
            terminator: ProcessController(),
            settings: SettingsStore.shared
        ))
    }

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
