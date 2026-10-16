import ComposerCore
import Foundation

/// `composer show --format=json`
public enum ShowJSON {
    struct Root: Decodable {
        var installed: [Entry]?
        // Platform packages appear under "platform" for `composer show -p`; ignored.
    }

    struct Entry: Decodable {
        var name: String
        var version: String?
        var description: String?
        var homepage: String?
        var source: String?
        var directDependency: Bool?
        var abandoned: AbandonedValue?

        enum CodingKeys: String, CodingKey {
            case name, version, description, homepage, source, abandoned
            case directDependency = "direct-dependency"
        }
    }

    /// Decodes the inventory. `devNames` are the packages listed in `require-dev` of the root
    /// `composer.json`, used to label direct dev dependencies.
    public static func decode(_ data: Data, devNames: Set<ComposerPackageID> = []) throws -> [InstalledPackage] {
        let trimmed = data.trimmedJSON
        guard !trimmed.isEmpty else { return [] }
        let root: Root
        do {
            root = try JSONDecoder.composer.decode(Root.self, from: trimmed)
        } catch {
            throw CommandError.malformedOutput("show: \(error.localizedDescription)")
        }
        return (root.installed ?? []).compactMap { entry in
            guard !entry.name.isEmpty else { return nil }
            let id = ComposerPackageID(entry.name)
            return InstalledPackage(
                id: id,
                version: entry.version ?? "",
                description: entry.description ?? "",
                homepage: entry.homepage.flatMap(URL.init(string:)),
                source: entry.source.flatMap(URL.init(string:)),
                isDirect: entry.directDependency ?? false,
                isAbandoned: entry.abandoned?.isAbandoned ?? false,
                replacement: entry.abandoned?.replacement,
                isDev: devNames.contains(id)
            )
        }
        .sorted { $0.name < $1.name }
    }
}

extension Data {
    /// Composer may print warnings before the JSON document on stdout. Skip to the first `{`.
    var trimmedJSON: Data {
        guard let start = firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }) else {
            return Data()
        }
        return self[start...]
    }
}
