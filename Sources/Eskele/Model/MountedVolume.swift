import Foundation

/// A disk, disk image or server that is mounted and can be ejected — what Finder puts on the
/// desktop and gives an Eject button in its sidebar.
struct MountedVolume: Equatable, Sendable {
    var url: URL
    var name: String
    /// A disk image is usually read-only, and copying onto one fails file by file; knowing up front
    /// lets a drop on the cell be refused instead.
    var isReadOnly: Bool = false

    /// The keys `isShown` reads, asked for in one go when the volumes are listed.
    static let resourceKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeIsBrowsableKey, .volumeIsRootFileSystemKey,
        .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsLocalKey,
        .volumeIsReadOnlyKey, .isVolumeKey,
    ]

    /// Whether a mounted volume belongs on the bar.
    ///
    /// Finder's rule for its Eject button rather than its rule for the desktop: an external disk,
    /// a disk image, a card, a server. The startup disk and a second volume on the internal drive
    /// stay off — there is nothing to eject. So do the volumes Finder does not show at all: macOS
    /// mounts a dozen of its own under `/System/Volumes`, and Xcode one per simulator runtime, all
    /// ejectable and none browsable.
    ///
    /// `isInternal` is nil for a server, which has no drive to be inside; only a firm yes keeps a
    /// volume off.
    static func isShown(
        isBrowsable: Bool, isRoot: Bool, isEjectable: Bool, isRemovable: Bool,
        isInternal: Bool?, isLocal: Bool
    ) -> Bool {
        guard isBrowsable, !isRoot else { return false }
        return isEjectable || isRemovable || isInternal != true || !isLocal
    }

    /// The volume mounted at `url`, if it is one the bar shows — nil for a folder, a volume Finder
    /// hides, or one with nothing to eject.
    init?(url: URL) {
        guard let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys)),
              values.isVolume == true,
              Self.isShown(
                isBrowsable: values.volumeIsBrowsable ?? false,
                isRoot: values.volumeIsRootFileSystem ?? false,
                isEjectable: values.volumeIsEjectable ?? false,
                isRemovable: values.volumeIsRemovable ?? false,
                isInternal: values.volumeIsInternal,
                isLocal: values.volumeIsLocal ?? true)
        else { return nil }
        self.url = url
        name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
        isReadOnly = values.volumeIsReadOnly ?? false
    }

    init(url: URL, name: String, isReadOnly: Bool = false) {
        self.url = url
        self.name = name
        self.isReadOnly = isReadOnly
    }

    /// The volumes the bar shows, by name — mount order is the order things happened to be plugged
    /// in, which says nothing the next time they are.
    static func list(_ volumes: [MountedVolume]) -> [MountedVolume] {
        volumes.enumerated().sorted { left, right in
            let comparison = left.element.name.localizedStandardCompare(right.element.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.offset < right.offset
        }.map(\.element)
    }

    /// Whether a drop of `urls` on the Trash means "eject these" rather than "throw these away".
    ///
    /// All or nothing: a drop that mixes a disk with files has no one meaning, and the Trash cannot
    /// take the disk. `volume` is the lookup, so a test can answer it without mounting anything.
    static func ejectsOnTrash(_ urls: [URL], volume: (URL) -> MountedVolume?) -> [MountedVolume]? {
        let volumes = urls.compactMap(volume)
        guard !urls.isEmpty, volumes.count == urls.count else { return nil }
        return volumes
    }
}
