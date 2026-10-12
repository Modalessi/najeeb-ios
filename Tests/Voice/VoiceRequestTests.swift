import Foundation
import Testing
@testable import NajeebLogic

struct VoiceRequestTests {
    @Test(arguments: ["يا نجيب", "يانجيب", "ينجيب", "ي نجيب", "يَا نَجِيب", "يَنَجِيب", "طيب، يا نجيب", "نجيب"])
    func activationVariants(_ text: String) {
        #expect(VoiceRequest.isAddressed(text))
        #expect(VoiceRequest.answerText(text).isEmpty)
    }

    @Test(arguments: ["حنا نعتمد الرياض", "إجابتنا هي الرياض", "احنا نعتمد الرياض", "نعتمد الرياض",
                      "جوابنا هو الرياض", "إجابتنا النهائية هي الرياض", "طيب حنا نعتمد على الرياض",
                      "يانجيب، إجابتنا هي الرياض", "حنا إجابتنا هي الرياض"])
    func explicitSubmissions(_ text: String) {
        #expect(VoiceRequest.isDirected(text))
        #expect(VoiceRequest.answerText(text) == "الرياض")
    }

    @Test(arguments: ["وش رايكم نعتمد الرياض؟", "يمكن الرياض", "نجيب يعرف الإجابة", "قال يا نجيب الرياض",
                      "ما نعتمد الرياض", "لو إجابتنا هي الرياض", "تتوقعون الإجابة الرياض؟", "الرياض"])
    func discussionDoesNotActivate(_ text: String) {
        #expect(!VoiceRequest.isDirected(text))
    }

    @Test(arguments: ["حنا نعتمد", "إجابتنا هي", "حنا نعتمد على", "جوابنا هو", "يا نجيب إجابتنا هي"])
    func incompleteSubmissionDoesNotContainAnAnswer(_ text: String) {
        #expect(VoiceRequest.isDirected(text))
        #expect(VoiceRequest.answerText(text).isEmpty)
    }

    @Test(arguments: [
        "وهذي فيها شوية بق كذا. أعطيني فرصة أصلح عليها، بس أنا لازم الظاهر تكون، آآآ، مـ-مرتبة. يا نجيب، إجابتنا هي جار.",
        "خلنا نتشاور شوي، خلاص يانجيب إجابتنا هي جار",
        "أظن عرفناها. ينجيب، جوابنا هو جار",
        "آآآ، يَا نَجِيب، آآآ، إجابتنا هي، آآآ، جار"
    ])
    func directCallCanFollowDiscussionAndHesitation(_ text: String) {
        #expect(VoiceRequest.isAddressed(text))
        #expect(VoiceRequest.answerText(text) == "جار")
        var gate = VoiceInputGate()
        #expect(gate.receive(text, questionToken: "turn1") == .request)
        #expect(gate.authorizesRequest(questionToken: "turn1"))
    }

    @Test(arguments: ["يا نجيب", "يانجيب", "ينجيب", "ي نجيب"])
    func helpersAndSplitActivationUseTheSameVariants(_ name: String) {
        let start = Date(timeIntervalSince1970: 100)
        var gate = VoiceInputGate()
        #expect(gate.receive("خلنا نفكر. \(name)", questionToken: "turn1", now: start) == .activation)
        #expect(gate.receive("نبي تلميح", questionToken: "turn1", now: start.addingTimeInterval(2)) == .request)
        gate.closeWindow()
        #expect(gate.receive("نتفق على مساعدة. \(name)، نبي خيارات", questionToken: "turn1", now: start) == .request)
    }

    @Test(arguments: ["قال يا نجيب الرياض", "تقولون آآآ يا نجيب إجابتنا هي جار", "لو يا نجيب الرياض", "يانجيبة الرياض", "ينجيبون الرياض"])
    func quotedHypotheticalAndPartialNamesDoNotActivate(_ text: String) {
        #expect(!VoiceRequest.isAddressed(text))
        #expect(!VoiceRequest.isDirected(text))
    }

    @Test func extractedAnswerMatchesWithoutAllowingTheReferenceToReplaceIt() {
        let transcript = "وهذي فيها شوية بق كذا. أعطيني فرصة أصلح عليها، بس أنا لازم الظاهر تكون، آآآ، مـ-مرتبة. يا نجيب، إجابتنا هي جار."
        #expect(VoiceRequest.matchesAnswer(transcript, transcript: transcript))
        #expect(VoiceRequest.matchesAnswer("جار", transcript: transcript))
        #expect(VoiceRequest.matchesAnswer("إجابتنا هي جار", transcript: transcript))
        #expect(VoiceRequest.matchesAnswer("جار", transcript: "يا نجيب، إجابتنا هي جار."))
        #expect(!VoiceRequest.matchesAnswer("جاري", transcript: transcript))
        #expect(!VoiceRequest.matchesAnswer("الرياض", transcript: transcript))
        #expect(!VoiceRequest.matchesAnswer("جار", transcript: "يا نجيب، إجابتنا هي جار أو الرياض"))
        #expect(!VoiceRequest.matchesAnswer("", transcript: transcript))
    }

    @Test func separateUtteranceIsAuthorizedOnlyDuringTheWindow() {
        let start = Date(timeIntervalSince1970: 100)
        var gate = VoiceInputGate()
        #expect(gate.receive("يا نجيب", questionToken: "turn1", now: start) == .activation)
        #expect(!gate.authorizesRequest(questionToken: "turn1"))
        #expect(gate.receive("الرياض", questionToken: "turn1", now: start.addingTimeInterval(4)) == .request)
        #expect(gate.authorizesRequest(questionToken: "turn1"))
        gate.closeWindow()
        #expect(gate.receive("باريس", questionToken: "turn1", now: start.addingTimeInterval(5)) == .discussion)
        #expect(!gate.authorizesRequest(questionToken: "turn1"))
    }

    @Test func windowExpiresAndCannotCrossQuestionsOrBombTurns() {
        let start = Date(timeIntervalSince1970: 100)
        var gate = VoiceInputGate()
        _ = gate.receive("يانجيب", questionToken: "turn1", now: start)
        #expect(gate.receive("الرياض", questionToken: "turn1", now: start.addingTimeInterval(8)) == .discussion)
        _ = gate.receive("حنا نعتمد", questionToken: "turn1", now: start)
        #expect(gate.receive("الرياض", questionToken: "turn1-bomb", now: start.addingTimeInterval(1)) == .discussion)
        _ = gate.receive("يا نجيب", questionToken: "turn1-bomb", now: start)
        gate.synchronize(questionToken: nil)
        #expect(!gate.isWindowOpen(now: start))
        #expect(gate.receive("الرياض", questionToken: "turn2", now: start) == .discussion)
    }

    @Test func setupStillAllowsOrdinaryConversation() {
        var gate = VoiceInputGate()
        #expect(gate.receive("نبي تاريخ وكرة قدم", questionToken: nil) == .request)
        #expect(!gate.authorizesRequest(questionToken: "turn1"))
        #expect(gate.receive("الرياض", questionToken: "turn1") == .discussion)
    }

    @Test func acceptedTranscriptRemainsAuthorizedDuringProviderProcessing() {
        let start = Date(timeIntervalSince1970: 100)
        var gate = VoiceInputGate()
        #expect(gate.receive("إجابتنا هي الرياض", questionToken: "turn1", now: start) == .request)
        #expect(!gate.isWindowOpen(now: start.addingTimeInterval(9)))
        #expect(gate.authorizesRequest(questionToken: "turn1"))
        #expect(!gate.authorizesRequest(questionToken: "turn2"))
    }
}
