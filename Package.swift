// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PDFBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PDFBar",
            path: "Sources/PDFBar"
        )
    ]
)
