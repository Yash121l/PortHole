import SwiftUI

/// The panel that drops down from the menu-bar icon.
///
/// Deliberately split into small subviews: with @Observable, each subview's
/// body only re-runs when a property *it reads* changes. Keeping the header
/// (spinner), footer (timestamp), and list in separate views means a
/// background scan tick re-renders a line of text — not every row — which is
/// what keeps scrolling smooth.
struct PortListView: View {
    @Bindable var viewModel: PortListViewModel
    @Bindable var settings: SettingsStore

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                PanelHeaderView(viewModel: viewModel)
                PanelSearchField(viewModel: viewModel)
                Divider()
                PanelFilterBar(viewModel: viewModel)
                Divider()
                PanelContentView(viewModel: viewModel, settings: settings)
                Divider()
                PanelFooterView(viewModel: viewModel)
            }
            // Freeze the content while a dialog is up: blocks clicks and keeps
            // the list's ⏎/⌫ key handlers from stealing the dialog's shortcuts.
            .disabled(dialogIsPresented)

            // Confirm-before-kill (toggleable in Settings → General) and kill
            // outcomes that need attention (EPERM, survived SIGTERM…). These
            // are drawn in-panel instead of via .confirmationDialog/.alert:
            // window-hosted presentations inside a MenuBarExtra window swallow
            // their button actions — the click makes the panel resign key and
            // close before SwiftUI delivers the action, so the kill never ran.
            if let port = viewModel.pendingKill {
                PanelDialogOverlay(
                    title: "Kill \(port.processName)?",
                    message: "This sends SIGTERM to \(port.processName), which is listening on port \(String(port.port)).",
                    onDismiss: { viewModel.pendingKill = nil }
                ) {
                    Button {
                        viewModel.confirmPendingKill()
                    } label: {
                        Text("Kill \(port.processName) (PID \(String(port.pid)))")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)

                    Button {
                        viewModel.pendingKill = nil
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                }
            } else if let message = viewModel.killMessage {
                PanelDialogOverlay(
                    title: "PortHole",
                    message: message,
                    onDismiss: { viewModel.killMessage = nil }
                ) {
                    Button {
                        viewModel.killMessage = nil
                    } label: {
                        Text("OK")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear { viewModel.panelAppeared() }
        .onDisappear { viewModel.panelDisappeared() }
        .onChange(of: settings.refreshInterval) {
            viewModel.rescheduleRefreshLoop()
        }
    }

    private var dialogIsPresented: Bool {
        viewModel.pendingKill != nil || viewModel.killMessage != nil
    }
}

// MARK: - In-panel dialog

/// Alert-style card drawn inside the panel's own window. Same-window rendering
/// is what makes the buttons reliable here (see the note at the use site);
/// clicking the dimmed backdrop or pressing Esc dismisses.
private struct PanelDialogOverlay<Actions: View>: View {
    let title: String
    let message: String
    var onDismiss: () -> Void
    @ViewBuilder var actions: Actions

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.3))
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 6) {
                    actions
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .padding(16)
            .frame(width: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .accessibilityAddTraits(.isModal)
        }
        .onExitCommand(perform: onDismiss)
    }
}

// MARK: - Header

private struct PanelHeaderView: View {
    @Bindable var viewModel: PortListViewModel

    /// "8 of 28 ports" whenever filtering hides rows — a filtered-down list
    /// must never read as an empty or broken scan.
    private var countText: String {
        let shown = viewModel.filteredPorts.count
        let total = viewModel.portCount
        if shown == total {
            return "\(shown) \(shown == 1 ? "port" : "ports")"
        }
        return "\(shown) of \(total) ports"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(countText)
                .font(.headline)
                .contentTransition(.numericText())
                .accessibilityLabel("\(viewModel.filteredPorts.count) of \(viewModel.portCount) listening ports shown")

            // Always present (opacity-toggled) so the header never reflows
            // when a user-initiated scan starts.
            ProgressView()
                .controlSize(.small)
                .opacity(viewModel.isScanning ? 1 : 0)
                .accessibilityLabel("Scanning")
                .accessibilityHidden(!viewModel.isScanning)

            Spacer()

            Menu {
                Picker("Sort By", selection: $viewModel.sortOrder) {
                    ForEach(PortListViewModel.SortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Group by App", isOn: $viewModel.groupByProcess)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sort and grouping")
            .accessibilityLabel("Sort and grouping options")

            Button {
                Task { await viewModel.refresh(userInitiated: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh now (⌘R)")
            .accessibilityLabel("Refresh")

            Menu {
                SettingsLink {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
                .simultaneousGesture(TapGesture().onEnded {
                    // Menu-bar-only apps aren't active when the panel opens;
                    // activating makes the Settings window come to the front.
                    NSApp.activate(ignoringOtherApps: true)
                })
                Divider()
                Button("Quit PortHole") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Settings and app menu")
            .accessibilityLabel("App menu")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Search

private struct PanelSearchField: View {
    @Bindable var viewModel: PortListViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter by port, process, or PID", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Filter ports")
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Filter chips

private struct PanelFilterBar: View {
    @Bindable var viewModel: PortListViewModel

    var body: some View {
        HStack(spacing: 6) {
            FilterChip(title: "TCP", isOn: $viewModel.showTCP)
            FilterChip(title: "UDP", isOn: $viewModel.showUDP)
            FilterChip(title: "Exposed only", systemImage: "globe", isOn: $viewModel.exposedOnly)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Content

private struct PanelContentView: View {
    @Bindable var viewModel: PortListViewModel
    @Bindable var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let error = viewModel.scanError {
            ContentUnavailableView {
                Label("Scan Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.refresh(userInitiated: true) }
                }
            }
        } else if viewModel.filteredPorts.isEmpty {
            if viewModel.ports.isEmpty {
                ContentUnavailableView {
                    Label("No Listening Ports", systemImage: "powerplug")
                } description: {
                    Text("Nothing is listening for connections right now.")
                }
            } else {
                noMatchesView
            }
        } else {
            list
        }
    }

    /// Empty state for "ports exist, but the filter hides them all". The
    /// stock `.search` copy ("Check the spelling…") is wrong for a port
    /// scanner — for a numeric query the honest answer is that nothing is
    /// listening there.
    private var noMatchesView: some View {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespaces)
        return ContentUnavailableView {
            Label("No Matches", systemImage: "magnifyingglass")
        } description: {
            if query.isEmpty {
                Text("No ports match the current filters.")
            } else if let portNumber = Int(query), (0...65535).contains(portNumber) {
                Text("Nothing is listening on port \(String(portNumber)).")
            } else {
                Text("No port, process, or PID matches “\(query)”.")
            }
        } actions: {
            Button("Clear Filters") {
                viewModel.clearFilters()
            }
        }
    }

    private var list: some View {
        List(selection: $viewModel.selection) {
            if viewModel.groupByProcess {
                ForEach(viewModel.groupedPorts) { group in
                    Section {
                        ForEach(group.ports) { port in
                            PortRowView(port: port,
                                        viewModel: viewModel,
                                        settings: settings,
                                        showsProcessName: false)
                                .tag(port.id)
                        }
                    } header: {
                        HStack(spacing: 5) {
                            if let first = group.ports.first {
                                AppIconView(port: first, size: 14)
                            }
                            Text("\(group.processName) — PID \(String(group.pid))")
                        }
                    }
                }
            } else {
                ForEach(viewModel.filteredPorts) { port in
                    PortRowView(port: port, viewModel: viewModel, settings: settings)
                        .tag(port.id)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // Keyed to the structural-change counter, not the array: rows animate
        // in/out, but metadata refreshes never start a list-wide animation.
        .animation(reduceMotion ? nil : .default, value: viewModel.structuralChanges)
        // Keyboard: arrows move the List selection natively; ⌫ kills the
        // selected row; ⏎ opens likely-HTTP ports in the browser.
        .onDeleteCommand {
            if let selected = viewModel.selectedPort {
                viewModel.requestKill(selected)
            }
        }
        .onKeyPress(.return) {
            guard let selected = viewModel.selectedPort, selected.likelyServesHTTP else {
                return .ignored
            }
            viewModel.openInBrowser(selected)
            return .handled
        }
    }
}

// MARK: - Footer

private struct PanelFooterView: View {
    var viewModel: PortListViewModel

    var body: some View {
        HStack {
            if let last = viewModel.lastRefresh {
                Text("Updated \(Formatting.timeOnly.string(from: last))")
            } else {
                Text("Scanning…")
            }
            Spacer()
            Text("⌫ kill · ⏎ open")
                .accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

/// Small capsule toggle used for the TCP/UDP/Exposed filter chips.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isOn ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                        in: Capsule())
            .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .help(isOn ? "Hide: \(title)" : "Show: \(title)")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
