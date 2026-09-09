// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "WTMKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "AdapterGPT4All", targets: ["AdapterGPT4All"]),
    .library(name: "AdapterJan", targets: ["AdapterJan"]),
    .library(name: "RuntimeLocalAI", targets: ["RuntimeLocalAI"]),
    .library(name: "ClientOpenWebUI", targets: ["ClientOpenWebUI"]),

    .library(name: "WTMDomain", targets: ["WTMDomain"]),
    .library(name: "WTMAdapterContracts", targets: ["WTMAdapterContracts"]),
    .library(name: "WTMInventory", targets: ["WTMInventory"]),
    .library(name: "WTMSecurity", targets: ["WTMSecurity"]),
    .library(name: "WTMActions", targets: ["WTMActions"]),
    .library(name: "WTMRuntime", targets: ["WTMRuntime"]),
    .library(name: "RuntimeOllama", targets: ["RuntimeOllama"]),
    .library(name: "RuntimeLlamaCpp", targets: ["RuntimeLlamaCpp"]),
    .library(name: "ClientOpenClaw", targets: ["ClientOpenClaw"]),
    .library(name: "ClientUnsloth", targets: ["ClientUnsloth"]),
    .library(name: "WTMPersistence", targets: ["WTMPersistence"]),
    .library(name: "AdapterOllama", targets: ["AdapterOllama"]),
    .library(name: "AdapterHuggingFace", targets: ["AdapterHuggingFace"]),
    .library(name: "AdapterMLX", targets: ["AdapterMLX"]),
    .library(name: "AdapterLMStudio", targets: ["AdapterLMStudio"]),
    .library(name: "AdapterManual", targets: ["AdapterManual"]),
    .library(name: "ActionOllama", targets: ["ActionOllama"]),
    .library(name: "ActionHuggingFace", targets: ["ActionHuggingFace"]),
    .library(name: "ActionManual", targets: ["ActionManual"]),
  ],
  targets: [
    .target(
      name: "AdapterGPT4All", dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]),
    .target(name: "AdapterJan", dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]),
    .target(
      name: "RuntimeLocalAI", dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMRuntime"]),
    .target(
      name: "ClientOpenWebUI", dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMRuntime"]),

    .target(name: "WTMDomain"),
    .target(name: "WTMAdapterContracts", dependencies: ["WTMDomain"]),
    .target(name: "WTMSecurity", dependencies: ["WTMDomain"]),
    .target(
      name: "WTMActions",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "WTMRuntime",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"],
      linkerSettings: [.linkedFramework("Security")]
    ),
    .target(
      name: "RuntimeOllama",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMRuntime"]
    ),
    .target(
      name: "RuntimeLlamaCpp",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMRuntime", "WTMSecurity"]
    ),
    .target(
      name: "ClientOpenClaw",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMRuntime"]
    ),
    .target(
      name: "ClientUnsloth",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMRuntime", "WTMSecurity"]
    ),
    .target(name: "WTMPersistence", dependencies: ["WTMDomain", "WTMActions"]),
    .target(
      name: "WTMInventory",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "AdapterOllama",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "AdapterHuggingFace",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "AdapterMLX",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "AdapterLMStudio",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "AdapterManual",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "ActionOllama",
      dependencies: ["WTMDomain", "WTMAdapterContracts"]
    ),
    .target(
      name: "ActionHuggingFace",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .target(
      name: "ActionManual",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMSecurity"]
    ),
    .testTarget(name: "WTMDomainTests", dependencies: ["WTMDomain"]),
    .testTarget(
      name: "WTMAdapterContractsTests",
      dependencies: ["WTMDomain", "WTMAdapterContracts"]
    ),
    .testTarget(
      name: "WTMInventoryTests",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMInventory", "WTMSecurity"]
    ),
    .testTarget(
      name: "WTMAdapterTests",
      dependencies: [
        "WTMDomain",
        "WTMAdapterContracts",
        "AdapterOllama",
        "AdapterHuggingFace",
        "AdapterMLX",
        "AdapterLMStudio", "AdapterGPT4All", "AdapterJan",
        "AdapterManual",
        "WTMInventory",
      ],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "WTMActionsTests",
      dependencies: [
        "WTMDomain", "WTMAdapterContracts", "WTMSecurity", "WTMActions",
      ]
    ),
    .testTarget(
      name: "WTMRuntimeTests",
      dependencies: ["WTMDomain", "WTMAdapterContracts", "WTMRuntime"]
    ),
    .testTarget(
      name: "WTMRuntimeAdapterTests",
      dependencies: [
        "WTMDomain", "WTMAdapterContracts", "WTMRuntime", "RuntimeOllama",
        "RuntimeLlamaCpp", "RuntimeLocalAI",
      ]
    ),
    .testTarget(
      name: "WTMClientAdapterTests",
      dependencies: [
        "WTMDomain", "WTMAdapterContracts", "WTMRuntime", "ClientOpenClaw",
        "ClientUnsloth", "ClientOpenWebUI",
      ]
    ),
    .testTarget(
      name: "WTMActionAdapterTests",
      dependencies: [
        "WTMDomain", "WTMAdapterContracts", "WTMSecurity", "WTMActions",
        "ActionOllama", "ActionHuggingFace", "ActionManual", "AdapterOllama",
      ]
    ),
    .testTarget(
      name: "WTMPersistenceTests",
      dependencies: ["WTMDomain", "WTMActions", "WTMPersistence", "WTMRuntime"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
