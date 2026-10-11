// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopyShelf",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CopyShelf", targets: ["CopyShelf"])],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(name: "CopyShelf", dependencies: ["ClipboardCore"],
                          linkerSettings: [.linkedFramework("AppKit"),
                                           .linkedFramework("Carbon"),
                                           .linkedFramework("ApplicationServices"),
                                           .linkedFramework("ServiceManagement")]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
        .testTarget(name: "CopyShelfTests", dependencies: ["CopyShelf", "ClipboardCore"])
    ]
)
