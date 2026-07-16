import Foundation

/// Abstraction over "give me every listening socket on this machine".
///
/// v1 ships an `lsof`-backed implementation (`LsofPortScanner`). Keeping the
/// UI and view model against this protocol means a future sandbox-friendly
/// implementation built on `libproc`/`proc_pidinfo` can replace it without
/// touching anything above this layer.
protocol PortScanning: Sendable {
    func scan() async throws -> [ListeningPort]
}

/// Error surfaced to the UI when a scan cannot complete (e.g. `lsof` missing
/// or failing to launch).
struct PortScanError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}
