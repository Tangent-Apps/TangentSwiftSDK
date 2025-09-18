// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TangentSwiftSDK",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "TangentSwiftSDK",
            targets: ["TangentSwiftSDK"]
        ),
    ],
    dependencies: [
        // Analytics
        .package(url: "https://github.com/mixpanel/mixpanel-swift", from: "5.0.0"),
        .package(url: "https://github.com/adjust/ios_sdk", from: "4.0.0"),
        
        // Paywall & Subscriptions
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm", from: "5.0.0"),
        .package(url: "https://github.com/superwall/Superwall-iOS", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "TangentSwiftSDK",
            dependencies: [
                .product(name: "Mixpanel", package: "mixpanel-swift"),
                .product(name: "Adjust", package: "ios_sdk"),
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
                .product(name: "SuperwallKit", package: "Superwall-iOS"),
            ]
        ),
        .testTarget(
            name: "TangentSwiftSDKTests",
            dependencies: ["TangentSwiftSDK"]
        ),
    ]
)
