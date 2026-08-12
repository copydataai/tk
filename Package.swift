// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "tk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "tk", targets: ["TK"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.5")
    ],
    targets: [
        .executableTarget(
            name: "TK",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: ["Views/SettingsProfilesPrototype.html"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "TKTests",
            dependencies: ["TK"]
        )
    ]
)
