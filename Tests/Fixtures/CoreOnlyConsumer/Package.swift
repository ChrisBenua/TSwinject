// swift-tools-version: 6.0

import PackageDescription

// A stand-in for a real consumer that wants the DI container and nothing else.
//
// TSwinject's own manifest declares Swinject and swift-syntax as dependencies,
// but both are reachable only from the TSwinjectSwinjectInterop and
// TSwinjectMacro products. SE-0226 target-based dependency resolution is what
// keeps them out of this package's graph. `swift test` in the parent package
// cannot prove that — a root build always resolves everything — so this fixture
// exists to be built separately and have its Package.resolved inspected.
//
// See Tests/Fixtures/verify-isolation.sh.
let package = Package(
    name: "CoreOnlyConsumer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../..")
    ],
    targets: [
        .target(
            name: "CoreOnlyConsumer",
            dependencies: [
                .product(name: "TSwinject", package: "TSwinject")
            ]
        )
    ]
)
