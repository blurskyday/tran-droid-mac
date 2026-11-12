// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "tranandroi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "tranandroi", targets: ["tranandroi"])
    ],
    targets: [
        .systemLibrary(
            name: "CLibMTP",
            path: "Sources/CLibMTP",
            pkgConfig: "libmtp",
            providers: [
                .brew(["libmtp"])
            ]
        ),
        .executableTarget(
            name: "tranandroi",
            dependencies: ["CLibMTP"],
            path: "Sources/tranandroi",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/opt/libmtp/include"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L/opt/homebrew/opt/libmtp/lib",
                    "-lmtp",
                    "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/opt/libmtp/lib"
                ])
            ]
        )
    ]
)
