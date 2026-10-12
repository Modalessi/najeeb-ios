import Foundation
import Testing
@testable import NajeebLogic

struct GameEngineTests {
    @Test func testToolParsingPreservesRetryIDsAndValidatesBeforeExecution() throws {
        let request = try ToolRouter.parse(
            name: "useHelper",
            arguments: ["helper_id": .string("hint"), "expected_question_id": .string("q1"),
                        "turn_token": .string("turn-1"), "request_id": .string("retry-1")],
            requestID: "sdk-1"
        )
        #expect(request.operation == .useHelper(helperID: .hint, questionID: "q1", turnToken: "turn-1"))
        #expect(request.requestID == "retry-1")
        #expect(throws: ToolRoutingError.invalidArguments) {
            try ToolRouter.parse(name: "startGame", arguments: ["request_id": .number(1)], requestID: "sdk-2")
        }
        #expect(throws: ToolRoutingError.invalidArguments) {
            try ToolRouter.parse(name: "useHelper", arguments: ["helper_id": .string("hint")], requestID: "sdk-3")
        }
        #expect(throws: ToolRoutingError.unknownTool) {
            try ToolRouter.parse(name: "awardPoints", arguments: [:], requestID: "sdk-4")
        }
        #expect(throws: ToolRoutingError.invalidRequestID) {
            try ToolRouter.parse(name: "startGame", arguments: ["request_id": .string(String(repeating: "x", count: 201))], requestID: "sdk-5")
        }
    }

    @Test func testRetiredQuestionMetadataDoesNotPreventSavedGameRestore() throws {
        var engine = try playing()
        let question = try next(&engine)
        _ = answer(&engine, question: question)
        func addingRetiredFields(_ value: GameJSONValue) -> GameJSONValue {
            switch value {
            case .object(var fields):
                if fields["correct_answer"] != nil && fields["text"] != nil {
                    fields["acceptable_answers"] = .array([.string("Riyadh")])
                    fields["hint"] = .string("old static hint")
                }
                if fields["phase"] != nil { fields["presentation_mode"] = .string("audio_only") }
                if fields["catalog"] != nil { fields["storedPresentationMode"] = .string("audio_only") }
                return .object(fields.mapValues(addingRetiredFields))
            case .array(let items): return .array(items.map(addingRetiredFields))
            default: return value
            }
        }
        let old = addingRetiredFields(.encoding(engine))
        let restored = try JSONDecoder().decode(GameEngine.self, from: JSONEncoder().encode(old))
        #expect(restored.snapshot == engine.snapshot)
        #expect(restored.questionHistory == engine.questionHistory)
        #expect(!restored.requiresRestartForMediaFreeContent)
    }

    private var categories: [GameCategory] {
        (1...7).map { GameCategory(id: String($0), name: "فئة \($0)", interests: $0 == 2 ? ["رياضة", "كرة قدم"] : []) }
    }

    /// Synthetic fixtures exercise rules only; the application has no fabricated fallback trivia.
    private func questions(audio: Bool = false) -> [TriviaQuestion] {
        Difficulty.allCases.flatMap { difficulty in
            (1...6).map { category in
                TriviaQuestion(
                    id: "q-\(difficulty.rawValue)-\(category)", categoryID: String(category), difficulty: difficulty,
                    text: "سؤال اختبار \(category)", correctAnswer: "الرياض",
                    media: audio && category == 1 && difficulty == .easy ? .audio(url: URL(string: "https://example.com/test.mp3")!) : nil
                )
            }
        }
    }

    private func setup(audio: Bool = false) throws -> GameEngine {
        var engine = GameEngine(categories: categories)
        try engine.installQuestions(questions(audio: audio))
        for category in categories.prefix(6) {
            #expect(engine.perform(.addCategory(categoryID: category.id), requestID: "category-\(category.id)").success)
        }
        #expect(engine.perform(.createTeam(name: "الملوك"), requestID: "team-1").success)
        #expect(engine.perform(.createTeam(name: "الأساطير"), requestID: "team-2").success)
        return engine
    }

    private func playing(audio: Bool = false) throws -> GameEngine {
        var engine = try setup(audio: audio)
        #expect(engine.perform(.confirmGameSetup(expectedRevision: engine.snapshot.revision), requestID: "confirm").success)
        #expect(engine.perform(.startGame, requestID: "start").success)
        return engine
    }

    private func next(_ engine: inout GameEngine, requestID: String = UUID().uuidString) throws -> PresentedQuestion {
        #expect(engine.perform(.getNextQuestion(expectedRevision: engine.snapshot.revision), requestID: requestID).success)
        return try #require(engine.snapshot.currentQuestion)
    }

    private func answer(_ engine: inout GameEngine, question: PresentedQuestion, text: String = "الرياض", requestID: String = UUID().uuidString) -> ToolResult {
        engine.perform(.submitAnswer(answer: "يا نجيب، "+text, isCorrect: text == "الرياض" || text == "Riyadh", questionID: question.id, turnToken: question.turnToken), requestID: requestID)
    }

    @Test func testEmbeddedActivationPreservesTranscriptAndScoresOnlyOnce() throws {
        var engine = try playing()
        let question = try next(&engine)
        let transcript = "خلنا نفكر شوي. ينجيب، إجابتنا هي الرياض."
        var gate = VoiceInputGate()
        #expect(gate.receive(transcript, questionToken: question.turnToken) == .request)
        #expect(VoiceRequest.matchesAnswer("الرياض", transcript: transcript))
        let operation = GameOperation.submitAnswer(
            answer: transcript, isCorrect: true, questionID: question.id, turnToken: question.turnToken
        )
        let result = engine.perform(operation, requestID: "embedded-answer", voiceAuthorized: gate.authorizesRequest(questionToken: question.turnToken))
        #expect(result.success)
        #expect(engine.questionHistory.first?.submittedAnswer == transcript)
        #expect(engine.snapshot.teams[0].score == question.points)
        #expect(engine.perform(operation, requestID: "embedded-answer", voiceAuthorized: true) == result)
        #expect(engine.questionHistory.count == 1)
        #expect(engine.snapshot.teams[0].score == question.points)
    }

    @Test func testRecommendationsComeFromCatalogAndMultipleSelectionsAreCounted() throws {
        var engine = GameEngine(categories: categories)
        let result = engine.perform(.getCategorySuggestions(interests: "كرة قدم"), requestID: "read")
        guard case .array(let suggested) = result.data else { Issue.record("Expected categories"); return }
        #expect((suggested.count) == (1))
        #expect((suggested.first) == (.encoding(categories[1])))
        for id in ["1", "2", "3"] {
            #expect(ToolRouter.dispatch(name: "addCategory", arguments: ["category_id": .string(id)], requestID: "add-\(id)", engine: &engine).success)
        }
        #expect((engine.snapshot.categoriesRemaining) == (3))
        #expect((engine.perform(.addCategory(categoryID: "made-up"), requestID: "made-up").code) == ("CATEGORY_NOT_FOUND"))
        #expect((engine.perform(.addCategory(categoryID: "1"), requestID: "duplicate").code) == ("CATEGORY_ALREADY_SELECTED"))
    }

    @Test func testCategoryChangeAndRenameInvalidateConfirmation() throws {
        var engine = try setup()
        #expect(engine.perform(.confirmGameSetup(expectedRevision: engine.snapshot.revision), requestID: "confirm").success)
        #expect(engine.perform(.removeCategory(categoryID: "2"), requestID: "remove").success)
        #expect(!(engine.snapshot.configurationConfirmed))
        #expect(engine.perform(.addCategory(categoryID: "7"), requestID: "replace").success)
        #expect((engine.snapshot.selectedCategories.map(\.id)) == (["1", "3", "4", "5", "6", "7"]))
        #expect(engine.perform(.renameTeam(teamID: "team1", name: "الأبطال"), requestID: "rename").success)
        #expect((engine.snapshot.teams.first?.name) == ("الأبطال"))
        #expect((engine.perform(.startGame, requestID: "start").code) == ("SETUP_CONFIRMATION_REQUIRED"))
    }

    @Test func testInsufficientCategoriesCannotStartAndHelpersAreDefault() {
        var engine = GameEngine(categories: categories)
        #expect((engine.perform(.confirmGameSetup(expectedRevision: 0), requestID: "confirm").code) == ("SIX_CATEGORIES_REQUIRED"))
        #expect((engine.perform(.createTeam(name: "الملوك"), requestID: "create").code) == ("SIX_CATEGORIES_REQUIRED"))
        #expect((engine.perform(.startGame, requestID: "start").code) == ("SETUP_CONFIRMATION_REQUIRED"))
        for id in 1...6 { _ = engine.perform(.addCategory(categoryID: String(id)), requestID: "cat-\(id)") }
        _ = engine.perform(.createTeam(name: "الملوك"), requestID: "t1")
        _ = engine.perform(.createTeam(name: "الأساطير"), requestID: "t2")
        #expect(engine.perform(.confirmGameSetup(expectedRevision: engine.snapshot.revision), requestID: "confirm-2").success)
        #expect(engine.snapshot.teams.allSatisfy { $0.helperIDs == [.choices, .hint, .bomb] })
    }

    @Test func testDuplicateTeamNameAndCategoryLimitAreRejected() throws {
        var engine = try setup()
        #expect((engine.perform(.renameTeam(teamID: "team2", name: "الملوك"), requestID: "rename").code) == ("INVALID_TEAM_NAME"))
        #expect((engine.perform(.addCategory(categoryID: "7"), requestID: "seventh").code) == ("CATEGORY_LIMIT"))
    }

    @Test func testStaleSetupConfirmationDoesNotConfirmNewConfiguration() throws {
        var engine = try setup()
        let revision = engine.snapshot.revision
        _ = engine.perform(.renameTeam(teamID: "team1", name: "الأبطال"), requestID: "rename")
        #expect((engine.perform(.confirmGameSetup(expectedRevision: revision), requestID: "confirm").code) == ("STALE_REVISION"))
        #expect(!(engine.snapshot.configurationConfirmed))
    }

    @Test func testQuestionQueueIsDifficultyFirstAndTeamTurnsAlternate() throws {
        var engine = try playing()
        for (index, expected) in questions().enumerated() {
            let question = try next(&engine)
            #expect((question.id) == (expected.id))
            #expect((question.difficulty) == (expected.difficulty))
            #expect((question.teamID) == (index % 2 == 0 ? "team1" : "team2"))
            #expect(answer(&engine, question: question).success)
        }
        #expect((engine.snapshot.phase) == (.finished))
        #expect((engine.snapshot.completedQuestions) == (18))
    }

    @Test func testRepeatAndReadToolsNeverAdvanceAndAgentGetsReference() throws {
        var engine = try playing()
        let question = try next(&engine)
        let revision = engine.snapshot.revision
        for _ in 0..<3 {
            #expect(engine.perform(.repeatQuestion, requestID: "repeat").success)
            #expect(engine.perform(.getScoreboard, requestID: "score").success)
        }
        #expect((engine.snapshot.revision) == (revision))
        #expect((engine.snapshot.currentQuestion) == (question))
        #expect((engine.snapshot.completedQuestions) == (0))
        let encoded = try JSONEncoder().encode(engine.snapshot)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!(text.contains("correct_answer")))
        #expect(text.contains("reference_answer"))
        #expect(text.contains("الرياض"))
        #expect(!(text.contains("Riyadh")))
    }

    @Test func testIncorrectAnswerAwardsNoPointsAndUsesNextTeam() throws {
        var engine = try playing()
        let question = try next(&engine)
        let result = answer(&engine, question: question, text: "جدة")
        #expect((result.code) == ("ANSWER_INCORRECT"))
        #expect((engine.snapshot.teams.map(\.score)) == ([0, 0]))
        #expect((engine.snapshot.lastAnswer?.correctAnswer) == ("الرياض"))
        #expect((try next(&engine).teamID) == ("team2"))
    }

    @Test func testEmptyAnswerKeepsQuestionOpen() throws {
        var engine = try playing()
        let question = try next(&engine)
        for text in ["", "   ", "إجابتنا هي "] {
            #expect((answer(&engine, question: question, text: text).code) == ("ANSWER_NEEDS_CLARIFICATION"))
        }
        #expect((engine.snapshot.currentQuestion) == (question))
        #expect((engine.snapshot.completedQuestions) == (0))
        #expect((answer(&engine, question: question, text: "Riyadh").code) == ("ANSWER_CORRECT"))
    }

    @Test func testArabicNormalizationAndExplicitAliasesOnly() {
        #expect((AnswerNormalizer.normalize(" أَبْرِيل، ١٢ ")) == ("ابريل 12"))
        #expect((AnswerNormalizer.normalize("مَكَّة")) == ("مكه"))
        #expect((AnswerNormalizer.normalize("  الـرِّيَاض  ")) == ("الرياض"))
        #expect((AnswerNormalizer.normalize("الرياض")) != (AnswerNormalizer.normalize("العاصمة")))
    }

    @Test func testSurrenderAdvancesOnceAndCannotApplyToNextQuestion() throws {
        var engine = try playing()
        let question = try next(&engine)
        let operation = GameOperation.surrender(questionID: question.id, turnToken: question.turnToken)
        let result = engine.perform(operation, requestID: "surrender")
        #expect(result.success)
        #expect(engine.snapshot.lastAnswer?.surrendered == true)
        let newQuestion = try next(&engine)
        #expect((engine.perform(operation, requestID: "surrender")) == (result))
        #expect((engine.perform(operation, requestID: "retry-with-new-id").code) == ("STALE_QUESTION"))
        #expect((engine.snapshot.currentQuestion) == (newQuestion))
        #expect((engine.snapshot.completedQuestions) == (1))
    }

    @Test func testDuplicateAnswerCannotDoubleAwardAndCacheSurvivesPersistence() throws {
        var engine = try playing()
        let question = try next(&engine)
        let result = answer(&engine, question: question, requestID: "answer-once")
        let encoded = try JSONEncoder().encode(engine)
        engine = try JSONDecoder().decode(GameEngine.self, from: encoded)
        #expect((answer(&engine, question: question, requestID: "answer-once")) == (result))
        #expect((engine.snapshot.teams[0].score) == (100))
        #expect((engine.snapshot.completedQuestions) == (1))
        #expect((answer(&engine, question: question, requestID: "new-answer-id").code) == ("STALE_QUESTION"))
        _ = try next(&engine)
        #expect((answer(&engine, question: question, requestID: "another-answer-id").code) == ("STALE_QUESTION"))
        #expect((engine.snapshot.teams[0].score) == (100))
    }

    @Test func testDuplicateNextCallCannotConsumeNextTurn() throws {
        var engine = try playing()
        let before = engine.snapshot.revision
        let operation = GameOperation.getNextQuestion(expectedRevision: before)
        let result = engine.perform(operation, requestID: "next-once")
        let first = try #require(engine.snapshot.currentQuestion)
        _ = answer(&engine, question: first)
        #expect((engine.perform(operation, requestID: "next-once")) == (result))
        #expect((engine.perform(operation, requestID: "next-new-id").code) == ("STALE_REVISION"))
        #expect((engine.snapshot.currentQuestion?.id) != first.id)
        let second = try next(&engine)
        #expect((first.id) != (second.id))
        #expect((engine.snapshot.completedQuestions) == (1))
    }

    @Test func testAnswersPrepareAllFollowingQuestionsWithoutAnotherNextCall() throws {
        var engine = try playing()
        var question = try next(&engine)
        for index in 0..<18 {
            #expect(question.teamID == "team\(index % 2 + 1)")
            let result = answer(&engine, question: question, requestID: "auto-answer-\(index)")
            #expect(result.success)
            #expect(result.state.completedQuestions == index + 1)
            #expect(result.state.lastAnswer?.questionID == question.id)
            #expect(result.state == engine.snapshot)
            if index < 17 {
                let following = try #require(result.state.currentQuestion)
                #expect(following.id != question.id)
                #expect(following.turnToken != question.turnToken)
                #expect(following.categoryID == String((index + 1) % 6 + 1))
                #expect(following.difficulty == Difficulty.allCases[(index + 1) / 6])
                question = following
            } else {
                #expect(result.state.phase == .finished)
                #expect(result.state.currentQuestion == nil)
                #expect(result.state.winner?.isTie == true)
            }
        }
    }

    @Test func testSecondAnswerProgressionSurvivesReplayPauseAndPersistence() throws {
        var engine = try playing()
        let first = try next(&engine)
        let firstResult = answer(&engine, question: first)
        let second = try #require(firstResult.state.currentQuestion)
        let secondResult = answer(&engine, question: second, text: "جدة", requestID: "second-answer")
        let third = try #require(secondResult.state.currentQuestion)
        #expect(secondResult.code == "ANSWER_INCORRECT")
        #expect(third.teamID == "team1")
        #expect(secondResult.state.completedQuestions == 2)
        #expect(secondResult.state.teams.map(\.score) == [100, 0])

        engine = try JSONDecoder().decode(GameEngine.self, from: JSONEncoder().encode(engine))
        #expect(answer(&engine, question: second, text: "جدة", requestID: "second-answer") == secondResult)
        #expect(answer(&engine, question: second, text: "جدة").code == "STALE_QUESTION")
        _ = engine.perform(.pauseGame, requestID: "pause-third")
        #expect(engine.perform(.getNextQuestion(expectedRevision: engine.snapshot.revision), requestID: "paused-next").code == "INVALID_GAME_STATE")
        _ = engine.perform(.resumeGame, requestID: "resume-third")
        #expect(engine.perform(.repeatQuestion, requestID: "repeat-third").state.currentQuestion == third)
        #expect(try next(&engine) == third)
        #expect(engine.snapshot.completedQuestions == 2)
        #expect(engine.snapshot.teams.map(\.score) == [100, 0])
    }

    @Test func testSurrenderAdvancesOnceAndRequiresFreshVoiceAuthorization() throws {
        var engine = try playing()
        let first = try next(&engine)
        var gate = VoiceInputGate()
        #expect(gate.receive("يا نجيب استسلمنا", questionToken: first.turnToken) == .request)
        let operation = GameOperation.surrender(questionID: first.id, turnToken: first.turnToken)
        let result = engine.perform(operation, requestID: "surrender-first")
        let second = try #require(result.state.currentQuestion)
        #expect(result.code == "ANSWER_SURRENDERED")
        #expect(result.state.completedQuestions == 1)
        #expect(result.state.teams.map(\.score) == [0, 0])
        #expect(engine.perform(operation, requestID: "surrender-first") == result)
        #expect(engine.perform(operation, requestID: "surrender-stale").code == "STALE_QUESTION")
        gate.synchronize(questionToken: second.turnToken)
        #expect(!gate.authorizesRequest(questionToken: second.turnToken))
        #expect(engine.snapshot.currentQuestion == second)
        #expect(engine.snapshot.completedQuestions == 1)
    }

    @Test func testAgentCanJudgeShortYesNoAnswersWithoutStringHeuristics() throws {
        var engine = try playing()
        let question = try next(&engine)
        let result = engine.perform(.submitAnswer(answer: "يا نجيب، إجابتنا هي لا", isCorrect: true, questionID: question.id, turnToken: question.turnToken), requestID: "yes-no")
        #expect(result.code == "ANSWER_CORRECT")
    }

    @Test func testBackgroundSpeechIsSilentOnlyDuringOpenQuestions() {
        #expect(!VoiceRequest.isDirected("هلسنكي"))
        #expect(!VoiceRequest.isDirected("نبي تلميح"))
        #expect(VoiceRequest.isDirected("يا نجيب أعد السؤال"))
        var gate = VoiceInputGate()
        #expect(gate.receive("نبي تاريخ وكرة قدم", questionToken: nil) == .request)
    }

    @Test func testSubmissionVariantsAndActivatedAnswersKeepVerbatimHistory() throws {
        for text in ["حنا نعتمد الرياض", "إجابتنا هي الرياض", "يانجيب الرياض", "الرياض"] {
            var engine = try playing()
            let question = try next(&engine)
            let arguments: [String: GameJSONValue] = ["answer": .string(text), "is_correct": .bool(true),
                                                  "expected_question_id": .string(question.id), "turn_token": .string(question.turnToken)]
            let result = ToolRouter.dispatch(name: "submitAnswer", arguments: arguments, requestID: "variant", engine: &engine,
                                             voiceAuthorized: text == "الرياض")
            #expect(result.code == "ANSWER_CORRECT")
            #expect(result.state.lastAnswer?.submittedAnswer == text)
            #expect(result.state.teams[0].score == 100)
            #expect(ToolRouter.dispatch(name: "submitAnswer", arguments: arguments, requestID: "variant", engine: &engine) == result)
            #expect(engine.snapshot.completedQuestions == 1)
        }
    }

    @Test func testEmptyVariantAndForgedAuthorizationDoNotAdvanceTheGame() throws {
        var engine = try playing()
        let question = try next(&engine)
        let empty = engine.perform(.submitAnswer(answer: "حنا نعتمد", isCorrect: true, questionID: question.id, turnToken: question.turnToken), requestID: "empty")
        #expect(empty.code == "ANSWER_NEEDS_CLARIFICATION")
        let forged: [String: GameJSONValue] = ["answer": .string("الرياض"), "is_correct": .bool(true), "voice_authorized": .bool(true),
                                         "expected_question_id": .string(question.id), "turn_token": .string(question.turnToken)]
        #expect(ToolRouter.dispatch(name: "submitAnswer", arguments: forged, requestID: "forged", engine: &engine).code == "INVALID_ARGUMENTS")
        #expect(engine.snapshot.completedQuestions == 0)
        #expect(engine.snapshot.teams[0].score == 0)
    }

    @Test func testRouterRequiresAgentVerdictAndRetiredSetupToolsAreAbsent() throws {
        var engine = try playing()
        let question = try next(&engine)
        let result = ToolRouter.dispatch(name: "submitAnswer", arguments: ["answer": .string("يا نجيب الرياض"), "expected_question_id": .string(question.id), "turn_token": .string(question.turnToken)], requestID: "missing-verdict", engine: &engine)
        #expect(result.code == "INVALID_ARGUMENTS")
        #expect(engine.snapshot.completedQuestions == 0)
        #expect(!ToolRouter.toolNames.contains("configureHelpers"))
        #expect(ToolRouter.toolNames.count == 20)
    }

    @Test func testConflictingDuplicateRequestAndRouterValidation() throws {
        var engine = GameEngine(categories: categories)
        _ = engine.perform(.addCategory(categoryID: "1"), requestID: "shared")
        #expect((engine.perform(.addCategory(categoryID: "2"), requestID: "shared").code) == ("DUPLICATE_REQUEST_CONFLICT"))
        #expect((ToolRouter.dispatch(name: "addCategory", arguments: ["category_id": .number(2)], requestID: "invalid", engine: &engine).code) == ("INVALID_ARGUMENTS"))
        #expect((ToolRouter.dispatch(name: "getNextQuestion", arguments: ["expected_revision": .number(1.2)], requestID: "invalid2", engine: &engine).code) == ("INVALID_ARGUMENTS"))
        #expect((ToolRouter.dispatch(name: "getScoreboard", arguments: ["score": .number(999)], requestID: "invalid3", engine: &engine).code) == ("INVALID_ARGUMENTS"))
        #expect((ToolRouter.dispatch(name: "awardPoints", arguments: [:], requestID: "unknown", engine: &engine).code) == ("UNKNOWN_TOOL"))
        #expect((engine.snapshot.selectedCategories.count) == (1))
    }

    @Test func testSemanticRequestIDDeduplicatesNewTransportCallID() {
        var engine = GameEngine(categories: categories)
        let args: [String: GameJSONValue] = ["category_id": .string("1"), "request_id": .string("semantic")]
        let first = ToolRouter.dispatch(name: "addCategory", arguments: args, requestID: "transport1", engine: &engine)
        let retry = ToolRouter.dispatch(name: "addCategory", arguments: args, requestID: "transport2", engine: &engine)
        #expect((first) == (retry))
        #expect((engine.snapshot.selectedCategories.count) == (1))
    }

    @Test func testPauseResumeAndVoiceReconnectRetainSameTurn() throws {
        var engine = try playing()
        let question = try next(&engine)
        #expect(engine.perform(.pauseGame, requestID: "pause").success)
        #expect((answer(&engine, question: question).code) == ("INVALID_GAME_STATE"))
        #expect((engine.snapshot.currentQuestion) == (question))
        engine = try JSONDecoder().decode(GameEngine.self, from: JSONEncoder().encode(engine))
        #expect(engine.perform(.resumeGame, requestID: "resume").success)
        #expect((engine.snapshot.currentQuestion) == (question))
        #expect(answer(&engine, question: question).success)
    }

    @Test func testDefaultHelpersUseGeneratedContentAndFailuresDoNotConsume() throws {
        var engine = try playing()
        let question = try next(&engine)
        #expect(engine.snapshot.availableHelpers.map(\.id) == [.choices, .hint, .bomb])
        let missing = engine.perform(.useHelper(helperID: .hint, questionID: question.id, turnToken: question.turnToken), requestID: "missing")
        #expect(missing.code == "HELPER_CONTENT_REQUIRED")
        #expect(engine.snapshot.teams[0].usedHelperIDs.isEmpty)
        let leaking = engine.perform(.useHelper(helperID: .hint, questionID: question.id, turnToken: question.turnToken, content: .hint("الرياض")), requestID: "leaking")
        #expect(leaking.code == "HELPER_CONTENT_INVALID")
        let hint = engine.perform(.useHelper(helperID: .hint, questionID: question.id, turnToken: question.turnToken, content: .hint("مدينة في وسط المملكة")), requestID: "hint")
        #expect(hint.success)
        #expect(engine.snapshot.currentQuestion?.hint == "مدينة في وسط المملكة")
        #expect(engine.perform(.useHelper(helperID: .hint, questionID: question.id, turnToken: question.turnToken), requestID: "again").code == "HELPER_ALREADY_USED")
        let choices = ["جدة", "الرياض", "مكة", "الدمام"]
        #expect(engine.perform(.useHelper(helperID: .choices, questionID: question.id, turnToken: question.turnToken, content: .choices(choices)), requestID: "choices").success)
        #expect(engine.snapshot.currentQuestion?.choices == choices)
    }

    @Test func testBombTransfersTurnAndDeductsPointsWithoutChangingNextNormalTurn() throws {
        var engine = try playing()
        let original = try next(&engine)
        let operation = GameOperation.useHelper(helperID: .bomb, questionID: original.id, turnToken: original.turnToken)
        let result = engine.perform(operation, requestID: "bomb")
        #expect(result.success)
        #expect(engine.perform(operation, requestID: "bomb") == result)
        let transferred = try #require(engine.snapshot.currentQuestion)
        #expect(transferred.teamID == "team2")
        #expect(transferred.turnToken != original.turnToken)
        #expect(answer(&engine, question: original).code == "STALE_QUESTION")
        #expect(engine.perform(.useHelper(helperID: .bomb, questionID: transferred.id, turnToken: transferred.turnToken), requestID: "rebomb").code == "BOMB_ALREADY_ACTIVE")
        _ = answer(&engine, question: transferred, text: "جدة")
        #expect(engine.snapshot.teams.map(\.score) == [0, -100])
        #expect(try next(&engine).teamID == "team2")
    }

    @Test func testBombCorrectAnswerAwardsTargetAndSurrenderDeducts() throws {
        for correct in [true, false] {
            var engine = try playing()
            let original = try next(&engine)
            _ = engine.perform(.useHelper(helperID: .bomb, questionID: original.id, turnToken: original.turnToken), requestID: "bomb")
            let target = try #require(engine.snapshot.currentQuestion)
            if correct { _ = answer(&engine, question: target) }
            else { _ = engine.perform(.surrender(questionID: target.id, turnToken: target.turnToken), requestID: "surrender") }
            #expect(engine.snapshot.teams[1].score == (correct ? 100 : -100))
        }
    }

    @Test func testAgentVerdictAcceptsExpandedAnswerAndWakePhraseIsRequired() throws {
        var engine = try setup()
        var bank = questions()
        bank[0] = TriviaQuestion(id: bank[0].id, categoryID: "1", difficulty: .easy, text: "وش وثيقة السفر؟", correctAnswer: "جواز")
        try engine.installQuestions(bank)
        _ = engine.perform(.confirmGameSetup(expectedRevision: engine.snapshot.revision), requestID: "confirm")
        _ = engine.perform(.startGame, requestID: "start")
        let question = try next(&engine)
        let ignored = engine.perform(.submitAnswer(answer: "جواز السفر", isCorrect: true, questionID: question.id, turnToken: question.turnToken), requestID: "ignored")
        #expect(ignored.code == "IGNORED_INPUT")
        #expect(ignored.message.isEmpty)
        #expect(engine.snapshot.completedQuestions == 0)
        let judged = engine.perform(.submitAnswer(answer: "يا نجيب، إجابتنا هي جواز السفر", isCorrect: true, questionID: question.id, turnToken: question.turnToken), requestID: "judged")
        #expect(judged.code == "ANSWER_CORRECT")
        #expect(engine.snapshot.teams[0].score == 100)
        #expect(VoiceRequest.isAddressed("يا نجيب، نبي تلميح"))
        #expect(!VoiceRequest.isAddressed("نجيب يعرف الإجابة"))
        #expect(VoiceRequest.answerText("يا نجيب، إجابتنا هي جواز السفر") == "جواز السفر")
    }

    @Test func testAllQuestionMediaAreRejectedBeforeInstallation() throws {
        var engine = try setup()
        let url = try #require(URL(string: "https://example.com/legacy"))
        for media in [QuestionMedia.audio(url: url), .image(url: url), .images(urls: [url])] {
            var supplied = questions()
            supplied[0] = TriviaQuestion(id: supplied[0].id, categoryID: "1", difficulty: .easy,
                text: "اختبار", correctAnswer: "الرياض", media: media)
            #expect(throws: GameEngineError.invalidQuestionBank) { try engine.installQuestions(supplied) }
        }
        #expect(!engine.requiresRestartForMediaFreeContent)
    }

    @Test func testMissingDifficultyContentNeverUsesFallback() throws {
        var engine = try setup()
        try engine.installQuestions(Array(questions().dropLast()))
        _ = engine.perform(.confirmGameSetup(expectedRevision: engine.snapshot.revision), requestID: "confirm")
        #expect(engine.perform(.startGame, requestID: "start").code == "QUESTION_CONTENT_UNAVAILABLE")
        #expect(engine.snapshot.phase == .confirmed)
    }

    @Test func testWinnerOnlyAfterFinalAnswerAndEarlyEndDoesNotInventWinner() throws {
        var engine = try playing()
        for index in 0..<18 {
            #expect((engine.snapshot.winner) == nil)
            let question = try next(&engine)
            _ = answer(&engine, question: question, text: index % 2 == 0 ? "الرياض" : "جدة")
        }
        #expect((engine.snapshot.winner?.teamID) == ("team1"))
        #expect((engine.snapshot.teams[0].score) == (2700))
        #expect((engine.snapshot.teams[1].score) == (0))
        #expect((engine.perform(.getNextQuestion(expectedRevision: engine.snapshot.revision), requestID: "nineteenth").code) == ("INVALID_GAME_STATE"))
        var ended = try playing()
        _ = ended.perform(.endGame, requestID: "stop")
        #expect((ended.snapshot.phase) == (.ended))
        #expect((ended.snapshot.winner) == nil)
    }

    @Test func testVerifiedContentHydrationPreservesConfigurationConfirmation() throws {
        var engine = GameEngine(categories: categories)
        for id in 1...6 { _ = engine.perform(.addCategory(categoryID: String(id)), requestID: "cat-\(id)") }
        _ = engine.perform(.createTeam(name: "الملوك"), requestID: "t1")
        _ = engine.perform(.createTeam(name: "الأساطير"), requestID: "t2")
        _ = engine.perform(.confirmGameSetup(expectedRevision: engine.snapshot.revision), requestID: "confirm")
        try engine.installQuestions(questions())
        #expect(engine.snapshot.configurationConfirmed)
        #expect((engine.snapshot.phase) == (.confirmed))
        #expect(engine.perform(.startGame, requestID: "start").success)
    }

    private func restoringLegacyContent(media: QuestionMedia? = nil, sourcePoints: Int? = nil) throws -> GameEngine {
        var engine = try playing()
        let first = try next(&engine)
        _ = answer(&engine, question: first)
        _ = try next(&engine)
        guard case .object(var fields) = try JSONDecoder().decode(GameJSONValue.self, from: JSONEncoder().encode(engine)) else {
            throw GameEngineError.invalidQuestionBank
        }
        fields["storedPresentationMode"] = .string("iphone_images")
        for key in ["queue", "questionBank"] {
            guard case .array(var items) = fields[key], case .object(var question) = items[1] else {
                throw GameEngineError.invalidQuestionBank
            }
            if let media { question["media"] = .encoding(media) }
            if let sourcePoints { question["source_difficulty_points"] = .number(Double(sourcePoints)) }
            items[1] = .object(question)
            fields[key] = .array(items)
        }
        return try JSONDecoder().decode(GameEngine.self, from: JSONEncoder().encode(GameJSONValue.object(fields)))
    }

    @Test func testLegacyQuestionMediaRestorePausedWithoutChangingScoresOrHistory() throws {
        let url = try #require(URL(string: "https://example.com/legacy"))
        for media in [QuestionMedia.audio(url: url), .image(url: url), .images(urls: [url])] {
            var restored = try restoringLegacyContent(media: media)
            #expect(restored.requiresRestartForMediaFreeContent)
            #expect(restored.snapshot.requiresRestartForMediaFreeContent)
            #expect(restored.snapshot.phase == .paused)
            #expect(restored.snapshot.currentQuestion == nil)
            #expect(restored.snapshot.teams[0].score == 100)
            #expect(restored.questionHistory.count == 1)
            #expect(restored.perform(.resumeGame, requestID: "resume-legacy").code == "LEGACY_CONTENT_REQUIRES_RESTART")
            #expect(restored.perform(.getNextQuestion(expectedRevision: restored.snapshot.revision), requestID: "advance-legacy").code == "LEGACY_CONTENT_REQUIRES_RESTART")
            #expect(restored.questionHistory.count == 1)
        }
    }

    @Test func testLegacyWrongSourcePointsRequireRestartAndCannotInstall() throws {
        var restored = try restoringLegacyContent(sourcePoints: 200)
        #expect(restored.requiresRestartForMediaFreeContent)
        #expect(restored.snapshot.phase == .paused)
        #expect(restored.snapshot.teams[0].score == 100)
        #expect(restored.perform(.resumeGame, requestID: "resume-wrong-points").code == "LEGACY_CONTENT_REQUIRES_RESTART")
        var engine = try setup()
        var supplied = questions()
        supplied[0] = TriviaQuestion(id: supplied[0].id, categoryID: "1", difficulty: .easy,
            text: "اختبار", correctAnswer: "الرياض", sourceDifficultyPoints: 200)
        #expect(throws: GameEngineError.invalidQuestionBank) { try engine.installQuestions(supplied) }
    }

    @Test func testLegacyNumericDifficultyIsPreservedForRestartDetection() throws {
        let value = GameJSONValue.object([
            "id": .string("legacy"), "category_id": .string("1"), "difficulty": .number(400),
            "text": .string("اختبار"), "correct_answer": .string("جواب")
        ])
        let question = try JSONDecoder().decode(TriviaQuestion.self, from: JSONEncoder().encode(value))
        #expect(question.difficulty == .medium)
        #expect(question.sourceDifficultyPoints == 400)
    }

    @Test func testLegacyArchivesWithoutPresentationModeKeepPlayableTextOnlyState() throws {
        var engine = try playing()
        _ = try next(&engine)
        func removingMode(_ value: GameJSONValue) -> GameJSONValue {
            switch value {
            case .object(let fields): return .object(fields.filter { $0.key != "storedPresentationMode" && $0.key != "presentation_mode" && $0.key != "requires_restart_for_media_free_content" }.mapValues(removingMode))
            case .array(let values): return .array(values.map(removingMode))
            default: return value
            }
        }
        let old = removingMode(try JSONDecoder().decode(GameJSONValue.self, from: JSONEncoder().encode(engine)))
        let restored = try JSONDecoder().decode(GameEngine.self, from: JSONEncoder().encode(old))
        #expect(!restored.requiresRestartForMediaFreeContent)
        #expect(restored.snapshot.phase == .playing)
        #expect(restored.snapshot.currentQuestion != nil)
        #expect(restored.cachedResult(for: "start")?.state.phase == .playing)
    }

    @Test func testLegacyStringDifficultyWithoutSourceMetadataRequiresRestart() throws {
        var engine = try playing()
        let question = try next(&engine)
        _ = answer(&engine, question: question)
        guard case .object(var fields) = try JSONDecoder().decode(GameJSONValue.self, from: JSONEncoder().encode(engine)) else {
            throw GameEngineError.invalidQuestionBank
        }
        for key in ["queue", "questionBank"] {
            guard case .array(let values) = fields[key] else { throw GameEngineError.invalidQuestionBank }
            fields[key] = .array(values.map { value in
                guard case .object(var question) = value else { return value }
                question.removeValue(forKey: "source_difficulty_points")
                return .object(question)
            })
        }
        var restored = try JSONDecoder().decode(GameEngine.self, from: JSONEncoder().encode(GameJSONValue.object(fields)))
        #expect(restored.requiresRestartForMediaFreeContent)
        #expect(restored.snapshot.phase == .paused)
        #expect(restored.snapshot.teams[0].score == 100)
        #expect(restored.questionHistory.count == 1)
        #expect(restored.perform(.resumeGame, requestID: "resume-missing-origin").code == "LEGACY_CONTENT_REQUIRES_RESTART")
        #expect(restored.perform(.getNextQuestion(expectedRevision: restored.snapshot.revision), requestID: "next-missing-origin").code == "LEGACY_CONTENT_REQUIRES_RESTART")
    }

    @Test func testTieIsReportedWithoutChoosingWinner() throws {
        var engine = try playing()
        for _ in 0..<18 {
            let question = try next(&engine)
            _ = answer(&engine, question: question)
        }
        #expect(engine.snapshot.winner?.isTie == true)
        #expect((engine.snapshot.winner?.teamID) == nil)
    }
}
