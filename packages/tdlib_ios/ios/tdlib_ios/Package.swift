// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tdlib_ios",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "tdlib-ios", targets: ["tdlib_ios"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Готовая сборка TDLib: https://github.com/Swiftgram/TDLibFramework/releases
        .package(url: "https://github.com/Swiftgram/TDLibFramework", exact: "1.8.68-4a85043f"),
    ],
    targets: [
        .target(
            name: "tdlib_ios",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "TDLibFramework", package: "TDLibFramework"),
            ]
        )
    ]
)
