import ComposerCore
import Foundation

/// Debug launch arguments for screenshots and UI checks, e.g.
/// `ComposerUI --project /path --tab updates --package laravel/framework --query monolog --console`.
/// They only set the initial state; nothing else reads them.
public struct LaunchOptions: Sendable {
    public var projectPath: String?
    public var tab: SidebarItem?
    public var package: ComposerPackageID?
    public var discoverQuery: String?
    public var consoleExpanded = false
    public var script: String?
    public var appearance: String?

    public static func parse(_ arguments: [String] = CommandLine.arguments) -> LaunchOptions {
        var options = LaunchOptions()
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--project": options.projectPath = iterator.next()
            case "--tab": options.tab = iterator.next().flatMap(SidebarItem.init(rawValue:))
            case "--package": options.package = iterator.next().map(ComposerPackageID.init)
            case "--query": options.discoverQuery = iterator.next()
            case "--console": options.consoleExpanded = true
            case "--script": options.script = iterator.next()
            case "--appearance": options.appearance = iterator.next()
            default: break
            }
        }
        return options
    }
}
