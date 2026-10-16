import Foundation

/// Where the app found Composer and PHP, and what versions they report.
public struct ComposerEnvironment: Sendable, Hashable {
    public var composerPath: String?
    public var phpPath: String?
    public var composerVersion: String?
    public var phpVersion: String?
    public var composerHome: String?
    public var config: [ConfigEntry]

    public init(
        composerPath: String? = nil,
        phpPath: String? = nil,
        composerVersion: String? = nil,
        phpVersion: String? = nil,
        composerHome: String? = nil,
        config: [ConfigEntry] = []
    ) {
        self.composerPath = composerPath
        self.phpPath = phpPath
        self.composerVersion = composerVersion
        self.phpVersion = phpVersion
        self.composerHome = composerHome
        self.config = config
    }

    public var isComplete: Bool { composerPath != nil && phpPath != nil }
}

/// A `[key] value` line from `composer config --list`.
public struct ConfigEntry: Identifiable, Hashable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    public var id: String { key }
}
