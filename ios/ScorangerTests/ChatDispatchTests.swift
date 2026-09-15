import Foundation
import XCTest

/// What the app does with a tool call, asserted against a STUBBED model.
///
/// The app is chat-driven and this path had no test at all. What a model
/// chooses to say is judgement and stays a manual question; what the code does
/// once a tool call arrives is not, and that is all this asserts.
///
/// The stub is the provider's own wire shape: an assistant message with
/// `tool_calls`, the arguments as a STRING of JSON, captured from the format
/// OpenRouter returns. Nothing here opens a connection or reads a key --
/// `ChatTools` is pure, which is why it was lifted out of `LocalChat` (this
/// bundle has no host app and could never have compiled the engine, the
/// Keychain and URLSession beside it).
///
/// The table under test is the shipping one: `ChatTools.all` is what
/// `LocalChat` hands the provider and what `LocalChat.dispatch` looks a call up
/// in. A test that built its own table would assert nothing.
final class ChatDispatchTests: XCTestCase {

    // MARK: - the stub

    /// One assistant message as a provider writes it.
    private func assistantMessage(_ calls: [(String, String)]) -> [String: Any] {
        ["role": "assistant",
         "content": NSNull(),
         "tool_calls": calls.enumerated().map { index, call in
             ["id": "call_\(index)", "type": "function",
              "function": ["name": call.0, "arguments": call.1]]
         }]
    }

    /// The whole journey a tool call makes inside the app: the provider's
    /// message in, the bridge op and its arguments out.
    private func dispatch(_ name: String, _ argsJSON: String,
                          slug: String = "sous-le-ciel-de-paris") throws -> ChatTools.Call {
        let calls = ChatTools.toolCalls(in: assistantMessage([(name, argsJSON)]))
        XCTAssertEqual(calls.count, 1)
        let first = try XCTUnwrap(calls.first)
        XCTAssertEqual(first.name, name)
        XCTAssertFalse(first.id.isEmpty, "a tool result has to be addressed back to its call")
        return try XCTUnwrap(ChatTools.call(named: first.name, argsJSON: first.argsJSON,
                                            slug: slug),
                             "the shipping table has no tool called \(name)")
    }

    // MARK: - the three tools this build wired, and the one it found missing

    /// `add-element`, `move-element` and `duplicate-element` existed as ops,
    /// in the CLI and in `bridge.py` for a whole build while the on-device
    /// agent was never told about them. A model cannot reach what is not
    /// described to it.
    func testTheMarkToolsReachTheirBridgeOps() throws {
        let add = try dispatch("add_element", #"""
            {"part": "Violin I", "kind": "dynamic", "measure": 5, "value": "mf", "offset": 1.5, "placement": "below"}
            """#)
        XCTAssertEqual(add.op, "add-element")
        XCTAssertEqual(add.args["part"] as? String, "Violin I")
        XCTAssertEqual(add.args["kind"] as? String, "dynamic")
        XCTAssertEqual(add.args["measure"] as? Int, 5)
        XCTAssertEqual(add.args["value"] as? String, "mf")
        XCTAssertEqual(add.args["offset"] as? Double, 1.5)
        XCTAssertEqual(add.args["placement"] as? String, "below")

        let move = try dispatch("move_element", #"""
            {"part": "Violin I", "kind": "fermata", "measure": 5, "ordinal": 1, "to_measure": 9, "to_offset": 0}
            """#)
        XCTAssertEqual(move.op, "move-element")
        XCTAssertEqual(move.args["to_measure"] as? Int, 9)
        XCTAssertEqual(move.args["ordinal"] as? Int, 1)

        let copy = try dispatch("duplicate_element", #"""
            {"part": "Violin I", "kind": "articulation", "measure": 5, "to_measure": 9, "to_offset": 2.0}
            """#)
        XCTAssertEqual(copy.op, "duplicate-element")
        XCTAssertEqual(copy.args["to_offset"] as? Double, 2.0)
    }

    /// Found in step 4: the engine has had `strip-notes` and the CLI reference
    /// has documented it since before the bridge existed, and nothing in the
    /// app could ask for it.
    func testStripNotesIsReachable() throws {
        let call = try dispatch("strip_notes", #"{"part": "Acc. Chords"}"#)
        XCTAssertEqual(call.op, "strip-notes")
        XCTAssertEqual(call.args["part"] as? String, "Acc. Chords")
    }

    /// Size is RELATIVE to the engraved default, and `scale` is how it is
    /// asked for. The app's chord-symbol row still holds a point value and
    /// sends `size`; both reach the same op, which refuses the two together.
    func testAdjustCarriesAScaleAndASizeSeparately() throws {
        let scaled = try dispatch("adjust_element", #"""
            {"part": "Violin I", "kind": "dynamic", "measure": 5, "scale": 1.5}
            """#)
        XCTAssertEqual(scaled.op, "adjust-element")
        XCTAssertEqual(scaled.args["scale"] as? Double, 1.5)
        XCTAssertNil(scaled.args["size"])

        let sized = try dispatch("adjust_element", #"""
            {"part": "Violin I", "kind": "harm", "measure": 1, "size": 14}
            """#)
        XCTAssertEqual(sized.args["size"] as? Int, 14)
        XCTAssertNil(sized.args["scale"])
    }

    // MARK: - argument shaping

    /// The model writes the tool's argument names; the bridge takes its own.
    /// Every one of these renames is a place the two have already disagreed.
    func testEveryRenamedArgumentArrivesUnderTheBridgesName() throws {
        let instrument = try dispatch("change_instrument",
                                      #"{"part": "Violoncello", "to_instrument": "Viola"}"#)
        XCTAssertEqual(instrument.args["to"] as? String, "Viola")
        XCTAssertNil(instrument.args["to_instrument"], "the tool's own name must not survive")

        let merge = try dispatch("merge_parts",
                                 #"{"parts": ["Viola", "Violoncello"], "new_name": "Accordion L.H."}"#)
        XCTAssertEqual(merge.args["name"] as? String, "Accordion L.H.")
        XCTAssertEqual(merge.args["parts"] as? [String], ["Viola", "Violoncello"])

        let pull = try dispatch("pull_part",
                                #"{"from_ref": "arr:quartet", "part": "Violin II", "as_name": "Harmony"}"#)
        XCTAssertEqual(pull.args["from"] as? String, "arr:quartet")
        XCTAssertEqual(pull.args["as"] as? String, "Harmony")

        let piece = try dispatch("assign_to_piece", #"{"piece_name": "Reels"}"#)
        XCTAssertEqual(piece.args["piece"] as? String, "Reels")
    }

    /// The model is never told which arrangement it is working on, so it
    /// cannot name the wrong one: the slug is added here, after the rename.
    func testTheScoreIsAddedAndCannotBeOverriddenByTheModel() throws {
        let call = try dispatch("transpose", #"{"interval": "M2", "score": "some-other-score"}"#,
                                slug: "the-real-one")
        XCTAssertEqual(call.args["score"] as? String, "the-real-one")
    }

    /// An invented tool name is nil rather than a guess -- `LocalChat` turns
    /// that into an error the model reads and corrects.
    func testAnInventedToolIsNotGuessedAt() {
        XCTAssertNil(ChatTools.call(named: "make_it_sound_nicer", argsJSON: "{}", slug: "x"))
    }

    /// Models do write malformed argument blobs. The call still reaches the
    /// engine, which refuses it in words the model can act on; what must not
    /// happen is the app deciding for itself what was meant.
    func testMalformedArgumentsStillCarryTheScoreAndNothingInvented() throws {
        let call = try XCTUnwrap(ChatTools.call(named: "transpose",
                                                argsJSON: "{not json at all",
                                                slug: "jig"))
        XCTAssertEqual(call.op, "transpose")
        XCTAssertEqual(call.args.count, 1)
        XCTAssertEqual(call.args["score"] as? String, "jig")
    }

    /// A model may ask for several things in one message; they dispatch in the
    /// order it wrote them, each with its own id.
    func testSeveralCallsInOneMessageDispatchInOrder() {
        let message = assistantMessage([
            ("get_score_info", "{}"),
            // `"#0"` is a part index, and it needs the extra pound: `"#` ends
            // a `#"..."#` raw string.
            ("add_element", ##"{"part": "#0", "kind": "fermata", "measure": 16}"##),
            ("adjust_element", ##"{"part": "#0", "kind": "fermata", "measure": 16, "scale": 2}"##),
        ])
        let calls = ChatTools.toolCalls(in: message)
        XCTAssertEqual(calls.map(\.name),
                       ["get_score_info", "add_element", "adjust_element"])
        XCTAssertEqual(Set(calls.map(\.id)).count, 3, "two tool results would answer one call")
        XCTAssertEqual(calls.compactMap { ChatTools.call(named: $0.name, argsJSON: $0.argsJSON,
                                                         slug: "jig")?.op },
                       ["info", "add-element", "adjust-element"])
    }

    /// An assistant message with no tool calls is the end of the turn, not an
    /// empty dispatch.
    func testAPlainReplyDispatchesNothing() {
        XCTAssertTrue(ChatTools.toolCalls(in: ["role": "assistant",
                                               "content": "I have transposed it."]).isEmpty)
    }

    // MARK: - the table the model is handed

    func testTheToolListIsWellFormedAndUnique() throws {
        let json = ChatTools.json
        XCTAssertEqual(json.count, ChatTools.all.count)
        var names: Set<String> = []
        for entry in json {
            XCTAssertEqual(entry["type"] as? String, "function")
            let function = try XCTUnwrap(entry["function"] as? [String: Any])
            let name = try XCTUnwrap(function["name"] as? String)
            XCTAssertTrue(names.insert(name).inserted, "two tools called \(name)")
            let description = try XCTUnwrap(function["description"] as? String)
            XCTAssertGreaterThan(description.count, 20,
                                 "\(name) is described too thinly to be chosen correctly")
            let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
            XCTAssertEqual(parameters["type"] as? String, "object")
            XCTAssertNotNil(parameters["properties"] as? [String: Any])
            let required = try XCTUnwrap(parameters["required"] as? [String])
            let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
            for key in required {
                XCTAssertNotNil(properties[key],
                                "\(name) requires '\(key)' and never describes it")
            }
            // JSONSerialization is what puts this on the wire; a value it
            // cannot encode takes the whole turn down with it.
            XCTAssertTrue(JSONSerialization.isValidJSONObject(entry), name)
        }
        XCTAssertTrue(names.isSuperset(of: ["add_element", "move_element",
                                            "duplicate_element", "strip_notes"]))
    }

    /// The description is the only thing standing between a reader saying
    /// "make that dynamic bigger" and a model sending a point size.
    func testAdjustIsDescribedAsRelative() throws {
        let spec = try XCTUnwrap(ChatTools.all.first { $0.name == "adjust_element" })
        XCTAssertTrue(spec.description.contains("SIZE IS RELATIVE"), spec.description)
        XCTAssertFalse(spec.description.contains("size is an absolute point size (12 is the default)"),
                       "the old wording described the interface that no longer exists")
        let properties = try XCTUnwrap(spec.parameters["properties"] as? [String: Any])
        XCTAssertNotNil(properties["scale"])
    }

    // MARK: - what the reader watches while it runs

    func testTheStepLineNamesTheMusicAndNotTheTool() {
        XCTAssertEqual(ChatSteps.stepTitle(name: "add_element",
                                           argsJSON: #"{"kind": "dynamic", "measure": 5}"#),
                       "Adding a dynamic at bar 5")
        XCTAssertEqual(ChatSteps.stepTitle(name: "move_element",
                                           argsJSON: #"{"kind": "fermata", "to_measure": 9}"#),
                       "Moving the fermata to bar 9")
        XCTAssertEqual(ChatSteps.stepTitle(name: "duplicate_element",
                                           argsJSON: #"{"kind": "articulation", "to_measure": 12}"#),
                       "Copying the articulation into bar 12")
        XCTAssertEqual(ChatSteps.stepTitle(name: "strip_notes",
                                           argsJSON: #"{"part": "Acc. Chords"}"#),
                       "Clearing the notes from Acc. Chords")
        // relative first, because relative is the interface
        XCTAssertEqual(ChatSteps.stepTitle(name: "adjust_element",
                                           argsJSON: #"{"kind": "text", "scale": 1.5}"#),
                       "Resizing the text mark to 1.5x")
        XCTAssertEqual(ChatSteps.stepTitle(name: "adjust_element",
                                           argsJSON: #"{"kind": "harm", "size": 14}"#),
                       "Setting the chord name to 14pt")
    }
}
