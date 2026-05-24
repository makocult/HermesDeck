// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HermesDeckNative",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HermesDeckNative", targets: ["HermesDeckNative"])
    ],
    targets: [
        .executableTarget(
            name: "HermesDeckNative",
            path: "Sources",
            resources: [
                .copy("../Resources/HermesDeckLogo.png")
            ]
        )
    ]
)
