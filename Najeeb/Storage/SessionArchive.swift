import Foundation

struct SessionArchive: Codable {
    let version: Int
    var gameID: String
    var engine: GameEngine
    var toolResults: [String: ToolResult]
    var toolSignatures: [String: ToolSignature]
    var contentPreparation: [String: ContentPreparation]

    init(engine: GameEngine = GameEngine()) {
        version = 1
        gameID = UUID().uuidString
        self.engine = engine
        toolResults = [:]
        toolSignatures = [:]
        contentPreparation = [:]
    }
}

enum ContentPreparation: Codable {
    case requested
    case ready([TriviaQuestion])
    case failed(String)
}

struct ToolSignature: Codable, Equatable {
    let name: String
    let arguments: [String: GameJSONValue]
}

struct SessionPersistence {
    let url: URL

    init() throws {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Najeeb", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var backupExcludedDirectory = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try backupExcludedDirectory.setResourceValues(resourceValues)
        url = directory.appendingPathComponent("session.json")
    }

    func load() throws -> SessionArchive? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let archive = try JSONDecoder().decode(SessionArchive.self, from: Data(contentsOf: url))
        guard archive.version == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return archive
    }

    func save(_ archive: SessionArchive) throws {
        let data = try JSONEncoder().encode(archive)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
