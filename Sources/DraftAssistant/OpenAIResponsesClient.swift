import Foundation
import DraftCore

public enum OpenAIError: LocalizedError, Equatable {
    case missingKey
    case invalidResponse
    case http(Int)
    case failed(String)
    case emptyAnswer

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Add an OpenAI API key in Settings → Assistant."
        case .invalidResponse: return "The OpenAI response could not be read."
        case .http(401): return "The OpenAI API key was rejected. Check it in Settings → Assistant."
        case .http(403): return "This API key cannot use the selected model."
        case .http(429): return "The OpenAI API rate or usage limit was reached. Try again later."
        case .http(let code): return "OpenAI returned HTTP \(code). Try again later."
        case .failed(let message): return "OpenAI could not finish the answer: \(message)"
        case .emptyAnswer: return "OpenAI returned no text."
        }
    }
}

public struct OpenAISSEParser {
    private var dataLines: [String] = []
    public private(set) var answer = ""
    public private(set) var completed = false

    public init() {}

    /// Feed one UTF-8 line. An empty line ends an SSE event.
    public mutating func feed(_ line: String) throws -> String? {
        if line.isEmpty {
            defer { dataLines.removeAll(keepingCapacity: true) }
            guard !dataLines.isEmpty else { return nil }
            let payload = dataLines.joined(separator: "\n")
            guard payload != "[DONE]", let bytes = payload.data(using: .utf8),
                  let event = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let type = event["type"] as? String else { return nil }
            switch type {
            case "response.output_text.delta":
                let delta = event["delta"] as? String ?? ""
                answer += delta
                return delta
            case "response.completed":
                completed = true
            case "response.failed", "error":
                let nested = event["response"] as? [String: Any]
                let error = (nested?["error"] as? [String: Any]) ?? (event["error"] as? [String: Any])
                throw OpenAIError.failed(error?["message"] as? String ?? event["message"] as? String ?? "Unknown error")
            default: break
            }
            return nil
        }
        if line.hasPrefix("data:") { dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    public mutating func finish() throws {
        if !dataLines.isEmpty { _ = try feed("") }
    }
}

public final class OpenAIResponsesClient {
    private let session: URLSession
    private let endpoint: URL

    public init(session: URLSession = .shared, endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!) {
        self.session = session
        self.endpoint = endpoint
    }

    public func generate(_ turns: [ChatTurn], model: String, apiKey: String, onDelta: @escaping (String) -> Void) async throws -> String {
        let request = try makeRequest(turns, model: model, apiKey: apiKey)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw OpenAIError.http(http.statusCode) }
        var parser = OpenAISSEParser()
        var lineBytes: [UInt8] = []
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte == 10 {
                if lineBytes.last == 13 { lineBytes.removeLast() }
                let line = String(decoding: lineBytes, as: UTF8.self)
                if let delta = try parser.feed(line), !delta.isEmpty { onDelta(delta) }
                lineBytes.removeAll(keepingCapacity: true)
            } else {
                lineBytes.append(byte)
                guard lineBytes.count < 2_000_000 else { throw OpenAIError.invalidResponse }
            }
        }
        if !lineBytes.isEmpty {
            if lineBytes.last == 13 { lineBytes.removeLast() }
            if let delta = try parser.feed(String(decoding: lineBytes, as: UTF8.self)), !delta.isEmpty { onDelta(delta) }
        }
        try parser.finish()
        guard parser.completed else { throw OpenAIError.invalidResponse }
        guard !parser.answer.isEmpty else { throw OpenAIError.emptyAnswer }
        return parser.answer
    }

    func makeRequest(_ turns: [ChatTurn], model: String, apiKey: String) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenAIError.missingKey }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        let instructions = turns.filter { $0.role == "system" }.map(\.text).joined(separator: "\n\n")
        let input = turns.filter { $0.role == "user" || $0.role == "assistant" }.map { ["role": $0.role, "content": $0.text] }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "instructions": instructions, "input": input,
            "stream": true, "store": false, "max_output_tokens": 2048,
        ] as [String: Any])

        return request
    }
}
