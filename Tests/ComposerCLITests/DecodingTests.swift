import ComposerCore
import ComposerCLI
import Foundation
import Testing

@Suite struct DecodingTests {
    func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func decodesInstalledInventory() throws {
        let packages = try ShowJSON.decode(fixture("show.json"), devNames: [ComposerPackageID("fakerphp/faker")])
        #expect(packages.count > 50)
        let dompdf = try #require(packages.first { $0.name == "barryvdh/laravel-dompdf" })
        #expect(dompdf.isDirect)
        #expect(dompdf.version == "v3.1.2")
        #expect(dompdf.scope == .production)
        let brick = try #require(packages.first { $0.name == "brick/math" })
        #expect(!brick.isDirect)
        #expect(brick.scope == .transitive)
    }

    @Test func decodesOutdated() throws {
        let outdated = try OutdatedJSON.decode(fixture("outdated.json"))
        #expect(!outdated.isEmpty)
        let brick = try #require(outdated.first { $0.name == "brick/math" })
        #expect(brick.latestVersion == "1.0.0")
        #expect(brick.status == .updatePossible)
        #expect(brick.releaseDate != nil)
    }

    @Test func decodesAudit() throws {
        let report = try AuditJSON.decode(fixture("audit.json"))
        #expect(!report.advisories.isEmpty)
        let first = try #require(report.advisories.first { $0.cve == "CVE-2026-59943" })
        #expect(first.package.name == "dompdf/dompdf")
        #expect(first.severity == .medium)
        #expect(first.link != nil)
    }

    @Test func emptyAuditIsClean() throws {
        let report = try AuditJSON.decode(Data(#"{"advisories": [], "abandoned": []}"#.utf8))
        #expect(report.isClean)
    }

    @Test func decodesPackageDetail() throws {
        let detail = try ShowPackageJSON.decode(fixture("show-one.json"))
        #expect(detail.id.name == "laravel/framework")
        #expect(detail.licenses.first?.spdx == "MIT")
        #expect(detail.sourceURL?.absoluteString == "https://github.com/laravel/framework")
        #expect(detail.requires.contains { $0.name == "php" })
        #expect(detail.released != nil)
    }

    @Test func parsesConfigList() throws {
        let text = try String(decoding: fixture("config-list.txt"), as: UTF8.self)
        let entries = ConfigListParser.parse(text)
        let vendor = try #require(entries.first { $0.key == "vendor-dir" })
        #expect(vendor.value.hasPrefix("vendor"))
        #expect(entries.contains { $0.key == "cache-dir" })
    }

    @Test func parsesVersions() {
        let (composer, php, path) = ConfigListParser.parseVersions("Composer version 2.10.2 2026-07-01 11:24:45\nPHP version 8.4.23 (/opt/homebrew/bin/php)")
        #expect(composer == "2.10.2")
        #expect(php == "8.4.23")
        #expect(path == "/opt/homebrew/bin/php")
    }

    @Test func terminalTextHidesParsingFlags() {
        let project = ComposerProject.project(at: URL(fileURLWithPath: "/tmp/demo"))
        let command = ComposerCommands.outdated(project)
        #expect(command.terminalText == "composer outdated --no-interaction --no-ansi")
        let req = ComposerCommands.require(ComposerPackageID("Monolog/Monolog"), dev: true, in: project)
        #expect(req.terminalText.contains("require --dev monolog/monolog"))
    }

    @Test func composerJSONScripts() throws {
        let json = #"{"name":"a/b","require":{"php":"^8.3","x/y":"^1"},"require-dev":{"z/w":"^2"},"scripts":{"test":"phpunit","post-install-cmd":["a","b"]},"scripts-descriptions":{"test":"Run tests"}}"#
        let file = try ComposerJSONFile.decode(Data(json.utf8))
        #expect(file.devPackageIDs.contains(ComposerPackageID("z/w")))
        #expect(file.scripts.first?.name == "test")
        #expect(file.scripts.first?.description == "Run tests")
        #expect(file.scripts.last?.isLifecycleEvent == true)
    }

    @Test func installedGraph() {
        let json = #"{"packages":[{"name":"a/a","require":{"b/b":"^1","php":"^8"}},{"name":"b/b","require":{},"replace":{"c/c":"self.version"}},{"name":"d/d","require":{"c/c":"^1"}}],"dev-package-names":["d/d"]}"#
        let contents = InstalledJSONFile.decode(Data(json.utf8))
        #expect(contents.graph.dependencies(of: ComposerPackageID("a/a")) == [ComposerPackageID("b/b")])
        #expect(contents.graph.dependents(of: ComposerPackageID("b/b")) == [ComposerPackageID("a/a"), ComposerPackageID("d/d")])
        #expect(contents.devPackageNames.contains(ComposerPackageID("d/d")))
    }
}
