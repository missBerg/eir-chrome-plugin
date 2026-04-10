import XCTest
@testable import EirViewer

final class ClinicalNoteImportTests: XCTestCase {

    func testDocumentReferenceExtractionUsesAttachmentTextForClinicalNoteBody() throws {
        let attachmentHTML = """
        <div xmlns="http://www.w3.org/1999/xhtml">
          <p>Patienten sökte för halsont och feber sedan tre dagar.</p>
          <p>Plan: vätska, vila och återkontakt vid försämring.</p>
        </div>
        """

        let json = """
        {
          "resourceType": "DocumentReference",
          "id": "note-acute-20250312",
          "status": "current",
          "date": "2025-03-12T08:14:00+01:00",
          "title": "Utskrivningsanteckning efter närakutbesök",
          "content": [
            {
              "attachment": {
                "contentType": "text/html",
                "data": "\(Data(attachmentHTML.utf8).base64EncodedString())"
              }
            }
          ]
        }
        """

        let extraction = ClinicalNoteFHIRExtractor.extract(
            from: try XCTUnwrap(json.data(using: .utf8)),
            fallbackTitle: "Fallback title"
        )

        XCTAssertEqual(extraction.summary, "Utskrivningsanteckning efter närakutbesök")
        XCTAssertTrue(extraction.noteBlocks.joined(separator: "\n\n").contains("Patienten sökte för halsont och feber sedan tre dagar."))
        XCTAssertTrue(extraction.noteBlocks.joined(separator: "\n\n").contains("Plan: vätska, vila och återkontakt vid försämring."))
        XCTAssertTrue(extraction.metadataLines.contains("FHIR-resurs: DocumentReference"))
        XCTAssertTrue(extraction.metadataLines.contains("FHIR-ID: note-acute-20250312"))
        XCTAssertTrue(extraction.metadataLines.contains("Status: current"))
        XCTAssertTrue(extraction.tags.contains("clinical-note"))
        XCTAssertTrue(extraction.tags.contains("documentreference"))
    }

    func testCompositionExtractionUsesSectionNarrativesAsNoteBlocks() throws {
        let json = """
        {
          "resourceType": "Composition",
          "id": "note-recovery-20250305",
          "status": "final",
          "date": "2025-03-05T19:42:00+01:00",
          "title": "Mottagningsanteckning om stress, sömn och återhämtning",
          "section": [
            {
              "title": "Aktuellt",
              "text": {
                "status": "generated",
                "div": "<div xmlns=\\"http://www.w3.org/1999/xhtml\\"><p>Patienten beskriver ökad stressbelastning senaste månaden.</p></div>"
              }
            },
            {
              "title": "Plan",
              "text": {
                "status": "generated",
                "div": "<div xmlns=\\"http://www.w3.org/1999/xhtml\\"><p>Prioritera kvällsrutin och minska skärmtid sent.</p></div>"
              }
            }
          ]
        }
        """

        let extraction = ClinicalNoteFHIRExtractor.extract(
            from: try XCTUnwrap(json.data(using: .utf8)),
            fallbackTitle: "Fallback title"
        )

        XCTAssertEqual(extraction.summary, "Mottagningsanteckning om stress, sömn och återhämtning")
        XCTAssertEqual(extraction.noteBlocks.count, 2)
        XCTAssertEqual(extraction.noteBlocks[0], "Aktuellt\n\nPatienten beskriver ökad stressbelastning senaste månaden.")
        XCTAssertEqual(extraction.noteBlocks[1], "Plan\n\nPrioritera kvällsrutin och minska skärmtid sent.")
        XCTAssertTrue(extraction.metadataLines.contains("FHIR-resurs: Composition"))
        XCTAssertTrue(extraction.tags.contains("composition"))
    }

    func testDiagnosticReportExtractionUsesPresentedFormAndConclusion() throws {
        let presentedText = "Sammanfattning av svar: ingen akut somatisk fara framkommer."
        let json = """
        {
          "resourceType": "DiagnosticReport",
          "id": "diag-123",
          "status": "final",
          "conclusion": "Tydligt behov av återhämtning och bättre sömnrutiner.",
          "presentedForm": [
            {
              "contentType": "text/plain",
              "data": "\(Data(presentedText.utf8).base64EncodedString())"
            }
          ]
        }
        """

        let extraction = ClinicalNoteFHIRExtractor.extract(
            from: try XCTUnwrap(json.data(using: .utf8)),
            fallbackTitle: "Diagnostiskt utlåtande"
        )

        XCTAssertEqual(extraction.summary, "Diagnostiskt utlåtande")
        XCTAssertTrue(extraction.noteBlocks.contains(presentedText))
        XCTAssertTrue(extraction.noteBlocks.contains("Tydligt behov av återhämtning och bättre sömnrutiner."))
        XCTAssertTrue(extraction.tags.contains("diagnosticreport"))
    }

    func testClinicalNoteEntryPresentationUsesDocumentStyleSections() throws {
        let yaml = """
        metadata:
          format_version: "1.0"
        entries:
          - id: "clinical_001"
            date: "2025-03-12"
            category: "Anteckningar"
            type: "Klinisk anteckning"
            provider:
              name: "Apple Health"
            content:
              summary: "Utskrivningsanteckning efter närakutbesök"
              details: |-
                Importerad från Apple Health
                FHIR-resurs: DocumentReference
                FHIR-ID: note-acute-20250312
              notes:
                - |-
                  Sammanfattning

                  Patienten sökte för halsont och feber sedan tre dagar.
                - |-
                  Plan

                  Vätska, vila och återkontakt vid försämring.
            tags: ["apple-health", "clinical-note", "documentreference"]
        """

        let document = try EirParser.parse(yaml: yaml)
        let entry = try XCTUnwrap(document.entries.first)

        XCTAssertTrue(entry.isClinicalNote)
        XCTAssertEqual(entry.detailSectionTitle, "Metadata")
        XCTAssertEqual(entry.notesSectionTitle, "Journaltext")
        XCTAssertEqual(entry.notePreviewText, "Sammanfattning\n\nPatienten sökte för halsont och feber sedan tre dagar.")
    }
}
