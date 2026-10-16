import Foundation

/// One entry from `composer audit`.
public struct SecurityAdvisory: Identifiable, Hashable, Sendable {
    public enum Severity: String, Sendable, Comparable {
        case critical, high, medium, low, unknown

        private var rank: Int {
            switch self {
            case .critical: 4
            case .high: 3
            case .medium: 2
            case .low: 1
            case .unknown: 0
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    public let id: String
    public var package: ComposerPackageID
    public var title: String
    public var cve: String?
    public var affectedVersions: String
    public var link: URL?
    public var reportedAt: Date?
    public var severity: Severity

    public init(
        id: String,
        package: ComposerPackageID,
        title: String,
        cve: String? = nil,
        affectedVersions: String,
        link: URL? = nil,
        reportedAt: Date? = nil,
        severity: Severity = .unknown
    ) {
        self.id = id
        self.package = package
        self.title = title
        self.cve = cve
        self.affectedVersions = affectedVersions
        self.link = link
        self.reportedAt = reportedAt
        self.severity = severity
    }
}

/// The outcome of `composer audit` for a project.
public struct AuditReport: Sendable, Hashable {
    public var advisories: [SecurityAdvisory]
    /// Abandoned packages and their suggested replacement, if any.
    public var abandoned: [ComposerPackageID: String?]
    public var checkedAt: Date

    public init(advisories: [SecurityAdvisory] = [], abandoned: [ComposerPackageID: String?] = [:], checkedAt: Date = .now) {
        self.advisories = advisories
        self.abandoned = abandoned
        self.checkedAt = checkedAt
    }

    public var isClean: Bool { advisories.isEmpty && abandoned.isEmpty }
    public var affectedPackages: [ComposerPackageID] {
        Array(Set(advisories.map(\.package))).sorted { $0.name < $1.name }
    }
}
