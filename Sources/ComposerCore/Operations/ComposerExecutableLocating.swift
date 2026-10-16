import Foundation

/// Where to find `composer` and `php`. Both are resolved once at startup and whenever the user
/// changes the override paths in Configuration.
public struct ComposerToolchain: Sendable, Hashable {
    public var composer: URL
    public var php: URL
    public var composerHome: URL

    public init(composer: URL, php: URL, composerHome: URL) {
        self.composer = composer
        self.php = php
        self.composerHome = composerHome
    }

    /// The clean PATH Composer runs with: the PHP directory, the Composer directory, then the
    /// system paths. The user's shell PATH is never used, so the app behaves the same from Finder.
    public var path: String {
        var dirs: [String] = []
        for url in [php, composer] {
            let dir = url.deletingLastPathComponent().path
            if !dirs.contains(dir) { dirs.append(dir) }
        }
        dirs += ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return dirs.joined(separator: ":")
    }
}

public protocol ComposerExecutableLocating: Sendable {
    func locate() -> Result<ComposerToolchain, CommandError>
}
