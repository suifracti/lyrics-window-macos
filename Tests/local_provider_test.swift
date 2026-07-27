import Foundation

@main
struct LocalProviderContract {
    static func main() async {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("spotifylyrics-local-contract-\(UUID().uuidString)")
        try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let track = Track(
            title: "Local Song",
            artist: "Local Artist",
            album: "Local Album",
            duration: 120,
            spotifyId: "local-track-1"
        )
        let identity = TrackIdentity(track: track)
        let file = root.appendingPathComponent("spotify-id-local-track-1.lrc")
        let content = "[ti:Local Song]\n[ar:Local Artist]\n[al:Local Album]\n[00:00.00]Local lyric\n"
        try! content.write(to: file, atomically: true, encoding: .utf8)
        let before = try! Data(contentsOf: file)

        let provider = LocalLyricsProvider(searchDirectories: [root])
        let result = await provider.lookup(track: track, identity: identity)
        guard case .match(let document) = result else {
            fatalError("expected a local LRC match, got \(result)")
        }
        precondition(document.lines.first?.originalText == "Local lyric")
        precondition(try! Data(contentsOf: file) == before)
        print("local provider contract passed")
    }
}
