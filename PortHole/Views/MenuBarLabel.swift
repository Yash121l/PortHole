import SwiftUI

/// The status-item content. Note: the menu bar renders status-item images as
/// template images, so explicit colors are best-effort — the exposed-port
/// warning therefore also *swaps the symbol*, so the state reads even when
/// the system strips the tint.
struct MenuBarLabel: View {
    var viewModel: PortListViewModel
    var settings: SettingsStore

    var body: some View {
        let warnExposed = settings.warnExposedInMenuBar && viewModel.hasExposedPorts
        HStack(spacing: 3) {
            Image(systemName: warnExposed ? settings.menuBarIconStyle.exposedSymbol
                                          : settings.menuBarIconStyle.symbol)
            if settings.showPortCountBadge, viewModel.portCount > 0 {
                Text(String(viewModel.portCount))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        // Best-effort tint (see note above — the system may render this as a
        // template regardless; the symbol swap carries the state either way).
        .foregroundStyle(warnExposed ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
        .accessibilityLabel(warnExposed
            ? "PortHole, \(viewModel.portCount) listening ports, some exposed to the network"
            : "PortHole, \(viewModel.portCount) listening ports")
    }
}
