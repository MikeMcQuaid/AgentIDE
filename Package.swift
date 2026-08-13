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
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.15.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.9.0"),
        // The newest grammar releases are generated with tree-sitter
        // ABI 15, which swift-tree-sitter 0.9.0's runtime rejects, so
        // both grammars pin the latest ABI 14 releases.
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", exact: "0.23.3"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.23.6"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", exact: "0.24.8"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", exact: "0.23.2"),
        // The Swift grammar the tree-sitter ecosystem standardises on;
        // the generated-files tag is the one consumable by SwiftPM.
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.3-with-generated-files"),
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
                .product(name: "SwiftTerm", package: "SwiftTerm"),
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
