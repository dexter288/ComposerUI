import Foundation

/// A Packagist search hit.
public struct DiscoveredPackage: Identifiable, Hashable, Sendable {
    public let id: ComposerPackageID
    public var description: String
    public var repository: URL?
    public var downloads: Int
    public var favers: Int
    public var isAbandoned: Bool
    public var replacement: String?

    public init(id: ComposerPackageID, description: String, repository: URL? = nil, downloads: Int = 0, favers: Int = 0, isAbandoned: Bool = false, replacement: String? = nil) {
        self.id = id
        self.description = description
        self.repository = repository
        self.downloads = downloads
        self.favers = favers
        self.isAbandoned = isAbandoned
        self.replacement = replacement
    }

    public var name: String { id.name }
}

/// Packagist's full record for one package, trimmed to what the detail pane shows.
public struct PackagistPackage: Hashable, Sendable {
    public struct Version: Hashable, Sendable, Identifiable {
        public var version: String
        public var normalized: String
        public var releasedAt: Date?
        public var license: [String]
        public var requiresPHP: String?
        public init(version: String, normalized: String, releasedAt: Date? = nil, license: [String] = [], requiresPHP: String? = nil) {
            self.version = version
            self.normalized = normalized
            self.releasedAt = releasedAt
            self.license = license
            self.requiresPHP = requiresPHP
        }
        public var id: String { version }
        public var isDev: Bool { version.hasPrefix("dev-") || version.hasSuffix("-dev") }
        public var isStable: Bool {
            !isDev && !normalized.contains("-")
        }
    }

    public let id: ComposerPackageID
    public var description: String
    public var type: String
    public var repository: URL?
    public var homepage: URL?
    public var downloadsTotal: Int
    public var downloadsMonthly: Int
    public var favers: Int
    public var githubStars: Int?
    public var maintainers: [String]
    public var keywords: [String]
    public var versions: [Version]
    public var isAbandoned: Bool
    public var replacement: String?

    public init(
        id: ComposerPackageID,
        description: String = "",
        type: String = "library",
        repository: URL? = nil,
        homepage: URL? = nil,
        downloadsTotal: Int = 0,
        downloadsMonthly: Int = 0,
        favers: Int = 0,
        githubStars: Int? = nil,
        maintainers: [String] = [],
        keywords: [String] = [],
        versions: [Version] = [],
        isAbandoned: Bool = false,
        replacement: String? = nil
    ) {
        self.id = id
        self.description = description
        self.type = type
        self.repository = repository
        self.homepage = homepage
        self.downloadsTotal = downloadsTotal
        self.downloadsMonthly = downloadsMonthly
        self.favers = favers
        self.githubStars = githubStars
        self.maintainers = maintainers
        self.keywords = keywords
        self.versions = versions
        self.isAbandoned = isAbandoned
        self.replacement = replacement
    }

    public var latestStable: Version? { versions.first(where: \.isStable) }
    public var latest: Version? { latestStable ?? versions.first }
}
