import SwiftUI

/// The panel that drops down from the menu-bar icon.
struct PortListView: View {
    @Bindable var viewModel: PortListViewModel
    @Bindable var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            filterBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 400, height: 500)
        .onAppear { viewModel.panelAppeared() }
        .onDisappear { viewModel.panelDisappeared() }
        .onChange(of: settings.refreshInterval) {
            viewModel.rescheduleRefreshLoop()
        }
        // Confirm-before-kill (toggleable in Settings → General).
        .confirmationDialog(
            "Kill \(viewModel.pendingKill?.processName ?? "process")?",
            isPresented: Binding(
                get: { viewModel.pendingKill != nil },
                set: { if !$0 { viewModel.pendingKill = nil } }
            ),
            presenting: viewModel.pendingKill
        ) { port in
            Button("Kill \(port.processName) (PID \(port.pid))", role: .destructive) {
                viewModel.confirmPendingKill()
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingKill = nil
            }
        } message: { port in
            Text("This sends SIGTERM to \(port.processName), which is listening on port \(port.port).")
        }
        // Kill outcomes that need the user's attention (EPERM, survived SIGTERM…).
        .alert(
            "PortHole",
            isPresented: Binding(
                get: { viewModel.killMessage != nil },
                set: { if !$0 { viewModel.killMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.killMessage = nil }
        } message: {
            Text(viewModel.killMessage ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(viewModel.filteredPorts.count) \(viewModel.filteredPorts.count == 1 ? "port" : "ports")")
                .font(.headline)
                .contentTransition(.numericText())
                .accessibilityLabel("\(viewModel.filteredPorts.count) listening ports")

            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Scanning")
            }

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
                Task { await viewModel.refresh() }
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

    // MARK: Search

    private var searchField: some View {
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

    // MARK: Filter chips

    private var filterBar: some View {
        HStack(spacing: 6) {
            FilterChip(title: "TCP", isOn: $viewModel.showTCP)
            FilterChip(title: "UDP", isOn: $viewModel.showUDP)
            FilterChip(title: "Exposed only", systemImage: "globe", isOn: $viewModel.exposedOnly)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.scanError {
            ContentUnavailableView {
                Label("Scan Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.refresh() }
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
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        } else {
            list
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
                        Text("\(group.processName) — PID \(String(group.pid))")
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
        .animation(reduceMotion ? nil : .default, value: viewModel.ports)
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

    // MARK: Footer

    private var footer: some View {
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
