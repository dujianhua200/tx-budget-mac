// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TXBudget",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TXBudget", targets: ["TXBudget"]),
    ],
    targets: [
        .executableTarget(name: "TXBudget", path: "Sources/TXBudget",
                          resources: [.copy("Resources/full-library.json")]),
        .testTarget(name: "TXBudgetTests", dependencies: ["TXBudget"], path: "Tests/TXBudgetTests",
                    resources: [.copy("Fixtures")]),
    ]
)
