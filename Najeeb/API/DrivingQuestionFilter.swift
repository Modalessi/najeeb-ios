import Foundation

/// Car-mode content must be fully answerable as spoken text, with no question media.
public enum DrivingQuestionFilter {
    public static func isTextAudioCompatible(question: String, answer: String) -> Bool {
        let text = normalize(question)
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !answer.isEmpty else { return false }

        let visualOrMediaWords: Set<String> = [
            "صورة", "الصورة", "صوره", "الصوره", "صور", "الصور", "الصورتين", "الصورتان",
            "شعار", "الشعار", "شعارات", "الشعارات", "الرسم", "ارسم", "المرئي",
            "فيديو", "الفيديو", "خريطة", "الخريطة", "خريطه", "الخريطه", "الشكل",
            "اشكال", "الاشكال", "المعروض", "الظاهر", "المرفق", "المرفقة", "المرفقه",
            "استمع", "اسمع", "المقطع", "مقطع", "الصوت", "المسموع", "التسجيل",
            "image", "pictured", "photo", "picture", "shown", "logo", "diagram", "video",
            "clip", "listen", "audio", "sound", "draw", "drawing", "screenshot", "map",
        ]
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard words.allSatisfy({ word in
            !visualOrMediaWords.contains(word)
                && !["ب", "و", "ل", "بال", "وال", "لل"].contains(where: { prefix in
                    word.hasPrefix(prefix) && visualOrMediaWords.contains(String(word.dropFirst(prefix.count)))
                })
        }) else { return false }
        let visualReferences = ["امامك", "قدامك", "الموضح", "ما تشاهد", "ما تري", "انظر الي", "look at"]
        return visualReferences.allSatisfy { !text.contains($0) }
    }

    static func isCompatible(_ question: BackendQuestion) -> Bool {
        question.type == "CLASSIC" && question.media.isEmpty &&
            isTextAudioCompatible(question: question.text, answer: question.correctAnswer)
    }

    static func selectQueue(
        from groups: [String: [BackendQuestion]], categoryIDs: [String]
    ) throws -> [TriviaQuestion] {
        guard Set(groups.keys) == Set(categoryIDs), groups.values.allSatisfy({ $0.count == 3 }),
              groups.values.reduce(0, { $0 + $1.count }) == 18 else {
            throw ContentError.invalidContent("Expected exactly three questions per selected category")
        }
        let rawQuestions = groups.values.flatMap { $0 }
        guard rawQuestions.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(rawQuestions.map(\.id)).count == 18 else {
            throw ContentError.invalidContent("Invalid or duplicate question identifiers")
        }
        var queue: [TriviaQuestion] = []
        var missing: [QuestionSlot] = []
        for difficulty in Difficulty.allCases {
            for categoryID in categoryIDs {
                let candidates = (groups[categoryID] ?? []).filter {
                    $0.difficulty == difficulty.points && $0.sourceDifficulty == difficulty.points && isCompatible($0)
                }
                guard candidates.count == 1, let question = candidates.first else {
                    missing.append(QuestionSlot(categoryID: categoryID, difficulty: difficulty))
                    continue
                }
                queue.append(TriviaQuestion(
                    id: question.id, categoryID: categoryID, difficulty: difficulty,
                    text: question.text, correctAnswer: question.correctAnswer,
                    sourceDifficultyPoints: question.sourceDifficulty
                ))
            }
        }
        guard missing.isEmpty else { throw ContentError.insufficientSafeQuestions(missing: missing) }
        return queue
    }

    private static func normalize(_ value: String) -> String {
        let stripped = value.unicodeScalars.filter { scalar in
            !CharacterSet.nonBaseCharacters.contains(scalar) && scalar.value != 0x0640
        }
        return String(String.UnicodeScalarView(stripped))
            .lowercased()
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
