import Foundation

/// Canonical `vendor/name` identity of a Composer package. Comparison is case-insensitive,
/// as Packagist treats names.
public struct ComposerPackageID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let name: String

    public init(_ name: String) {
        self.name = name.lowercased()
    }

    public var vendor: String { name.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "" }
    public var shortName: String { name.split(separator: "/", maxSplits: 1).last.map(String.init) ?? name }
    public var isPlatform: Bool { !name.contains("/") }
    public var description: String { name }
    public var packagistURL: URL? { URL(string: "https://packagist.org/packages/\(name)") }
}
