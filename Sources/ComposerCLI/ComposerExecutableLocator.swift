import ComposerCore
import Foundation

/// Finds `composer` and `php` in the places macOS developers install them. An explicit override
/// wins; otherwise the candidates are tried in order and the first executable file is used.
public struct ComposerExecutableLocator: ComposerExecutableLocating {
    public var composerOverride: String?
    public var phpOverride: String?
    private let home: String

    public init(composerOverride: String? = nil, phpOverride: String? = nil, home: String = NSHomeDirectory()) {
        self.composerOverride = composerOverride
        self.phpOverride = phpOverride
        self.home = home
    }

    public func composerCandidates() -> [String] {
        var list: [String] = []
        if let composerOverride, !composerOverride.isEmpty { list.append(composerOverride) }
        list += [
            "/opt/homebrew/bin/composer",
            "/usr/local/bin/composer",
            "\(home)/Library/Application Support/Herd/bin/composer",
            "\(home)/.composer/vendor/bin/composer",
            "\(home)/.config/composer/vendor/bin/composer",
            "/usr/bin/composer",
        ]
        return list
    }

    public func phpCandidates() -> [String] {
        var list: [String] = []
        if let phpOverride, !phpOverride.isEmpty { list.append(phpOverride) }
        list += [
            "/opt/homebrew/bin/php",
            "/usr/local/bin/php",
            "\(home)/Library/Application Support/Herd/bin/php",
        ]
        list += glob("/opt/homebrew/opt/php*/bin/php").sorted(by: >)
        list += glob("/usr/local/opt/php*/bin/php").sorted(by: >)
        list += glob("/Applications/MAMP/bin/php/php*/bin/php").sorted(by: >)
        list += glob("\(home)/Library/Application Support/Herd/bin/php*").sorted(by: >)
        list.append("/usr/bin/php")
        return list
    }

    public func locate() -> Result<ComposerToolchain, CommandError> {
        guard let composer = composerCandidates().first(where: isExecutable) else {
            return .failure(.composerNotFound)
        }
        guard let php = phpCandidates().first(where: isExecutable) else {
            return .failure(.phpNotFound)
        }
        return .success(ComposerToolchain(
            composer: URL(fileURLWithPath: composer),
            php: URL(fileURLWithPath: php),
            composerHome: composerHomeURL()
        ))
    }

    public func composerHomeURL() -> URL {
        if let env = ProcessInfo.processInfo.environment["COMPOSER_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let legacy = "\(home)/.composer"
        if FileManager.default.fileExists(atPath: legacy) { return URL(fileURLWithPath: legacy) }
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.config"
        return URL(fileURLWithPath: "\(xdg)/composer")
    }

    private func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    private func glob(_ pattern: String) -> [String] {
        var result = glob_t()
        defer { globfree(&result) }
        guard Darwin.glob(pattern, 0, nil, &result) == 0 else { return [] }
        return (0..<Int(result.gl_matchc)).compactMap { index in
            result.gl_pathv[index].map { String(cString: $0) }
        }
    }
}
