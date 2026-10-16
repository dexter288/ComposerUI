import AppKit
import ComposerCLI
import ComposerCore
import ComposerPackagist
import Foundation
import Observation

public enum SidebarItem: String, CaseIterable, Identifiable, Sendable {
    case installed, updates, discover, audit, scripts, configuration
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .installed: "Installed"
        case .updates: "Updates"
        case .discover: "Discover"
        case .audit: "Audit"
        case .scripts: "Scripts"
        case .configuration: "Configuration"
        }
    }

    public var subtitle: String {
        switch self {
        case .installed: "Browse or search the packages in this project"
        case .updates: "Packages with a newer release on Packagist"
        case .discover: "Search Packagist and add packages to this project"
        case .audit: "Security advisories and abandoned packages"
        case .scripts: "Scripts defined in composer.json"
        case .configuration: "Where Composer and PHP live, and Composer's settings"
        }
    }

    public var symbol: String {
        switch self {
        case .installed: "shippingbox"
        case .updates: "arrow.up.circle"
        case .discover: "magnifyingglass"
        case .audit: "checkmark.shield"
        case .scripts: "terminal"
        case .configuration: "gearshape"
        }
    }
}

/// Loading state shared by the feature stores.
public enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading(previous: Value?)
    case loaded(Value, at: Date)
    case failed(String, previous: Value?)

    public var value: Value? {
        switch self {
        case .idle: nil
        case let .loading(previous): previous
        case let .loaded(value, _): value
        case let .failed(_, previous): previous
        }
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var errorMessage: String? {
        if case let .failed(message, _) = self { return message }
        return nil
    }

    public var loadedAt: Date? {
        if case let .loaded(_, at) = self { return at }
        return nil
    }
}

public struct Inventory: Sendable {
    public var packages: [InstalledPackage]
    public var graph: DependencyGraph
    public var composerJSON: ComposerJSONFile?
    public var hasLockFile: Bool
    public var hasVendor: Bool

    public func package(_ id: ComposerPackageID) -> InstalledPackage? {
        packages.first { $0.id == id }
    }
}

/// Composition root: owns the command centre, the console and every feature's state.
@MainActor
@Observable
public final class AppModel {
    public let console = ConsoleStore()
    public let settings: ToolchainSettings
    public let projects: ProjectStore
    public let packagist = PackagistClient()

    public var sidebar: SidebarItem = .installed
    public var selectedPackage: ComposerPackageID?

    public var inventory: LoadState<Inventory> = .idle
    public var outdated: LoadState<[OutdatedPackage]> = .idle
    public var audit: LoadState<AuditReport> = .idle
    public var environment: LoadState<ComposerEnvironment> = .idle
    public var details: [ComposerPackageID: PackageDetail] = [:]
    public var alert: AppAlert?

    private let center: SerialCommandCenter
    private let locator: SettingsBackedLocator
    private var detailTasks: [ComposerPackageID: Task<Void, Never>] = [:]

    public struct AppAlert: Identifiable, Sendable {
        public let id = UUID()
        public var title: String
        public var message: String
    }

    public init() {
        let settings = ToolchainSettings()
        self.settings = settings
        let locator = SettingsBackedLocator(settings.makeLocator())
        self.locator = locator
        center = SerialCommandCenter(locator: locator)
        projects = ProjectStore(globalHome: settings.makeLocator().composerHomeURL())
        Task { await center.setObserver(console) }
    }

    public var project: ComposerProject { projects.current ?? projects.global }

    // MARK: Lifecycle

    public var launchOptions = LaunchOptions.parse()

    public func start() {
        switch launchOptions.appearance {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if let path = launchOptions.projectPath {
            try? projects.open(folder: URL(fileURLWithPath: path))
        }
        if let tab = launchOptions.tab { sidebar = tab }
        if launchOptions.consoleExpanded { console.isExpanded = true }
        Task { await loadEnvironment() }
        Task { await refreshProject() }
    }

    public func settingsChanged() {
        locator.update(settings.makeLocator())
        Task { await loadEnvironment() }
    }

    public func select(project: ComposerProject) {
        guard projects.current?.id != project.id else { return }
        projects.current = project
        selectedPackage = nil
        details = [:]
        inventory = .idle
        outdated = .idle
        audit = .idle
        Task { await refreshProject() }
    }

    public func openProjectFromPanel() {
        Task {
            guard let result = await projects.presentOpenPanel() else { return }
            switch result {
            case .success:
                selectedPackage = nil
                details = [:]
                inventory = .idle
                outdated = .idle
                audit = .idle
                await refreshProject()
            case let .failure(error):
                alert = AppAlert(title: "Could not open project", message: error.localizedDescription)
            }
        }
    }

    /// Reloads everything for the current project. Updates and audit run after the inventory.
    public func refreshProject() async {
        await refreshInventory()
        async let updates: () = refreshOutdated()
        async let security: () = refreshAudit()
        _ = await (updates, security)
    }

    // MARK: Reads

    public func refreshInventory() async {
        let project = self.project
        inventory = .loading(previous: inventory.value)
        let composerJSON = project.isGlobal
            ? try? ComposerJSONFile.read(at: project.composerJSONURL)
            : try? ComposerJSONFile.read(at: project.composerJSONURL)
        let hasLock = FileManager.default.fileExists(atPath: project.composerLockURL.path)
        let hasVendor = FileManager.default.fileExists(atPath: project.installedJSONURL.path)
        let installed = InstalledJSONFile.read(at: project.installedJSONURL)
        do {
            let result = try await center.run(ComposerCommands.show(project))
            let packages = try ShowJSON.decode(Data(result.stdout.utf8), devNames: composerJSON?.devPackageIDs ?? [])
            guard self.project.id == project.id else { return }
            inventory = .loaded(Inventory(packages: packages, graph: installed.graph, composerJSON: composerJSON, hasLockFile: hasLock, hasVendor: hasVendor), at: .now)
            if let selectedPackage, !packages.contains(where: { $0.id == selectedPackage }) {
                self.selectedPackage = nil
            }
            if let wanted = launchOptions.package, packages.contains(where: { $0.id == wanted }) {
                selectedPackage = wanted
            }
        } catch {
            guard self.project.id == project.id else { return }
            if case CommandError.cancelled = error { return }
            // A project without vendor/ still has composer.json; show it as empty rather than failed.
            if !hasVendor, let composerJSON {
                inventory = .loaded(Inventory(packages: [], graph: DependencyGraph(), composerJSON: composerJSON, hasLockFile: hasLock, hasVendor: false), at: .now)
            } else {
                inventory = .failed(error.localizedDescription, previous: inventory.value)
            }
        }
    }

    public func refreshOutdated() async {
        let project = self.project
        guard inventory.value?.hasVendor != false else {
            outdated = .loaded([], at: .now)
            return
        }
        outdated = .loading(previous: outdated.value)
        do {
            let result = try await center.run(ComposerCommands.outdated(project))
            let list = try OutdatedJSON.decode(Data(result.stdout.utf8))
            guard self.project.id == project.id else { return }
            outdated = .loaded(list, at: .now)
        } catch {
            guard self.project.id == project.id else { return }
            if case CommandError.cancelled = error { return }
            outdated = .failed(error.localizedDescription, previous: outdated.value)
        }
    }

    public func refreshAudit() async {
        let project = self.project
        guard inventory.value?.hasVendor != false else {
            audit = .loaded(AuditReport(), at: .now)
            return
        }
        audit = .loading(previous: audit.value)
        do {
            let result = try await center.run(ComposerCommands.audit(project))
            let report = try AuditJSON.decode(Data(result.stdout.utf8))
            guard self.project.id == project.id else { return }
            audit = .loaded(report, at: .now)
        } catch {
            guard self.project.id == project.id else { return }
            if case CommandError.cancelled = error { return }
            audit = .failed(error.localizedDescription, previous: audit.value)
        }
    }

    public func loadEnvironment() async {
        environment = .loading(previous: environment.value)
        var env = ComposerEnvironment()
        switch settings.makeLocator().locate() {
        case let .success(toolchain):
            env.composerPath = toolchain.composer.path
            env.phpPath = toolchain.php.path
            env.composerHome = toolchain.composerHome.path
        case let .failure(error):
            environment = .failed(error.localizedDescription, previous: nil)
            return
        }
        do {
            let version = try await center.run(ComposerCommands.version())
            let parsed = ConfigListParser.parseVersions(version.stdout)
            env.composerVersion = parsed.composer
            env.phpVersion = parsed.php
            let config = try await center.run(ComposerCommands.configList(project))
            env.config = ConfigListParser.parse(config.stdout)
            environment = .loaded(env, at: .now)
        } catch {
            environment = .failed(error.localizedDescription, previous: env)
        }
    }

    public func loadDetail(for id: ComposerPackageID) {
        guard details[id] == nil, detailTasks[id] == nil else { return }
        let project = self.project
        detailTasks[id] = Task {
            defer { detailTasks[id] = nil }
            do {
                let result = try await center.run(ComposerCommands.showPackage(id, in: project))
                let detail = try ShowPackageJSON.decode(Data(result.stdout.utf8))
                guard self.project.id == project.id else { return }
                details[id] = detail
            } catch {
                // The detail pane shows what the inventory already knows; no alert for a missing detail.
            }
        }
    }

    // MARK: Mutations

    public func perform(_ command: ComposerCommand, thenRefresh refresh: Bool = true) {
        let project = self.project
        Task {
            do {
                _ = try await center.run(command)
            } catch {
                if case CommandError.cancelled = error { return }
                alert = AppAlert(title: "\(command.title) failed", message: error.localizedDescription)
            }
            if refresh, self.project.id == project.id {
                await refreshProject()
            }
        }
    }

    public func cancel(jobID: UUID) {
        Task { await center.cancel(jobID: jobID) }
    }

    public func install() { perform(ComposerCommands.install(project)) }
    public func updateAll() { perform(ComposerCommands.update([], in: project)) }
    public func update(_ ids: [ComposerPackageID]) { perform(ComposerCommands.update(ids, in: project)) }
    public func require(_ id: ComposerPackageID, constraint: String?, dev: Bool) {
        perform(ComposerCommands.require(id, constraint: constraint, dev: dev, in: project))
    }
    public func remove(_ package: InstalledPackage) {
        perform(ComposerCommands.remove(package.id, dev: package.isDev, in: project))
    }
    public func runScript(_ name: String) { perform(ComposerCommands.runScript(name, in: project), thenRefresh: false) }
    public func diagnose() { perform(ComposerCommands.diagnose(project), thenRefresh: false); console.isExpanded = true }
    public func clearCache() { perform(ComposerCommands.clearCache(), thenRefresh: false) }
    public func selfUpdate() {
        let project = self.project
        Task {
            do {
                _ = try await center.run(ComposerCommands.selfUpdate())
            } catch {
                if case CommandError.cancelled = error { return }
                alert = AppAlert(title: "Update Composer failed", message: error.localizedDescription)
            }
            if self.project.id == project.id { await loadEnvironment() }
        }
    }

    // MARK: Derived

    public func outdatedEntry(_ id: ComposerPackageID) -> OutdatedPackage? {
        outdated.value?.first { $0.id == id }
    }

    public func advisories(for id: ComposerPackageID) -> [SecurityAdvisory] {
        audit.value?.advisories.filter { $0.package == id } ?? []
    }

    public var updateCount: Int { outdated.value?.filter(\.isDirect).count ?? 0 }
    public var auditIssueCount: Int {
        guard let report = audit.value else { return 0 }
        return report.affectedPackages.count + report.abandoned.count
    }
}
