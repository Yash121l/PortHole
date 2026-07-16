# PortHole

A native macOS menu bar utility that shows every port currently **listening** on your Mac, which process owns it, and lets you **kill that process with one click**. Built with Swift + SwiftUI to feel like a first-party Mac app — native controls and materials, full keyboard navigation, VoiceOver labels, light/dark/accent-aware.

## What it does

- **Live port list** — every TCP listener and bound UDP socket, refreshed automatically (1s/2s/5s/manual), diffed between scans so the list updates incrementally without flicker.
- **Process mapping** — each port shows its owning process with the real app icon, PID, owning user, uptime, bind address, and executable path (each field toggleable).
- **One-click kill** — SIGTERM first, then a configurable grace period, then optional SIGKILL escalation (or an explicit Force Kill button). Confirmation is on by default and can be turned off.
- **Exposure at a glance** — sockets bound beyond localhost (`0.0.0.0`, `*`, or a LAN IP) are flagged **Exposed** in orange; the menu bar icon can warn too, and a filter chip shows exposed ports only.
- **Port labels** — well-known dev ports get human labels ("Vite", "Postgres", "Ollama"…); the rule set (port + optional process hint → label + color) is fully editable in Settings.
- **Row actions** — kill, copy port/PID/command, open `http://localhost:<port>` for likely-HTTP ports, reveal executable in Finder, pin ports to the top. All available inline on hover and via right-click.
- **Search, filter, sort, group** — filter by port/process/PID, TCP/UDP chips, sort by port/process/PID/recently-appeared, optional group-by-app view.
- **Notifications (optional)** — when a new port starts listening, or when a port shows up exposed to the network. Bursts collapse into a single summary.
- **Menu bar** — choice of icon, optional listening-port count badge, optional exposed-port warning state.
- Menu-bar-only by default (`LSUIElement`); Dock icon and launch-at-login (via `SMAppService`) are toggles in Settings.

## Keyboard

| Key | Action |
| --- | --- |
| ↑ / ↓ | Move selection |
| ⌫ | Kill the selected process |
| ⏎ | Open the selected port in the browser (likely-HTTP ports) |
| ⌘R | Refresh now |
| ⌘, | Settings |
| ⌘Q | Quit |

## Build & run

Requirements: **Xcode 16 or newer**, macOS 14+ deployment target.

```bash
git clone https://github.com/Yash121l/PortHole.git
cd PortHole
open PortHole.xcodeproj   # then ⌘R
```

Or from the command line:

```bash
xcodebuild -project PortHole.xcodeproj -scheme PortHole -configuration Release build
xcodebuild -project PortHole.xcodeproj -scheme PortHole test   # unit + live integration tests
```

The app appears in the menu bar (no Dock icon). Click the icon to open the panel.

## Architecture

| Component | Role |
| --- | --- |
| `PortHoleApp` | `MenuBarExtra(.window)` + `Settings` scenes |
| `PortScanning` / `LsofPortScanner` | Scanner protocol; v1 implementation is an actor that shells out to `lsof` off the main thread |
| `LsofParser` | Pure parser for `lsof -F` field output (unit-tested against captured fixtures) |
| `PortDiff` | Scan-to-scan diff keyed by stable socket identity; no-change scans skip UI writes entirely |
| `ProcessController` | `kill(2)` wrapper: SIGTERM → grace poll → optional SIGKILL, EPERM/ESRCH mapping |
| `AppIconResolver` | pid/executable path → real app icon via NSRunningApplication / NSWorkspace, cached |
| `SettingsStore` | `@Observable`, UserDefaults-backed settings (incl. JSON-encoded label rules, pinned ports) |
| `PortListViewModel` | Filtering, sorting, scheduling, kill flow — views stay declarative |

The scanner sits behind the `PortScanning` protocol specifically so a future sandbox-permissible implementation (`libproc`-based) can replace the `lsof` one without touching the UI.

## Distribution & sandbox constraints

**This app cannot ship to the Mac App Store in its current form.** It shells out to `/usr/sbin/lsof` (system-provided) and sends signals to arbitrary processes — both incompatible with the App Sandbox. The intended distribution is:

- **Developer ID signing + notarization**, shipped as a DMG.
- No sandbox entitlement; hardened runtime enabled. No other special entitlements are required.
- `LSUIElement` is set in the Info.plist (generated via build settings), which is what makes it a menu-bar-only agent app.

If App Store distribution is ever required, that's a separate track: port enumeration must move to `libproc`/`proc_pidinfo` (sandbox-permissible for the user's own processes) and killing other users' processes must be dropped.

## Known limitations

- **Processes owned by other users / root:** `kill(2)` returns `EPERM`, and PortHole surfaces "*owned by another user and requires elevated privileges*" rather than failing silently. Actually killing those would need a privileged helper (SMAppService daemon + Authorization Services) — deliberately not built in v1. The same applies to some SIP-protected system processes.
- **"Copy Command" copies the executable path** (or process name when the path can't be resolved), not the full argv command line.
- **Menu bar tinting:** macOS renders status-item content as template images in most configurations, so the orange exposed-port tint is best-effort — the icon *shape* also changes so the state is always visible.
- **UDP semantics:** UDP has no LISTEN state; PortHole shows UDP sockets bound to a fixed local port and skips connected (`->`) and wildcard-port (`*:*`) sockets.
- Uptime/start-time and executable path come from `libproc` and may be unavailable for other users' processes; those fields show as absent.

## Tests

`PortHoleTests` covers the `lsof -F` parser (fixtures captured from real runs), the scan differ, bind-scope classification, label-rule matching, HTTP heuristics, uptime formatting, and libproc lookups — plus a live integration test that spawns `nc -l`, watches the real scanner find it, kills it through the real controller, and asserts it disappears.

## License

MIT
