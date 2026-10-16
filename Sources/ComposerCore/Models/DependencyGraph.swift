import Foundation

/// Who requires whom among the installed packages, built from `vendor/composer/installed.json`.
public struct DependencyGraph: Sendable {
    private var requires: [ComposerPackageID: Set<ComposerPackageID>] = [:]
    private var requiredBy: [ComposerPackageID: Set<ComposerPackageID>] = [:]
    /// Names a package also answers to (`replace` / `provide`), mapped to the real package.
    private var aliases: [ComposerPackageID: ComposerPackageID] = [:]

    public init() {}

    public mutating func add(package: ComposerPackageID, requires deps: [ComposerPackageID], aliases names: [ComposerPackageID] = []) {
        requires[package, default: []].formUnion(deps)
        for dep in deps {
            requiredBy[dep, default: []].insert(package)
        }
        for alias in names where alias != package {
            aliases[alias] = package
        }
    }

    public func resolve(_ id: ComposerPackageID) -> ComposerPackageID { aliases[id] ?? id }

    public func dependencies(of id: ComposerPackageID) -> [ComposerPackageID] {
        (requires[id] ?? []).map(resolve).filter { !$0.isPlatform }.sorted { $0.name < $1.name }
    }

    public func dependents(of id: ComposerPackageID) -> [ComposerPackageID] {
        var result = requiredBy[id] ?? []
        for (alias, real) in aliases where real == id {
            result.formUnion(requiredBy[alias] ?? [])
        }
        result.remove(id)
        return result.sorted { $0.name < $1.name }
    }

    public var isEmpty: Bool { requires.isEmpty }
}
