import ComposerCore
import Foundation

/// Parses `composer config --list`, whose lines look like `[vendor-dir] vendor (/abs/path)`.
public enum ConfigListParser {
    public static func parse(_ text: String) -> [ConfigEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
            let key = String(line[line.index(after: line.startIndex)..<close])
            let value = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            return ConfigEntry(key: key, value: value)
        }
    }

    /// `Composer version 2.10.2 2026-07-01 11:24:45` / `PHP version 8.4.23 (/path/php)`
    public static func parseVersions(_ text: String) -> (composer: String?, php: String?, phpPath: String?) {
        var composer: String?
        var php: String?
        var phpPath: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Composer version ") {
                composer = line.dropFirst("Composer version ".count).split(separator: " ").first.map(String.init)
            } else if line.hasPrefix("PHP version ") {
                let rest = line.dropFirst("PHP version ".count)
                php = rest.split(separator: " ").first.map(String.init)
                if let open = rest.firstIndex(of: "("), let close = rest.lastIndex(of: ")"), open < close {
                    phpPath = String(rest[rest.index(after: open)..<close])
                }
            }
        }
        return (composer, php, phpPath)
    }
}
