import Foundation

/// Full metadata for one package, from `composer show vendor/name`.
public struct PackageDetail: Hashable, Sendable {
    public struct License: Hashable, Sendable {
        public var name: String
        public var spdx: String?
        public var url: URL?
        public init(name: String, spdx: String? = nil, url: URL? = nil) {
            self.name = name
            self.spdx = spdx
            self.url = url
        }
    }

    public struct Requirement: Hashable, Sendable, Identifiable {
        public var id: ComposerPackageID
        public var constraint: String
        public init(id: ComposerPackageID, constraint: String) {
            self.id = id
            self.constraint = constraint
        }
        public var name: String { id.name }
    }

    public let id: ComposerPackageID
    public var description: String
    public var type: String
    public var keywords: [String]
    public var homepage: URL?
    public var versions: [String]
    public var licenses: [License]
    public var sourceURL: URL?
    public var installPath: String?
    public var released: Date?
    public var requires: [Requirement]
    public var devRequires: [Requirement]
    public var suggests: [String: String]
    public var support: [String: String]
    public var autoloadNamespaces: [String]

    public init(
        id: ComposerPackageID,
        description: String = "",
        type: String = "library",
        keywords: [String] = [],
        homepage: URL? = nil,
        versions: [String] = [],
        licenses: [License] = [],
        sourceURL: URL? = nil,
        installPath: String? = nil,
        released: Date? = nil,
        requires: [Requirement] = [],
        devRequires: [Requirement] = [],
        suggests: [String: String] = [:],
        support: [String: String] = [:],
        autoloadNamespaces: [String] = []
    ) {
        self.id = id
        self.description = description
        self.type = type
        self.keywords = keywords
        self.homepage = homepage
        self.versions = versions
        self.licenses = licenses
        self.sourceURL = sourceURL
        self.installPath = installPath
        self.released = released
        self.requires = requires
        self.devRequires = devRequires
        self.suggests = suggests
        self.support = support
        self.autoloadNamespaces = autoloadNamespaces
    }
}
