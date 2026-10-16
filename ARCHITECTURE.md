# Architecture

ComposerUI follows the same shape as BrewUI: views render state and forward actions, an
observable app model owns presentation state, repositories and decoders adapt the data sources,
and the `composer` executable plus the Packagist API are the only sources of truth.

```text
View → AppModel / feature ViewModel → decoders and clients → composer CLI | Packagist JSON API
```

## Modules

| Location | Owns |
| --- | --- |
| `Sources/ComposerCore` | `ComposerProject`, `ComposerPackageID`, `InstalledPackage`, `OutdatedPackage`, `PackageDetail`, `DependencyGraph`, `SecurityAdvisory`/`AuditReport`, `ComposerScript`, `ComposerEnvironment`, `DiscoveredPackage`/`PackagistPackage`. `ComposerCommand` and the `ComposerCommands` catalogue. The `CommandCenter` protocol, `CommandJob` and `CommandPhase`. |
| `Sources/ComposerCLI` | `ComposerExecutableLocator`, `ProcessRunner`, `SerialCommandCenter`, and one decoder per Composer output: `ShowJSON`, `OutdatedJSON`, `AuditJSON`, `ShowPackageJSON`, `InstalledJSONFile`, `ComposerJSONFile`, `ConfigListParser`. |
| `Sources/ComposerPackagist` | `PackagistClient` (`/search.json`, `/packages/{name}.json`). |
| `Sources/ComposerUI` | `AppModel` (composition root), `ConsoleStore`, `ProjectStore`, `ToolchainSettings`, `LaunchOptions`, shared components and the feature views. |
| `App/` | `ComposerUIApp`, assets, `Info.plist`. The Xcode project is generated from `project.yml`. |

`ComposerCore` depends on nothing. `ComposerCLI` and `ComposerPackagist` depend on `ComposerCore`
only. `ComposerUI` is the only module that imports SwiftUI or AppKit.

## Command execution

`SerialCommandCenter` is an actor. It runs one `composer` process at a time, so mutations never
race on `vendor/`, and coalesces queued commands with the same `operationID` (two refreshes become
one). Each job is published to the `ConsoleStore` (a `CommandJobObserver` on the main actor) as
it is queued, starts, streams output and finishes.

`ProcessRunner` launches `php /path/to/composer <args>` with `Process`, a clean environment and
argv-only arguments. Output is read from both pipes and split into lines, tolerating `\r` progress
updates and split UTF-8 sequences. Cancellation sends `SIGTERM` to the whole process group, so
child processes (git, scripts) end too.

`composer audit` and `composer outdated` exit non-zero when they find something. A read command
with usable stdout is therefore treated as succeeded, and the exit code is noted in the transcript.

## Data

- `ComposerPackageID` is the canonical, lower-cased `vendor/name`. Display names keep their case.
- `InstalledPackage` comes from `composer show --format=json` (which carries the
  `direct-dependency` flag). `isDev` is derived from the root `composer.json`'s `require-dev`.
- `DependencyGraph` is built from `vendor/composer/installed.json`, because `composer depends`
  has no JSON output. `replace` and `provide` names are treated as aliases of the real package.
- `PackageDetail` is loaded lazily per selection from `composer show <name> --format=json`.
- Packagist responses are decoded inside `ComposerPackagist` and returned as domain models.
  Unknown fields are ignored; malformed entries are skipped.
- Recent projects and toolchain overrides live in `UserDefaults`. Nothing else is persisted.

## Toolchain discovery

`ComposerExecutableLocator` tries, in order, the user override, `/opt/homebrew/bin`,
`/usr/local/bin`, Laravel Herd, `~/.composer/vendor/bin`, and `/usr/bin` for Composer, and the
same places plus versioned Homebrew and MAMP installs for PHP. Composer is a PHP archive, so the
app always runs it through the located `php` rather than relying on its shebang.

## Product constraints

- macOS only, SwiftUI with AppKit bridges (open panels, pasteboard, Finder reveal).
- Unsandboxed: it must run the user's Composer and read any project folder.
- Composer is never bypassed. The app does not edit `composer.json`, `composer.lock` or `vendor/`.
- No panics on bad input: every decoder tolerates unknown keys and returns errors the user can act
  on.
