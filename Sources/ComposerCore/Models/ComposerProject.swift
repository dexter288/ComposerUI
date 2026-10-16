import Foundation

/// A place Composer manages packages for: a project folder holding a `composer.json`,
/// or the global Composer home (`composer global …`).
public struct ComposerProject: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable {
        case project
        case global
    }

    public var kind: Kind
    public var rootURL: URL

    public init(kind: Kind, rootURL: URL) {
        self.kind = kind
        self.rootURL = rootURL.standardizedFileURL
    }

    public static func project(at url: URL) -> ComposerProject {
        ComposerProject(kind: .project, rootURL: url)
    }

    public static func global(home: URL) -> ComposerProject {
        ComposerProject(kind: .global, rootURL: home)
    }

    public var id: String { "\(kind.rawValue):\(rootURL.path)" }
    public var isGlobal: Bool { kind == .global }

    public var displayName: String {
        isGlobal ? "Global" : rootURL.lastPathComponent
    }

    public var composerJSONURL: URL { rootURL.appendingPathComponent("composer.json") }
    public var composerLockURL: URL { rootURL.appendingPathComponent("composer.lock") }
    public var vendorURL: URL { rootURL.appendingPathComponent("vendor") }
    public var installedJSONURL: URL { vendorURL.appendingPathComponent("composer/installed.json") }

    /// Arguments that select this project when invoking `composer`. Global uses the `global`
    /// proxy command; projects run with the working directory set to the root.
    public var commandPrefix: [String] { isGlobal ? ["global"] : [] }
}
