import Foundation

/// One invocation of the `composer` executable. Arguments travel as literal argv, never as
/// interpolated shell text, so package names and paths cannot be misread by a shell.
public struct ComposerCommand: Hashable, Sendable, Identifiable {
    public enum Effect: Sendable, Hashable {
        /// Only reads state (`show`, `outdated`, `audit`, `config`).
        case read
        /// Changes `vendor`, `composer.json` or `composer.lock`.
        case mutate
    }

    /// Stable identity for coalescing: two queued commands with the same operation ID collapse into one.
    public let operationID: String
    public var title: String
    public var arguments: [String]
    public var workingDirectory: URL?
    public var effect: Effect
    /// Arguments that exist only for machine parsing (`--format=json`) and are hidden from the
    /// Terminal command shown to the user.
    public var hiddenArguments: Set<String>

    public init(
        operationID: String,
        title: String,
        arguments: [String],
        workingDirectory: URL?,
        effect: Effect,
        hiddenArguments: Set<String> = []
    ) {
        self.operationID = operationID
        self.title = title
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.effect = effect
        self.hiddenArguments = hiddenArguments
    }

    public var id: String { operationID }

    /// The command as a user would type it in Terminal.
    public var terminalText: String {
        let shown = arguments.filter { !hiddenArguments.contains($0) }
        let quoted = shown.map(Self.shellQuote)
        return (["composer"] + quoted).joined(separator: " ")
    }

    static func shellQuote(_ argument: String) -> String {
        let safe = argument.allSatisfy { $0.isLetter || $0.isNumber || "-_./:=@^~*".contains($0) }
        if safe, !argument.isEmpty { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Factory for the commands the app runs. Keeping them in one place makes the Terminal text
/// shown to users reviewable.
public enum ComposerCommands {
    static let json = "--format=json"
    static let common = ["--no-interaction", "--no-ansi"]

    public static func show(_ project: ComposerProject) -> ComposerCommand {
        ComposerCommand(
            operationID: "show:\(project.id)",
            title: "Read installed packages",
            arguments: project.commandPrefix + ["show", json] + common,
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .read,
            hiddenArguments: [json]
        )
    }

    public static func showPackage(_ id: ComposerPackageID, in project: ComposerProject) -> ComposerCommand {
        ComposerCommand(
            operationID: "show:\(project.id):\(id.name)",
            title: "Read \(id.name)",
            arguments: project.commandPrefix + ["show", id.name, json] + common,
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .read,
            hiddenArguments: [json]
        )
    }

    public static func outdated(_ project: ComposerProject) -> ComposerCommand {
        ComposerCommand(
            operationID: "outdated:\(project.id)",
            title: "Check for updates",
            arguments: project.commandPrefix + ["outdated", json] + common,
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .read,
            hiddenArguments: [json]
        )
    }

    public static func audit(_ project: ComposerProject) -> ComposerCommand {
        ComposerCommand(
            operationID: "audit:\(project.id)",
            title: "Audit for vulnerabilities",
            arguments: project.commandPrefix + ["audit", json] + common,
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .read,
            hiddenArguments: [json]
        )
    }

    public static func install(_ project: ComposerProject) -> ComposerCommand {
        ComposerCommand(
            operationID: "install:\(project.id)",
            title: "Install dependencies",
            arguments: project.commandPrefix + ["install"] + common,
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .mutate
        )
    }

    public static func require(_ id: ComposerPackageID, constraint: String? = nil, dev: Bool, in project: ComposerProject) -> ComposerCommand {
        let spec = constraint.map { "\(id.name):\($0)" } ?? id.name
        var args = project.commandPrefix + ["require"]
        if dev { args.append("--dev") }
        args.append(spec)
        return ComposerCommand(
            operationID: "require:\(project.id):\(id.name)",
            title: "Require \(id.name)",
            arguments: args + common,
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .mutate
        )
    }

    public static func remove(_ id: ComposerPackageID, dev: Bool, in project: ComposerProject) -> ComposerCommand {
        var args = project.commandPrefix + ["remove"]
        if dev { args.append("--dev") }
        args.append(id.name)
        return ComposerCommand(
            operationID: "remove:\(project.id):\(id.name)",
            title: "Remove \(id.name)",
            arguments: args + common,
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .mutate
        )
    }

    public static func update(_ ids: [ComposerPackageID], in project: ComposerProject) -> ComposerCommand {
        var args = project.commandPrefix + ["update"]
        args += ids.map(\.name)
        if !ids.isEmpty { args.append("--with-all-dependencies") }
        let key = ids.isEmpty ? "all" : ids.map(\.name).joined(separator: ",")
        return ComposerCommand(
            operationID: "update:\(project.id):\(key)",
            title: ids.isEmpty ? "Update all packages" : "Update \(ids.map(\.name).joined(separator: ", "))",
            arguments: args + common,
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .mutate
        )
    }

    public static func bump(_ project: ComposerProject) -> ComposerCommand {
        ComposerCommand(
            operationID: "bump:\(project.id)",
            title: "Bump constraints to installed versions",
            arguments: project.commandPrefix + ["bump"] + common,
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .mutate
        )
    }

    public static func runScript(_ name: String, in project: ComposerProject) -> ComposerCommand {
        ComposerCommand(
            operationID: "script:\(project.id):\(name)",
            title: "Run script \(name)",
            arguments: project.commandPrefix + ["run-script", name, "--no-interaction"],
            workingDirectory: project.isGlobal ? nil : project.rootURL,
            effect: .mutate
        )
    }

    public static func version() -> ComposerCommand {
        ComposerCommand(operationID: "version", title: "Composer version", arguments: ["--version"] + common, workingDirectory: nil, effect: .read)
    }

    public static func configList(_ project: ComposerProject?) -> ComposerCommand {
        let prefix = project?.commandPrefix ?? ["global"]
        return ComposerCommand(
            operationID: "config:\(project?.id ?? "global")",
            title: "Read configuration",
            arguments: prefix + ["config", "--list"] + common,
            workingDirectory: project?.isGlobal == false ? project?.rootURL : nil,
            effect: .read
        )
    }

    public static func diagnose(_ project: ComposerProject?) -> ComposerCommand {
        ComposerCommand(
            operationID: "diagnose:\(project?.id ?? "global")",
            title: "Diagnose",
            arguments: ["diagnose"] + common,
            workingDirectory: project?.isGlobal == false ? project?.rootURL : nil,
            effect: .read
        )
    }

    public static func selfUpdate() -> ComposerCommand {
        ComposerCommand(operationID: "self-update", title: "Update Composer", arguments: ["self-update"] + common, workingDirectory: nil, effect: .mutate)
    }

    public static func clearCache() -> ComposerCommand {
        ComposerCommand(operationID: "clear-cache", title: "Clear Composer cache", arguments: ["clear-cache"] + common, workingDirectory: nil, effect: .mutate)
    }
}
