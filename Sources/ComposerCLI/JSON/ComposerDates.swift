import Foundation

enum ComposerDates {
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return iso.date(from: text) ?? isoFractional.date(from: text)
    }
}

extension JSONDecoder {
    /// Composer and Packagist emit RFC 3339 timestamps with a numeric offset.
    static var composer: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = ComposerDates.parse(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date \(text)"))
            }
            return date
        }
        return decoder
    }
}

/// Composer writes `"abandoned": false` or `"abandoned": "replacement/name"` or `true`.
struct AbandonedValue: Decodable, Sendable {
    let isAbandoned: Bool
    let replacement: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            isAbandoned = flag
            replacement = nil
        } else if let name = try? container.decode(String.self) {
            isAbandoned = true
            replacement = name.isEmpty ? nil : name
        } else {
            isAbandoned = false
            replacement = nil
        }
    }
}
