import Foundation

public enum AnswerNormalizer {
    public static func normalize(_ input: String) -> String {
        let replacements: [Character: Character] = [
            "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي", "ؤ": "و", "ئ": "ي", "ة": "ه", "ک": "ك", "ی": "ي",
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4", "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]
        let scalars = input.lowercased().unicodeScalars.filter { scalar in
            let value = scalar.value
            return value != 0x0640 && !(0x064B...0x065F).contains(value) &&
                value != 0x0670 && !(0x06D6...0x06ED).contains(value)
        }
        let text = String(String.UnicodeScalarView(scalars)).map { replacements[$0] ?? $0 }
        let cleaned = String(text).unicodeScalars.map { scalar -> String in
            CharacterSet.punctuationCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

}

public enum VoiceRequest {
    private static let wakePrefixes = ["يا نجيب", "يانجيب", "ينجيب", "ي نجيب"]
    private static let fillers: Set<String> = ["طيب", "تمام", "يلا", "اوكي", "خلاص", "اه", "امم", "اممم"]
    private static let quotationPrefixes: Set<String> = ["قال", "قالت", "يقول", "تقول", "تقولون", "قولوا", "قلت", "لو", "مثال", "مثلا"]
    private static let submissionPrefixes = [
        "اجابتنا النهائيه هي", "اجابتنا النهائيه", "اجابتنا هي", "اجابتنا",
        "جوابنا النهائي هو", "جوابنا النهائي", "جوابنا هو", "جوابنا",
        "الاجابه النهائيه هي", "الاجابه النهائيه",
        "حنا اجابتنا هي", "حنا اجابتنا", "احنا اجابتنا هي", "احنا اجابتنا",
        "حنا نعتمد", "احنا نعتمد", "نحن نعتمد", "نعتمد الاجابه", "نعتمد اجابه", "نعتمد"
    ].map(AnswerNormalizer.normalize).sorted { $0.count > $1.count }

    public static func isAddressed(_ text: String) -> Bool {
        let normalized = requestText(text)
        return normalized == "نجيب" || wakePrefix(normalized) != nil
    }

    public static func isDirected(_ text: String) -> Bool {
        isAddressed(text) || submissionPrefix(requestText(text)) != nil
    }

    public static func answerText(_ text: String) -> String {
        var answer = requestText(text)
        if answer == "نجيب" { return "" }
        if let prefix = wakePrefix(answer) { answer = removingFillers(removing(prefix, from: answer)) }
        if let prefix = submissionPrefix(answer) {
            answer = removingFillers(removing(prefix, from: answer))
            let preposition = AnswerNormalizer.normalize("على")
            if matches(preposition, in: answer) { answer = removingFillers(removing(preposition, from: answer)) }
        } else if let prefix = ["الاجابه هي", "الاجابه"].first(where: { matches($0, in: answer) }) {
            answer = removingFillers(removing(prefix, from: answer))
        }
        return answer
    }

    public static func matchesAnswer(_ answer: String, transcript: String) -> Bool {
        let submitted = AnswerNormalizer.normalize(answer)
        guard !submitted.isEmpty else { return false }
        if submitted == AnswerNormalizer.normalize(transcript) { return true }
        let actualAnswer = answerText(transcript)
        return !actualAnswer.isEmpty && answerText(answer) == actualAnswer
    }

    private static func requestText(_ text: String) -> String {
        let normalized = AnswerNormalizer.normalize(text)
        let words = normalized.split(separator: " ").map(String.init)
        // ASR can merge team discussion and a subsequent direct call into one transcript.
        for index in words.indices.reversed() {
            let suffix = words[index...].joined(separator: " ")
            guard wakePrefix(suffix) != nil else { continue }
            var preceding = words[..<index].reversed().drop(while: isFiller)
            if let word = preceding.first, ["لي", "له", "لها", "لهم", "لنا"].contains(word) {
                preceding = preceding.dropFirst()
            }
            if let word = preceding.first, quotationPrefixes.contains(word) { continue }
            return suffix
        }
        return removingFillers(normalized)
    }

    private static func wakePrefix(_ text: String) -> String? {
        wakePrefixes.first { matches($0, in: text) }
    }

    private static func removingFillers(_ text: String) -> String {
        text.split(separator: " ").map(String.init).drop(while: isFiller).joined(separator: " ")
    }

    private static func isFiller(_ word: String) -> Bool {
        fillers.contains(word) || (word.count > 1 && word.allSatisfy { $0 == "ا" })
    }

    private static func submissionPrefix(_ text: String) -> String? {
        submissionPrefixes.first { matches($0, in: text) }
    }

    private static func matches(_ prefix: String, in text: String) -> Bool {
        text == prefix || text.hasPrefix(prefix + " ")
    }

    private static func removing(_ prefix: String, from text: String) -> String {
        String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}

/// Transient conversation authorization, scoped to one question/turn; never persisted with game state.
public struct VoiceInputGate: Sendable {
    public enum Decision: String, Sendable { case discussion, activation, request }
    public private(set) var decision: Decision = .discussion
    private var questionToken: String?
    private var armedUntil: Date?
    private let windowDuration: TimeInterval

    public init(windowDuration: TimeInterval = 8) { self.windowDuration = windowDuration }

    public mutating func synchronize(questionToken: String?) {
        if self.questionToken != questionToken {
            self.questionToken = questionToken
            closeWindow()
        }
    }

    public mutating func receive(_ text: String, questionToken: String?, now: Date = Date()) -> Decision {
        synchronize(questionToken: questionToken)
        guard questionToken != nil else { decision = .request; return decision }
        let directed = VoiceRequest.isDirected(text)
        guard directed || isWindowOpen(now: now) else { decision = .discussion; return decision }
        guard !AnswerNormalizer.normalize(text).isEmpty else { decision = .discussion; return decision }
        armedUntil = now.addingTimeInterval(windowDuration)
        decision = directed && VoiceRequest.answerText(text).isEmpty ? .activation : .request
        return decision
    }

    public func isWindowOpen(now: Date = Date()) -> Bool {
        armedUntil.map { now < $0 } ?? false
    }

    public func authorizesRequest(questionToken: String?) -> Bool {
        questionToken != nil && questionToken == self.questionToken && decision == .request
    }

    public mutating func closeWindow() {
        armedUntil = nil
        decision = .discussion
    }
}
