// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-cache",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(
            name: "Cache",
            targets: ["Cache"]
        ),
        .library(
            name: "Cache Standard Library Integration",
            targets: ["Cache Standard Library Integration"]
        ),
        .library(
            name: "Cache Apple Foundation Integration",
            targets: ["Cache Apple Foundation Integration"]
        ),
    ],
    traits: [
        .trait(name: "Effect", description: "Absorbed swift-cache-effect APIs"),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-effect.git", branch: "main"),
        .package(url: "https://github.com/swift-molecules/swift-async-waiter.git", branch: "main"),
        .package(
            url: "https://github.com/swift-molecules/swift-array.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-atoms/swift-async.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-atoms/swift-ownership.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-buffer-ring.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-buffer-linear.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-atoms/swift-storage.git",
            branch: "main", traits: ["Generational", "Memory"]),
        .package(
            url: "https://github.com/swift-atoms/swift-memory.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-molecules/swift-memory-allocation.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-atoms/swift-buffer.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-atoms/swift-queue.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-atoms/swift-standard-library-extensions.git",
            branch: "main"
        ),
        .package(url: "https://github.com/swift-molecules/swift-ownership-shared.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-store.git", branch: "main"),
    ],
    targets: [
        .testTarget(
            name: "Absorbed swift-cache-effect Tests",
            dependencies: [
                .target(name: "Cache"),
                .product(name: "Effect", package: "swift-effect", condition: .when(traits: ["Effect"])),
            ],
            path: "Tests/Absorbed swift-cache-effect"
        ),
        .target(
            name: "Cache",
            dependencies: [
                .product(name: "Effect", package: "swift-effect", condition: .when(traits: ["Effect"])),
                .product(name: "Async Waiter", package: "swift-async-waiter"),
                .product(name: "Array Primitive", package: "swift-array"),
                .product(name: "Array", package: "swift-array"),
                .product(name: "Async", package: "swift-async"),
                .product(name: "Ownership", package: "swift-ownership"),
                .product(name: "Buffer Ring Primitive", package: "swift-buffer-ring"),
                .product(
                    name: "Buffer Linear Primitive",
                    package: "swift-buffer-linear"
                ),
                .product(name: "Storage", package: "swift-storage"),
                .product(name: "Memory", package: "swift-memory"),
                .product(name: "Buffer", package: "swift-buffer"),
                .product(name: "Queue", package: "swift-queue"),
                .product(
                    name: "Standard Library Extensions",
                    package: "swift-standard-library-extensions"
                ),
                .product(name: "Buffer Linear Bounded Primitive", package: "swift-buffer-linear"),
                .product(name: "Memory Allocator Pool", package: "swift-memory-allocation"),
                .product(name: "Memory Pool", package: "swift-memory-allocation"),
                .product(name: "Memory Allocator", package: "swift-memory-allocation"),
                .product(name: "Ownership Shared Primitive", package: "swift-ownership-shared"),
                .product(name: "Store", package: "swift-store"),
            ]
        ),
        .target(
            name: "Cache Standard Library Integration",
            dependencies: ["Cache"]
        ),
        .target(
            name: "Cache Apple Foundation Integration",
            dependencies: [
                "Cache",
                "Cache Standard Library Integration",
            ]
        ),
        .testTarget(
            name: "Cache Tests",
            dependencies: [
                "Cache",
                .product(name: "Async", package: "swift-async"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
