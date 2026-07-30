import Foundation

@main
struct LRCRoundTripContract {
    static func main() throws {
        let track = Track(id: "round-trip", title: "Round Trip", artist: "Artist", album: "Album", duration: 10)
        let identity = TrackIdentity(track: track)
        let document = LyricsDocument(
            identity: identity,
            title: "Round Trip",
            artist: "Artist",
            album: "Album",
            duration: 10,
            lines: [
                LyricLine(timestamp: 0.25, originalText: "第一"),
                LyricLine(timestamp: 2.5, originalText: "第二")
            ],
            isSynchronized: true,
            source: .manualImport
        )
        let output = LRCExporter.original(document: document, source: "manualImport", locked: false)
        let parsed = try LRCImportParser.parse(output)
        let parsedText = parsed.lines.map { $0.originalText }
        guard parsed.lines.count == 2,
              parsedText == ["第一", "第二"],
              abs((parsed.lines[0].startTime ?? -1) - 0.25) < 0.0001,
              abs((parsed.lines[1].startTime ?? -1) - 2.5) < 0.0001 else {
            throw ContractError("LRC round trip changed line data")
        }
        print("lrc round trip contract passed")
    }
}

struct ContractError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
