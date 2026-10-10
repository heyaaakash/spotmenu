// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlayMenu",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PlayMenu", targets: ["PlayMenu"])],
    targets: [.executableTarget(name: "PlayMenu", path: "Sources/PlayMenu")]
)
