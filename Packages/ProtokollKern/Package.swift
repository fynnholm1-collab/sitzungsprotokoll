// swift-tools-version:5.9
import PackageDescription

// Kernlogik der App ohne Apple-Oberflächen-Frameworks, damit sie
// unabhängig von der App getestet werden kann.
let package = Package(
    name: "ProtokollKern",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ProtokollKern", targets: ["ProtokollKern"]),
    ],
    targets: [
        .target(name: "ProtokollKern"),
        .testTarget(name: "ProtokollKernTests", dependencies: ["ProtokollKern"]),
    ]
)
