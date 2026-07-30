import Foundation

@main
struct AITranslationContract {
    static func main() async throws {
        try endpointContract()
        try blankLineContract()
        try responseSafetyContract()
        try await clientErrorContract()
        try await testConnectionContract()
        print("AI translation contracts passed")
    }

    static func endpointContract() throws {
        let cases: [(String, String)] = [
            ("https://example.test", "https://example.test/v1/chat/completions"),
            ("https://example.test/", "https://example.test/v1/chat/completions"),
            ("https://example.test/v1", "https://example.test/v1/chat/completions"),
            ("https://example.test/v1/", "https://example.test/v1/chat/completions"),
            ("https://example.test/v1/chat/completions", "https://example.test/v1/chat/completions"),
            ("https://proxy.test/api/openai/v1", "https://proxy.test/api/openai/v1/chat/completions")
        ]
        for (base, expected) in cases {
            guard AITranslationEndpoint(baseURL: base).chatCompletionsURL.absoluteString == expected else {
                throw ContractFailure(message: "endpoint normalization: \(base)")
            }
        }
    }

    static func blankLineContract() throws {
        let original = ["第一行", "", "第三行"]
        let valid = [
            AITranslationLine(index: 0, translation: "第一行译文"),
            AITranslationLine(index: 1, translation: ""),
            AITranslationLine(index: 2, translation: "第三行译文")
        ]
        guard try AITranslationResponseParser.validate(valid, against: original).count == 3 else {
            throw ContractFailure(message: "blank line should be preserved")
        }
        let invalid = [
            AITranslationLine(index: 0, translation: ""),
            AITranslationLine(index: 1, translation: ""),
            AITranslationLine(index: 2, translation: "第三行译文")
        ]
        do {
            _ = try AITranslationResponseParser.validate(invalid, against: original)
            throw ContractFailure(message: "nonblank source accepted blank translation")
        } catch AITranslationResponseError.validationFailed { }
    }

    static func responseSafetyContract() throws {
        let response = #"[{"index":0,"translation":"译文"}]"#.data(using: .utf8)!
        let parsed = try AITranslationResponseParser.parse(response, expectedLineCount: 1)
        guard parsed.count == 1, parsed[0].translation == "译文" else {
            throw ContractFailure(message: "strict response parse")
        }
        for body in [
            #"[{"index":0,"translation":"译文","startTime":1}]"#,
            #"{"index":0,"translation":"译文"}"#,
            #"[{"index":true,"translation":"译文"}]"#,
            #"[{"index":0.5,"translation":"译文"}]"#,
            #"not json"#
        ] {
            do {
                _ = try AITranslationResponseParser.parse(Data(body.utf8), expectedLineCount: 1)
                throw ContractFailure(message: "unsafe response accepted")
            } catch AITranslationResponseError.validationFailed { }
        }
    }

    static func clientErrorContract() async throws {
        let configuration = AITranslationConfiguration(baseURL: "https://proxy.test/api/openai/v1", model: "contract-model")
        let prompt = AITranslationPrompt(system: "system", user: "source", promptHash: "hash")

        let successBody = Data(#"{"choices":[{"message":{"content":"[{\"index\":0,\"translation\":\"ok\"}]"}}]}"#.utf8)
        let recording = RecordingHTTPClient(result: .response(successBody, 200))
        let client = OpenAICompatibleClient(httpClient: recording)
        let success = try await client.complete(
            prompt: prompt,
            configuration: configuration,
            apiKey: "test-key-not-logged",
            inputLineCount: 1
        )
        guard success.statusCode == 200,
              recording.lastRequest?.url?.absoluteString == "https://proxy.test/api/openai/v1/chat/completions" else {
            throw ContractFailure(message: "custom endpoint request")
        }
        guard let requestBody = recording.lastRequest?.httpBody,
              String(data: requestBody, encoding: .utf8)?.contains("source") == true else {
            throw ContractFailure(message: "request body missing prompt")
        }

        for (status, expected) in [(401, AITranslationError.unauthorized), (429, AITranslationError.rateLimited), (500, AITranslationError.server(500))] {
            let errorClient = OpenAICompatibleClient(httpClient: RecordingHTTPClient(result: .response(Data("{}".utf8), status)))
            do {
                _ = try await errorClient.complete(prompt: prompt, configuration: configuration, apiKey: "key", inputLineCount: 1)
                throw ContractFailure(message: "HTTP \(status) accepted")
            } catch let error as AITranslationError {
                guard error == expected else { throw ContractFailure(message: "HTTP \(status) classification") }
            }
        }

        let timeoutClient = OpenAICompatibleClient(httpClient: RecordingHTTPClient(result: .failure(.timedOut)))
        do {
            _ = try await timeoutClient.complete(prompt: prompt, configuration: configuration, apiKey: "key", inputLineCount: 1)
            throw ContractFailure(message: "timeout accepted")
        } catch AITranslationError.timedOut { }

        let networkClient = OpenAICompatibleClient(httpClient: RecordingHTTPClient(result: .failure(.network)))
        do {
            _ = try await networkClient.complete(prompt: prompt, configuration: configuration, apiKey: "key", inputLineCount: 1)
            throw ContractFailure(message: "network failure accepted")
        } catch AITranslationError.network { }

        let parseClient = OpenAICompatibleClient(httpClient: RecordingHTTPClient(result: .response(Data("{}".utf8), 200)))
        do {
            _ = try await parseClient.complete(prompt: prompt, configuration: configuration, apiKey: "key", inputLineCount: 1)
            throw ContractFailure(message: "parse failure accepted")
        } catch AITranslationError.invalidResponse { }
    }

    static func testConnectionContract() async throws {
        let keyStore = MemoryKeyStore(value: "key-not-printed")
        let http = RecordingHTTPClient(result: .response(
            Data(#"{"choices":[{"message":{"content":"[{\"index\":0,\"translation\":\"ok\"}]"}}]}"#.utf8),
            200
        ))
        let service = OpenAICompatibleTranslationService(
            client: OpenAICompatibleClient(httpClient: http),
            keyStore: keyStore
        )
        try await service.testConnection(
            configuration: AITranslationConfiguration(baseURL: "https://host.test", model: "model")
        )
        guard let body = http.lastRequest?.httpBody,
              let text = String(data: body, encoding: .utf8),
              text.contains("ping"), !text.contains("当前歌词") else {
            throw ContractFailure(message: "test connection was not minimal")
        }
    }
}

struct ContractFailure: Error { let message: String }

private enum FakeHTTPError: Error { case timedOut, network }

private final class RecordingHTTPClient: AIHTTPClient, @unchecked Sendable {
    enum Result {
        case response(Data, Int)
        case failure(FakeHTTPError)
    }

    let result: Result
    private(set) var lastRequest: URLRequest?

    init(result: Result) { self.result = result }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        switch result {
        case .response(let data, let status):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (data, response)
        case .failure(.timedOut): throw URLError(.timedOut)
        case .failure(.network): throw FakeHTTPError.network
        }
    }
}

private final class MemoryKeyStore: AITranslationAPIKeyStore, @unchecked Sendable {
    var value: String?
    init(value: String?) { self.value = value }
    func read() -> String? { value }
    func save(_ key: String) throws { value = key }
    func delete() throws { value = nil }
}
