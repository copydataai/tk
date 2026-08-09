// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "tk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "tk", targets: ["TK"])
    ],
    targets: [
        .executableTarget(
            name: "TK",
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
