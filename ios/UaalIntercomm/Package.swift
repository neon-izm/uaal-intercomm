// swift-tools-version: 6.0
import PackageDescription

// UnityFramework は Cloudflare R2 の zip を Swift Package Manager が取得する。
// checksum は swift package compute-checksum の値。zip を出し直したら更新する。
let package = Package(
    name: "UaalIntercomm",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "UaalIntercomm", targets: ["UaalIntercomm"]),
    ],
    targets: [
        .target(
            name: "UaalIntercomm",
            dependencies: ["UnityFramework"]
        ),
        .binaryTarget(
            name: "UnityFramework",
            url: "https://pub-9480de868c60413c80b39cefa6089251.r2.dev/ios/1.0.0/UnityFramework.xcframework.zip",
            checksum: "4e931afb1df1e1a0cb13ba1618cc2042bc8fe14eb8f838ddf5d0533b0a2d88e7"
        ),
    ]
)
