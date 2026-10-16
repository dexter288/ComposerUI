import Foundation

/// An installed package with a newer release available, from `composer outdated`.
public struct OutdatedPackage: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable {
        /// A newer version satisfies the constraint in `composer.json` (`composer update` will take it).
        case semverSafe = "semver-safe-update"
        /// A newer major exists; the constraint must change to reach it.
        case updatePossible = "update-possible"
        case upToDate = "up-to-date"
        case unknown
    }

    public let id: ComposerPackageID
    public var installedVersion: String
    public var latestVersion: String
    public var status: Status
    public var isDirect: Bool
    public var description: String
    public var releaseDate: Date?
    public var latestReleaseDate: Date?
    public var releaseAge: String?
    public var warning: String?
    public var isAbandoned: Bool

    public init(
        id: ComposerPackageID,
        installedVersion: String,
        latestVersion: String,
        status: Status,
        isDirect: Bool,
        description: String,
        releaseDate: Date? = nil,
        latestReleaseDate: Date? = nil,
        releaseAge: String? = nil,
        warning: String? = nil,
        isAbandoned: Bool = false
    ) {
        self.id = id
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.status = status
        self.isDirect = isDirect
        self.description = description
        self.releaseDate = releaseDate
        self.latestReleaseDate = latestReleaseDate
        self.releaseAge = releaseAge
        self.warning = warning
        self.isAbandoned = isAbandoned
    }

    public var name: String { id.name }
}
