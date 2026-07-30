import Foundation

public enum LyricsEditorError: Error, Equatable, Sendable, LocalizedError {
    case invalidLine
    case invalidSplitOffset
    case cannotDeleteLastLine
    case nothingToUndo
    case nothingToRedo
    case noChanges
    case staleSession
    case invalidDocument(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLine: return "找不到歌词行"
        case .invalidSplitOffset: return "拆分位置无效"
        case .cannotDeleteLastLine: return "至少需要保留一行歌词"
        case .nothingToUndo: return "没有可撤销的编辑"
        case .nothingToRedo: return "没有可重做的编辑"
        case .noChanges: return "没有需要保存的修改"
        case .staleSession: return "歌词在编辑期间已经变化，请重新打开编辑器"
        case .invalidDocument(let message): return message
        }
    }
}

public struct LyricsEditorLineDraft: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var originalText: String
    public var translationText: String?
    public var startTime: TimeInterval?
    public var endTime: TimeInterval?
    public var kanaText: String?
    public var romajiText: String?
    public var rubyTokens: [LyricRubyToken]?

    public init(
        id: UUID = UUID(),
        originalText: String,
        translationText: String? = nil,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        kanaText: String? = nil,
        romajiText: String? = nil,
        rubyTokens: [LyricRubyToken]? = nil
    ) {
        self.id = id
        self.originalText = originalText
        self.translationText = translationText
        self.startTime = startTime
        self.endTime = endTime
        self.kanaText = kanaText
        self.romajiText = romajiText
        self.rubyTokens = rubyTokens
    }

    public init(line: LyricLine, startTimeIsMeaningful: Bool = true) {
        self.init(
            id: line.id,
            originalText: line.originalText,
            translationText: line.translationText,
            // LyricLine keeps a zero placeholder for plain-text rows for
            // compatibility with the playback renderer. The editor must not
            // turn that placeholder into a real timestamp.
            startTime: startTimeIsMeaningful && line.timestamp.isFinite ? line.timestamp : nil,
            endTime: line.endTime,
            kanaText: line.kanaText,
            romajiText: line.romajiText,
            rubyTokens: line.rubyTokens
        )
    }

    public func asLyricLine() -> LyricLine {
        LyricLine(
            id: id,
            timestamp: startTime ?? 0,
            originalText: originalText,
            endTime: endTime,
            translationText: translationText,
            romajiText: romajiText,
            kanaText: kanaText,
            rubyTokens: rubyTokens
        )
    }
}

/// A value-type editing buffer. Every mutation records a complete line-array
/// snapshot, which keeps undo/redo deterministic when rows are split, merged,
/// reordered, or deleted.
public struct LyricsEditorDraft: Equatable, Sendable {
    public let identity: TrackIdentity
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?
    public let sourceVersionID: UUID
    public let sourceContentHash: String
    public let source: LyricsSource
    public var lines: [LyricsEditorLineDraft]

    private var savedLines: [LyricsEditorLineDraft]
    private var undoStack: [[LyricsEditorLineDraft]] = []
    private var redoStack: [[LyricsEditorLineDraft]] = []

    public init(
        identity: TrackIdentity,
        title: String?,
        artist: String?,
        album: String?,
        duration: TimeInterval?,
        lines: [LyricsEditorLineDraft],
        sourceVersionID: UUID,
        sourceContentHash: String,
        source: LyricsSource
    ) {
        self.identity = identity
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.lines = lines
        self.sourceVersionID = sourceVersionID
        self.sourceContentHash = sourceContentHash
        self.source = source
        self.savedLines = lines
    }

    public init(document: LyricsDocument, sourceVersionID: UUID, sourceContentHash: String) {
        self.init(
            identity: document.identity,
            title: document.title,
            artist: document.artist,
            album: document.album,
            duration: document.duration,
            lines: document.lines.map {
                LyricsEditorLineDraft(
                    line: $0,
                    startTimeIsMeaningful: document.isSynchronized
                )
            },
            sourceVersionID: sourceVersionID,
            sourceContentHash: sourceContentHash,
            source: document.source
        )
    }

    public var isDirty: Bool { lines != savedLines }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func markSaved() {
        savedLines = lines
        undoStack.removeAll()
        redoStack.removeAll()
    }

    public func document(source: LyricsSource = .manualEdit, isSynchronized: Bool? = nil) -> LyricsDocument {
        LyricsDocument(
            identity: identity,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            lines: lines.map { $0.asLyricLine() },
            isSynchronized: isSynchronized ?? LyricsTimelineValidator.validate(lines: lines, duration: duration).isSynchronized,
            source: source,
            confidence: 1,
            providerSourceID: "manualEdit"
        )
    }

    public mutating func update(_ lineID: UUID, _ change: (inout LyricsEditorLineDraft) -> Void) throws {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { throw LyricsEditorError.invalidLine }
        recordHistory()
        change(&lines[index])
    }

    public mutating func split(lineID: UUID, at offset: Int) throws {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { throw LyricsEditorError.invalidLine }
        let line = lines[index]
        let characters = Array(line.originalText)
        guard offset > 0, offset < characters.count else { throw LyricsEditorError.invalidSplitOffset }
        recordHistory()
        let left = String(characters[..<offset])
        let right = String(characters[offset...])
        let leftTranslation = splitCompanion(line.translationText, at: offset, preferLeft: true)
        let rightTranslation = splitCompanion(line.translationText, at: offset, preferLeft: false)
        lines[index] = LyricsEditorLineDraft(
            id: line.id,
            originalText: left,
            translationText: leftTranslation,
            startTime: line.startTime,
            endTime: nil,
            kanaText: nil,
            romajiText: nil
        )
        lines.insert(
            LyricsEditorLineDraft(
                originalText: right,
                translationText: rightTranslation,
                startTime: nil,
                endTime: line.endTime
            ),
            at: index + 1
        )
    }

    public mutating func merge(lineID: UUID, with nextID: UUID) throws {
        guard let index = lines.firstIndex(where: { $0.id == lineID }),
              index + 1 < lines.count,
              lines[index + 1].id == nextID else { throw LyricsEditorError.invalidLine }
        let first = lines[index]
        let second = lines[index + 1]
        recordHistory()
        lines[index] = LyricsEditorLineDraft(
            id: first.id,
            originalText: first.originalText + second.originalText,
            translationText: mergeCompanion(first.translationText, second.translationText),
            startTime: first.startTime ?? second.startTime,
            endTime: second.endTime ?? first.endTime,
            kanaText: nil,
            romajiText: nil
        )
        lines.remove(at: index + 1)
    }

    public mutating func insertBlank(after lineID: UUID? = nil) {
        recordHistory()
        let index: Int
        if let lineID, let found = lines.firstIndex(where: { $0.id == lineID }) {
            index = found + 1
        } else {
            index = lines.count
        }
        lines.insert(LyricsEditorLineDraft(originalText: ""), at: index)
    }

    public mutating func delete(lineID: UUID) throws {
        guard lines.count > 1 else { throw LyricsEditorError.cannotDeleteLastLine }
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { throw LyricsEditorError.invalidLine }
        recordHistory()
        lines.remove(at: index)
    }

    public mutating func move(lineID: UUID, offset: Int) {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        let target = min(max(0, index + offset), lines.count - 1)
        guard target != index else { return }
        recordHistory()
        let line = lines.remove(at: index)
        lines.insert(line, at: target)
    }

    public mutating func undo() throws {
        guard let previous = undoStack.popLast() else { throw LyricsEditorError.nothingToUndo }
        redoStack.append(lines)
        lines = previous
    }

    public mutating func redo() throws {
        guard let next = redoStack.popLast() else { throw LyricsEditorError.nothingToRedo }
        undoStack.append(lines)
        lines = next
    }

    private mutating func recordHistory() {
        undoStack.append(lines)
        redoStack.removeAll()
    }

    private func splitCompanion(_ value: String?, at offset: Int, preferLeft: Bool) -> String? {
        guard let value, !value.isEmpty else { return value }
        let chars = Array(value)
        let split = min(offset, chars.count)
        if preferLeft { return String(chars[..<split]) }
        return String(chars[split...])
    }

    private func mergeCompanion(_ lhs: String?, _ rhs: String?) -> String? {
        switch (lhs?.isEmpty == false ? lhs : nil, rhs?.isEmpty == false ? rhs : nil) {
        case let (left?, right?): return left + " " + right
        case let (left?, nil): return left
        case let (nil, right?): return right
        default: return nil
        }
    }
}
