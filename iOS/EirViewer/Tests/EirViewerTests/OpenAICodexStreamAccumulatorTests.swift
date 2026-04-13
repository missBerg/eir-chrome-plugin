import XCTest
@testable import EirViewer

final class OpenAICodexStreamAccumulatorTests: XCTestCase {

    func testParsesStandardSSEOutputTextDeltas() throws {
        var parser = OpenAICodexStreamAccumulator(responseContentType: "text/event-stream")
        var tokens: [String] = []

        try feed(
            [
                "event: response.output_text.delta",
                #"data: {"delta":"Hej ","type":"response.output_text.delta"}"#,
                "",
                "event: response.output_text.delta",
                #"data: {"delta":"varlden","type":"response.output_text.delta"}"#,
                "",
                "event: response.completed",
                #"data: {"type":"response.completed","response":{"output":[]}}"#,
                "",
            ],
            to: &parser,
            tokens: &tokens
        )

        let result = try parser.finish { tokens.append($0) }
        XCTAssertEqual(tokens, ["Hej ", "varlden"])
        XCTAssertText(result, equals: "Hej varlden")
    }

    func testParsesDataOnlyEventUsingJsonTypeField() throws {
        var parser = OpenAICodexStreamAccumulator(responseContentType: "")
        var tokens: [String] = []

        try feed(
            [
                #"data: {"type":"response.output_text.delta","delta":"Hello"}"#,
                "",
            ],
            to: &parser,
            tokens: &tokens
        )

        let result = try parser.finish { tokens.append($0) }
        XCTAssertEqual(tokens, ["Hello"])
        XCTAssertText(result, equals: "Hello")
    }

    func testFallsBackToCompletedMessageOutputWhenNoDeltasArrive() throws {
        var parser = OpenAICodexStreamAccumulator(responseContentType: "text/event-stream")
        var tokens: [String] = []

        try feed(
            [
                "event: response.completed",
                #"data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"Final answer"}]}]}}"#,
                "",
            ],
            to: &parser,
            tokens: &tokens
        )

        let result = try parser.finish { tokens.append($0) }
        XCTAssertEqual(tokens, ["Final answer"])
        XCTAssertText(result, equals: "Final answer")
    }

    func testBuildsToolCallsFromArgumentDeltasAndDoneEvent() throws {
        var parser = OpenAICodexStreamAccumulator(responseContentType: "text/event-stream")

        try feed(
            [
                "event: response.function_call_arguments.delta",
                #"data: {"type":"response.function_call_arguments.delta","item_id":"fc_item_1","delta":"{\"entry_id\":\"entry_002\""}"#,
                "",
                "event: response.function_call_arguments.delta",
                #"data: {"type":"response.function_call_arguments.delta","item_id":"fc_item_1","delta":"}"}"#,
                "",
                "event: response.output_item.done",
                #"data: {"type":"response.output_item.done","item":{"type":"function_call","id":"fc_item_1","call_id":"call_1","name":"open_journal_entry"}}"#,
                "",
            ],
            to: &parser
        )

        let result = try parser.finish { _ in }
        guard case .toolCalls(let calls) = result else {
            return XCTFail("Expected tool calls result.")
        }

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].id, "call_1|fc_item_1")
        XCTAssertEqual(calls[0].name, "open_journal_entry")
        XCTAssertEqual(calls[0].arguments, #"{"entry_id":"entry_002"}"#)
    }

    func testThrowsReadableFailureFromResponseFailedEvent() throws {
        var parser = OpenAICodexStreamAccumulator(responseContentType: "text/event-stream")

        XCTAssertThrowsError(try feed(
            [
                "event: response.failed",
                #"data: {"type":"response.failed","response":{"error":{"message":"Bad request","code":"invalid_request"}}}"#,
                "",
            ],
            to: &parser
        )) { error in
            guard case LLMError.requestFailed(let message) = error else {
                return XCTFail("Expected requestFailed error, got \(error)")
            }
            XCTAssertEqual(message, "Bad request (invalid_request)")
        }
    }

    func testReportsClosedStreamWithPreviewWhenNoReadableEventsArrive() throws {
        var parser = OpenAICodexStreamAccumulator(responseContentType: "")

        try feed(
            [
                #"{"foo":"bar"}"#,
                "",
            ],
            to: &parser
        )

        XCTAssertThrowsError(try parser.finish { _ in }) { error in
            guard case LLMError.requestFailed(let message) = error else {
                return XCTFail("Expected requestFailed error, got \(error)")
            }
            XCTAssertTrue(message.contains("stream closed before readable Codex events arrived"))
            XCTAssertTrue(message.contains(#"Preview: {"foo":"bar"}"#))
        }
    }

    private func feed(
        _ lines: [String],
        to parser: inout OpenAICodexStreamAccumulator,
        tokens: inout [String]
    ) throws {
        for line in lines {
            try parser.consume(rawLine: line) { tokens.append($0) }
        }
    }

    private func feed(
        _ lines: [String],
        to parser: inout OpenAICodexStreamAccumulator
    ) throws {
        var tokens: [String] = []
        try feed(lines, to: &parser, tokens: &tokens)
    }

    private func XCTAssertText(
        _ result: StreamResult,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .text(let value) = result else {
            return XCTFail("Expected text result.", file: file, line: line)
        }
        XCTAssertEqual(value, expected, file: file, line: line)
    }
}
