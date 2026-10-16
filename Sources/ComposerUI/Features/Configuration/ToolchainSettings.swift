import ComposerCLI
import ComposerCore
import Foundation
import Observation

/// User overrides for where Composer and PHP live. Empty means "detect automatically".
@MainActor
@Observable
public final class ToolchainSettings {
    public var composerPath: String { didSet { save() } }
    public var phpPath: String { didSet { save() } }
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        composerPath = defaults.string(forKey: "composerui.composerPath") ?? ""
        phpPath = defaults.string(forKey: "composerui.phpPath") ?? ""
    }

    private func save() {
        defaults.set(composerPath, forKey: "composerui.composerPath")
        defaults.set(phpPath, forKey: "composerui.phpPath")
    }

    public func makeLocator() -> ComposerExecutableLocator {
        ComposerExecutableLocator(
            composerOverride: composerPath.isEmpty ? nil : composerPath,
            phpOverride: phpPath.isEmpty ? nil : phpPath
        )
    }
}

/// The locator the command centre consults on every launch, so settings changes apply immediately.
final class SettingsBackedLocator: ComposerExecutableLocating, @unchecked Sendable {
    private let lock = NSLock()
    private var locator: ComposerExecutableLocator

    init(_ locator: ComposerExecutableLocator) { self.locator = locator }

    func update(_ locator: ComposerExecutableLocator) {
        lock.lock(); defer { lock.unlock() }
        self.locator = locator
    }

    func locate() -> Result<ComposerToolchain, CommandError> {
        lock.lock(); defer { lock.unlock() }
        return locator.locate()
    }
}
