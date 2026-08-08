import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private final class LyricsStubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler,
              let client,
              let url = request.url else {
            fatalError("missing lyrics URLProtocol fixture")
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
struct LyricsCompanionLayersContract {
    static func main() async {
        let source = [
            LyricLine(timestamp: 1.00, originalText: "満を持して"),
            LyricLine(timestamp: 2.50, originalText: "次の行"),
            LyricLine(timestamp: 8.00, originalText: "離れた行")
        ]
        let translations = """
        [00:01.02]万事俱备
        [00:02.47]下一行
        [00:09.00]不应错误匹配
        """
        let romaji = """
        [00:00.98]man o jishite
        [00:02.53]tsugi no gyou
        """

        let translated = TimedLyricsCompanionMerger.merge(
            translations,
            into: source,
            layer: .translation
        )
        let merged = TimedLyricsCompanionMerger.merge(
            romaji,
            into: translated,
            layer: .romaji
        )

        require(merged[0].originalText == "満を持して", "original lyrics must remain authoritative")
        require(merged[0].translationText == "万事俱备", "nearby translation timestamp should merge")
        require(merged[1].translationText == "下一行", "second nearby translation should merge")
        require(merged[2].translationText == nil, "out-of-tolerance translation must not attach")
        require(merged[0].romajiText == "man o jishite", "romaji layer should remain distinct")
        require(merged[1].romajiText == "tsugi no gyou", "second romaji line should merge")
        require(merged.allSatisfy { $0.kanaText == nil }, "provider companion text must never become whole-line kana")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let original = "[00:01.00]満を持して\n[00:02.50]次の行"
        let translation = "[00:01.03]万事俱备\n[00:02.48]下一行"
        let romanization = "[00:00.99]man o jishite\n[00:02.52]tsugi no gyou"

        LyricsStubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/soso/fcgi-bin/client_search_cp":
                let payload = """
                {"data":{"song":{"list":[{
                  "songmid":"song-mid",
                  "songname":"満を持して",
                  "singer":[{"name":"Fixture Artist"}],
                  "albumname":"Fixture Album",
                  "interval":180
                }]}}}
                """
                return (200, Data(payload.utf8))
            case "/lyric/fcgi-bin/fcg_query_lyric_new.fcg":
                let object: [String: Any] = [
                    "retcode": 0,
                    "code": 0,
                    "lyric": Data(original.utf8).base64EncodedString(),
                    "trans": Data(translation.utf8).base64EncodedString(),
                    "roma": Data(romanization.utf8).base64EncodedString()
                ]
                return (200, try! JSONSerialization.data(withJSONObject: object))
            default:
                fatalError("unexpected provider request: \(request.url?.absoluteString ?? "nil")")
            }
        }

        let track = Track(
            title: "満を持して",
            artist: "Fixture Artist",
            album: "Fixture Album",
            duration: 180
        )
        let identity = TrackIdentity(track: track)
        let provider = QQExperimentalLyricsProvider(session: session)
        guard case .match(let document) = await provider.lookup(track: track, identity: identity) else {
            preconditionFailure("exact QQ fixture should be adopted as a match")
        }
        require(document.lines.count == 2, "QQ original LRC should parse")
        require(document.lines[0].translationText == "万事俱备", "QQ trans field should be preserved")
        require(document.lines[0].romajiText == "man o jishite", "QQ roma field should be preserved")
        require(document.lines[0].kanaText == nil, "QQ roma must not populate kana")
    }
}
