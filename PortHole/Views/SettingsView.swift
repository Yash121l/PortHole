import SwiftUI

/// Mac-standard tabbed preferences window. Milestone 1 ships the General and
/// Appearance basics; the remaining tabs are completed in milestone 5.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var viewModel: PortListViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings, viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            AppearanceSettingsTab(settings: settings)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 460)
    }
}

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    var viewModel: PortListViewModel

    var body: some View {
        Form {
            Picker("Refresh ports", selection: $settings.refreshInterval) {
                ForEach(SettingsStore.RefreshInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }

            Divider()

            Toggle("Ask before killing a process", isOn: $settings.confirmBeforeKill)
        }
        .padding(20)
    }
}

struct AppearanceSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(SettingsStore.Appearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }

            Picker("Row density", selection: $settings.rowDensity) {
                ForEach(SettingsStore.RowDensity.allCases) { density in
                    Text(density.title).tag(density)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
    }
}
