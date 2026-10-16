// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ComposerKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ComposerCore", targets: ["ComposerCore"]),
        .library(name: "ComposerCLI", targets: ["ComposerCLI"]),
        .library(name: "ComposerPackagist", targets: ["ComposerPackagist"]),
        .library(name: "ComposerUI", targets: ["ComposerUI"]),
    ],
    targets: [
        .target(name: "ComposerCore"),
        .target(name: "ComposerCLI", dependencies: ["ComposerCore"]),
        .target(name: "ComposerPackagist", dependencies: ["ComposerCore"]),
        .target(name: "ComposerUI", dependencies: ["ComposerCore", "ComposerCLI", "ComposerPackagist"]),
        .testTarget(
            name: "ComposerCLITests",
            dependencies: ["ComposerCLI", "ComposerCore", "ComposerPackagist"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
