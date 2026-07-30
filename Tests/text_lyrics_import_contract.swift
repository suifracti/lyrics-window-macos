import Foundation

@main
struct TextLyricsImportContract {
    static func main() throws {
        try testUTF8BOMAndDeterministicCleaning()
        try testUTF16AndAllNewlineStyles()
        try testPasteAndEmptyInput()
        try testPlainDocumentKeepsUntimedRows()
        print("text lyrics import contract passed")
    }

    static func testUTF8BOMAndDeterministicCleaning() throws {
        let source = "\u{FEFF}  第一行  \r\n\r\n\r\n[Verse 1]\r\n[00:12.30]第二行\r\n\r\n歌词网站广告\r\n作词：作者\r\n重复\r\n重复\r\n"
        let result = try TextLyricsImportParser.parse(Data(source.data(using: .utf8)!))
        try require(result.encoding == .utf8BOM, "UTF-8 BOM detected")
        try require(result.lines == ["第一行", "", "[Verse 1]", "[00:12.30]第二行", "", "歌词网站广告", "作词：作者", "重复", "重复"], "trim and collapse preserve lyric lines")
        try require(result.warnings.contains { $0.kind == .sectionMarker }, "section marker warning")
        try require(result.warnings.contains { $0.kind == .timestampLabel }, "timestamp warning")
        try require(result.warnings.contains { $0.kind == .advertisement }, "advertisement warning")
        try require(result.warnings.contains { $0.kind == .credits }, "credits warning")
        try require(result.lines.filter { $0 == "重复" }.count == 2, "duplicate lyric lines preserved")
    }

    static func testUTF16AndAllNewlineStyles() throws {
        let littleEndian = Data([0xFF, 0xFE]) + "甲\r乙\n丙\r\n丁".data(using: .utf16LittleEndian)!
        let result = try TextLyricsImportParser.parse(littleEndian)
        try require(result.encoding == .utf16LittleEndian, "UTF-16LE detected")
        try require(result.lines == ["甲", "乙", "丙", "丁"], "CR/LF/CRLF normalized")

        let bigEndian = Data([0xFE, 0xFF]) + "一\n二".data(using: .utf16BigEndian)!
        let bigResult = try TextLyricsImportParser.parse(bigEndian)
        try require(bigResult.encoding == .utf16BigEndian, "UTF-16BE detected")
        try require(bigResult.lines == ["一", "二"], "UTF-16BE lines decoded")
    }

    static func testPasteAndEmptyInput() throws {
        let pasted = try TextLyricsImportParser.parse("  貼り付け一  \n\n\n貼り付け二\n")
        try require(pasted.encoding == .plainText, "paste is plain text")
        try require(pasted.lines == ["貼り付け一", "", "貼り付け二"], "paste uses the same cleaner")

        do {
            _ = try TextLyricsImportParser.parse(" \r\n\n\t")
            throw ContractError("empty input accepted")
        } catch TextLyricsImportError.empty {
            // expected
        }
    }

    static func testPlainDocumentKeepsUntimedRows() throws {
        let track = Track(title: "Forever", artist: "VILLSHANA, Mahiru", album: "Single", duration: 180, spotifyId: "forever-test")
        let identity = TrackIdentity(track: track)
        let result = try TextLyricsImportParser.parse("一行\n\n二行")
        let document = result.document(identity: identity, track: track, source: .manualCreate)
        try require(document.source == .manualCreate, "manual create source preserved")
        try require(!document.isSynchronized, "plain import is not synchronized")
        try require(document.lines.map(\.originalText) == ["一行", "", "二行"], "blank row preserved")
        try require(document.lines.allSatisfy { $0.timestamp == 0 && $0.endTime == nil }, "plain rows have no timing")
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
