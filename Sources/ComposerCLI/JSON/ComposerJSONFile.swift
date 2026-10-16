import ComposerCore
import Foundation

/// The parts of the root `composer.json` the app shows: requirements, scripts and identity.
public struct ComposerJSONFile: Sendable {
    public var name: String?
    public var description: String?
    public var type: String?
    public var require: [String: String]
    public var requireDev: [String: String]
    public var scripts: [ComposerScript]
    public var minimumStability: String?
    public var preferStable: Bool?
    public var platformPHP: String?

    struct Root: Decodable {
        var name: String?
        var description: String?
        var type: String?
        var require: [String: String]?
        var requireDev: [String: String]?
        var scripts: [String: ScriptValue]?
        var scriptsDescriptions: [String: String]?
        var minimumStability: String?
        var preferStable: Bool?
        var config: Config?

        enum CodingKeys: String, CodingKey {
            case name, description, type, require, scripts, config
            case requireDev = "require-dev"
            case scriptsDescriptions = "scripts-descriptions"
            case minimumStability = "minimum-stability"
            case preferStable = "prefer-stable"
        }
    }

    struct Config: Decodable {
        var platform: [String: String]?
    }

    struct ScriptValue: Decodable {
        var commands: [String]
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let one = try? container.decode(String.self) {
                commands = [one]
            } else if let many = try? container.decode([String].self) {
                commands = many
            } else {
                commands = []
            }
        }
    }

    public static func read(at url: URL) throws -> ComposerJSONFile {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> ComposerJSONFile {
        let root = try JSONDecoder().decode(Root.self, from: data)
        let descriptions = root.scriptsDescriptions ?? [:]
        let scripts = (root.scripts ?? [:]).map { name, value in
            ComposerScript(name: name, commands: value.commands, description: descriptions[name])
        }
        .sorted { lhs, rhs in
            if lhs.isLifecycleEvent != rhs.isLifecycleEvent { return !lhs.isLifecycleEvent }
            return lhs.name < rhs.name
        }
        return ComposerJSONFile(
            name: root.name,
            description: root.description,
            type: root.type,
            require: root.require ?? [:],
            requireDev: root.requireDev ?? [:],
            scripts: scripts,
            minimumStability: root.minimumStability,
            preferStable: root.preferStable,
            platformPHP: root.config?.platform?["php"]
        )
    }

    public var devPackageIDs: Set<ComposerPackageID> { Set(requireDev.keys.map(ComposerPackageID.init)) }
    public var requiredPHP: String? { require["php"] }
}
