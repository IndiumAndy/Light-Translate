import XCTest
@testable import HoverTranslate

/// Fake network. No test in this file touches the internet or uses a real key.
final class TranslationServiceTests: XCTestCase {
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    private func service() -> DeepSeekTranslationService {
        DeepSeekTranslationService(client: FakeHTTPClient.shared, endpoint: endpoint)
    }

    private func translate(_ text: String = "charge",
                           model: String = "deepseek-flash") async throws -> TranslationResult {
        try await service().translate(TranslationRequest(text: text),
                                      apiKey: "sk-test-not-a-real-key",
                                      model: model)
    }

    /// Test-only wrapper: keeps illegal states unrepresentable in assertions.
    private func translateResult(_ text: String = "charge") async -> Result<TranslationResult, TranslationFailure> {
        do {
            return .success(try await translate(text))
        } catch let failure as TranslationFailure {
            return .failure(failure)
        } catch {
            return .failure(.network)
        }
    }

    override func tearDown() {
        FakeHTTPClient.shared.reset()
        super.tearDown()
    }

    // MARK: - Success

    func testSuccessfulStopReturnsTheTranslation() async throws {
        FakeHTTPClient.shared.enqueueJSON("""
        {"model":"deepseek-flash","choices":[{"finish_reason":"stop","index":0,
         "message":{"role":"assistant","content":"  收费  "}}]}
        """)
        let result = try await translate()
        XCTAssertEqual(result.text, "收费")
        XCTAssertEqual(result.model, "deepseek-flash")
        XCTAssertEqual(result.provider, "deepseek")
        XCTAssertEqual(result.promptVersion, TranslationRequestBuilder.promptVersion)
    }

    /// v0.4: the model picker was inert before this — the adapter always asked
    /// for its own default, so choosing a model changed nothing. The request body
    /// must carry the configured model.
    func testTheConfiguredModelIsWhatTheRequestAsksFor() async throws {
        FakeHTTPClient.shared.enqueueJSON("""
        {"model":"deepseek-v4-pro","choices":[{"finish_reason":"stop","message":{"content":"x"}}]}
        """)
        _ = try await translate("charge", model: "deepseek-v4-pro")

        let sent = try XCTUnwrap(FakeHTTPClient.shared.lastRequest)
        let body = try XCTUnwrap(sent.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["model"] as? String, "deepseek-v4-pro")
    }

    func testAnEmptyModelIsRefusedBeforeAnyRequest() async {
        FakeHTTPClient.shared.reset()
        let result = await translateResult(service(), "charge", apiKey: "sk-test", model: "  ")
        XCTAssertEqual(result, .failure(.configuration))
        XCTAssertNil(FakeHTTPClient.shared.lastRequest, "a configuration failure must not reach the network")
    }

    func testRequestIsPostWithBearerKeyAndNoToolCalls() async throws {
        FakeHTTPClient.shared.enqueueJSON("""
        {"model":"deepseek-flash","choices":[{"finish_reason":"stop","message":{"content":"x"}}]}
        """)
        _ = try await translate()

        let sent = try XCTUnwrap(FakeHTTPClient.shared.lastRequest)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url, endpoint)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-not-a-real-key")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(sent.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertNil(body["tools"])
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertEqual(body["stream"] as? Bool, false)
    }

    // MARK: - Unusable successes

    func testEmptyChoicesIsInvalidResponse() async {
        FakeHTTPClient.shared.enqueueJSON("{\"choices\":[],\"model\":\"deepseek-flash\"}")
        await assertFailure(.invalidResponse)
    }

    func testMissingContentIsInvalidResponse() async {
        FakeHTTPClient.shared.enqueueJSON("""
        {"choices":[{"finish_reason":"stop","message":{"role":"assistant"}}]}
        """)
        await assertFailure(.invalidResponse)
    }

    func testWhitespaceOnlyContentIsInvalidResponse() async {
        FakeHTTPClient.shared.enqueueJSON("""
        {"choices":[{"finish_reason":"stop","message":{"content":"   \n "}}]}
        """)
        await assertFailure(.invalidResponse)
    }

    func testReasoningOnlyReplyIsNotASuccess() async {
        FakeHTTPClient.shared.enqueueJSON("""
        {"choices":[{"finish_reason":"stop","message":{"reasoning_content":"thinking…"}}]}
        """)
        await assertFailure(.invalidResponse)
    }

    func testBrokenJSONIsInvalidResponse() async {
        FakeHTTPClient.shared.enqueueJSON("{not json at all")
        await assertFailure(.invalidResponse)
    }

    func testUnknownFinishReasonIsInvalidResponse() async {
        FakeHTTPClient.shared.enqueueJSON("""
        {"choices":[{"finish_reason":"insufficient_system_resource","message":{"content":"部分"}}]}
        """)
        await assertFailure(.invalidResponse)
    }

    func testLengthFinishReasonIsTruncatedOutput() async {
        FakeHTTPClient.shared.enqueueJSON("""
        {"choices":[{"finish_reason":"length","message":{"content":"半段译文"}}]}
        """)
        await assertFailure(.truncatedOutput)
    }

    // MARK: - HTTP failures

    func testHTTPStatusMapping() async {
        let cases: [(Int, TranslationFailure)] = [
            (401, .invalidKey),
            (429, .rateLimited),
            (400, .invalidResponse),
            (402, .invalidResponse),
            (500, .invalidResponse),
            (503, .invalidResponse),
        ]
        for (status, expected) in cases {
            FakeHTTPClient.shared.reset()
            FakeHTTPClient.shared.enqueue(status: status, body: "{\"error\":\"whatever\"}")
            await assertFailure(expected, note: "status \(status)")
        }
    }

    func testFailureNeverCarriesTheRawResponseBody() async {
        FakeHTTPClient.shared.enqueue(status: 500, body: "secret-looking-detail-from-the-server")
        do {
            _ = try await translate()
            XCTFail("expected a failure")
        } catch let failure as TranslationFailure {
            XCTAssertFalse(failure.message.contains("secret-looking-detail-from-the-server"))
        } catch {
            XCTFail("unexpected error type")
        }
    }

    // MARK: - Transport

    func testOfflineIsNetworkFailure() async {
        FakeHTTPClient.shared.enqueueError(URLError(.notConnectedToInternet))
        await assertFailure(.network)
    }

    func testTimeoutIsTimeoutFailure() async {
        FakeHTTPClient.shared.enqueueError(URLError(.timedOut))
        await assertFailure(.timeout)
    }

    func testCancellationIsCancelledFailure() async {
        FakeHTTPClient.shared.enqueueError(URLError(.cancelled))
        await assertFailure(.cancelled)
    }

    // MARK: - Configuration

    func testMissingKeyNeverReachesTheNetwork() async {
        let result = await translateResult(apiKey: "   ")
        XCTAssertEqual(result.failure, .apiKeyMissing)
        XCTAssertEqual(FakeHTTPClient.shared.requestCount, 0)
    }

    func testPlainHTTPEndpointIsRefused() async {
        let insecure = DeepSeekTranslationService(client: FakeHTTPClient.shared,
                                                  endpoint: URL(string: "http://api.deepseek.com/chat/completions")!)
        let result = await translateResult(insecure, apiKey: "sk-test")
        XCTAssertEqual(result.failure, .configuration)
        XCTAssertEqual(FakeHTTPClient.shared.requestCount, 0)
    }

    private func assertFailure(_ expected: TranslationFailure,
                               note: String = "",
                               file: StaticString = #filePath,
                               line: UInt = #line) async {
        let result = await translateResult()
        XCTAssertEqual(result.failure, expected, note, file: file, line: line)
    }
}

private extension Result where Success == TranslationResult, Failure == TranslationFailure {
    var failure: TranslationFailure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}

private extension TranslationServiceTests {
    func translateResult(_ service: DeepSeekTranslationService,
                         _ text: String = "charge",
                         apiKey: String = "sk-test",
                         model: String = "deepseek-flash") async -> Result<TranslationResult, TranslationFailure> {
        do {
            return .success(try await service.translate(TranslationRequest(text: text),
                                                        apiKey: apiKey,
                                                        model: model))
        } catch let failure as TranslationFailure {
            return .failure(failure)
        } catch {
            return .failure(.network)
        }
    }

    func translateResult(apiKey: String) async -> Result<TranslationResult, TranslationFailure> {
        await translateResult(service(), "charge", apiKey: apiKey)
    }
}

/// The fake network: records every request and replays scripted responses.
final class FakeHTTPClient: HTTPPerforming, @unchecked Sendable {
    static let shared = FakeHTTPClient()

    private let lock = NSLock()
    private var responses: [Result<HTTPResponse, Error>] = []
    private var requests: [URLRequest] = []

    func enqueueJSON(_ json: String, status: Int = 200) {
        enqueue(status: status, body: json)
    }

    func enqueue(status: Int, body: String) {
        lock.lock(); defer { lock.unlock() }
        responses.append(.success(HTTPResponse(statusCode: status, body: Data(body.utf8))))
    }

    func enqueueError(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        responses.append(.failure(error))
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        responses.removeAll()
        requests.removeAll()
    }

    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }

    func postJSON(url: URL,
                  body: Data,
                  headers: [String: String],
                  timeout: TimeInterval) async throws -> HTTPResponse {
        lock.lock()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        requests.append(request)
        let next = responses.isEmpty ? nil : responses.removeFirst()
        lock.unlock()
        guard let next else { throw TranslationFailure.network }
        switch next {
        case .success(let response):
            return response
        case .failure(let error as URLError):
            // Mirrors URLSessionHTTPClient: a cancelled or timed-out transport
            // failure is not a generic network failure.
            switch error.code {
            case .cancelled: throw TranslationFailure.cancelled
            case .timedOut: throw TranslationFailure.timeout
            default: throw TranslationFailure.network
            }
        case .failure:
            throw TranslationFailure.network
        }
    }
}
