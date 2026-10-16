import ComposerCore
import Foundation

/// `composer show vendor/name --format=json`
public enum ShowPackageJSON {
    struct Root: Decodable {
        var name: String
        var description: String?
        var keywords: [String]?
        var type: String?
        var homepage: String?
        var versions: [String]?
        var licenses: [License]?
        var source: Link?
        var dist: Link?
        var path: String?
        var released: String?
        var requires: [String: String]?
        var devRequires: [String: String]?
        var suggests: [String: String]?
        var support: [String: String]?
        var autoload: [String: AutoloadValue]?

        enum CodingKeys: String, CodingKey {
            case name, description, keywords, type, homepage, versions, licenses, source, dist, path, released, requires, suggests, support, autoload
            case devRequires = "devRequires"
        }
    }

    struct License: Decodable {
        var name: String?
        var osi: String?
        var url: String?
    }

    struct Link: Decodable {
        var type: String?
        var url: String?
        var reference: String?
    }

    /// `autoload` values are `{ "psr-4": {"Ns\\": "src/"} }`, `{"classmap": [...]}` or `{"files": [...]}`.
    struct AutoloadValue: Decodable {
        var namespaces: [String]
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let map = try? container.decode([String: StringOrList].self) {
                namespaces = map.keys.sorted()
            } else {
                namespaces = []
            }
        }
    }

    struct StringOrList: Decodable {
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if (try? container.decode(String.self)) == nil {
                _ = try? container.decode([String].self)
            }
        }
    }

    public static func decode(_ data: Data) throws -> PackageDetail {
        let trimmed = data.trimmedJSON
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: trimmed)
        } catch {
            throw CommandError.malformedOutput("show package: \(error.localizedDescription)")
        }
        func requirements(_ map: [String: String]?) -> [PackageDetail.Requirement] {
            (map ?? [:]).map { PackageDetail.Requirement(id: ComposerPackageID($0.key), constraint: $0.value) }
                .sorted { $0.name < $1.name }
        }
        let namespaces = (root.autoload ?? [:])
            .filter { $0.key.hasPrefix("psr") }
            .flatMap(\.value.namespaces)
            .sorted()
        return PackageDetail(
            id: ComposerPackageID(root.name),
            description: root.description ?? "",
            type: root.type ?? "library",
            keywords: root.keywords ?? [],
            homepage: root.homepage.flatMap(URL.init(string:)),
            versions: root.versions ?? [],
            licenses: (root.licenses ?? []).compactMap { license in
                guard let name = license.name ?? license.osi else { return nil }
                return PackageDetail.License(name: name, spdx: license.osi, url: license.url.flatMap(URL.init(string:)))
            },
            sourceURL: root.source?.url.flatMap(Self.webURL),
            installPath: root.path,
            released: ComposerDates.parse(root.released),
            requires: requirements(root.requires),
            devRequires: requirements(root.devRequires),
            suggests: root.suggests ?? [:],
            support: root.support ?? [:],
            autoloadNamespaces: namespaces
        )
    }

    /// Turns `https://github.com/x/y.git` into a browsable URL.
    static func webURL(_ text: String) -> URL? {
        var cleaned = text
        if cleaned.hasSuffix(".git") { cleaned.removeLast(4) }
        if cleaned.hasPrefix("git@github.com:") {
            cleaned = "https://github.com/" + cleaned.dropFirst("git@github.com:".count)
        }
        return URL(string: cleaned)
    }
}
