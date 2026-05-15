// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OhbeeEditor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "OhbeeEditor",
            targets: ["OhbeeEditor"]
        ),
        .executable(
            name: "OhbeeEditorSelfTests",
            targets: ["OhbeeEditorSelfTests"]
        )
    ],
    targets: [
        .target(
            name: "OhbeeEditorCore"
        ),
        .executableTarget(
            name: "OhbeeEditor",
            dependencies: ["OhbeeEditorCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "OhbeeEditorSelfTests",
            dependencies: ["OhbeeEditorCore"]
        )
    ]
)
