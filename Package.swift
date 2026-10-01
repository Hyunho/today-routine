// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TodayRoutine", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "RoutineCore", targets: ["RoutineCore"])], targets: [.target(name: "RoutineCore", path: "TodayRoutine", exclude: ["App", "Features"], sources: ["Models", "Data", "Domain", "Services"]), .testTarget(name: "RoutineCoreTests", dependencies: ["RoutineCore"], path: "TodayRoutineTests")])
