import ComposerCore
import Foundation

/// `composer audit --format=json`
public enum AuditJSON {
    struct Root: Decodable {
        var advisories: [String: [Entry]]?
        var abandoned: [String: AbandonedReplacement]?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            // `advisories` is `[]` (empty list) when there are none and an object otherwise.
            advisories = try? container.decode([String: [Entry]].self, forKey: .advisories)
            abandoned = try? container.decode([String: AbandonedReplacement].self, forKey: .abandoned)
        }

        enum Keys: String, CodingKey { case advisories, abandoned }
    }

    struct AbandonedReplacement: Decodable {
        var replacement: String?
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                replacement = text.isEmpty ? nil : text
            } else {
                replacement = nil
            }
        }
    }

    struct Entry: Decodable {
        var advisoryId: String?
        var packageName: String?
        var affectedVersions: String?
        var title: String?
        var cve: String?
        var link: String?
        var reportedAt: String?
        var severity: String?
    }

    public static func decode(_ data: Data) throws -> AuditReport {
        let trimmed = data.trimmedJSON
        guard !trimmed.isEmpty else { return AuditReport() }
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: trimmed)
        } catch {
            throw CommandError.malformedOutput("audit: \(error.localizedDescription)")
        }
        var advisories: [SecurityAdvisory] = []
        for (packageName, entries) in root.advisories ?? [:] {
            for entry in entries {
                let name = entry.packageName ?? packageName
                let id = entry.advisoryId ?? entry.cve ?? "\(name)#\(advisories.count)"
                advisories.append(SecurityAdvisory(
                    id: id,
                    package: ComposerPackageID(name),
                    title: entry.title ?? "Security advisory",
                    cve: entry.cve.flatMap { $0.isEmpty ? nil : $0 },
                    affectedVersions: entry.affectedVersions ?? "",
                    link: entry.link.flatMap(URL.init(string:)),
                    reportedAt: ComposerDates.parse(entry.reportedAt),
                    severity: entry.severity.flatMap { SecurityAdvisory.Severity(rawValue: $0.lowercased()) } ?? .unknown
                ))
            }
        }
        advisories.sort {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            if $0.package != $1.package { return $0.package.name < $1.package.name }
            return ($0.reportedAt ?? .distantPast) > ($1.reportedAt ?? .distantPast)
        }
        var abandoned: [ComposerPackageID: String?] = [:]
        for (name, value) in root.abandoned ?? [:] {
            abandoned[ComposerPackageID(name)] = value.replacement
        }
        return AuditReport(advisories: advisories, abandoned: abandoned)
    }
}
