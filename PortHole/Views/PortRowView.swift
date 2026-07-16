import SwiftUI

/// One socket row: prominent port number, protocol badge, bind-scope
/// indicator, label chip, process details, and inline/context actions.
struct PortRowView: View {
    let port: ListeningPort
    var viewModel: PortListViewModel
    var settings: SettingsStore
    /// Hidden when the row is inside a per-process group header context.
    var showsProcessName: Bool = true

    @State private var isHovering = false

    private var rule: PortLabelRule? { settings.rule(for: port) }
    private var isPinned: Bool { settings.isPinned(port.port) }
    private var survivedSigterm: Bool { viewModel.survivedSigterm.contains(port.id) }

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(port: port)

            VStack(alignment: .leading, spacing: 2) {
                primaryLine
                secondaryLine
            }

            Spacer(minLength: 4)

            if isHovering {
                inlineActions
            } else if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.vertical, settings.rowDensity == .compact ? 1 : 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Lines

    private var primaryLine: some View {
        HStack(spacing: 6) {
            Text(String(port.port))
                .font(.system(.body, design: .monospaced).weight(.semibold))

            if settings.showProtocolBadge {
                Text(port.networkProtocol.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.secondary)
            }

            if let rule {
                Text(rule.label)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RuleColor.color(named: rule.colorName).opacity(0.18),
                                in: Capsule())
                    .foregroundStyle(RuleColor.color(named: rule.colorName))
            }

            bindScopeBadge

            if survivedSigterm {
                Text("SIGTERM sent")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Loopback vs all-interfaces indicator. "Exposed" (reachable from the
    /// network) is the security-relevant state, so it gets color + a word,
    /// not just an icon.
    @ViewBuilder
    private var bindScopeBadge: some View {
        switch port.bindScope {
        case .loopback:
            Image(systemName: "house.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("Bound to \(port.bindAddress) — reachable from this Mac only")
                .accessibilityLabel("Loopback only")
        case .allInterfaces, .specificInterface:
            HStack(spacing: 2) {
                Image(systemName: "globe")
                Text("Exposed")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .help("Bound to \(port.bindAddress) — reachable from other machines on the network")
            .accessibilityLabel("Exposed to the network")
        }
    }

    private var secondaryLine: some View {
        HStack(spacing: 4) {
            if showsProcessName {
                Text(port.processName)
            }
            if settings.showPID {
                Text("PID \(String(port.pid))")
            }
            if settings.showUser, let user = port.user {
                Text(user)
            }
            if settings.showUptime, let start = port.processStartDate {
                Text("up \(Formatting.uptime(since: start))")
            }
            Text(port.bindAddress)
            if settings.showPath, let path = port.executablePath {
                Text(path)
                    .truncationMode(.middle)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    // MARK: Actions

    private var inlineActions: some View {
        HStack(spacing: 2) {
            Button {
                settings.togglePin(port.port)
            } label: {
                Image(systemName: isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.borderless)
            .help(isPinned ? "Unpin port \(port.port)" : "Pin port \(port.port) to the top")
            .accessibilityLabel(isPinned ? "Unpin" : "Pin")

            if port.likelyServesHTTP {
                Button {
                    viewModel.openInBrowser(port)
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .help("Open http://localhost:\(port.port) in the browser")
                .accessibilityLabel("Open in browser")
            }

            if survivedSigterm {
                Button {
                    Task { await viewModel.forceKill(port) }
                } label: {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Force Kill (SIGKILL) \(port.processName)")
                .accessibilityLabel("Force kill \(port.processName)")
            } else {
                Button {
                    viewModel.requestKill(port)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Kill \(port.processName) (PID \(port.pid))")
                .accessibilityLabel("Kill \(port.processName)")
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Kill \(port.processName)") {
            viewModel.requestKill(port)
        }
        Button("Force Kill (SIGKILL)") {
            Task { await viewModel.forceKill(port) }
        }
        Divider()
        Button("Copy Port") {
            viewModel.copyToPasteboard(String(port.port))
        }
        Button("Copy PID") {
            viewModel.copyToPasteboard(String(port.pid))
        }
        Button("Copy Command") {
            viewModel.copyToPasteboard(port.executablePath ?? port.processName)
        }
        Divider()
        if port.likelyServesHTTP {
            Button("Open in Browser") {
                viewModel.openInBrowser(port)
            }
        }
        if port.executablePath != nil {
            Button("Reveal in Finder") {
                viewModel.revealInFinder(port)
            }
        }
        Divider()
        Button(isPinned ? "Unpin Port \(port.port)" : "Pin Port \(port.port)") {
            settings.togglePin(port.port)
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            "Port \(port.port)",
            port.networkProtocol.rawValue,
            port.processName,
            "PID \(port.pid)",
        ]
        if let rule { parts.append(rule.label) }
        parts.append(port.isExposed ? "exposed to the network" : "loopback only")
        if isPinned { parts.append("pinned") }
        return parts.joined(separator: ", ")
    }
}

/// The owning app's real icon where the executable maps to a bundle or a
/// running GUI app; a generic executable icon otherwise.
struct AppIconView: View {
    let port: ListeningPort
    var size: CGFloat = 22

    var body: some View {
        Image(nsImage: AppIconResolver.shared.icon(pid: port.pid,
                                                   executablePath: port.executablePath))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
