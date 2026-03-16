// swift-tools-version: 6.2
import PackageDescription

let package = Package (
    name: "Allocators",
    
    products: [
        .library(
            name: "SwiftAllocators",
            targets: ["Allocators"]
        ),
    ],
    
    targets: [
        .target(
            name: "Allocators"
        ),
        .testTarget(
            name: "AllocatorTests",
            dependencies: ["Allocators"]
        ),
    ]
)
