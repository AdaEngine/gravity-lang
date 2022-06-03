// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Gravity",
    products: [
        .library(
            name: "Gravity",
            targets: ["Gravity"]
        ),
        
        .executable(
            name: "GravityExample",
            targets: ["GravitySwiftExample"]
        )
    ],
    targets: [
        
        .executableTarget(
            name: "GravitySwiftExample",
            dependencies: ["Gravity"],
            path: "examples/GravitySwiftExample"
        ),
        
        .target(
            name: "Gravity",
            dependencies: ["CGravity"],
            path: "binding/GravitySwift"
        ),
        
        .target(
            name: "CGravity",
            path: "src",
            exclude: ["cli"],
            publicHeadersPath: "."
        )
    ],
    cLanguageStandard: .gnu99,
    cxxLanguageStandard: .gnucxx11
)
