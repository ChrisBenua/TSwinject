// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "TSwinject",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "TSwinject", targets: ["TSwinject"]),
        .library(name: "TSwinjectSwinjectInterop", targets: ["TSwinjectSwinjectInterop"]),
        .library(name: "TSwinjectMacro", targets: ["TSwinjectMacro"])
    ],
    dependencies: [
        // Both dependencies below are reachable only from the interop and macro
        // products. SwiftPM still *resolves and checks out* both for any consumer
        // of this package — they will appear in your Package.resolved, costing
        // ~13 MB of checkout — but neither is compiled unless you actually depend
        // on the TSwinjectSwinjectInterop or TSwinjectMacro product.
        // Tests/Fixtures/verify-isolation.sh guards that.
        .package(url: "https://github.com/Swinject/Swinject.git", from: "2.9.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.1" ..< "603.0.0")
    ],
    targets: [
        // Core. Deliberately has no dependencies — keep it that way.
        .target(
            name: "TSwinject",
            path: "Sources/TSwinject"
        ),
        .target(
            name: "TSwinjectSwinjectInterop",
            dependencies: [
                "TSwinject",
                .product(name: "Swinject", package: "Swinject")
            ],
            path: "Sources/TSwinjectSwinjectInterop"
        ),
        // The #implements macro. The plugin is a macOS host executable built by
        // SwiftPM here; the CocoaPods path builds the same plugin via prepare_command.
        .macro(
            name: "TSwinjectMacroPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "Sources/TSwinjectMacroPlugin"
        ),
        .target(
            name: "TSwinjectMacro",
            dependencies: ["TSwinjectMacroPlugin"],
            path: "Sources/TSwinjectMacro"
        ),
        .testTarget(
            name: "TSwinjectTests",
            dependencies: ["TSwinject"],
            path: "Tests/TSwinjectTests"
        ),
        .testTarget(
            name: "TSwinjectMacroTests",
            dependencies: [
                "TSwinject",
                "TSwinjectMacro",
                "TSwinjectMacroPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ],
            path: "Tests/TSwinjectMacroTests"
        ),
        // Run explicitly, in release: swift test -c release --filter ContainerBenchmarkTests
        .testTarget(
            name: "TSwinjectBenchmarks",
            dependencies: [
                "TSwinject",
                .product(name: "Swinject", package: "Swinject")
            ],
            path: "Tests/TSwinjectBenchmarks"
        ),
        .testTarget(
            name: "TSwinjectInteropTests",
            dependencies: [
                "TSwinject",
                "TSwinjectSwinjectInterop",
                .product(name: "Swinject", package: "Swinject")
            ],
            path: "Tests/TSwinjectInteropTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
