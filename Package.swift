// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Tokenmon",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "TokenmonDomain", targets: ["TokenmonDomain"]),
        .library(name: "TokenmonGameEngine", targets: ["TokenmonGameEngine"]),
        .library(name: "TokenmonProviders", targets: ["TokenmonProviders"]),
        .library(name: "TokenmonPersistence", targets: ["TokenmonPersistence"]),
        .executable(name: "TokenmonApp", targets: ["TokenmonApp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-testing.git",
            revision: "5ee435b15ad40ec1f644b5eb9d247f263ccd2170"
        ),
        .package(
            url: "https://github.com/PostHog/posthog-ios.git",
            from: "3.0.0"
        ),
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            from: "2.9.1"
        ),
        .package(
            url: "https://github.com/grpc/grpc-swift.git",
            from: "1.23.0"
        ),
    ],
    targets: [
        .target(
            name: "TokenmonDomain"
        ),
        .target(
            name: "TokenmonGameEngine",
            dependencies: [
                "TokenmonDomain",
            ]
        ),
        .target(
            name: "TokenmonProviders",
            dependencies: [
                "TokenmonDomain",
                .product(name: "GRPC", package: "grpc-swift"),
            ]
        ),
        .target(
            name: "TokenmonPersistence",
            dependencies: [
                "TokenmonDomain",
                "TokenmonGameEngine",
                "TokenmonProviders",
            ]
        ),
        .executableTarget(
            name: "TokenmonApp",
            dependencies: [
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "Sparkle", package: "Sparkle"),
                "TokenmonDomain",
                "TokenmonGameEngine",
                "TokenmonProviders",
                "TokenmonPersistence",
            ],
            resources: [
                .process("Resources"),
                .copy("../../assets/sprites"),
                .copy("../../assets/backgrounds"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "TokenmonAppTests",
            dependencies: [
                .product(name: "Testing", package: "swift-testing"),
                "TokenmonApp",
                "TokenmonGameEngine",
                "TokenmonPersistence",
                "TokenmonDomain",
            ]
        ),
    ]
)
