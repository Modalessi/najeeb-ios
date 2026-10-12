import Foundation

public enum ToolRouter {
    public static let toolNames = [
        "listCategories", "getCategorySuggestions", "addCategory", "removeCategory",
        "getSelectedCategories", "createTeam", "renameTeam", "listHelpers",
        "getGameSummary",
        "confirmGameSetup", "startGame", "getNextQuestion", "submitAnswer",
        "surrender", "repeatQuestion", "useHelper", "getScoreboard", "pauseGame",
        "resumeGame", "endGame"
    ]

    /// Parse once before any network request or game mutation.
    public static func parse(
        name: String, arguments: [String: GameJSONValue], requestID: String,
        helperContent: HelperContent? = nil
    ) throws(ToolRoutingError) -> (operation: GameOperation, requestID: String) {
        let parameters = Parameters(arguments)
        let operation: GameOperation
        switch name {
        case "listCategories":
            try parameters.validate([])
            operation = .listCategories
        case "getCategorySuggestions":
            try parameters.validate(["interests"])
            operation = .getCategorySuggestions(interests: try parameters.string("interests", allowEmpty: true))
        case "addCategory":
            try parameters.validate(["category_id"])
            operation = .addCategory(categoryID: try parameters.string("category_id"))
        case "removeCategory":
            try parameters.validate(["category_id"])
            operation = .removeCategory(categoryID: try parameters.string("category_id"))
        case "getSelectedCategories":
            try parameters.validate([])
            operation = .getSelectedCategories
        case "createTeam":
            try parameters.validate(["name"])
            operation = .createTeam(name: try parameters.string("name"))
        case "renameTeam":
            try parameters.validate(["team_id", "name"])
            operation = .renameTeam(teamID: try parameters.string("team_id"), name: try parameters.string("name"))
        case "listHelpers":
            try parameters.validate([])
            operation = .listHelpers
        case "getGameSummary":
            try parameters.validate([])
            operation = .getGameSummary
        case "confirmGameSetup":
            try parameters.validate(["expected_revision"])
            operation = .confirmGameSetup(expectedRevision: try parameters.integer("expected_revision"))
        case "startGame":
            try parameters.validate([])
            operation = .startGame
        case "getNextQuestion":
            try parameters.validate(["expected_revision"])
            operation = .getNextQuestion(expectedRevision: try parameters.integer("expected_revision"))
        case "submitAnswer":
            try parameters.validate(["answer", "is_correct", "expected_question_id", "turn_token"])
            operation = .submitAnswer(
                answer: try parameters.string("answer"), isCorrect: try parameters.boolean("is_correct"),
                questionID: try parameters.string("expected_question_id"),
                turnToken: try parameters.string("turn_token")
            )
        case "surrender":
            try parameters.validate(["expected_question_id", "turn_token"])
            operation = .surrender(questionID: try parameters.string("expected_question_id"), turnToken: try parameters.string("turn_token"))
        case "repeatQuestion":
            try parameters.validate([])
            operation = .repeatQuestion
        case "useHelper":
            try parameters.validate(["helper_id", "expected_question_id", "turn_token"])
            operation = .useHelper(
                helperID: try parameters.helperID("helper_id"),
                questionID: try parameters.string("expected_question_id"),
                turnToken: try parameters.string("turn_token"), content: helperContent
            )
        case "getScoreboard":
            try parameters.validate([])
            operation = .getScoreboard
        case "pauseGame":
            try parameters.validate([])
            operation = .pauseGame
        case "resumeGame":
            try parameters.validate([])
            operation = .resumeGame
        case "endGame":
            try parameters.validate([])
            operation = .endGame
        default:
            throw ToolRoutingError.unknownTool
        }
        let effectiveRequestID = try parameters.optionalString("request_id") ?? requestID
        if !operation.isReadOnly {
            guard !effectiveRequestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  effectiveRequestID.count <= 200 else { throw ToolRoutingError.invalidRequestID }
        }
        return (operation, effectiveRequestID)
    }

    public static func dispatch(
        name: String, arguments: [String: GameJSONValue], requestID: String, engine: inout GameEngine,
        helperContent: HelperContent? = nil, voiceAuthorized: Bool = false
    ) -> ToolResult {
        do {
            let request = try parse(name: name, arguments: arguments, requestID: requestID, helperContent: helperContent)
            return engine.perform(request.operation, requestID: request.requestID, voiceAuthorized: voiceAuthorized)
        } catch {
            return ToolResult(success: false, code: error.code, message: error.message, state: engine.snapshot)
        }
    }
}

public enum ToolRoutingError: Error, Equatable, Sendable {
    case unknownTool, invalidArguments, invalidRequestID

    public var code: String {
        switch self {
        case .unknownTool: "UNKNOWN_TOOL"
        case .invalidArguments: "INVALID_ARGUMENTS"
        case .invalidRequestID: "INVALID_REQUEST_ID"
        }
    }
    public var message: String {
        switch self {
        case .unknownTool: "الحركة المطلوبة مو مدعومة."
        case .invalidArguments: "بيانات الطلب ناقصة أو غير صحيحة؛ راجع الحالة وحاول مرة ثانية."
        case .invalidRequestID: "نحتاج رقم طلب صحيح عشان نحفظ نتيجة الحركة."
        }
    }
}

private struct Parameters {
    let arguments: [String: GameJSONValue]

    init(_ arguments: [String: GameJSONValue]) { self.arguments = arguments }

    func validate(_ keys: Set<String>) throws(ToolRoutingError) {
        guard Set(arguments.keys).isSubset(of: keys.union(["request_id"])) else { throw ToolRoutingError.invalidArguments }
    }

    func string(_ key: String, allowEmpty: Bool = false) throws(ToolRoutingError) -> String {
        guard let value = arguments[key]?.stringValue, value.count <= 500,
              allowEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolRoutingError.invalidArguments
        }
        return value
    }

    func optionalString(_ key: String) throws(ToolRoutingError) -> String? {
        guard arguments[key] != nil else { return nil }
        return try string(key)
    }

    func integer(_ key: String) throws(ToolRoutingError) -> Int {
        guard case .number(let value) = arguments[key], value.isFinite,
              value >= 0, value < Double(Int.max), value.rounded() == value else { throw ToolRoutingError.invalidArguments }
        return Int(value)
    }

    func helperID(_ key: String) throws(ToolRoutingError) -> HelperID {
        guard let id = HelperID(rawValue: try string(key)) else { throw ToolRoutingError.invalidArguments }
        return id
    }

    func boolean(_ key: String) throws(ToolRoutingError) -> Bool {
        guard case .bool(let value) = arguments[key] else { throw ToolRoutingError.invalidArguments }
        return value
    }
}
