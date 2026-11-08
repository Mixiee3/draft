import XCTest
import DraftCore
@testable import DraftAssistant

final class OpenAIResponsesTests: XCTestCase {
    private final class StubProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let body = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello\"}\n\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\" world\"}\n\ndata: {\"type\":\"response.completed\"}\n\n"
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func testStreamingParserCollectsTextAndCompletion() throws {
        var parser = OpenAISSEParser()
        XCTAssertNil(try parser.feed("event: response.output_text.delta"))
        XCTAssertNil(try parser.feed(#"data: {"type":"response.output_text.delta","delta":"Hello "}"#))
        XCTAssertEqual(try parser.feed(""), "Hello ")
        XCTAssertNil(try parser.feed(#"data: {"type":"response.output_text.delta","delta":"world"}"#))
        XCTAssertEqual(try parser.feed(""), "world")
        XCTAssertNil(try parser.feed(#"data: {"type":"response.completed"}"#))
        _ = try parser.feed("")
        XCTAssertEqual(parser.answer, "Hello world")
        XCTAssertTrue(parser.completed)
    }

    func testStreamingParserSurfacesFailure() throws {
        var parser = OpenAISSEParser()
        _ = try parser.feed(#"data: {"type":"response.failed","response":{"error":{"message":"unavailable"}}}"#)
        XCTAssertThrowsError(try parser.feed("")) { error in
            XCTAssertEqual(error as? OpenAIError, .failed("unavailable"))
        }
    }

    func testRequestUsesOnlySuppliedTurnsAndDoesNotStoreServerSide() throws {
        let client = OpenAIResponsesClient()
        let request = try client.makeRequest([ChatTurn("system", "Use only these notes"), ChatTurn("user", "Selected sentence")], model: "test-model", apiKey: "test-key")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["instructions"] as? String, "Use only these notes")
        let input = try XCTUnwrap(json["input"] as? [[String: String]])
        XCTAssertEqual(input, [["role": "user", "content": "Selected sentence"]])
        XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("private diary"))
    }

    func testClientStreamsFromAStubbedResponse() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let client = OpenAIResponsesClient(session: URLSession(configuration: config))
        var pieces: [String] = []
        let answer = try await client.generate([ChatTurn("system", "Be brief"), ChatTurn("user", "Say hello")], model: "test", apiKey: "test-key") { pieces.append($0) }
        XCTAssertEqual(answer, "Hello world")
        XCTAssertEqual(pieces, ["Hello", " world"])
    }
}
