import Foundation
import Testing
@testable import NajeebLogic

struct APIClientTests {
    @Test func fetchesGeneratedHintFromExistingAuthenticatedEndpoint() async throws {
        let transport = MockTransport(data: Data("{\"question_id\":\"q1\",\"hint\":\"مدينة في وسط المملكة\"}".utf8))
        let result = try await client(transport).fetchHelper(.hint, questionID: "q1", categoryID: "1")
        #expect(result == .hint("مدينة في وسط المملكة"))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/game/question/hint")
        let body = try JSONDecoder().decode([String: GameJSONValue].self, from: #require(request.httpBody))
        #expect(body == ["question_id": .string("q1")])
    }

    @Test func fetchesFourChoicesAndRejectsWrongQuestionResponse() async throws {
        let transport = MockTransport(data: Data("{\"question_id\":\"q1\",\"choices\":[\"الرياض\",\"جدة\",\"مكة\",\"الدمام\"]}".utf8))
        #expect(try await client(transport).fetchHelper(.choices, questionID: "q1", categoryID: "6") == .choices(["الرياض", "جدة", "مكة", "الدمام"]))
        let request = try #require(await transport.requests.first)
        let body = try JSONDecoder().decode([String: GameJSONValue].self, from: #require(request.httpBody))
        #expect(body["category_id"] == .number(6))
        #expect(request.url?.path == "/api/game/question/choices")
        await #expect(throws: ContentError.invalidResponse) { try await client(transport).fetchHelper(.choices, questionID: "other", categoryID: "6") }
    }

    @Test func helperHTTPFailureReturnsWithoutInventingContent() async throws {
        let transport = MockTransport(data: Data("{\"code\":\"OPENROUTER_NOT_CONFIGURED\"}".utf8), status: 400)
        await #expect(throws: ContentError.server(status: 400, code: "OPENROUTER_NOT_CONFIGURED")) {
            try await client(transport).fetchHelper(.hint, questionID: "q1", categoryID: "1")
        }
    }

    @Test func decodesCatalogAndUsesActualSectionNamesForSuggestions() async throws {
        let fixture = """
        {"categories":[{"id":1,"name":"الفئة الفعلية","description":"وصف"}],
         "sections":[{"name":"الاهتمامات الفعلية","categories":[{"id":1,"name":"الفئة الفعلية"}]}]}
        """
        let transport = MockTransport(data: Data(fixture.utf8))
        let client = try client(transport)
        let categories = try await client.fetchCategories()
        #expect(categories.count == 1)
        #expect(categories[0].id == "1")
        #expect(categories[0].interests == ["الفئة الفعلية", "الاهتمامات الفعلية"])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/game/categories")
    }

    @Test func rejectsDuplicatedCategoryCatalogIDs() async throws {
        let transport = MockTransport(data: Data("""
        {"categories":[{"id":1,"name":"أ"},{"id":1,"name":"ب"}]}
        """.utf8))
        await #expect(throws: ContentError.invalidContent("Invalid or duplicate catalog category")) {
            try await client(transport).fetchCategories()
        }
    }

    @Test func preparesEighteenUniqueQuestionsInDifficultyThenCategoryOrder() async throws {
        let transport = MockTransport(data: try questionFixture())
        let queue = try await client(transport).fetchQuestions(categoryIDs: categoryIDs, gameID: "game-1")
        #expect(queue.count == 18)
        #expect(Array(queue.prefix(6)).map(\.categoryID) == categoryIDs)
        #expect(Array(queue.prefix(6)).allSatisfy { $0.difficulty == .easy })
        #expect(Array(queue.suffix(6)).allSatisfy { $0.difficulty == .hard })
        #expect(Set(queue.map(\.id)).count == 18)
        #expect(queue.allSatisfy { $0.media == nil })
        let request = try #require(await transport.requests.first)
        let body = try JSONDecoder().decode(QuestionsBody.self, from: #require(request.httpBody))
        #expect(body.categories == [1, 2, 3, 4, 5, 6])
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/game/carmode_questions")
        #expect(queue.allSatisfy { $0.sourceDifficultyPoints == $0.difficulty.points })
        #expect(body.analytics_game_id == "game-1")
    }

    @Test func cachesSuccessfulPreparationAndCoalescesConcurrentToolCalls() async throws {
        let transport = MockTransport(data: try questionFixture())
        let client = try client(transport)
        async let first = client.fetchQuestions(categoryIDs: categoryIDs, gameID: "same-game")
        async let duplicate = client.fetchQuestions(categoryIDs: categoryIDs, gameID: "same-game")
        let (a, b) = try await (first, duplicate)
        let replay = try await client.fetchQuestions(categoryIDs: categoryIDs, gameID: "same-game")
        #expect(a == b && b == replay)
        #expect(await transport.requests.count == 1)
    }

    @Test func cachesInvalidResponseShapeWithoutMakingAnotherBackendRequest() async throws {
        let transport = MockTransport(data: Data("{}".utf8))
        let client = try client(transport)
        for _ in 0..<2 {
            await #expect(throws: ContentError.invalidContent("Expected exactly three questions per selected category")) {
                try await client.fetchQuestions(categoryIDs: categoryIDs, gameID: "same-game")
            }
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func rejectsMediaDependentQuestionAndReportsExactMissingSlot() async throws {
        let transport = MockTransport(data: try questionFixture(mediaCategory: 2))
        do {
            _ = try await client(transport).fetchQuestions(categoryIDs: categoryIDs, gameID: "game")
            Issue.record("Expected media rejection")
        } catch ContentError.insufficientSafeQuestions(let missing) {
            #expect(missing == [QuestionSlot(categoryID: "2", difficulty: .easy)])
        }
    }













    @Test func doesNotMislabelFallbackDifficultyAsActualDifficulty() async throws {
        let transport = MockTransport(data: try questionFixture(fallbackCategory: 4))
        do {
            _ = try await client(transport).fetchQuestions(categoryIDs: categoryIDs, gameID: "game")
            Issue.record("Expected source difficulty rejection")
        } catch ContentError.insufficientSafeQuestions(let missing) {
            #expect(missing == [QuestionSlot(categoryID: "4", difficulty: .hard)])
        }
    }

    @Test func rejectsVisualLanguageEvenWithoutMediaAttachments() {
        for text in [
            "من الشخص في الصورة؟", "وش اسم الفريق بالشعار؟", "اسم المكان بالخريطة؟",
            "وش تشوف قدامك؟", "شوف المقطع وقل لنا", "Listen to the clip", "Who is pictured?",
        ] {
            #expect(!DrivingQuestionFilter.isTextAudioCompatible(question: text, answer: "جواب"))
        }
        #expect(DrivingQuestionFilter.isTextAudioCompatible(question: "سؤال اختباري لفظي واضح؟", answer: "جواب"))
        #expect(!DrivingQuestionFilter.isTextAudioCompatible(question: "سؤال؟", answer: "   "))
    }

    @Test func rejectsNonClassicQuestionsButIgnoresAnswerAssets() throws {
        let data = Data("""
        [
         {"id":"drawing","question_text":"سؤال؟","difficulty":100,"correct_answer":"جواب","type":"DRAWING"},
         {"id":"answer-media","question_text":"سؤال؟","difficulty":100,"correct_answer":"جواب","correct_answer_media":["https://example.invalid/x.png"]},
         {"id":"malformed-answer-media","question_text":"سؤال؟","difficulty":100,"correct_answer":"جواب","correct_answer_media":{"ignored":true}}
        ]
        """.utf8)
        let questions = try JSONDecoder().decode([BackendQuestion].self, from: data)
        #expect(!DrivingQuestionFilter.isCompatible(questions[0]))
        #expect(DrivingQuestionFilter.isCompatible(questions[1]))
        #expect(DrivingQuestionFilter.isCompatible(questions[2]))
    }

    @Test func acceptsBackwardCompatibleNullMediaAndMissingOptionalFields() throws {
        let data = Data("""
        {"id":"legacy","question_text":"سؤال اختباري؟","difficulty":100,"correct_answer":"جواب","media":null,"correct_answer_media":null}
        """.utf8)
        let question = try JSONDecoder().decode(BackendQuestion.self, from: data)
        #expect(question.sourceDifficulty == 100)
        #expect(DrivingQuestionFilter.isCompatible(question))
    }

    @Test func requiresSixDistinctCatalogIDsBeforeMakingNetworkRequest() async throws {
        let transport = MockTransport(data: Data("{}".utf8))
        let client = try client(transport)
        for invalid in [["1", "2"], ["1", "1", "3", "4", "5", "6"], ["1", "2", "3", "4", "5", "-6"], ["1", "2", "3", "4", "5", "2147483648"]] {
            do {
                _ = try await client.fetchQuestions(categoryIDs: invalid, gameID: "game")
                Issue.record("Expected invalid category selection")
            } catch ContentError.invalidInput { }
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func normalizesEmailAndSupportsAlphanumericOTP() async throws {
        let transport = MockTransport(data: Data("""
        {"message":"ok","requires_name":false,"new_user":false,"user_id":"verified-user"}
        """.utf8))
        let client = try client(transport)
        try await client.requestOTP(email: "  PLAYER@Example.COM ")
        let result = try await client.verifyOTP(email: "PLAYER@Example.COM", otp: " ab12cd ", name: "  اللاعب  ")
        #expect(result.userID == "verified-user")
        let request = try #require(await transport.requests.last)
        let body = try JSONDecoder().decode(VerifyBody.self, from: #require(request.httpBody))
        #expect(body.email == "player@example.com")
        #expect(body.otp == "AB12CD")
        #expect(body.name == "اللاعب")
    }

    @Test func newUserNameRequirementDoesNotClaimAuthentication() async throws {
        let transport = MockTransport(data: Data("{\"message\":\"name required\",\"requires_name\":true}".utf8))
        let client = try client(transport)
        let result = try await client.verifyOTP(email: "test@example.com", otp: "ABC123")
        #expect(result.requiresName)
        #expect(!(await client.hasSessionCookie()))
    }

    @Test func completesNewUserWithSameOTPAndTrimmedName() async throws {
        let transport = MockTransport(data: Data("{\"requires_name\":true}".utf8))
        let client = try client(transport)
        #expect(try await client.verifyOTP(email: "new@example.com", otp: "ABC123").requiresName)
        await transport.updateResponse(data: Data("{\"requires_name\":false,\"new_user\":true,\"user_id\":\"new-user\"}".utf8))
        let result = try await client.verifyOTP(email: "new@example.com", otp: "ABC123", name: "  نورة  ")
        #expect(!result.requiresName)
        #expect(result.newUser)
        #expect(result.userID == "new-user")
        let requests = await transport.requests
        #expect(requests.count == 2)
        let bodies = try requests.map { try JSONDecoder().decode(VerifyBody.self, from: #require($0.httpBody)) }
        #expect(bodies.map(\.email) == ["new@example.com", "new@example.com"])
        #expect(bodies.map(\.otp) == ["ABC123", "ABC123"])
        #expect(bodies.first?.name == nil)
        #expect(bodies.last?.name == "نورة")
    }

    @Test func rejectsBlankAccountNamesBeforeSendingAnotherRequest() async throws {
        let transport = MockTransport(data: Data("{\"requires_name\":true}".utf8))
        let client = try client(transport)
        for name in ["", "   ", "\n\t"] {
            await #expect(throws: ContentError.invalidInput("اكتب اسمك عشان نكمل حسابك.")) {
                try await client.verifyOTP(email: "new@example.com", otp: "ABC123", name: name)
            }
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func mapsUnauthenticatedAndQuotaErrorsWithoutLeakingRawServerMessages() async throws {
        let privateMessage = "internal/private/path"
        for (status, code) in [(401, "UNAUTHORIZED"), (429, "GAME_CREATION_LIMITED"), (500, "INTERNAL_SERVER_ERROR")] {
            let transport = MockTransport(data: Data("{\"code\":\"\(code)\",\"message\":\"\(privateMessage)\"}".utf8), status: status)
            do {
                _ = try await client(transport).fetchCategories()
                Issue.record("Expected API failure")
            } catch let error as ContentError {
                #expect(!(error.errorDescription ?? "").contains(privateMessage))
                switch status {
                case 401: #expect(error == .unauthenticated)
                case 429: #expect(error == .rateLimited(code: code))
                default: #expect(error == .server(status: status, code: code))
                }
            }
        }
    }

    @Test func memoizesTransportTimeoutBecauseBackendMayAlreadyHaveCommitted() async throws {
        let transport = MockTransport(data: Data(), shouldTimeout: true)
        let client = try client(transport)
        for _ in 0..<2 {
            await #expect(throws: ContentError.connectionFailed) {
                try await client.fetchQuestions(categoryIDs: categoryIDs, gameID: "timeout-game")
            }
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func authenticationFailureCanRetrySameGameAfterSuccessfulLogin() async throws {
        let transport = MockTransport(data: Data("{\"code\":\"UNAUTHORIZED\"}".utf8), status: 401)
        let client = try client(transport)
        await #expect(throws: ContentError.unauthenticated) {
            try await client.fetchQuestions(categoryIDs: categoryIDs, gameID: "recoverable-game")
        }
        await transport.updateResponse(data: Data("""
        {"message":"login successful","requires_name":false,"user_id":"authenticated-user"}
        """.utf8))
        let login = try await client.verifyOTP(email: "player@example.com", otp: "ABC123")
        #expect(login.userID == "authenticated-user")
        await transport.updateResponse(data: try questionFixture())
        let queue = try await client.fetchQuestions(categoryIDs: categoryIDs, gameID: "recoverable-game")
        #expect(queue.count == 18)
        #expect(await transport.requests.filter { $0.url?.path == "/api/game/carmode_questions" }.count == 2)
    }

    @Test func rejectsHTTPAndCredentialBearingBaseURLs() {
        for raw in ["http://example.invalid", "https://user:password@example.invalid", "https://example.invalid?token=x"] {
            #expect(throws: ContentError.insecureBaseURL) {
                try NajeebAPIClient(baseURL: #require(URL(string: raw)))
            }
        }
    }

    @Test func returnsExplicitMalformedResponseFailure() async throws {
        let transport = MockTransport(data: Data("not JSON".utf8))
        await #expect(throws: ContentError.invalidResponse) {
            try await client(transport).fetchCategories()
        }
    }

    @Test func cookieAuthenticationAndLogoutUseTheSameSessionStorage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        let cookieStorage = try #require(configuration.httpCookieStorage)
        let baseURL = try #require(URL(string: "https://\(UUID().uuidString).example.invalid"))
        let host = try #require(baseURL.host)
        let cookie = try #require(HTTPCookie(properties: [
            .domain: host, .path: "/", .name: "session_token",
            .value: "test-session", .secure: "TRUE", .expires: Date().addingTimeInterval(60),
        ]))
        cookieStorage.setCookie(cookie)
        let transport = MockTransport(data: Data("{\"message\":\"logged out\"}".utf8))
        let client = try NajeebAPIClient(baseURL: baseURL, transport: transport, cookieStorage: cookieStorage)
        #expect(await client.hasSessionCookie())
        try await client.logout()
        #expect(!(await client.hasSessionCookie()))
        #expect(cookieStorage.cookies(for: baseURL)?.allSatisfy { $0.name != "session_token" } ?? true)
        #expect(await transport.requests.last?.url?.path == "/users/logout")
    }

    @Test func rejectsEveryKindOfQuestionMedia() async throws {
        for urls in [["https://example.invalid/clip.mp3"], ["https://example.invalid/picture.png"], ["unknown"], [" "]] {
            let transport = MockTransport(data: try questionFixture(mediaCategory: 2, mediaURLs: urls))
            await #expect(throws: ContentError.insufficientSafeQuestions(missing: [QuestionSlot(categoryID: "2", difficulty: .easy)])) {
                try await client(transport).fetchQuestions(categoryIDs: categoryIDs, gameID: "media-free")
            }
        }
    }

    @Test func answerAssetsAreIgnoredAndNeverCopiedToGameContent() async throws {
        var groups = try #require(JSONSerialization.jsonObject(with: questionFixture()) as? [String: [[String: Any]]])
        for category in categoryIDs {
            for index in 0..<3 {
                groups[category]?[index]["correct_answer_media"] = index == 0 ? ["https://example.invalid/answer.png"] : ["malformed": true]
            }
        }
        let transport = MockTransport(data: try JSONSerialization.data(withJSONObject: groups))
        let queue = try await client(transport).fetchQuestions(categoryIDs: categoryIDs, gameID: "answer-assets")
        #expect(queue.count == 18)
        let encoded = String(decoding: try JSONEncoder().encode(queue), as: UTF8.self)
        #expect(!encoded.contains("answer.png"))
        #expect(!encoded.contains("correct_answer_media"))
        #expect(queue.allSatisfy { $0.media == nil })
    }

    @Test func rejectsExtraMissingAndDuplicatedRawQuestionContent() async throws {
        let base = try #require(JSONSerialization.jsonObject(with: questionFixture()) as? [String: [[String: Any]]])
        var extra = base
        extra["7"] = base["1"]
        var missing = base
        missing["2"]?.removeLast()
        var duplicate = base
        duplicate["2"]?[0]["id"] = base["1"]?[0]["id"]
        for groups in [extra, missing, duplicate] {
            let transport = MockTransport(data: try JSONSerialization.data(withJSONObject: groups))
            do {
                _ = try await client(transport).fetchQuestions(categoryIDs: categoryIDs, gameID: "invalid-contract")
                Issue.record("Malformed car-mode content must never be playable")
            } catch ContentError.invalidContent { }
        }
    }

    @Test func rejectsNonCanonicalDeployedDifficultyWithoutRelabelling() async throws {
        var groups = try #require(JSONSerialization.jsonObject(with: questionFixture()) as? [String: [[String: Any]]])
        for category in categoryIDs {
            for (index, points) in [200, 400, 600].enumerated() {
                groups[category]?[index]["difficulty"] = points
                groups[category]?[index]["source_difficulty"] = points
            }
        }
        let transport = MockTransport(data: try JSONSerialization.data(withJSONObject: groups))
        do {
            _ = try await client(transport).fetchQuestions(categoryIDs: categoryIDs, gameID: "incorrect-deployment")
            Issue.record("Wrong deployed difficulty values must not be relabelled")
        } catch ContentError.insufficientSafeQuestions(let missing) { #expect(missing.count == 18) }
    }

    @Test func returnsExplicitCarModeUnavailableErrorWithoutFallingBackToRegularRoute() async throws {
        let transport = MockTransport(data: Data("{\"code\":\"CARMODE_QUESTIONS_UNAVAILABLE\"}".utf8), status: 422)
        await #expect(throws: ContentError.carModeQuestionsUnavailable) {
            try await client(transport).fetchQuestions(categoryIDs: categoryIDs, gameID: "unavailable")
        }
        #expect(await transport.requests.count == 1)
        #expect(await transport.requests.first?.url?.path == "/api/game/carmode_questions")
    }

    @Test func mapsOTPStatusCodesToSafeActionableErrors() async throws {
        for (status, code, expected) in [
            (429, "OTP_LOCKED", ContentError.otpLocked),
            (429, "RATE_LIMITED", .otpRateLimited),
            (503, "EMAIL_SERVICE_UNAVAILABLE", .emailServiceUnavailable),
            (500, "EMAIL_SEND_FAILED", .otpEmailSendFailed),
        ] {
            let transport = MockTransport(data: Data("{\"code\":\"\(code)\",\"message\":\"private/server/detail\"}".utf8), status: status)
            await #expect(throws: expected) {
                try await client(transport).requestOTP(email: "player@example.com")
            }
            #expect(!(expected.errorDescription ?? "").contains("private/server/detail"))
            #expect(!(expected.errorDescription ?? "").contains("الأسئلة"))
            #expect(await transport.requests.count == 1)
        }
    }

    @Test func invalidAndExpiredOTPHaveTheSameSafeVerificationMessage() async throws {
        let transport = MockTransport(data: Data("{\"code\":\"INVALID_OTP\",\"message\":\"private/otp/detail\"}".utf8), status: 400)
        await #expect(throws: ContentError.invalidOTP) {
            try await client(transport).verifyOTP(email: "player@example.com", otp: "ABC123")
        }
        #expect((ContentError.invalidOTP.errorDescription ?? "").contains("آخر رمز"))
        await transport.updateResponse(data: Data("{\"code\":\"OTP_LOCKED\"}".utf8), status: 429)
        await #expect(throws: ContentError.otpLocked) {
            try await client(transport).verifyOTP(email: "player@example.com", otp: "ABC123")
        }
    }

    @Test func unknownOTPServerFailuresDoNotInventEmailServiceCauses() async throws {
        let transport = MockTransport(data: Data("{\"message\":\"internal/email/config/detail\"}".utf8), status: 500)
        let client = try client(transport)
        await #expect(throws: ContentError.otpRequestFailed) { try await client.requestOTP(email: "player@example.com") }
        await #expect(throws: ContentError.otpVerificationFailed) {
            try await client.verifyOTP(email: "player@example.com", otp: "ABC123")
        }
        #expect(!(ContentError.otpRequestFailed.errorDescription ?? "").contains("config"))
        #expect(await transport.requests.count == 2)
    }

    @Test func OTPConnectivityAndMalformedResponsesNeverUseTriviaMessages() async throws {
        let timeout = MockTransport(data: Data(), shouldTimeout: true)
        await #expect(throws: ContentError.otpConnectionFailed) {
            try await client(timeout).requestOTP(email: "player@example.com")
        }
        #expect(await timeout.requests.count == 1)
        let malformed = MockTransport(data: Data("not JSON".utf8))
        await #expect(throws: ContentError.otpInvalidResponse) {
            try await client(malformed).requestOTP(email: "player@example.com")
        }
        await malformed.updateResponse(data: Data("{\"message\":\"ok\",\"requires_name\":false}".utf8))
        await #expect(throws: ContentError.otpInvalidResponse) {
            try await client(malformed).verifyOTP(email: "player@example.com", otp: "ABC123")
        }
        #expect(!(ContentError.otpConnectionFailed.errorDescription ?? "").contains("محفوظة"))
        #expect(!(ContentError.otpInvalidResponse.errorDescription ?? "").contains("الأسئلة"))
    }

    @Test func backendOTPInputRejectionDoesNotExposeRawValidationDetails() async throws {
        let transport = MockTransport(data: Data("{\"code\":\"INVALID_INPUT\",\"message\":\"private/validation/detail\"}".utf8), status: 400)
        do {
            try await client(transport).requestOTP(email: "player@example.com")
            Issue.record("Expected safe email input guidance")
        } catch ContentError.invalidInput(let message) {
            #expect(message.contains("البريد"))
            #expect(!message.contains("private/validation/detail"))
        }
    }

    private var categoryIDs: [String] { (1...6).map(String.init) }

    private func client(_ transport: MockTransport) throws -> NajeebAPIClient {
        try NajeebAPIClient(baseURL: #require(URL(string: "https://\(UUID().uuidString).example.invalid/api")), transport: transport)
    }

    /// These are test placeholders, never production trivia or an offline game catalog.
    private func questionFixture(
        mediaCategory: Int? = nil, fallbackCategory: Int? = nil,
        mediaURLs: [String] = ["https://example.invalid/fixture.png"]
    ) throws -> Data {
        var groups: [String: [[String: Any]]] = [:]
        for category in 1...6 {
            groups[String(category)] = [100, 300, 500].map { difficulty in
                [
                    "id": "fixture-\(category)-\(difficulty)",
                    "question_text": "سؤال اختباري للفئة \(category) في المستوى \(difficulty)؟",
                    "difficulty": difficulty,
                    "source_difficulty": category == fallbackCategory && difficulty == 500 ? 300 : difficulty,
                    "correct_answer": "جواب اختباري \(category)",
                    "media": category == mediaCategory && difficulty == 100 ? mediaURLs : [],
                    "correct_answer_media": [],
                    "type": "CLASSIC",
                ]
            }
        }
        return try JSONSerialization.data(withJSONObject: groups)
    }


}

private actor MockTransport: HTTPTransport {
    var fixture: Data
    var status: Int
    let shouldTimeout: Bool
    var requests: [URLRequest] = []

    init(data: Data, status: Int = 200, shouldTimeout: Bool = false) {
        fixture = data
        self.status = status
        self.shouldTimeout = shouldTimeout
    }

    func updateResponse(data: Data, status: Int = 200) {
        fixture = data
        self.status = status
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        await Task.yield()
        if shouldTimeout { throw URLError(.timedOut) }
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (fixture, response)
    }
}

private struct QuestionsBody: Decodable {
    let categories: [Int]
    let analytics_game_id: String
}

private struct VerifyBody: Decodable {
    let email: String
    let otp: String
    let name: String?
}
