import Foundation

/// One HTTP result, reduced to what the failure classifier needs.
struct HTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
}

/// The seam that keeps the network replaceable in tests. The API key is a
/// parameter, never stored on the client.
protocol HTTPPerforming: Sendable {
    func postJSON(url: URL,
                  body: Data,
                  headers: [String: String],
                  timeout: TimeInterval) async throws -> HTTPResponse
}

/// Official chat-completions endpoint. Verified 2026-09-17 against
/// `https://api-docs.deepseek.com/api/create-chat-completion`.
enum DeepSeekEndpoint {
    static let chatCompletions = URL(string: "https://api.deepseek.com/chat/completions")!
}

/// Refuses every HTTP redirect, so a key that was accepted for the official
/// host can never be forwarded to a host the app does not know.
final class RedirectRefusingSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct URLSessionHTTPClient: HTTPPerforming {
    let session: URLSession

    init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        // No cookies, no credential storage, no disk cache for source text.
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        session = URLSession(configuration: configuration,
                             delegate: RedirectRefusingSessionDelegate(),
                             delegateQueue: nil)
    }

    func postJSON(url: URL,
                  body: Data,
                  headers: [String: String],
                  timeout: TimeInterval) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeout
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TranslationFailure.invalidResponse }
            return HTTPResponse(statusCode: http.statusCode, body: data)
        } catch let failure as TranslationFailure {
            throw failure
        } catch is CancellationError {
            throw TranslationFailure.cancelled
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw TranslationFailure.cancelled
            case .timedOut: throw TranslationFailure.timeout
            default: throw TranslationFailure.network
            }
        } catch {
            throw TranslationFailure.network
        }
    }
}

/// DeepSeek chat-completions adapter: non-streaming, no retries, no raw
/// response ever surfaced. Only status code, duration and generation are
/// logged; never the key, the request body or the response body.
struct DeepSeekTranslationService: TranslationService {
    let client: HTTPPerforming
    let endpoint: URL
    let timeout: TimeInterval

    init(client: HTTPPerforming = URLSessionHTTPClient(),
         endpoint: URL = DeepSeekEndpoint.chatCompletions,
         timeout: TimeInterval = 15) {
        self.client = client
        self.endpoint = endpoint
        self.timeout = timeout
    }

    func translate(_ request: TranslationRequest, apiKey: String, model: String) async throws -> TranslationResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranslationFailure.apiKeyMissing }
        guard let scheme = endpoint.scheme?.lowercased(), scheme == "https" else {
            throw TranslationFailure.configuration
        }
        let requestedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedModel.isEmpty else { throw TranslationFailure.configuration }

        let body: Data
        do {
            body = try TranslationRequestBuilder.makeBody(text: request.text,
                                                          context: request.context,
                                                          model: requestedModel,
                                                          mode: request.mode,
                                                          targetLanguage: request.targetLanguage)
        } catch {
            throw TranslationFailure.configuration
        }

        let response = try await client.postJSON(url: endpoint,
                                                 body: body,
                                                 headers: ["Authorization": "Bearer \(key)",
                                                           "Content-Type": "application/json",
                                                           "Accept": "application/json"],
                                                 timeout: timeout)

        if let failure = HTTPFailureMapper.map(statusCode: response.statusCode) {
            throw failure
        }
        return try Self.parse(response.body)
    }

    /// Only a natural stop with non-empty content counts as a translation.
    static func parse(_ data: Data) throws -> TranslationResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let choice = choices.first else {
            throw TranslationFailure.invalidResponse
        }
        let finishReason = choice["finish_reason"] as? String
        if finishReason == "length" { throw TranslationFailure.truncatedOutput }
        guard finishReason == "stop" else { throw TranslationFailure.invalidResponse }
        guard let message = choice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationFailure.invalidResponse
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // A thinking-only reply (reasoning_content, no answer) is not a result.
        guard !text.isEmpty else { throw TranslationFailure.invalidResponse }
        return TranslationResult(text: text,
                                 model: root["model"] as? String ?? "unknown",
                                 provider: "deepseek",
                                 promptVersion: TranslationRequestBuilder.promptVersion)
    }
}
