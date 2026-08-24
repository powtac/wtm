// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "WTMKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "WTMDomain", targets: ["WTMDomain"]),
    .library(name: "WTMAdapterContracts", targets: ["WTMAdapterContracts"]),
    .library(name: "WTMInventory", targets: ["WTMInventory"]),
    .library(name: "WTMPersistence", targets: ["WTMPersistence"]),
    .library(name: "WTMSecurity", targets: ["WTMSecurity"]),
    .library(name: "AdapterOllama", targets: ["AdapterOllama"]),
    .library(name: "AdapterHuggingFace", targets: ["AdapterHuggingFace"]),
    .library(name: "AdapterManual", targets: ["AdapterManual"]),
  ],
  targets: [
    .target(name: "WTMDomain"),
    .target(name: "WTMAdapterContracts", dependencies: ["WTMDomain"]),
    .target(name: "WTMSecurity"),
    .target(
      name: "WTMInventory",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(name: "WTMPersistence", dependencies: ["WTMDomain"]),
    .target(
      name: "AdapterOllama",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "AdapterHuggingFace",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "AdapterManual",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .testTarget(name: "WTMDomainTests", dependencies: ["WTMDomain"]),
    .testTarget(
      name: "WTMInventoryTests",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMInventory", "WTMSecurity"]
    ),
    .testTarget(name: "WTMPersistenceTests", dependencies: ["WTMPersistence"]),
    .testTarget(
      name: "WTMAdapterTests",
      dependencies: [
        "WTMDomain",
        "WTMAdapterContracts",
        "AdapterOllama",
        "AdapterHuggingFace",
        "AdapterManual",
      ],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
