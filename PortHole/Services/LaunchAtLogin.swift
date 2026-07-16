import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService — the supported ServiceManagement API.
/// (The legacy LSSharedFileList / SMLoginItemSetEnabled routes are deprecated
/// and deliberately not used.)
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
