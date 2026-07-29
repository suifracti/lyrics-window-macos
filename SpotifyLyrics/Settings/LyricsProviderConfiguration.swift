import Foundation

/// Stable identifiers used by the settings layer. `sqliteDatabase` is a
/// persistence source rather than a LyricsProvider instance, so PlaybackState
/// keeps it ahead of the network providers without constructing a second
/// provider type.
public enum LyricsProviderID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case localFiles
    case sqliteDatabase
    case lrclib
    case netEaseExperimental
    case qqExperimental

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .localFiles: return "本地歌词"
        case .sqliteDatabase: return "SQLite 本地数据库"
        case .lrclib: return "LRCLIB"
        case .netEaseExperimental: return "网易云实验源"
        case .qqExperimental: return "QQ 音乐实验源"
        }
    }

    public var systemImage: String {
        switch self {
        case .localFiles: return "doc.text"
        case .sqliteDatabase: return "internaldrive"
        case .lrclib: return "network"
        case .netEaseExperimental: return "globe.asia.australia"
        case .qqExperimental: return "bubble.left.and.bubble.right"
        }
    }

    public var isLocal: Bool {
        self == .localFiles || self == .sqliteDatabase
    }

    public var isExperimental: Bool {
        self == .netEaseExperimental || self == .qqExperimental
    }

    public var stabilityLabel: String {
        switch self {
        case .localFiles, .sqliteDatabase: return "稳定"
        case .lrclib: return "在线"
        case .netEaseExperimental, .qqExperimental: return "实验"
        }
    }

    public var detail: String {
        switch self {
        case .localFiles:
            return "只读扫描用户歌词目录，不修改文件"
        case .sqliteDatabase:
            return "优先恢复已采用的本地歌词版本"
        case .lrclib:
            return "公共在线歌词源，网络失败会隔离"
        case .netEaseExperimental:
            return "实验源；目录命中不代表正文可用"
        case .qqExperimental:
            return "实验源；结果必须经过版本匹配"
        }
    }
}

public struct LyricsProviderConfiguration: Equatable, Sendable {
    public var enabled: Set<LyricsProviderID>
    public var order: [LyricsProviderID]

    public static let `default` = LyricsProviderConfiguration(
        enabled: Set(LyricsProviderID.allCases),
        order: [
            .localFiles,
            .sqliteDatabase,
            .lrclib,
            .netEaseExperimental,
            .qqExperimental
        ]
    )

    public init(
        enabled: Set<LyricsProviderID> = Set(LyricsProviderID.allCases),
        order: [LyricsProviderID] = LyricsProviderConfiguration.default.order
    ) {
        self.enabled = enabled
        self.order = order
        normalize()
    }

    public mutating func normalize() {
        let all = Set(LyricsProviderID.allCases)
        enabled.formUnion([.localFiles, .sqliteDatabase])
        enabled = enabled.intersection(all)

        var seen = Set<LyricsProviderID>()
        order = order.filter { all.contains($0) && seen.insert($0).inserted }
        for id in LyricsProviderID.allCases where seen.insert(id).inserted {
            order.append(id)
        }
    }

    public var orderedEnabledIDs: [LyricsProviderID] {
        order.filter { enabled.contains($0) }
    }
}
