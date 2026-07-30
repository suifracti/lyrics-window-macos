import Foundation

@main
struct LyricsEditorContract {
    static func main() throws {
        try testLineMutationsAndHistory()
        try testTimelineValidation()
        try testLRCImportAndExport()
        print("lyrics editor contracts passed")
    }

    static func testLineMutationsAndHistory() throws {
        let editorTrack = Track(id: "track-editor", title: "编辑测试", artist: "Test", album: "Album", duration: 120)
        var editor = LyricsEditorDraft(
            identity: TrackIdentity(track: editorTrack),
            title: "编辑测试",
            artist: "Test",
            album: "Album",
            duration: 120,
            lines: [
                LyricsEditorLineDraft(originalText: "第一句", startTime: 1),
                LyricsEditorLineDraft(originalText: "第二句", startTime: 3)
            ],
            sourceVersionID: UUID(),
            sourceContentHash: "source-hash",
            source: .lrclib
        )

        let firstID = try require(editor.lines.first?.id, "first line id")
        try editor.split(lineID: firstID, at: 2)
        try require(editor.lines.map { $0.originalText } == ["第一", "句", "第二句"], "split keeps order")
        try editor.merge(lineID: editor.lines[0].id, with: editor.lines[1].id)
        try require(editor.lines.map { $0.originalText } == ["第一句", "第二句"], "merge restores text")
        editor.insertBlank(after: editor.lines[0].id)
        try require(editor.lines.count == 3 && editor.lines[1].originalText.isEmpty, "insert blank")
        editor.move(lineID: editor.lines[2].id, offset: -2)
        try require(editor.lines.map { $0.originalText } == ["第二句", "第一句", ""], "move line")
        try editor.delete(lineID: editor.lines[2].id)
        try require(editor.lines.map { $0.originalText } == ["第二句", "第一句"], "delete line")
        try editor.undo()
        try require(editor.lines.map { $0.originalText } == ["第二句", "第一句", ""], "undo")
        try editor.redo()
        try require(editor.lines.map { $0.originalText } == ["第二句", "第一句"], "redo")
    }

    static func testTimelineValidation() throws {
        let valid = LyricsTimelineValidator.validate(
            lines: [
                LyricsEditorLineDraft(originalText: "A", startTime: 0, endTime: 2),
                LyricsEditorLineDraft(originalText: "B", startTime: 2, endTime: 5)
            ],
            duration: 5
        )
        try require(valid.isSaveAllowed && valid.isSynchronized && valid.warnings.isEmpty, "valid timeline")

        let duplicate = LyricsTimelineValidator.validate(
            lines: [
                LyricsEditorLineDraft(originalText: "A", startTime: 1),
                LyricsEditorLineDraft(originalText: "B", startTime: 1)
            ],
            duration: 5
        )
        try require(duplicate.isSaveAllowed && duplicate.isSynchronized && !duplicate.warnings.isEmpty, "duplicate timestamp warning")

        let invalid = LyricsTimelineValidator.validate(
            lines: [
                LyricsEditorLineDraft(originalText: "A", startTime: 4),
                LyricsEditorLineDraft(originalText: "B", startTime: 2)
            ],
            duration: 5
        )
        try require(!invalid.isSaveAllowed, "reverse timestamps rejected")

        let plain = LyricsTimelineValidator.validate(
            lines: [
                LyricsEditorLineDraft(originalText: "A"),
                LyricsEditorLineDraft(originalText: "")
            ],
            duration: 5
        )
        try require(plain.isSaveAllowed && !plain.isSynchronized, "plain text remains unsynchronized")

        let plainDocument = LyricsDocument(
            identity: TrackIdentity(track: Track(title: "纯文本", artist: "Test", album: "", duration: 30)),
            lines: [LyricLine(timestamp: 0, originalText: "没有时间")],
            isSynchronized: false,
            source: .qqExperimental
        )
        let plainDraft = LyricsEditorDraft(
            document: plainDocument,
            sourceVersionID: UUID(),
            sourceContentHash: "plain"
        )
        try require(plainDraft.lines[0].startTime == nil, "plain lyric zero placeholder stays untimed")
    }

    static func testLRCImportAndExport() throws {
        let source = """
        [ti:恋風]
        [ar:Lilas]
        [al:Single]
        [length:03:02]
        [00:01.20][00:02.345]第一行
        [00:05.00]第二行
        """
        let imported = try LRCImportParser.parse(source)
        try require(imported.metadata.title == "恋風", "metadata title")
        try require(imported.metadata.artist == "Lilas", "metadata artist")
        try require(imported.lines.count == 3, "multiple timestamps preserve lines")
        try require(abs((imported.lines[0].startTime ?? -1) - 1.2) < 0.0001 && abs((imported.lines[1].startTime ?? -1) - 2.345) < 0.0001, "fraction parsing")
        try require(imported.isSynchronized, "timed import")

        let track = Track(title: "恋風", artist: "Lilas", album: "Single", duration: 182)
        let identity = TrackIdentity(track: track)
        let document = imported.document(identity: identity, track: track)
        let exported = LRCExporter.original(document: document, source: "manualImport", locked: true)
        let reparsed = try LRCImportParser.parse(exported)
        try require(reparsed.lines.count == document.lines.count, "export round trip count \(reparsed.lines.count)/\(document.lines.count)")
        try require(reparsed.lines.map { $0.startTime } == document.lines.map { Optional($0.timestamp) }, "export round trip timestamps")

        let plain = try LRCImportParser.parse("第一行\n\n第二行\n")
        try require(!plain.isSynchronized && plain.lines.count == 3, "untimed text import")

        let translationExport = LRCExporter.translation(
            document: document,
            translations: ["第一行译文", "第二行译文", ""],
            targetLanguage: "zh-Hans",
            source: "manualEdit",
            locked: true
        )
        let translated = try LRCImportParser.parse(translationExport)
        try require(translated.metadata.language == "zh-Hans", "translation language metadata")

        let mismatched = LRCImportMatcher.compare(
            metadata: imported.metadata,
            track: Track(title: "别的歌", artist: "别的艺人", album: "", duration: 20)
        )
        try require(mismatched.isMismatchWarning, "metadata mismatch warning")
    }

    static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw ContractError(message) }
        return value
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw ContractError(message) }
    }
}

struct ContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { "FAIL: \(message)" }
}
