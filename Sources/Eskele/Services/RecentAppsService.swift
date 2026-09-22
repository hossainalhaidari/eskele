import AppKit

/// A most-recently-used list of applications.
///
/// Kept ourselves rather than read from the system: the Dock's own recents live in a shared file
/// list with no public read API. Observing activations costs nothing and starts working immediately.
@MainActor
final class RecentAppsService {
    private(set) var bundleIDs: [String] = []

    private let persistence: Persistence
    private let limit: Int
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    private let ownBundleID = Bundle.main.bundleIdentifier

    init(persistence: Persistence, limit: Int = 20) {
        self.persistence = persistence
        self.limit = limit
        bundleIDs = persistence.loadRecents()
        seedFromRunningApps()

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            // Pull the identifier out before hopping actors: the notification itself is not Sendable.
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.note(id) }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// Without this the menu is empty until the user has switched apps a few times, which reads as
    /// broken rather than new.
    private func seedFromRunningApps() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
        for id in running where !bundleIDs.contains(id) {
            bundleIDs.append(id)
        }
        bundleIDs = Array(bundleIDs.prefix(limit))
    }

    func note(_ bundleID: String) {
        guard bundleID != ownBundleID else { return }
        var updated = bundleIDs.filter { $0 != bundleID }
        updated.insert(bundleID, at: 0)
        bundleIDs = Array(updated.prefix(limit))
        persistence.saveRecents(bundleIDs)
    }

    /// Resolves to installed apps, dropping anything that has since been uninstalled.
    func entries() -> [CatalogEntry] {
        bundleIDs.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return nil
            }
            let name = FileManager.default.displayName(atPath: url.path)
            return CatalogEntry(url: url, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
        }
    }
}
