import ComposerCore
import Foundation

/// `composer outdated --format=json`
public enum OutdatedJSON {
    struct Root: Decodable {
        var installed: [Entry]?
    }

    struct Entry: Decodable {
        var name: String
        var version: String?
        var latest: String?
        var latestStatus: String?
        var directDependency: Bool?
        var description: String?
        var releaseAge: String?
        var releaseDate: String?
        var latestReleaseDate: String?
        var warning: String?
        var abandoned: AbandonedValue?

        enum CodingKeys: String, CodingKey {
            case name, version, latest, description, warning, abandoned
            case latestStatus = "latest-status"
            case directDependency = "direct-dependency"
            case releaseAge = "release-age"
            case releaseDate = "release-date"
            case latestReleaseDate = "latest-release-date"
        }
    }

    public static func decode(_ data: Data) throws -> [OutdatedPackage] {
        let trimmed = data.trimmedJSON
        guard !trimmed.isEmpty else { return [] }
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: trimmed)
        } catch {
            throw CommandError.malformedOutput("outdated: \(error.localizedDescription)")
        }
        return (root.installed ?? []).compactMap { entry in
            guard !entry.name.isEmpty, let latest = entry.latest, let version = entry.version else { return nil }
            let status = entry.latestStatus.flatMap(OutdatedPackage.Status.init(rawValue:)) ?? .unknown
            guard status != .upToDate else { return nil }
            return OutdatedPackage(
                id: ComposerPackageID(entry.name),
                installedVersion: version,
                latestVersion: latest,
                status: status,
                isDirect: entry.directDependency ?? false,
                description: entry.description ?? "",
                releaseDate: ComposerDates.parse(entry.releaseDate),
                latestReleaseDate: ComposerDates.parse(entry.latestReleaseDate),
                releaseAge: entry.releaseAge,
                warning: entry.warning,
                isAbandoned: entry.abandoned?.isAbandoned ?? false
            )
        }
        .sorted { $0.name < $1.name }
    }
}
