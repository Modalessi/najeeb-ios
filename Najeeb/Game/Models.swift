import Foundation

public struct GameCategory: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let interests: [String]
    public let description: String?

    public init(id: String, name: String, interests: [String] = [], description: String? = nil) {
        self.id = id
        self.name = name
        self.interests = interests
        self.description = description
    }
}

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard

    public var points: Int {
        switch self {
        case .easy: 100
        case .medium: 300
        case .hard: 500
        }
    }

    public var arabicName: String {
        switch self {
        case .easy: "سهل"
        case .medium: "متوسط"
        case .hard: "صعب"
        }
    }
}

/// Retained only to decode saved data. New game content rejects every media case.
public enum QuestionMedia: Codable, Equatable, Sendable {
    case audio(url: URL)
    case image(url: URL)
    case images(urls: [URL])
}

public struct TriviaQuestion: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let categoryID: String
    public let difficulty: Difficulty
    public let text: String
    public let correctAnswer: String
    public let media: QuestionMedia?
    public let isAudioCompatible: Bool
    public let sourceDifficultyPoints: Int?

    public var isCompatibleWithVoiceGame: Bool {
        media == nil && isAudioCompatible && sourceDifficultyPoints == difficulty.points
    }

    public init(
        id: String, categoryID: String, difficulty: Difficulty, text: String,
        correctAnswer: String,
        media: QuestionMedia? = nil, isAudioCompatible: Bool = true, sourceDifficultyPoints: Int? = nil
    ) {
        self.id = id
        self.categoryID = categoryID
        self.difficulty = difficulty
        self.text = text
        self.correctAnswer = correctAnswer
        self.media = media
        self.isAudioCompatible = isAudioCompatible
        self.sourceDifficultyPoints = sourceDifficultyPoints ?? difficulty.points
    }

    enum CodingKeys: String, CodingKey {
        case id, difficulty, text, media
        case categoryID = "category_id"
        case correctAnswer = "correct_answer"
        case isAudioCompatible = "is_audio_compatible"
        case sourceDifficultyPoints = "source_difficulty_points"
        case legacySourceDifficulty = "source_difficulty"
        case legacyPoints = "points"
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(categoryID, forKey: .categoryID)
        try values.encode(difficulty, forKey: .difficulty)
        try values.encode(text, forKey: .text)
        try values.encode(correctAnswer, forKey: .correctAnswer)
        try values.encodeIfPresent(media, forKey: .media)
        try values.encode(isAudioCompatible, forKey: .isAudioCompatible)
        try values.encodeIfPresent(sourceDifficultyPoints, forKey: .sourceDifficultyPoints)
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        categoryID = try values.decode(String.self, forKey: .categoryID)
        var numericDifficulty: Int?
        if let level = try? values.decode(Difficulty.self, forKey: .difficulty) { difficulty = level }
        else {
            let raw = try values.decode(Int.self, forKey: .difficulty)
            numericDifficulty = raw
            switch raw {
            case 100, 200: difficulty = .easy
            case 300, 400: difficulty = .medium
            case 500, 600: difficulty = .hard
            default: throw DecodingError.dataCorruptedError(forKey: .difficulty, in: values, debugDescription: "Unsupported saved difficulty")
            }
        }
        text = try values.decode(String.self, forKey: .text)
        correctAnswer = try values.decode(String.self, forKey: .correctAnswer)
        media = try values.decodeIfPresent(QuestionMedia.self, forKey: .media)
        isAudioCompatible = try values.decodeIfPresent(Bool.self, forKey: .isAudioCompatible) ?? (media == nil)
        sourceDifficultyPoints = try values.decodeIfPresent(Int.self, forKey: .sourceDifficultyPoints)
            ?? values.decodeIfPresent(Int.self, forKey: .legacySourceDifficulty)
            ?? values.decodeIfPresent(Int.self, forKey: .legacyPoints) ?? numericDifficulty
    }
}

public enum GamePhase: String, Codable, Sendable {
    case setup, confirmed, playing, paused, finished, ended
}

public enum HelperID: String, Codable, Sendable, CaseIterable {
    case choices, hint, bomb
    case double // Decode existing archives only; no longer available.

    public static let allCases: [HelperID] = [.choices, .hint, .bomb]
}

public enum HelperContent: Codable, Equatable, Sendable {
    case hint(String)
    case choices([String])
}

public struct HelperDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: HelperID
    public let name: String
    public let rules: String
    public let usesPerTeam: Int

    enum CodingKeys: String, CodingKey {
        case id, name, rules
        case usesPerTeam = "uses_per_team"
    }
}

public struct GameTeam: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public internal(set) var name: String
    public internal(set) var score: Int = 0
    public internal(set) var helperIDs: [HelperID] = HelperID.allCases
    public internal(set) var usedHelperIDs: [HelperID] = []

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case id, name, score
        case helperIDs = "helper_ids"
        case usedHelperIDs = "used_helper_ids"
    }
}

extension GameTeam {
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(String.self, forKey: .id), name: try values.decode(String.self, forKey: .name))
        score = try values.decodeIfPresent(Int.self, forKey: .score) ?? 0
        usedHelperIDs = (try values.decodeIfPresent([HelperID].self, forKey: .usedHelperIDs) ?? []).filter(HelperID.allCases.contains)
    }
}

public struct PresentedQuestion: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let categoryID: String
    public let categoryName: String
    public let difficulty: Difficulty
    public let points: Int
    public let text: String
    public let turnToken: String
    public let teamID: String
    public let activeHelperIDs: [HelperID]
    public let referenceAnswer: String?
    public let hint: String?
    public let choices: [String]?

    enum CodingKeys: String, CodingKey {
        case id, difficulty, points, text
        case categoryID = "category_id"
        case categoryName = "category_name"
        case turnToken = "turn_token"
        case teamID = "team_id"
        case activeHelperIDs = "active_helper_ids"
        case referenceAnswer = "reference_answer"
        case hint, choices
    }
}

public struct QuestionOutcome: Codable, Equatable, Sendable {
    public let questionID: String
    public let turnToken: String
    public let teamID: String
    public let submittedAnswer: String?
    public let correctAnswer: String
    public let isCorrect: Bool
    public let surrendered: Bool
    public let awardedPoints: Int

    enum CodingKeys: String, CodingKey {
        case surrendered
        case questionID = "question_id"
        case turnToken = "turn_token"
        case teamID = "team_id"
        case submittedAnswer = "submitted_answer"
        case correctAnswer = "correct_answer"
        case isCorrect = "is_correct"
        case awardedPoints = "awarded_points"
    }
}

public struct GameWinner: Codable, Equatable, Sendable {
    public let teamID: String?
    public let teamName: String?
    public let isTie: Bool

    enum CodingKeys: String, CodingKey {
        case teamID = "team_id"
        case teamName = "team_name"
        case isTie = "is_tie"
    }
}

public struct AgentGameState: Codable, Equatable, Sendable {
    public let phase: GamePhase
    public let revision: Int
    public let requiresRestartForMediaFreeContent: Bool
    public let selectedCategories: [GameCategory]
    public let categoriesRemaining: Int
    public let teams: [GameTeam]
    public let availableHelpers: [HelperDefinition]
    public let currentQuestion: PresentedQuestion?
    public let currentTeamID: String?
    public let completedQuestions: Int
    public let totalQuestions: Int
    public let configurationConfirmed: Bool
    public let winner: GameWinner?
    public let lastAnswer: QuestionOutcome?

    enum CodingKeys: String, CodingKey {
        case phase, revision, teams, winner
        case requiresRestartForMediaFreeContent = "requires_restart_for_media_free_content"
        case selectedCategories = "selected_categories"
        case categoriesRemaining = "categories_remaining"
        case availableHelpers = "available_helpers"
        case currentQuestion = "current_question"
        case currentTeamID = "current_team_id"
        case completedQuestions = "completed_questions"
        case totalQuestions = "total_questions"
        case configurationConfirmed = "configuration_confirmed"
        case lastAnswer = "last_answer"
    }
}

extension AgentGameState {
    // Decode older cached tool replies without requiring newer state fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(GamePhase.self, forKey: .phase)
        revision = try container.decode(Int.self, forKey: .revision)
        requiresRestartForMediaFreeContent = try container.decodeIfPresent(Bool.self, forKey: .requiresRestartForMediaFreeContent) ?? false
        selectedCategories = try container.decode([GameCategory].self, forKey: .selectedCategories)
        categoriesRemaining = try container.decode(Int.self, forKey: .categoriesRemaining)
        teams = try container.decode([GameTeam].self, forKey: .teams)
        availableHelpers = try container.decode([HelperDefinition].self, forKey: .availableHelpers)
        currentQuestion = try container.decodeIfPresent(PresentedQuestion.self, forKey: .currentQuestion)
        currentTeamID = try container.decodeIfPresent(String.self, forKey: .currentTeamID)
        completedQuestions = try container.decode(Int.self, forKey: .completedQuestions)
        totalQuestions = try container.decode(Int.self, forKey: .totalQuestions)
        configurationConfirmed = try container.decode(Bool.self, forKey: .configurationConfirmed)
        winner = try container.decodeIfPresent(GameWinner.self, forKey: .winner)
        lastAnswer = try container.decodeIfPresent(QuestionOutcome.self, forKey: .lastAnswer)
    }
}

public enum GameJSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: GameJSONValue]), array([GameJSONValue]), null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([GameJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: GameJSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public static func encoding(_ value: some Encodable) -> GameJSONValue {
        do {
            return try JSONDecoder().decode(GameJSONValue.self, from: JSONEncoder().encode(value))
        } catch {
            return .null
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

public struct ToolResult: Codable, Equatable, Sendable {
    public let success: Bool
    public let code: String
    public let message: String
    public let state: AgentGameState
    public let data: GameJSONValue

    public init(success: Bool, code: String, message: String, state: AgentGameState, data: GameJSONValue = .null) {
        self.success = success
        self.code = code
        self.message = message
        self.state = state
        self.data = data
    }

    public func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let value = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "Invalid UTF-8"))
        }
        return value
    }
}
