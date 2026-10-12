import Foundation

public enum ContentError: Error, LocalizedError, Sendable, Equatable {
    case insecureBaseURL
    case invalidInput(String)
    case unauthenticated
    case rateLimited(code: String?)
    case server(status: Int, code: String?)
    case invalidResponse
    case connectionFailed
    case invalidContent(String)
    case insufficientSafeQuestions(missing: [QuestionSlot])
    case carModeQuestionsUnavailable
    case otpLocked
    case otpRateLimited
    case emailServiceUnavailable
    case otpEmailSendFailed
    case invalidOTP
    case otpRequestFailed
    case otpVerificationFailed
    case otpConnectionFailed
    case otpInvalidResponse

    public var errorDescription: String? {
        switch self {
        case .insecureBaseURL:
            "رابط خدمة نجيب لازم يستخدم اتصال HTTPS."
        case .invalidInput(let reason):
            reason
        case .unauthenticated:
            "سجّل دخولك في تطبيق الآيفون قبل بدء المسابقة."
        case .rateLimited:
            "وصلنا الحد المسموح للمحاولات. جرّب مرة ثانية لاحقًا."
        case .server:
            "خدمة نجيب ما قدرت تكمل الطلب الحين. جرّب مرة ثانية."
        case .invalidResponse, .invalidContent:
            "بيانات الأسئلة ما اكتملت. جرّب مرة ثانية أو اختر فئات ثانية."
        case .connectionFailed:
            "الاتصال بخدمة نجيب انقطع. اللعبة محفوظة، نقدر نكمل إذا رجع الاتصال."
        case .insufficientSafeQuestions:
            "ما لقينا أسئلة مناسبة كافية لكل الفئات والمستويات. اختر فئات ثانية قبل بدء اللعبة."
        case .carModeQuestionsUnavailable:
            "ما توفرت أسئلة منطوقة بدون وسائط لكل الفئات والمستويات. غيّر الفئات أو ابدأ لعبة جديدة."
        case .otpLocked:
            "توقفت محاولات الدخول مؤقتًا لكثرة المحاولات الخاطئة. انتظر حتى تنتهي مدة الإيقاف، اللي قد تصل إلى ساعة، ثم جرّب."
        case .otpRateLimited:
            "طلبات رمز الدخول كثيرة الحين. انتظر شوي ثم جرّب مرة ثانية."
        case .emailServiceUnavailable:
            "خدمة إرسال رمز الدخول غير متاحة الحين. جرّب لاحقًا."
        case .otpEmailSendFailed, .otpRequestFailed:
            "ما قدرنا نرسل رمز الدخول الحين. تأكد من البريد وجرّب مرة ثانية."
        case .invalidOTP:
            "رمز الدخول غير صحيح أو انتهت صلاحيته. اكتب آخر رمز وصلك أو اطلب رمز جديد."
        case .otpVerificationFailed:
            "ما قدرنا نتحقق من رمز الدخول الحين. جرّب مرة ثانية."
        case .otpConnectionFailed:
            "الاتصال بخدمة الدخول انقطع. تأكد من الإنترنت وجرّب مرة ثانية."
        case .otpInvalidResponse:
            "رد خدمة الدخول ما اكتمل. جرّب مرة ثانية بعد شوي."
        }
    }
}

public struct QuestionSlot: Codable, Sendable, Equatable {
    public let categoryID: String
    public let difficulty: Difficulty

    public init(categoryID: String, difficulty: Difficulty) {
        self.categoryID = categoryID
        self.difficulty = difficulty
    }
}

public struct LoginResult: Decodable, Sendable, Equatable {
    public let requiresName: Bool
    public let newUser: Bool
    public let userID: String?

    enum CodingKeys: String, CodingKey {
        case requiresName = "requires_name"
        case newUser = "new_user"
        case userID = "user_id"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requiresName = try values.decodeIfPresent(Bool.self, forKey: .requiresName) ?? false
        newUser = try values.decodeIfPresent(Bool.self, forKey: .newUser) ?? false
        userID = try values.decodeIfPresent(String.self, forKey: .userID)
    }
}

struct CategoryCatalog: Decodable {
    let categories: [BackendCategory]
    let sections: [BackendSection]

    enum CodingKeys: String, CodingKey { case categories, sections }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        categories = try values.decode([BackendCategory].self, forKey: .categories)
        sections = try values.decodeIfPresent([BackendSection].self, forKey: .sections) ?? []
    }
}

struct BackendCategory: Decodable {
    let id: Int
    let name: String
    let description: String?
    let active: Bool?
}

struct BackendSection: Decodable {
    let name: String
    let categories: [BackendCategory]
}

struct BackendQuestion: Decodable, Sendable {
    let id: String
    let text: String
    let difficulty: Int
    let sourceDifficulty: Int
    let correctAnswer: String
    let media: [String]
    let type: String

    enum CodingKeys: String, CodingKey {
        case id, difficulty, media, type
        case text = "question_text"
        case sourceDifficulty = "source_difficulty"
        case correctAnswer = "correct_answer"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        difficulty = try values.decode(Int.self, forKey: .difficulty)
        sourceDifficulty = try values.decodeIfPresent(Int.self, forKey: .sourceDifficulty) ?? difficulty
        correctAnswer = try values.decode(String.self, forKey: .correctAnswer)
        media = try values.decodeIfPresent([String].self, forKey: .media) ?? []
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "CLASSIC"
    }
}

struct BackendError: Decodable {
    let code: String?
}
