import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class URLSessionHTTPTransport: HTTPTransport, Sendable {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .default) {
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ContentError.invalidResponse }
        return (data, response)
    }
}

public actor NajeebAPIClient {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let cookieStorage: HTTPCookieStorage
    private var categories: [GameCategory] = []
    private var preparedGames: [String: [TriviaQuestion]] = [:]
    private var pendingGames: [String: Task<[TriviaQuestion], Error>] = [:]

    public init(
        baseURL: URL,
        transport: (any HTTPTransport)? = nil,
        cookieStorage: HTTPCookieStorage = .shared
    ) throws {
        guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil,
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil
        else { throw ContentError.insecureBaseURL }
        self.baseURL = baseURL
        self.cookieStorage = cookieStorage
        if let transport {
            self.transport = transport
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = cookieStorage
            self.transport = URLSessionHTTPTransport(configuration: configuration)
        }
    }

    public func fetchCategories() async throws -> [GameCategory] {
        let catalog: CategoryCatalog = try await request(path: "game/categories")
        var seen = Set<Int>()
        categories = try catalog.categories.filter { $0.active != false }.map { category in
            guard category.id > 0, !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(category.id).inserted else {
                throw ContentError.invalidContent("Invalid or duplicate catalog category")
            }
            let sections = catalog.sections.filter { section in
                section.categories.contains { $0.id == category.id }
            }.map(\.name)
            return GameCategory(
                id: String(category.id), name: category.name,
                interests: [category.name] + sections,
                description: category.description
            )
        }
        guard !categories.isEmpty else { throw ContentError.invalidContent("Empty category catalog") }
        return categories
    }

    /// Fetch once per native game. The backend charges its game-creation quota and records history.
    /// Concurrent/repeated calls with the same configuration return the same success or failure.
    public func fetchQuestions(categoryIDs: [String], gameID: String) async throws -> [TriviaQuestion] {
        guard categoryIDs.count == 6, Set(categoryIDs).count == 6 else {
            throw ContentError.invalidInput("اختاروا ست فئات مختلفة أول.")
        }
        let numericIDs = try categoryIDs.map { id in
            guard let number = Int(id), number > 0, number <= Int(Int32.max), String(number) == id else {
                throw ContentError.invalidInput("رقم الفئة غير صحيح.")
            }
            return number
        }
        guard !gameID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContentError.invalidInput("معرّف اللعبة مطلوب.")
        }
        if !categories.isEmpty {
            let catalogIDs = Set(categories.map(\.id))
            guard categoryIDs.allSatisfy(catalogIDs.contains) else {
                throw ContentError.invalidInput("فيه فئة مو موجودة في قائمة نجيب.")
            }
        }
        let cacheKey = "carmode-v1:" + gameID + ":" + categoryIDs.joined(separator: ",")
        if let prepared = preparedGames[cacheKey] { return prepared }
        if let pending = pendingGames[cacheKey] { return try await pending.value }

        let task = Task<[TriviaQuestion], Error> {
            let groups: [String: [BackendQuestion]] = try await self.request(
                path: "game/carmode_questions", method: "POST",
                body: QuestionsRequest(categories: numericIDs, analyticsGameID: gameID)
            )
            return try DrivingQuestionFilter.selectQueue(from: groups, categoryIDs: categoryIDs)
        }
        pendingGames[cacheKey] = task
        do {
            let queue = try await task.value
            preparedGames[cacheKey] = queue
            pendingGames[cacheKey] = nil
            return queue
        } catch {
            // A 401 occurs before game creation. Login can safely retry this same configuration.
            // Retain other failures: a timeout may follow a committed backend quota/history change.
            if error as? ContentError == .unauthenticated { pendingGames[cacheKey] = nil }
            throw error
        }
    }

    public func fetchHelper(_ helper: HelperID, questionID: String, categoryID: String) async throws -> HelperContent {
        struct Response: Decodable { let questionID: String; let hint: String?; let choices: [String]?
            enum CodingKeys: String, CodingKey { case questionID = "question_id"; case hint, choices }
        }
        struct Request: Encodable { let question_id: String; let category_id: Int? }
        guard !questionID.isEmpty, let category = Int(categoryID), category > 0,
              helper == .hint || helper == .choices else { throw ContentError.invalidInput("المساعدة غير صحيحة.") }
        let response: Response = try await request(
            path: "game/question/\(helper == .hint ? "hint" : "choices")", method: "POST",
            body: Request(question_id: questionID, category_id: helper == .choices ? category : nil)
        )
        guard response.questionID == questionID else { throw ContentError.invalidResponse }
        if helper == .hint, let text = response.hint, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .hint(text)
        }
        if helper == .choices, let items = response.choices, items.count == 4 { return .choices(items) }
        throw ContentError.invalidResponse
    }

    public func requestOTP(email: String) async throws {
        let email = try normalizedEmail(email)
        let _: MessageResponse = try await request(
            path: "users/login", method: "POST", body: OTPRequest(email: email), purpose: .otpRequest
        )
    }

    public func verifyOTP(email: String, otp: String, name: String? = nil) async throws -> LoginResult {
        let email = try normalizedEmail(email)
        let otp = otp.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard otp.count == 6, otp.unicodeScalars.allSatisfy({
            (65...90).contains($0.value) || (48...57).contains($0.value)
        }) else { throw ContentError.invalidInput("اكتب رمز التحقق المكوّن من ستة حروف أو أرقام.") }
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, name.isEmpty {
            throw ContentError.invalidInput("اكتب اسمك عشان نكمل حسابك.")
        }
        if let name, name.count > 255 {
            throw ContentError.invalidInput("الاسم طويل مرة. اختصره شوي.")
        }
        let result: LoginResult = try await request(
            path: "users/check_otp", method: "POST", body: VerifyOTPRequest(email: email, otp: otp, name: name),
            purpose: .otpVerification
        )
        if !result.requiresName {
            guard let userID = result.userID, !userID.isEmpty else { throw ContentError.otpInvalidResponse }
        }
        return result
    }

    /// Cookie presence is a local hint; protected requests verify authentication on the server.
    public func hasSessionCookie() -> Bool {
        cookieStorage.cookies(for: baseURL)?.contains {
            $0.name == "session_token" && !$0.value.isEmpty && ($0.expiresDate.map { $0 > Date() } ?? true)
        } ?? false
    }

    public func logout() async throws {
        let _: MessageResponse = try await request(path: "users/logout", method: "POST", body: EmptyRequest())
        preparedGames = [:]
        for task in pendingGames.values { task.cancel() }
        pendingGames = [:]
        for cookie in cookieStorage.cookies(for: baseURL) ?? [] where cookie.name == "session_token" {
            cookieStorage.deleteCookie(cookie)
        }
    }

    private func request<Response: Decodable>(path: String) async throws -> Response {
        try await request(path: path, method: "GET", body: Optional<EmptyRequest>.none)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String, method: String, body: Body?, purpose: RequestPurpose = .general
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw purpose == .general ? ContentError.connectionFailed : ContentError.otpConnectionFailed }
        let succeeded = (200...299).contains(response.statusCode)
        let code = succeeded ? nil : (try? JSONDecoder().decode(BackendError.self, from: data).code)
        if purpose != .general, !succeeded {
            throw otpError(status: response.statusCode, code: code, purpose: purpose)
        }
        switch response.statusCode {
        case 200...299: break
        case 401:
            throw ContentError.unauthenticated
        case 429:
            throw ContentError.rateLimited(code: code)
        case 422:
            if code == "CARMODE_QUESTIONS_UNAVAILABLE" { throw ContentError.carModeQuestionsUnavailable }
            throw ContentError.server(status: 422, code: code)
        default:
            throw ContentError.server(status: response.statusCode, code: code)
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw purpose == .general ? ContentError.invalidResponse : ContentError.otpInvalidResponse }
    }

    private func otpError(status: Int, code: String?, purpose: RequestPurpose) -> ContentError {
        switch code {
        case "OTP_LOCKED": return .otpLocked
        case "INVALID_OTP": return .invalidOTP
        case "EMAIL_SERVICE_UNAVAILABLE": return .emailServiceUnavailable
        case "EMAIL_SEND_FAILED": return .otpEmailSendFailed
        case "INVALID_INPUT":
            return .invalidInput(purpose == .otpRequest ? "تأكد من البريد الإلكتروني واكتبه بشكل صحيح." : "تأكد من البريد ورمز الدخول والاسم ثم جرّب مرة ثانية.")
        default:
            if status == 429 { return .otpRateLimited }
            return purpose == .otpRequest ? .otpRequestFailed : .otpVerificationFailed
        }
    }

    private func normalizedEmail(_ raw: String) throws -> String {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !email.contains(where: \.isWhitespace), email.count <= 254 else {
            throw ContentError.invalidInput("اكتب بريد إلكتروني صحيح.")
        }
        return email
    }
}

private enum RequestPurpose { case general, otpRequest, otpVerification }

private struct QuestionsRequest: Encodable, Sendable {
    let categories: [Int]
    let analyticsGameID: String
    enum CodingKeys: String, CodingKey {
        case categories
        case analyticsGameID = "analytics_game_id"
    }
}
private struct OTPRequest: Encodable { let email: String }
private struct VerifyOTPRequest: Encodable { let email: String; let otp: String; let name: String? }
private struct EmptyRequest: Encodable {}
private struct MessageResponse: Decodable { let message: String }
