import Foundation

public enum DockPrefKey {
    public static let autohide = "autohide"
    public static let autohideDelay = "autohide-delay"
    public static let autohideTimeModifier = "autohide-time-modifier"
    public static let orientation = "orientation"
    public static let tilesize = "tilesize"
    public static let launchAnimation = "launchanim"
    public static let noBouncing = "no-bouncing"
}

/// Screen space the system reserves for the Dock, exploited to give Eskele reserved space of its own.
///
/// A visible Dock reserves exactly `tilesize + 20` points along its edge. Parking one on the same
/// edge as the bar, sized to match and covered by it, makes maximized windows stop short of the
/// bar — something no public API offers.
public enum DockReservation {
    public static let offset: Double = 20
    /// `defaults` accepts tile sizes below the 16pt floor the Dock's own UI enforces.
    public static let minimumTileSize: Double = 1
    public static let maximumTileSize: Double = 128

    public static func tileSize(forReservedThickness thickness: Double) -> Double {
        min(maximumTileSize, max(minimumTileSize, (thickness - offset).rounded()))
    }

    public static func reservedThickness(forTileSize tileSize: Double) -> Double {
        tileSize + offset
    }
}

/// The values we write to make the system Dock unreachable.
///
/// `autohide-delay` is a reveal delay in seconds: with auto-hide on and the delay set to a value
/// no user will ever wait out, the Dock never comes back on a hover. `autohide-time-modifier: 0`
/// removes the slide animation so nothing flickers at the screen edge.
public enum DockSuppressionValues {
    public static let autohide = true
    public static let autohideDelay: Double = 1000
    public static let autohideTimeModifier: Double = 0
}

/// The values that park the Dock underneath the bar, for reserved-space mode.
///
/// The Dock stays **visible**, because only a visible Dock holds a reservation the system respects.
/// Measured on macOS 27: an auto-hidden Dock publishes a zero-height rect the next time it re-lays
/// out — which any app launching or quitting triggers — and although another process can publish a
/// rect of its own, the window server passes only the Dock's publications on to running apps. What
/// keeps a parked Dock out of sight is the bar, one window level above it and exactly as thick as
/// its reservation.
///
/// The launch and attention bounces are the only parts of a parked Dock that reach past its own
/// edge, so they are switched off. The auto-hide delay is kept for wherever the Dock auto-hides
/// regardless of this setting, a full-screen Space being the one that matters.
public enum DockParkingValues {
    public static let autohide = false
    public static let launchAnimation = false
    public static let noBouncing = true
}

/// The user's Dock preferences as they were *before* we touched them.
///
/// `nil` for a key means the key was absent, i.e. the Dock was using its built-in default; restoring
/// must remove the key rather than write a value, or we would silently make a default explicit.
public struct DockPrefsSnapshot: Codable, Equatable, Sendable {
    public var autohide: Bool?
    public var autohideDelay: Double?
    public var autohideTimeModifier: Double?
    public var orientation: String?
    public var tilesize: Double?
    public var launchAnimation: Bool?
    public var noBouncing: Bool?
    public var capturedAt: Date
    /// Set to `true` only once the values above have been written back successfully. A backup found
    /// on disk with this still `false` means we exited without restoring — see `recoverIfNeeded()`.
    public var cleanlyRestored: Bool
    /// Which keys this backup speaks for. `nil` is a backup written before `launchAnimation` and
    /// `noBouncing` existed: its `nil` for those means "never captured", not "absent", so restoring
    /// must leave them alone rather than remove them.
    public var schema: Int?

    public static let currentSchema = 2

    public init(
        autohide: Bool? = nil,
        autohideDelay: Double? = nil,
        autohideTimeModifier: Double? = nil,
        orientation: String? = nil,
        tilesize: Double? = nil,
        launchAnimation: Bool? = nil,
        noBouncing: Bool? = nil,
        capturedAt: Date = Date(),
        cleanlyRestored: Bool = false,
        schema: Int? = nil
    ) {
        self.autohide = autohide
        self.autohideDelay = autohideDelay
        self.autohideTimeModifier = autohideTimeModifier
        self.orientation = orientation
        self.tilesize = tilesize
        self.launchAnimation = launchAnimation
        self.noBouncing = noBouncing
        self.capturedAt = capturedAt
        self.cleanlyRestored = cleanlyRestored
        self.schema = schema
    }

    /// True when this backup captured the bounce keys, so restoring may write them back.
    var capturesBounceKeys: Bool { (schema ?? 1) >= 2 }
}

public protocol BackupStore: AnyObject, Sendable {
    func loadBackup() -> DockPrefsSnapshot?
    func saveBackup(_ snapshot: DockPrefsSnapshot?)
}

/// File-backed backup, written before the first preference change.
public final class FileBackupStore: BackupStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    public func loadBackup() -> DockPrefsSnapshot? {
        lock.withLock {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(DockPrefsSnapshot.self, from: data)
        }
    }

    public func saveBackup(_ snapshot: DockPrefsSnapshot?) {
        lock.withLock {
            guard let snapshot else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

public final class InMemoryBackupStore: BackupStore, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: DockPrefsSnapshot?
    public init(_ snapshot: DockPrefsSnapshot? = nil) { self.snapshot = snapshot }
    public func loadBackup() -> DockPrefsSnapshot? { lock.withLock { snapshot } }
    public func saveBackup(_ s: DockPrefsSnapshot?) { lock.withLock { snapshot = s } }
}
