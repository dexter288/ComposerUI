import Foundation

/// A package present in the project's `vendor` directory, as reported by `composer show`.
public struct InstalledPackage: Identifiable, Hashable, Sendable {
    public enum Scope: String, Sendable, CaseIterable {
        case production
        case development
        case transitive
    }

    public let id: ComposerPackageID
    public var version: String
    public var description: String
    public var homepage: URL?
    public var source: URL?
    public var isDirect: Bool
    public var isAbandoned: Bool
    public var replacement: String?
    /// Whether the root `composer.json` lists it under `require-dev`.
    public var isDev: Bool

    public init(
        id: ComposerPackageID,
        version: String,
        description: String,
        homepage: URL? = nil,
        source: URL? = nil,
        isDirect: Bool,
        isAbandoned: Bool = false,
        replacement: String? = nil,
        isDev: Bool = false
    ) {
        self.id = id
        self.version = version
        self.description = description
        self.homepage = homepage
        self.source = source
        self.isDirect = isDirect
        self.isAbandoned = isAbandoned
        self.replacement = replacement
        self.isDev = isDev
    }

    public var name: String { id.name }

    public var scope: Scope {
        guard isDirect else { return .transitive }
        return isDev ? .development : .production
    }
}
