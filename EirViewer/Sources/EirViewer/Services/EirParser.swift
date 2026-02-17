import Foundation
import Yams

enum EirParserError: LocalizedError {
    case fileNotFound(String)
    case invalidYAML(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidYAML(let detail):
            return "Invalid YAML: \(detail)"
        case .decodingFailed(let detail):
            return "Failed to decode EIR document: \(detail)"
        }
    }
}

struct EirParser {
    static func parse(url: URL) throws -> EirDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EirParserError.fileNotFound(url.path)
        }

        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw EirParserError.invalidYAML("Could not read file as UTF-8")
        }

        return try parse(yaml: yamlString)
    }

    static func parse(yaml: String) throws -> EirDocument {
        let decoder = YAMLDecoder()
        do {
            return try decoder.decode(EirDocument.self, from: yaml)
        } catch {
            throw EirParserError.decodingFailed(error.localizedDescription)
        }
    }
}
