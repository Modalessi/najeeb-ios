// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NajeebLogic",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(
            name: "NajeebLogic",
            path: "Najeeb",
            exclude: [
                "NajeebApp.swift", "Info.plist", "Game/GameSession.swift",
                "CarPlay", "Storage", "Views", "Voice/AgentConfiguration",
                "Voice/GameSounds.swift", "Voice/Sounds", "Voice/VoiceAudioSession.swift",
                "Voice/VoiceStatus.swift"
            ],
            sources: ["Game/GameEngine.swift", "Game/Models.swift", "Game/ToolRouter.swift",
                      "API", "Voice/VoiceInput.swift"]
        ),
        .testTarget(name: "NajeebTests", dependencies: ["NajeebLogic"], path: "Tests")
    ]
)
