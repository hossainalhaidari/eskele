import AppKit
import ServiceManagement

/// Launch-at-login through `SMAppService`.
@MainActor
enum LoginItemService {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// `requiresApproval` means the user disabled it in System Settings ▸ General ▸ Login Items;
    /// re-registering will not override that, so the caller should say so rather than silently fail.
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            NSLog("Eskele: login item \(enabled ? "registration" : "removal") failed — \(error)")
            return .failure(error)
        }
    }
}
