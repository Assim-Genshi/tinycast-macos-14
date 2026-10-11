import Foundation

/// The filesystem entry kind returned by `fsearch`.
public enum FileItemKind: String, Sendable, Codable {
    case file
    case directory = "dir"
    case link
    case other

    public var systemImage: String {
        switch self {
        case .directory: return "folder.fill"
        case .link: return "link"
        case .file, .other: return "doc"
        }
    }
}

/// A single search result entry from the `fsearch` engine.
public struct FileSearchItem: Identifiable, Sendable, Equatable, Hashable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let parentPath: String
    public let kind: FileItemKind
    public let size: UInt64
    public let mtime: Date
    public let score: Int

    public init(
        path: String,
        kind: FileItemKind,
        size: UInt64,
        mtime: Date,
        score: Int
    ) {
        self.path = path
        let url = URL(fileURLWithPath: path)
        self.name = url.lastPathComponent
        self.parentPath = url.deletingLastPathComponent().path
        self.kind = kind
        self.size = size
        self.mtime = mtime
        self.score = score
    }

    public var url: URL {
        URL(fileURLWithPath: path)
    }

    public var isDirectory: Bool {
        kind == .directory
    }

    /// Pre-abbreviated parent path (e.g. `~/Developer/fsearch`).
    public var abbreviatedParentPath: String {
        let home = NSHomeDirectory()
        if parentPath == home { return "~" }
        if parentPath.hasPrefix(home + "/") {
            return "~/" + parentPath.dropFirst(home.count + 1)
        }
        return parentPath
    }

    /// Formatted human-readable file size (e.g. "4.2 MB"), empty for directories.
    public var formattedSize: String {
        guard kind != .directory else { return "" }
        return Self.byteFormatter.string(fromByteCount: Int64(size))
    }

    /// Relative or short date string for modification time.
    public var formattedDate: String {
        Self.relativeDateFormatter.localizedString(for: mtime, relativeTo: Date())
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
