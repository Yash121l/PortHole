import SwiftUI

@main
struct PortHoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var viewModel: PortListViewModel

    private var settings: SettingsStore { SettingsStore.shared }

    init() {
        // Milestone 1 runs against mock data; milestone 2 swaps in the real
        // lsof-backed scanner and signal-based process controller.
        let scanner = MockPortScanner()
        let terminator = MockProcessTerminator(scanner: scanner)
        _viewModel = State(initialValue: PortListViewModel(
            scanner: scanner,
            terminator: terminator,
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
