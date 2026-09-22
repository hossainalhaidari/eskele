import Foundation

/// Abstraction over the preferences backend.
///
/// Exists so the suppression/restore state machine can be unit-tested without touching the real
/// `com.apple.dock` domain — see `InMemoryPreferencesStore`.
public protocol PreferencesStore: AnyObject, Sendable {
    func bool(forKey key: String) -> Bool?
    func double(forKey key: String) -> Double?
    func string(forKey key: String) -> String?
    /// Passing `nil` removes the key, restoring the system default.
    func setBool(_ value: Bool?, forKey key: String)
    func setDouble(_ value: Double?, forKey key: String)
    func setString(_ value: String?, forKey key: String)
    func synchronize()
}

/// Reads and writes another application's preference domain via CoreFoundation.
///
/// We deliberately do not shell out to `defaults(1)`: it races with `cfprefsd`, which caches the
/// domain in memory and can silently discard a write made behind its back.
public final class CFPreferencesStore: PreferencesStore, @unchecked Sendable {
    private let domain: CFString

    public init(domain: String = "com.apple.dock") {
        self.domain = domain as CFString
    }

    public func bool(forKey key: String) -> Bool? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain) else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        return (value as? NSNumber)?.boolValue
    }

    public func double(forKey key: String) -> Double? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain) else { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    public func string(forKey key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, domain) as? String
    }

    public func setBool(_ value: Bool?, forKey key: String) {
        let cf: CFPropertyList? = value.map { $0 as CFBoolean }
        CFPreferencesSetAppValue(key as CFString, cf, domain)
    }

    public func setString(_ value: String?, forKey key: String) {
        let cf: CFPropertyList? = value.map { $0 as CFString }
        CFPreferencesSetAppValue(key as CFString, cf, domain)
    }

    public func setDouble(_ value: Double?, forKey key: String) {
        let cf: CFPropertyList? = value.map { NSNumber(value: $0) }
        CFPreferencesSetAppValue(key as CFString, cf, domain)
    }

    public func synchronize() {
        CFPreferencesAppSynchronize(domain)
    }
}

/// Test double.
public final class InMemoryPreferencesStore: PreferencesStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]
    public private(set) var synchronizeCount = 0

    public init(initial: [String: Any] = [:]) { storage = initial }

    public func bool(forKey key: String) -> Bool? {
        lock.withLock { storage[key] as? Bool }
    }
    public func double(forKey key: String) -> Double? {
        lock.withLock { storage[key] as? Double }
    }
    public func string(forKey key: String) -> String? {
        lock.withLock { storage[key] as? String }
    }
    public func setBool(_ value: Bool?, forKey key: String) {
        lock.withLock { storage[key] = value }
    }
    public func setDouble(_ value: Double?, forKey key: String) {
        lock.withLock { storage[key] = value }
    }
    public func setString(_ value: String?, forKey key: String) {
        lock.withLock { storage[key] = value }
    }
    public func synchronize() {
        lock.withLock { synchronizeCount += 1 }
    }
    public var keys: Set<String> { lock.withLock { Set(storage.keys) } }
}
