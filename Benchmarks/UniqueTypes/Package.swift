// swift-tools-version: 6.0

import PackageDescription

// Deliberately a *separate* package from the root TSwinject manifest: this one
// carries ~12 MB of generated sources, and nobody building or testing the
// library should pay for that. It joins the root package only by path.
//
// Two executables, not one with a compile flag: each binary must link exactly
// one container library. The effect under test — the Swift runtime's
// process-wide conformance cache warming up between the first and second
// resolve pass — is a property of the image and the process, so a binary
// containing both containers would not measure either of them cleanly.
let package = Package(
    name: "UniqueTypesBench",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/Swinject/Swinject.git", from: "2.10.0")
    ],
    targets: [
        // 10 000 protocol/class pairs. No DI dependency, so this — the expensive
        // half of the build — compiles once and is shared by both runners.
        .target(
            name: "BenchModels",
            path: "Sources/BenchModels"
        ),
        .executableTarget(
            name: "BenchTSwinject",
            dependencies: [
                "BenchModels",
                .product(name: "TSwinject", package: "TSwinject")
            ],
            path: "Sources/BenchTSwinject"
        ),
        .executableTarget(
            name: "BenchSwinject",
            dependencies: [
                "BenchModels",
                .product(name: "Swinject", package: "Swinject")
            ],
            path: "Sources/BenchSwinject"
        )
    ],
    swiftLanguageModes: [.v6]
)
