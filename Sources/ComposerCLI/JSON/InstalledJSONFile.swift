import ComposerCore
import Foundation

/// Reads `vendor/composer/installed.json` to build the dependency graph. Composer has no JSON
/// form of `depends`, so this file is the source for dependents and dependencies.
public enum InstalledJSONFile {
    struct Root: Decodable {
        var packages: [Entry]
        var devPackageNames: [String]?

        enum CodingKeys: String, CodingKey {
            case packages
            case devPackageNames = "dev-package-names"
        }

        init(from decoder: any Decoder) throws {
            // Composer 1 wrote a bare array; Composer 2 writes an object with `packages`.
            if let container = try? decoder.container(keyedBy: CodingKeys.self),
               let list = try? container.decode([Entry].self, forKey: .packages) {
                packages = list
                devPackageNames = try? container.decode([String].self, forKey: .devPackageNames)
            } else {
                packages = try decoder.singleValueContainer().decode([Entry].self)
                devPackageNames = nil
            }
        }
    }

    struct Entry: Decodable {
        var name: String
        var require: [String: String]?
        var replace: [String: String]?
        var provide: [String: String]?
    }

    public struct Contents: Sendable {
        public var graph: DependencyGraph
        /// Packages installed only because of `require-dev` (transitively).
        public var devPackageNames: Set<ComposerPackageID>
    }

    public static func read(at url: URL) -> Contents {
        guard let data = try? Data(contentsOf: url) else {
            return Contents(graph: DependencyGraph(), devPackageNames: [])
        }
        return decode(data)
    }

    public static func decode(_ data: Data) -> Contents {
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else {
            return Contents(graph: DependencyGraph(), devPackageNames: [])
        }
        var graph = DependencyGraph()
        for entry in root.packages where !entry.name.isEmpty {
            let id = ComposerPackageID(entry.name)
            let deps = (entry.require ?? [:]).keys.map(ComposerPackageID.init)
            let aliases = (Array((entry.replace ?? [:]).keys) + Array((entry.provide ?? [:]).keys)).map(ComposerPackageID.init)
            graph.add(package: id, requires: deps, aliases: aliases)
        }
        return Contents(graph: graph, devPackageNames: Set((root.devPackageNames ?? []).map(ComposerPackageID.init)))
    }
}
