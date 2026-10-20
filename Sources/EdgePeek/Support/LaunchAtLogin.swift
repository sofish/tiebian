import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    static var requiresApproval: Bool {
        status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isRegistered else { return }
            try SMAppService.mainApp.register()
        } else {
            guard isRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
