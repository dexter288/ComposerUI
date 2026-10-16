import Foundation

/// A named script from the `scripts` section of `composer.json`.
public struct ComposerScript: Identifiable, Hashable, Sendable {
    public let name: String
    public var commands: [String]
    public var description: String?

    public init(name: String, commands: [String], description: String? = nil) {
        self.name = name
        self.commands = commands
        self.description = description
    }

    public var id: String { name }

    /// Composer's own lifecycle hooks run automatically; everything else is a user script.
    public var isLifecycleEvent: Bool {
        name.hasPrefix("pre-") || name.hasPrefix("post-") || name == "command"
    }
}
