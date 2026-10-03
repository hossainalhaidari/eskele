import Foundation

/// *Open at Login* for other applications, as the Dock offers it on an app's Options menu.
///
/// **Why not `SMAppService`.** It registers the calling app, or a helper inside its own bundle, and
/// nothing else; Eskele's own launch at login goes through it (`LoginItemService`). Another app's
/// entry is what the old shared file list holds — `kLSSharedFileListSessionLoginItems`, the list
/// System Settings shows under *Open at Login*.
///
/// **Measured on macOS 27.0.1.** The list reads back what System Settings has, and an app inserted
/// into it is in a fresh read a second later and gone after it is removed. The calls have been
/// deprecated since 10.11 and are looked up by name, as `SystemShortcuts` does: that keeps the
/// deprecation out of the build, and if a later macOS removes them the lookup fails and the menu
/// item is simply not offered.
///
/// **The trap.** `kLSSharedFileListItemLast`, the "insert at the end" marker, is not an object but
/// the tagged value `0x2`. Bridged into Swift it is an `Unmanaged<LSSharedFileListItem>`, and
/// taking its value retains it — which crashes. So every call here passes raw pointers.
@MainActor
enum AppLoginItems {
    /// Whether the list can be read and written at all on this macOS.
    static var isAvailable: Bool { functions != nil }

    /// Whether `app` opens at login — by path, or by bundle identifier for a copy that has moved
    /// since it was added.
    static func isEnabled(url: URL, bundleID: String?) -> Bool {
        guard let functions, let list = functions.list() else { return false }
        return !functions.entries(of: list).filter {
            matches($0.url, url: url, bundleID: bundleID, identify: identify)
        }.isEmpty
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool, url: URL, bundleID: String?) -> Bool {
        guard let functions, let list = functions.list() else { return false }
        let existing = functions.entries(of: list).filter {
            matches($0.url, url: url, bundleID: bundleID, identify: identify)
        }
        if enabled {
            guard existing.isEmpty else { return true }
            return functions.append(url, to: list)
        }
        // Every copy, so a duplicate left by some other tool does not keep it opening.
        return existing.allSatisfy { functions.remove($0.item, from: list) }
    }

    /// The same app as `url`: the same path, or a bundle with the same identifier.
    ///
    /// - Parameter identify: the bundle identifier at a URL — `Bundle(url:)` in the app, a table in
    ///   the tests.
    static func matches(
        _ entry: URL?, url: URL, bundleID: String?, identify: (URL) -> String?
    ) -> Bool {
        guard let entry else { return false }
        if entry.standardizedFileURL.path == url.standardizedFileURL.path { return true }
        guard let bundleID else { return false }
        return identify(entry) == bundleID
    }

    private static func identify(_ url: URL) -> String? { Bundle(url: url)?.bundleIdentifier }

    private static let functions = Functions()

    /// The calls, looked up by name. Nil if any is missing.
    private struct Functions {
        typealias Create = @convention(c) (
            UnsafeRawPointer?, UnsafeRawPointer, UnsafeRawPointer?) -> UnsafeRawPointer?
        typealias Snapshot = @convention(c) (
            UnsafeRawPointer, UnsafeMutablePointer<UInt32>?) -> UnsafeRawPointer?
        typealias Resolve = @convention(c) (
            UnsafeRawPointer, UInt32, UnsafeMutablePointer<UnsafeRawPointer?>?) -> UnsafeRawPointer?
        typealias Insert = @convention(c) (
            UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer?, UnsafeRawPointer?,
            UnsafeRawPointer, UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeRawPointer?
        typealias Remove = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> OSStatus

        let create: Create
        let snapshot: Snapshot
        let resolve: Resolve
        let insert: Insert
        let removeItem: Remove
        /// `kLSSharedFileListSessionLoginItems`, a CFString.
        let loginItems: UnsafeRawPointer
        /// `kLSSharedFileListItemLast` — the tagged marker, never dereferenced.
        let last: UnsafeRawPointer

        init?() {
            guard let image = dlopen(
                "/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY)
            else { return nil }
            func symbol(_ name: String) -> UnsafeMutableRawPointer? { dlsym(image, name) }
            guard
                let create = symbol("LSSharedFileListCreate"),
                let snapshot = symbol("LSSharedFileListCopySnapshot"),
                let resolve = symbol("LSSharedFileListItemCopyResolvedURL"),
                let insert = symbol("LSSharedFileListInsertItemURL"),
                let remove = symbol("LSSharedFileListItemRemove"),
                let loginItems = symbol("kLSSharedFileListSessionLoginItems")?
                    .assumingMemoryBound(to: UnsafeRawPointer?.self).pointee,
                let last = symbol("kLSSharedFileListItemLast")?
                    .assumingMemoryBound(to: UnsafeRawPointer?.self).pointee
            else { return nil }
            self.create = unsafeBitCast(create, to: Create.self)
            self.snapshot = unsafeBitCast(snapshot, to: Snapshot.self)
            self.resolve = unsafeBitCast(resolve, to: Resolve.self)
            self.insert = unsafeBitCast(insert, to: Insert.self)
            self.removeItem = unsafeBitCast(remove, to: Remove.self)
            self.loginItems = loginItems
            self.last = last
        }

        /// The list, owned by the caller for as long as it holds the returned object.
        func list() -> AnyObject? {
            create(nil, loginItems, nil).map { Unmanaged<AnyObject>.fromOpaque($0).takeRetainedValue() }
        }

        /// Each entry with where it resolves to. Resolved without asking the user anything and
        /// without mounting a volume, so reading the menu never brings up a dialog or spins a disk.
        func entries(of list: AnyObject) -> [(item: AnyObject, url: URL?)] {
            let pointer = Unmanaged.passUnretained(list).toOpaque()
            guard let array = snapshot(pointer, nil) else { return [] }
            let items = Unmanaged<CFArray>.fromOpaque(array).takeRetainedValue() as [AnyObject]
            let flags: UInt32 = 1 | 2  // kLSSharedFileListNoUserInteraction | DoNotMountVolumes
            return items.map { item in
                let url = resolve(Unmanaged.passUnretained(item).toOpaque(), flags, nil)
                    .map { Unmanaged<CFURL>.fromOpaque($0).takeRetainedValue() as URL }
                return (item, url)
            }
        }

        func append(_ url: URL, to list: AnyObject) -> Bool {
            // Bridged once and held, so the object passed is the one kept alive.
            let target = url as CFURL
            let added = withExtendedLifetime((list, target)) {
                insert(
                    Unmanaged.passUnretained(list).toOpaque(), last, nil, nil,
                    Unmanaged.passUnretained(target).toOpaque(), nil, nil)
            }
            guard let added else { return false }
            Unmanaged<AnyObject>.fromOpaque(added).release()
            return true
        }

        func remove(_ item: AnyObject, from list: AnyObject) -> Bool {
            removeItem(
                Unmanaged.passUnretained(list).toOpaque(),
                Unmanaged.passUnretained(item).toOpaque()) == noErr
        }
    }
}
