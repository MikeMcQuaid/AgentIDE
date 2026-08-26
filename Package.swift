// swift-tools-version: 6.2
import PackageDescription

let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]
let mainActorByDefault = approachableConcurrency + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "AgentIDE",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "AgentIDEDomain", targets: ["AgentIDEDomain"]),
        .library(name: "AgentIDEData", targets: ["AgentIDEData"]),
        .library(name: "DashboardFeature", targets: ["DashboardFeature"]),
        .library(name: "SessionFeature", targets: ["SessionFeature"]),
        .library(name: "ReviewFeature", targets: ["ReviewFeature"]),
        .library(name: "PRFeature", targets: ["PRFeature"]),
        .library(name: "TerminalUI", targets: ["TerminalUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.19.0"),
        // Apple's GitHub-flavoured markdown parser; parsing by hand
        // kept misreading real review comments.
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.5.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", exact: "0.25.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", exact: "0.24.8"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", exact: "0.23.2"),
        // The latest 0.7.3 grammar with the generated parser sources SwiftPM needs.
        .package(
            url: "https://github.com/alex-pinkus/tree-sitter-swift",
            revision: "31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5",
        ),
    ],
    targets: [
        .target(
            name: "AgentIDEDomain",
            swiftSettings: approachableConcurrency,
        ),
        .target(
            name: "AgentIDEData",
            dependencies: ["AgentIDEDomain"],
            swiftSettings: approachableConcurrency,
            linkerSettings: [
                // CI's runners boot an older macOS than the 27.0 SDK
                // they build with, so a hard link aborts every test
                // bundle at load over missing FoundationModels
                // symbols; weak linking defers to the availability
                // guard in FoundationModelClient.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]),
            ],
        ),
        .target(
            name: "DashboardFeature",
            dependencies: ["AgentIDEDomain", "AgentIDEData", "TerminalUI"],
            swiftSettings: mainActorByDefault,
        ),
        .target(
            name: "SessionFeature",
            dependencies: ["AgentIDEDomain", "AgentIDEData", "TerminalUI"],
            swiftSettings: mainActorByDefault,
        ),
        .target(
            name: "ReviewFeature",
            dependencies: ["AgentIDEDomain", "AgentIDEData", "TerminalUI"],
            swiftSettings: mainActorByDefault,
        ),
        .target(
            name: "PRFeature",
            dependencies: ["AgentIDEDomain", "AgentIDEData", "TerminalUI"],
            swiftSettings: mainActorByDefault,
        ),
        .target(
            name: "TerminalUI",
            dependencies: [
                "AgentIDEDomain",
                "AgentIDEData",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterRuby", package: "tree-sitter-ruby"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
            ],
            swiftSettings: mainActorByDefault,
        ),
        .testTarget(
            name: "AgentIDEDomainTests",
            dependencies: ["AgentIDEDomain"],
            swiftSettings: approachableConcurrency,
        ),
        .testTarget(
            name: "AgentIDEDataTests",
            dependencies: ["AgentIDEData"],
            swiftSettings: approachableConcurrency,
        ),
        .testTarget(
            name: "DashboardFeatureTests",
            dependencies: ["DashboardFeature"],
            swiftSettings: mainActorByDefault,
        ),
        .testTarget(
            name: "TerminalUITests",
            dependencies: ["TerminalUI"],
            swiftSettings: mainActorByDefault,
        ),
        .testTarget(
            name: "ReviewFeatureTests",
            dependencies: ["ReviewFeature"],
            swiftSettings: mainActorByDefault,
        ),
        .testTarget(
            name: "SessionFeatureTests",
            dependencies: ["SessionFeature"],
            swiftSettings: mainActorByDefault,
        ),
        .testTarget(
            name: "PRFeatureTests",
            dependencies: ["PRFeature"],
            swiftSettings: mainActorByDefault,
        ),
    ],
)
