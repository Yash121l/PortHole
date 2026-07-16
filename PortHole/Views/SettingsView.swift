import SwiftUI

/// Mac-standard tabbed preferences window.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var viewModel: PortListViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            AppearanceSettingsTab(settings: settings)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
            MenuBarSettingsTab(settings: settings)
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }
            PortLabelsSettingsTab(settings: settings)
                .tabItem {
                    Label("Port Labels", systemImage: "tag")
                }
            NotificationSettingsTab(settings: settings)
                .tabItem {
                    Label("Notifications", systemImage: "bell.badge")
                }
        }
        .frame(width: 520)
        // The menu-bar badge and exposed warning need scans even while the
        // panel is closed; re-plan the polling loop whenever that changes.
        .onChange(of: settings.needsBackgroundScanning) {
            viewModel.rescheduleRefreshLoop()
        }
        .onChange(of: settings.refreshInterval) {
            viewModel.rescheduleRefreshLoop()
        }
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore

    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var didLoadLoginState = false

    var body: some View {
        Form {
            Section("Refreshing") {
                Picker("Refresh ports", selection: $settings.refreshInterval) {
                    ForEach(SettingsStore.RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                Text("The list always refreshes when the panel opens. Polling pauses while the panel is closed unless a menu-bar badge or notification needs fresh data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Killing Processes") {
                Toggle("Ask before killing a process", isOn: $settings.confirmBeforeKill)
                Toggle("Escalate to SIGKILL automatically", isOn: $settings.autoEscalateToSigkill)
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $settings.killGracePeriod, in: 1...10, step: 0.5) {
                        Text("SIGTERM grace period")
                    } minimumValueLabel: {
                        Text("1s")
                    } maximumValueLabel: {
                        Text("10s")
                    }
                    Text("Wait \(settings.killGracePeriod, specifier: "%.1f") seconds for a process to exit cleanly after SIGTERM\(settings.autoEscalateToSigkill ? ", then force-kill it." : " before offering Force Kill.")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("App") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show Dock icon", isOn: $settings.showDockIcon)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            didLoadLoginState = true
        }
        .onChange(of: launchAtLogin) { _, newValue in
            guard didLoadLoginState else { return }
            do {
                try LaunchAtLogin.set(enabled: newValue)
            } catch {
                launchAtLoginError = error.localizedDescription
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
        .alert("Couldn’t Update Login Item",
               isPresented: Binding(
                   get: { launchAtLoginError != nil },
                   set: { if !$0 { launchAtLoginError = nil } }
               )) {
            Button("OK", role: .cancel) { launchAtLoginError = nil }
        } message: {
            Text(launchAtLoginError ?? "")
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(SettingsStore.Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                Picker("Accent tint", selection: $settings.accentTint) {
                    ForEach(SettingsStore.AccentTint.allCases) { tint in
                        Text(tint.title).tag(tint)
                    }
                }
                Picker("Row density", selection: $settings.rowDensity) {
                    ForEach(SettingsStore.RowDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Show in Each Row") {
                Toggle("PID", isOn: $settings.showPID)
                Toggle("Protocol badge", isOn: $settings.showProtocolBadge)
                Toggle("Owning user", isOn: $settings.showUser)
                Toggle("Process uptime", isOn: $settings.showUptime)
                Toggle("Executable path", isOn: $settings.showPath)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Menu Bar

struct MenuBarSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Icon", selection: $settings.menuBarIconStyle) {
                    ForEach(SettingsStore.MenuBarIconStyle.allCases) { style in
                        Label(style.title, systemImage: style.symbol).tag(style)
                    }
                }
                Toggle("Show listening-port count", isOn: $settings.showPortCountBadge)
            }

            Section {
                Toggle("Warn when a port is exposed to the network", isOn: $settings.warnExposedInMenuBar)
                Text("Swaps the menu-bar icon (and tints it orange where macOS allows) whenever something listens beyond localhost.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

struct NotificationSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("When a new port starts listening", isOn: $settings.notifyOnNewPort)
                Toggle("When a port is exposed to the network", isOn: $settings.notifyOnExposedPort)
            } footer: {
                Text("Bursts of new ports are collapsed into a single summary notification. Notification permission is requested the first time you enable one of these.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.notifyOnNewPort) { _, enabled in
            if enabled { NotificationManager.shared.requestAuthorization() }
        }
        .onChange(of: settings.notifyOnExposedPort) { _, enabled in
            if enabled { NotificationManager.shared.requestAuthorization() }
        }
    }
}

// MARK: - Port Labels

/// Master-detail: the list shows lightweight read-only rows and the editor
/// below binds to the selected rule. The previous design embedded two text
/// fields and an AppKit popup in *every* row, which made the list scroll
/// jankily and re-encoded the whole rule set on each keystroke's re-layout.
struct PortLabelsSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rules attach a label and color to a port. A rule matches on the port number; add a process fragment to narrow it (e.g. 5000 + “python” → Flask, so AirPlay doesn’t match). Live inference from the running command may override port-only rules.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selection) {
                ForEach(settings.labelRules) { rule in
                    RuleRowView(rule: rule)
                        .tag(rule.id)
                }
            }
            .frame(minHeight: 240)
            .onDeleteCommand { removeSelectedRule() }

            HStack(spacing: 8) {
                Button {
                    let rule = PortLabelRule(port: 0, label: "New rule")
                    settings.labelRules.insert(rule, at: 0)
                    selection = rule.id
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a rule")
                .accessibilityLabel("Add rule")

                Button {
                    removeSelectedRule()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                .help("Remove the selected rule (⌫)")
                .accessibilityLabel("Remove selected rule")

                Spacer()

                Button("Restore Defaults") {
                    settings.labelRules = PortLabelRule.defaultRules
                    selection = nil
                }
            }

            Divider()

            if let ruleBinding = selectedRuleBinding {
                RuleEditorView(rule: ruleBinding)
            } else {
                Text("Select a rule to edit it.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .padding(20)
    }

    private func removeSelectedRule() {
        guard let selection else { return }
        settings.labelRules.removeAll { $0.id == selection }
        self.selection = nil
    }

    /// Looks the rule up by id on every access so the binding can never hold
    /// a stale index into a mutated array.
    private var selectedRuleBinding: Binding<PortLabelRule>? {
        guard let selection,
              settings.labelRules.contains(where: { $0.id == selection }) else { return nil }
        return Binding(
            get: {
                settings.labelRules.first { $0.id == selection }
                    ?? PortLabelRule(port: 0, label: "")
            },
            set: { newValue in
                if let index = settings.labelRules.firstIndex(where: { $0.id == selection }) {
                    settings.labelRules[index] = newValue
                }
            }
        )
    }
}

/// Read-only, layout-cheap row: plain text and a capsule — nothing that
/// bridges to AppKit controls.
private struct RuleRowView: View {
    let rule: PortLabelRule

    var body: some View {
        HStack(spacing: 10) {
            Text(rule.port == 0 ? "—" : String(rule.port))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 56, alignment: .leading)

            Text(rule.label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(RuleColor.color(named: rule.colorName).opacity(0.18), in: Capsule())
                .foregroundStyle(RuleColor.color(named: rule.colorName))

            if !rule.processHint.isEmpty {
                Text("process contains “\(rule.processHint)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Port \(rule.port), \(rule.label)\(rule.processHint.isEmpty ? "" : ", process contains \(rule.processHint)")")
    }
}

private struct RuleEditorView: View {
    @Binding var rule: PortLabelRule

    var body: some View {
        HStack(spacing: 8) {
            TextField("Port", value: $rule.port, format: .number.grouping(.never))
                .frame(width: 70)
                .accessibilityLabel("Port number")
            TextField("Label", text: $rule.label)
                .frame(minWidth: 140)
                .accessibilityLabel("Label")
            Picker("Color", selection: $rule.colorName) {
                ForEach(RuleColor.allNames, id: \.self) { name in
                    Text(name.capitalized).tag(name)
                }
            }
            .labelsHidden()
            .frame(width: 96)
            .accessibilityLabel("Label color")
            TextField("Process contains…", text: $rule.processHint)
                .frame(minWidth: 120)
                .accessibilityLabel("Process name filter")
        }
        .textFieldStyle(.roundedBorder)
        .frame(minHeight: 52)
    }
}
