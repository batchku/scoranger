import XCTest

/// The two things that went wrong in Ali's arrange chat, held apart.
///
/// He saw this in the transcript:
///
///     Unexpected OpenRouter response: {"error":{"message":"Corrupted thought
///     signature.","code":400}}
///
/// The bodies below are not invented. Each was captured from the live provider
/// while reproducing the failure: the flat shape is Ali's own, arriving as HTTP
/// 200 with an error object and no `choices` -- which is exactly why the app
/// fell through to its "I did not recognise this" branch and printed the
/// evidence at him. The nested shape is what the same failure looks like when
/// OpenRouter wraps it, with the provider's real words two envelopes down in
/// `error.metadata.raw`, itself a string of JSON that has to be parsed again.
final class ChatWireTests: XCTestCase {

    private func fault(_ body: String, status: Int) -> ChatWire.Fault? {
        ChatWire.fault(in: Data(body.utf8), status: status)
    }

    // the body Ali got, verbatim
    private let alis = #"{"error":{"message":"Corrupted thought signature.","code":400}}"#

    // the same failure as OpenRouter wraps it, captured by truncating a
    // signature blob and re-sending the conversation
    private let wrapped = #"""
    {"error":{"message":"Provider returned error","code":400,"metadata":{"raw":"{\n  \"error\": {\n    \"code\": 400,\n    \"message\": \"Corrupted thought signature.\",\n    \"status\": \"INVALID_ARGUMENT\"\n  }\n}\n","provider_name":"Google AI Studio","is_byok":false,"provider_error_code":"400"}}}
    """#

    func testAlisErrorIsRecognisedForWhatItIs() throws {
        let fault = try XCTUnwrap(fault(alis, status: 200),
                                 "a 200 with an error object is not a success")
        XCTAssertEqual(fault.kind, .staleReasoning)
        XCTAssertTrue(fault.isRetryable)
    }

    func testTheWrappedShapeFindsTheProvidersOwnWords() throws {
        let fault = try XCTUnwrap(fault(wrapped, status: 400))
        XCTAssertEqual(fault.kind, .staleReasoning,
                       "the real message is two envelopes down, not \"Provider returned error\"")
        XCTAssertEqual(fault.providerMessage, "Corrupted thought signature")
    }

    func testNoFaultRaisedOnASuccess() {
        let ok = #"{"choices":[{"message":{"role":"assistant","content":"Done."}}]}"#
        XCTAssertNil(fault(ok, status: 200))
    }

    func testAProviderMessageNeverReachesTheReaderAsJSON() {
        // every shape, including ones designed to smuggle the envelope through
        let bodies = [
            alis, wrapped,
            #"{"error":"{\"nested\":\"json as a bare string\"}"}"#,
            #"{"error":{"message":"{\"code\":400}"}}"#,
            #"{"error":{"message":"Provider returned error","metadata":{"raw":"{\"x\":1}"}}}"#,
            "not json at all",
            "",
        ]
        for body in bodies {
            guard let fault = fault(body, status: 400) else { continue }
            XCTAssertFalse(fault.readable.contains("{"),
                           "a JSON brace reached the reader from: \(body.prefix(40))")
            XCTAssertFalse(fault.readable.contains("\"message\""),
                           "an envelope key reached the reader from: \(body.prefix(40))")
            XCTAssertFalse(fault.readable.isEmpty, "every fault says something")
        }
    }

    func testTheReaderIsToldWhatToDo() throws {
        let stale = try XCTUnwrap(fault(alis, status: 200)).readable
        XCTAssertTrue(stale.contains("again"), "a retryable fault should ask for a retry")
        XCTAssertTrue(stale.lowercased().contains("version"),
                      "tools that already ran already made versions; say so")
        XCTAssertFalse(stale.contains("thought signature"),
                       "the provider's jargon is not the reader's problem")
    }

    func testTheOtherFaultsAreToldApart() throws {
        let busy = #"{"error":{"message":"Rate limit exceeded: free-models-per-day","code":429}}"#
        XCTAssertEqual(try XCTUnwrap(fault(busy, status: 429)).kind, .busy)
        let credits = #"{"error":{"message":"Insufficient credits","code":402}}"#
        XCTAssertEqual(try XCTUnwrap(fault(credits, status: 402)).kind, .busy)
        let key = #"{"error":{"message":"No auth credentials found","code":401}}"#
        XCTAssertEqual(try XCTUnwrap(fault(key, status: 401)).kind, .credentials)
        let odd = #"{"error":{"message":"Model does not support tools","code":400}}"#
        let other = try XCTUnwrap(fault(odd, status: 400))
        XCTAssertEqual(other.kind, .other)
        XCTAssertFalse(other.isRetryable)
        XCTAssertTrue(other.readable.contains("Model does not support tools"),
                      "an unexplained refusal should still carry the provider's sentence")
    }

    func testAnUnreadableBodyIsAFaultAndNotACrash() throws {
        let fault = try XCTUnwrap(fault("<html>502 Bad Gateway</html>", status: 502))
        XCTAssertEqual(fault.kind, .busy, "a gateway status is a busy provider")
        XCTAssertTrue(fault.isRetryable)
    }

    // MARK: the reasoning state itself

    private var conversation: [[String: Any]] {
        [["role": "system", "content": "You are Scoranger's arrangement agent."],
         ["role": "user", "content": "Harmonise a sixth below."],
         ["role": "assistant",
          "content": "",
          "reasoning": NSNull(),
          "reasoning_details": [["type": "reasoning.encrypted",
                                 "format": "google-gemini-v1",
                                 "data": "AY89a1/7lpVIIErGpyaFiBJ",
                                 "id": "call_1802374", "index": 0]],
          "tool_calls": [["id": "call_1802374", "type": "function",
                          "function": ["name": "get_score_info", "arguments": "{}"]]]],
         ["role": "tool", "tool_call_id": "call_1802374", "content": #"{"ok":true}"#]]
    }

    func testStrippingTakesTheReasoningAndNothingElse() throws {
        XCTAssertTrue(ChatWire.carriesReasoning(conversation))
        let stripped = ChatWire.withoutReasoning(conversation)
        XCTAssertFalse(ChatWire.carriesReasoning(stripped))
        XCTAssertEqual(stripped.count, conversation.count, "no message is dropped")

        let assistant = stripped[2]
        XCTAssertNil(assistant["reasoning_details"])
        XCTAssertNil(assistant["reasoning"])
        // what the model needs to know what it did is all still there
        let calls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls.first?["id"] as? String, "call_1802374")
        XCTAssertEqual(assistant["content"] as? String, "")
        // and the tool result still answers that call, or the history is broken
        XCTAssertEqual(stripped[3]["tool_call_id"] as? String, "call_1802374")
        XCTAssertEqual(stripped[0]["role"] as? String, "system")
        XCTAssertEqual(stripped[1]["content"] as? String, "Harmonise a sixth below.")
    }

    func testStrippingATurnWithNoReasoningChangesNothing() {
        let plain: [[String: Any]] = [["role": "user", "content": "hello"]]
        XCTAssertFalse(ChatWire.carriesReasoning(plain))
        XCTAssertEqual(ChatWire.withoutReasoning(plain).count, 1)
        XCTAssertEqual(ChatWire.withoutReasoning(plain)[0]["content"] as? String, "hello")
    }

    func testAReasoningBlobOnAUserMessageIsLeftAlone() {
        // only the assistant's own state is the provider's to reject; nothing
        // else should be quietly rewritten on the way out
        let odd: [[String: Any]] = [["role": "user", "content": "hi", "reasoning": "mine"]]
        XCTAssertEqual(ChatWire.withoutReasoning(odd)[0]["reasoning"] as? String, "mine")
    }
}
