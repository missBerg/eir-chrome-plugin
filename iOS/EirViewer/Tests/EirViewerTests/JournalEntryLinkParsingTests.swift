import XCTest
@testable import EirViewer

final class JournalEntryLinkParsingTests: XCTestCase {

    func testParsesStructuredJournalEntryTag() {
        let parts = parseJournalEntryTags(
            "See this note <JOURNAL_ENTRY id=\"entry_002\"/> for details."
        )

        XCTAssertEqual(parts.count, 3)
        XCTAssertText(parts[0], equals: "See this note ")
        XCTAssertJournalRef(parts[1], equals: "entry_002")
        XCTAssertText(parts[2], equals: " for details.")
    }

    func testParsesBareEntryIdentifierAsFallback() {
        let parts = parseJournalEntryTags(
            "The most relevant note is entry_003 and it looks recent."
        )

        XCTAssertEqual(parts.count, 3)
        XCTAssertText(parts[0], equals: "The most relevant note is ")
        XCTAssertJournalRef(parts[1], equals: "entry_003")
        XCTAssertText(parts[2], equals: " and it looks recent.")
    }

    private func XCTAssertText(
        _ part: ChatContentPart,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .text(let value) = part else {
            return XCTFail("Expected text part.", file: file, line: line)
        }
        XCTAssertEqual(value, expected, file: file, line: line)
    }

    private func XCTAssertJournalRef(
        _ part: ChatContentPart,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .journalRef(let value) = part else {
            return XCTFail("Expected journal ref part.", file: file, line: line)
        }
        XCTAssertEqual(value, expected, file: file, line: line)
    }
}
