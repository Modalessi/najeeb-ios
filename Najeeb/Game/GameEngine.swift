import Foundation

public enum GameOperation: Codable, Equatable, Sendable {
    case listCategories
    case getCategorySuggestions(interests: String)
    case addCategory(categoryID: String)
    case removeCategory(categoryID: String)
    case getSelectedCategories
    case createTeam(name: String)
    case renameTeam(teamID: String, name: String)
    case listHelpers
    case getGameSummary
    case confirmGameSetup(expectedRevision: Int)
    case startGame
    case getNextQuestion(expectedRevision: Int)
    case submitAnswer(answer: String, isCorrect: Bool, questionID: String, turnToken: String)
    case surrender(questionID: String, turnToken: String)
    case repeatQuestion
    case useHelper(helperID: HelperID, questionID: String, turnToken: String, content: HelperContent? = nil)
    case getScoreboard
    case pauseGame
    case resumeGame
    case endGame

    var isReadOnly: Bool {
        switch self {
        case .listCategories, .getCategorySuggestions, .getSelectedCategories,
             .listHelpers, .getGameSummary, .repeatQuestion, .getScoreboard:
            true
        default:
            false
        }
    }
}

public enum GameEngineError: Error, Equatable, Sendable {
    case invalidCatalog, invalidQuestionBank, cannotReplaceContentDuringGame
}

private struct ActiveQuestion: Codable, Equatable, Sendable {
    let queueIndex: Int
    var turnToken: String
    var teamID: String
    var helperIDs: [HelperID] = []
    var content: [HelperID: HelperContent]?
}

private struct CachedResult: Codable, Sendable {
    let operation: GameOperation
    let result: ToolResult
}

/// Every game mutation is serialized by the app and applied to this value.
/// Persist the entire engine after a mutation to retain request deduplication after reconnects.
public struct GameEngine: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case catalog, selectedCategoryIDs, teams, questionBank, queue
        case phase, revision, setupConfirmed, activeQuestion, history, cachedResults
    }
    private var catalog: [GameCategory]
    private var selectedCategoryIDs: [String] = []
    private var teams: [GameTeam] = []
    private var questionBank: [TriviaQuestion] = []
    private var queue: [TriviaQuestion] = []
    private var phase: GamePhase = .setup
    private var revision: Int = 0
    private var setupConfirmed = false
    private var activeQuestion: ActiveQuestion?
    private var history: [QuestionOutcome] = []
    private var cachedResults: [String: CachedResult] = [:]

    public init(categories: [GameCategory] = []) {
        self.catalog = categories
    }

    public var snapshot: AgentGameState {
        AgentGameState(
            phase: phase,
            revision: revision,
            requiresRestartForMediaFreeContent: requiresRestartForMediaFreeContent,
            selectedCategories: selectedCategories,
            categoriesRemaining: max(0, 6 - selectedCategoryIDs.count),
            teams: teams,
            availableHelpers: availableHelpers,
            currentQuestion: presentedQuestion,
            currentTeamID: currentTeamID,
            completedQuestions: history.count,
            totalQuestions: 18,
            configurationConfirmed: setupConfirmed,
            winner: winner,
            lastAnswer: history.last
        )
    }

    public var questionHistory: [QuestionOutcome] { history }

    public var requiresRestartForMediaFreeContent: Bool {
        !(questionBank + queue).allSatisfy(\.isCompatibleWithVoiceGame)
    }

    public func cachedResult(for requestID: String) -> ToolResult? {
        cachedResults[requestID]?.result
    }

    public mutating func replaceCatalog(_ categories: [GameCategory]) throws {
        guard phase == .setup || phase == .confirmed else {
            throw GameEngineError.cannotReplaceContentDuringGame
        }
        guard Set(categories.map(\.id)).count == categories.count,
              categories.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              selectedCategoryIDs.allSatisfy({ id in categories.contains { $0.id == id } }) else {
            throw GameEngineError.invalidCatalog
        }
        if catalog != categories {
            catalog = categories
            invalidateSetup()
        }
    }

    public mutating func installQuestions(_ questions: [TriviaQuestion]) throws {
        guard phase == .setup || phase == .confirmed else {
            throw GameEngineError.cannotReplaceContentDuringGame
        }
        guard Set(questions.map(\.id)).count == questions.count,
              questions.allSatisfy({
                  !$0.id.isEmpty && !$0.categoryID.isEmpty &&
                  !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !AnswerNormalizer.normalize($0.correctAnswer).isEmpty &&
                  $0.isCompatibleWithVoiceGame
              }) else {
            throw GameEngineError.invalidQuestionBank
        }
        if questionBank != questions {
            questionBank = questions
            revision += 1

        }
    }

    public mutating func perform(_ operation: GameOperation, requestID: String, voiceAuthorized: Bool = false) -> ToolResult {
        if !operation.isReadOnly {
            guard !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  requestID.count <= 200 else {
                return failure("INVALID_REQUEST_ID", "نحتاج رقم طلب صحيح عشان نحفظ نتيجة الحركة.")
            }
            if let cached = cachedResults[requestID] {
                guard cached.operation == operation else {
                    return failure("DUPLICATE_REQUEST_CONFLICT", "رقم الطلب هذا سبق استُخدم لحركة ثانية.")
                }
                return cached.result
            }
        }
        let result = apply(operation, voiceAuthorized: voiceAuthorized)
        if !operation.isReadOnly {
            cachedResults[requestID] = CachedResult(operation: operation, result: result)
        }
        return result
    }

    private var selectedCategories: [GameCategory] {
        selectedCategoryIDs.compactMap { id in catalog.first { $0.id == id } }
    }

    private var availableHelpers: [HelperDefinition] {
        [
            HelperDefinition(id: .choices, name: "خيارات", rules: "أربعة خيارات فيها الإجابة الصحيحة. مرة لكل فريق.", usesPerTeam: 1),
            HelperDefinition(id: .hint, name: "تلميح", rules: "تلميح يساعدكم بدون كشف الإجابة. مرة لكل فريق.", usesPerTeam: 1),
            HelperDefinition(id: .bomb, name: "القنبلة", rules: "تنقل السؤال للفريق الآخر؛ الصحيح يكسب نقاط السؤال والخطأ أو الاستسلام يخصمها. مرة لكل فريق، وقنبلة واحدة للسؤال.", usesPerTeam: 1)
        ]
    }

    private var currentTeamID: String? {
        guard teams.count == 2, phase == .playing || phase == .paused else { return nil }
        return activeQuestion?.teamID ?? teams[history.count % 2].id
    }

    private var presentedQuestion: PresentedQuestion? {
        guard !requiresRestartForMediaFreeContent else { return nil }
        guard let active = activeQuestion, queue.indices.contains(active.queueIndex) else { return nil }
        let question = queue[active.queueIndex]
        return PresentedQuestion(
            id: question.id,
            categoryID: question.categoryID,
            categoryName: catalog.first { $0.id == question.categoryID }?.name ?? "",
            difficulty: question.difficulty,
            points: question.difficulty.points,
            text: question.text,
            turnToken: active.turnToken,
            teamID: active.teamID,
            activeHelperIDs: active.helperIDs,
            referenceAnswer: question.correctAnswer,
            hint: { if case .hint(let text) = active.content?[.hint] { return text }; return nil }(),
            choices: { if case .choices(let items) = active.content?[.choices] { return items }; return nil }()
        )
    }

    private var winner: GameWinner? {
        guard phase == .finished, history.count == queue.count, queue.count == 18, teams.count == 2 else { return nil }
        if teams[0].score == teams[1].score {
            return GameWinner(teamID: nil, teamName: nil, isTie: true)
        }
        let team = teams[0].score > teams[1].score ? teams[0] : teams[1]
        return GameWinner(teamID: team.id, teamName: team.name, isTie: false)
    }

    private mutating func apply(_ operation: GameOperation, voiceAuthorized: Bool) -> ToolResult {
        if requiresRestartForMediaFreeContent {
            switch operation {
            case .startGame, .getNextQuestion, .submitAnswer, .surrender, .repeatQuestion,
                 .useHelper, .resumeGame:
                return failure("LEGACY_CONTENT_REQUIRES_RESTART", "اللعبة المحفوظة تحتوي محتوى من النسخة السابقة. الأسماء والنتيجة محفوظة؛ ابدأ لعبة جديدة بأسئلة صوتية بدون وسائط.")
            default: break
            }
        }
        switch operation {
        case .listCategories:
            return success("CATEGORIES", "هذه الفئات الموجودة فعلاً.", data: .encoding(catalog))
        case .getCategorySuggestions(let interests):
            let search = AnswerNormalizer.normalize(interests)
            let unselected = catalog.filter { !selectedCategoryIDs.contains($0.id) }
            let tokens = search.split(separator: " ").map(String.init)
            let matches = unselected.filter { category in
                let haystack = AnswerNormalizer.normalize(
                    ([category.name, category.description ?? ""] + category.interests).joined(separator: " ")
                )
                return !tokens.isEmpty && tokens.contains { haystack.contains($0) }
            }
            let suggestions = Array((matches.isEmpty ? unselected : matches).prefix(3))
            return success("SUGGESTIONS", "اقتراحات من الفئات المتاحة.", data: .encoding(suggestions))
        case .getSelectedCategories:
            return success("SELECTED_CATEGORIES", "هذه الفئات المختارة.", data: .encoding(selectedCategories))
        case .getGameSummary:
            return success("GAME_SUMMARY", "هذه حالة المسابقة الحالية.")
        case .listHelpers:
            return success("HELPERS", "هذه مساعدات نسخة الصوت وقواعدها.", data: .encoding(availableHelpers))
        case .getScoreboard:
            return success("SCOREBOARD", "هذه النتيجة الحالية.", data: .encoding(teams))
        case .addCategory(let id):
            guard isEditingSetup else { return invalidPhase() }
            guard catalog.contains(where: { $0.id == id }) else { return failure("CATEGORY_NOT_FOUND", "الفئة هذه مو موجودة بالقائمة.") }
            guard !selectedCategoryIDs.contains(id) else { return failure("CATEGORY_ALREADY_SELECTED", "الفئة مختارة من قبل.") }
            guard selectedCategoryIDs.count < 6 else { return failure("CATEGORY_LIMIT", "عندنا ست فئات؛ احذف واحدة قبل الإضافة.") }
            selectedCategoryIDs.append(id)
            invalidateSetup()
            return success("CATEGORY_ADDED", "انضافت الفئة.")
        case .removeCategory(let id):
            guard isEditingSetup else { return invalidPhase() }
            guard selectedCategoryIDs.contains(id) else { return failure("CATEGORY_NOT_SELECTED", "الفئة هذه مو ضمن اختياراتنا.") }
            selectedCategoryIDs.removeAll { $0 == id }
            invalidateSetup()
            return success("CATEGORY_REMOVED", "انحذفت الفئة.")
        case .createTeam(let name):
            guard isEditingSetup else { return invalidPhase() }
            guard selectedCategoryIDs.count == 6 else { return failure("SIX_CATEGORIES_REQUIRED", "نحتاج نختار ست فئات أول.") }
            guard teams.count < 2 else { return failure("TEAM_LIMIT", "الفريقان موجودان؛ تقدر تغير الاسم.") }
            guard validTeamName(name) else { return failure("INVALID_TEAM_NAME", "عطنا اسم واضح ومختلف للفريق.") }
            let team = GameTeam(id: "team\(teams.count + 1)", name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            teams.append(team)
            invalidateSetup()
            return success("TEAM_CREATED", "تسجل اسم الفريق.", data: .encoding(team))
        case .renameTeam(let teamID, let name):
            guard isEditingSetup else { return invalidPhase() }
            guard let index = teams.firstIndex(where: { $0.id == teamID }) else { return failure("TEAM_NOT_FOUND", "الفريق هذا مو موجود.") }
            guard validTeamName(name, excluding: teamID) else { return failure("INVALID_TEAM_NAME", "عطنا اسم واضح ومختلف للفريق.") }
            teams[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            invalidateSetup()
            return success("TEAM_RENAMED", "تغير اسم الفريق.")
        case .confirmGameSetup(let expectedRevision):
            guard isEditingSetup else { return invalidPhase() }
            guard revision == expectedRevision else { return staleRevision() }
            guard selectedCategoryIDs.count == 6 else { return failure("SIX_CATEGORIES_REQUIRED", "نحتاج ست فئات مختلفة قبل البداية.") }
            guard teams.count == 2 else { return failure("TWO_TEAMS_REQUIRED", "نحتاج اسمين للفريقين.") }
            setupConfirmed = true
            phase = .confirmed
            revision += 1
            return success("SETUP_CONFIRMED", "تأكدت إعدادات المسابقة.")
        case .startGame:
            guard phase == .confirmed, setupConfirmed else { return failure("SETUP_CONFIRMATION_REQUIRED", "نراجع الإعدادات ونتأكد منها أول.") }
            guard let validatedQueue = makeQueue() else { return failure("QUESTION_CONTENT_UNAVAILABLE", "ما توفرت أسئلة صوتية موثوقة لكل الفئات والمستويات. لازم نجهز المحتوى أول.") }
            queue = validatedQueue
            phase = .playing
            revision += 1
            return success("GAME_STARTED", "بدأت المسابقة؛ الدور للفريق الأول.")
        case .getNextQuestion(let expectedRevision):
            guard phase == .playing else { return invalidPhase() }
            guard revision == expectedRevision else { return staleRevision() }
            if presentedQuestion != nil { return success("CURRENT_QUESTION", "هذا السؤال الحالي؛ ما تغيّر الدور.", data: .encoding(presentedQuestion)) }
            guard queue.indices.contains(history.count), teams.count == 2 else { return failure("NO_QUESTION_AVAILABLE", "ما فيه سؤال جديد متاح.") }
            openNextQuestion()
            revision += 1
            return success("QUESTION_READY", "السؤال جاهز للفريق اللي عليه الدور.", data: .encoding(presentedQuestion))
        case .repeatQuestion:
            guard phase == .playing || phase == .paused, presentedQuestion != nil else { return failure("NO_CURRENT_QUESTION", "ما عندنا سؤال حالي نعيده.") }
            return success("QUESTION_REPEATED", "هذا نفس السؤال بدون تغيير الدور.", data: .encoding(presentedQuestion))
        case .submitAnswer(let answer, let isCorrect, let questionID, let turnToken):
            if let issue = validateActiveQuestion(questionID: questionID, turnToken: turnToken) { return issue }
            guard voiceAuthorized || VoiceRequest.isDirected(answer) else { return failure("IGNORED_INPUT", "") }
            guard !VoiceRequest.answerText(answer).isEmpty, answer.count <= 500 else {
                return failure("ANSWER_NEEDS_CLARIFICATION", "وش إجابتكم النهائية؟")
            }
            return finishQuestion(answer: answer, correct: isCorrect, surrendered: false)
        case .surrender(let questionID, let turnToken):
            if let issue = validateActiveQuestion(questionID: questionID, turnToken: turnToken) { return issue }
            return finishQuestion(answer: nil, correct: false, surrendered: true)
        case .useHelper(let helperID, let questionID, let turnToken, let content):
            if let issue = validateHelperRequest(helperID: helperID, questionID: questionID, turnToken: turnToken) { return issue }
            guard let active = activeQuestion, let teamIndex = teams.firstIndex(where: { $0.id == active.teamID }) else { return invalidPhase() }
            let question = queue[active.queueIndex]
            switch (helperID, content) {
            case (.hint, .hint(let text)):
                let normalized = AnswerNormalizer.normalize(text)
                guard !normalized.isEmpty, !normalized.contains(AnswerNormalizer.normalize(question.correctAnswer)) else {
                    return failure("HELPER_CONTENT_INVALID", "ما توفّر تلميح مناسب. ما استخدمنا المساعدة.")
                }
            case (.choices, .choices(let items)):
                let normalized = items.map(AnswerNormalizer.normalize)
                guard items.count == 4, Set(normalized).count == 4, !normalized.contains(""), normalized.contains(AnswerNormalizer.normalize(question.correctAnswer)) else {
                    return failure("HELPER_CONTENT_INVALID", "ما توفرت خيارات مناسبة. ما استخدمنا المساعدة.")
                }
            case (.bomb, nil): break
            default: return failure("HELPER_CONTENT_REQUIRED", "نحتاج نجهز المساعدة أول.")
            }
            teams[teamIndex].usedHelperIDs.append(helperID)
            activeQuestion?.helperIDs.append(helperID)
            if let content {
                if activeQuestion?.content == nil { activeQuestion?.content = [:] }
                activeQuestion?.content?[helperID] = content
            }
            if helperID == .bomb {
                activeQuestion?.teamID = teams[1 - teamIndex].id
                activeQuestion?.turnToken += "-bomb"
            }
            revision += 1
            return success("HELPER_USED", "المساعدة جاهزة.", data: .encoding(presentedQuestion))
        case .pauseGame:
            guard phase == .playing else { return invalidPhase() }
            phase = .paused
            revision += 1
            return success("GAME_PAUSED", "وقفت المسابقة؛ السؤال والنتيجة محفوظة.")
        case .resumeGame:
            guard phase == .paused else { return invalidPhase() }
            phase = .playing
            revision += 1
            return success("GAME_RESUMED", "كملنا من نفس المكان.")
        case .endGame:
            guard phase != .finished, phase != .ended else { return invalidPhase() }
            phase = .ended
            activeQuestion = nil
            revision += 1
            return success("GAME_ENDED", "انتهت الجلسة قبل إكمال المسابقة؛ ما أعلنّا فائز.")

        }
    }

    private var isEditingSetup: Bool { phase == .setup || phase == .confirmed }

    private mutating func invalidateSetup() {
        setupConfirmed = false
        phase = .setup
        revision += 1
    }

    private func validTeamName(_ name: String, excluding id: String? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = AnswerNormalizer.normalize(name)
        return !normalized.isEmpty && trimmed.count <= 50 &&
            !teams.contains { $0.id != id && AnswerNormalizer.normalize($0.name) == normalized }
    }

    public func validateHelperRequest(helperID: HelperID, questionID: String, turnToken: String) -> ToolResult? {
        if let issue = validateActiveQuestion(questionID: questionID, turnToken: turnToken) { return issue }
        guard HelperID.allCases.contains(helperID) else { return failure("HELPER_UNAVAILABLE", "المساعدة غير متوفرة.") }
        guard let active = activeQuestion, let team = teams.first(where: { $0.id == active.teamID }) else { return invalidPhase() }
        guard !team.usedHelperIDs.contains(helperID) else { return failure("HELPER_ALREADY_USED", "استخدمتوا المساعدة من قبل.") }
        if helperID == .bomb && active.helperIDs.contains(.bomb) { return failure("BOMB_ALREADY_ACTIVE", "القنبلة مفعّلة لهذا السؤال.") }
        return nil
    }

    private func makeQueue() -> [TriviaQuestion]? {
        guard selectedCategoryIDs.count == 6, teams.count == 2 else { return nil }
        var result: [TriviaQuestion] = []
        for difficulty in Difficulty.allCases {
            for categoryID in selectedCategoryIDs {
                let candidates = questionBank.filter { question in
                    guard question.categoryID == categoryID, question.difficulty == difficulty else { return false }
                    return question.isCompatibleWithVoiceGame
                }.sorted { $0.id < $1.id }
                guard let candidate = candidates.first else { return nil }
                result.append(candidate)
            }
        }
        guard Set(result.map(\.id)).count == 18 else { return nil }
        return result
    }

    private func validateActiveQuestion(questionID: String, turnToken: String) -> ToolResult? {
        guard phase == .playing else { return invalidPhase() }
        guard let active = activeQuestion, queue.indices.contains(active.queueIndex) else {
            return failure("NO_CURRENT_QUESTION", "ما فيه سؤال مفتوح الآن.")
        }
        guard queue[active.queueIndex].id == questionID, active.turnToken == turnToken else {
            return failure("STALE_QUESTION", "الطلب يخص سؤال قديم؛ نستخدم السؤال والدور الحاليين.")
        }
        return nil
    }

    private mutating func openNextQuestion() {
        let question = queue[history.count]
        activeQuestion = ActiveQuestion(
            queueIndex: history.count,
            turnToken: "turn-\(history.count + 1)-\(question.id)",
            teamID: teams[history.count % 2].id
        )
    }

    private mutating func finishQuestion(answer: String?, correct: Bool, surrendered: Bool) -> ToolResult {
        guard let active = activeQuestion, let index = teams.firstIndex(where: { $0.id == active.teamID }) else { return invalidPhase() }
        let question = queue[active.queueIndex]
        let points = correct ? question.difficulty.points : (active.helperIDs.contains(.bomb) ? -question.difficulty.points : 0)
        teams[index].score += points
        let outcome = QuestionOutcome(
            questionID: question.id, turnToken: active.turnToken, teamID: active.teamID,
            submittedAnswer: answer, correctAnswer: question.correctAnswer,
            isCorrect: correct, surrendered: surrendered, awardedPoints: points
        )
        history.append(outcome)
        activeQuestion = nil
        if history.count == queue.count { phase = .finished }
        else { openNextQuestion() }
        revision += 1
        return success(correct ? "ANSWER_CORRECT" : (surrendered ? "ANSWER_SURRENDERED" : "ANSWER_INCORRECT"),
                       correct ? "الإجابة صحيحة وانضافت النقاط." : (points < 0 ? "إجابة خاطئة؛ انخصمت نقاط القنبلة." : "ما انضافت نقاط لهذا السؤال."), data: .encoding(outcome))
    }

    private func success(_ code: String, _ message: String, data: GameJSONValue = .null) -> ToolResult {
        ToolResult(success: true, code: code, message: message, state: snapshot, data: data)
    }

    private func failure(_ code: String, _ message: String) -> ToolResult {
        ToolResult(success: false, code: code, message: message, state: snapshot)
    }

    private func invalidPhase() -> ToolResult { failure("INVALID_GAME_STATE", "الحركة هذه ما تصلح في مرحلة المسابقة الحالية.") }
    private func staleRevision() -> ToolResult { failure("STALE_REVISION", "تغيرت حالة المسابقة؛ راجع ملخصها قبل تنفيذ الطلب.") }
}

extension GameEngine {
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        catalog = try values.decode([GameCategory].self, forKey: .catalog)
        selectedCategoryIDs = try values.decode([String].self, forKey: .selectedCategoryIDs)
        teams = try values.decode([GameTeam].self, forKey: .teams)
        questionBank = try values.decode([TriviaQuestion].self, forKey: .questionBank)
        queue = try values.decode([TriviaQuestion].self, forKey: .queue)
        phase = try values.decode(GamePhase.self, forKey: .phase)
        revision = try values.decode(Int.self, forKey: .revision)
        setupConfirmed = try values.decode(Bool.self, forKey: .setupConfirmed)
        activeQuestion = try values.decodeIfPresent(ActiveQuestion.self, forKey: .activeQuestion)
        history = try values.decode([QuestionOutcome].self, forKey: .history)
        // Old operation schemas cannot replay; transport results remain in SessionArchive.
        cachedResults = (try? values.decode([String: CachedResult].self, forKey: .cachedResults)) ?? [:]
        if requiresRestartForMediaFreeContent, phase == .playing {
            phase = .paused
            revision += 1
        }
    }
}
