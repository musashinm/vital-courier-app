// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "VitalCourierCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "VitalCourierCore", targets: ["VitalCourierCore"]),
    .library(name: "VitalCourierHealthKit", targets: ["VitalCourierHealthKit"]),
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
  ],
  targets: [
    .target(
      name: "VitalCourierCore",
      dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
    ),
    .target(
      name: "VitalCourierHealthKit",
      dependencies: ["VitalCourierCore"]
    ),
    .testTarget(
      name: "VitalCourierCoreTests",
      dependencies: ["VitalCourierCore"]
    ),
    .testTarget(
      name: "VitalCourierHealthKitTests",
      dependencies: ["VitalCourierHealthKit"]
    ),
  ]
)
