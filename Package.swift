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
            dependencies: ["AgentIDEDomain", "AgentIDEData"],
            swiftSettings: mainActorByDefault,
        ),
        .target(
            name: "SessionFeature",
            dependencies: ["AgentIDEDomain", "AgentIDEData", "TerminalUI"],
            swiftSettings: mainActorByDefault,
        ),
        .target(
            name: "ReviewFeature",
            dependencies: ["AgentIDEDomain", "AgentIDEData"],
            swiftSettings: mainActorByDefault,
        ),
        .target(
            name: "PRFeature",
            dependencies: ["AgentIDEDomain", "AgentIDEData"],
            swiftSettings: mainActorByDefault,
        ),
        .target(
            name: "TerminalUI",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
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
    ],
)
