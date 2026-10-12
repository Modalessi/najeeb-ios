import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            List {
                Section("حالة اللعبة") {
                    LabeledContent("المرحلة", value: session.state.phase.rawValue)
                    LabeledContent("مراجعة الحالة", value: String(session.state.revision))
                    LabeledContent("الأسئلة المكتملة", value: "\(session.state.completedQuestions) / \(session.state.totalQuestions)")
                    LabeledContent("الدور", value: session.state.currentTeamID ?? "—")
                    LabeledContent("الاتصال", value: session.voiceStatus.rawValue)
                    LabeledContent("CarPlay متصل", value: session.isCarPlayConnected ? "نعم" : "لا")
                    if let failure = session.voiceFailure {
                        LabeledContent("آخر خطأ اتصال", value: failure)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    if let message = session.carPlayMessage { Text(message).font(.caption).foregroundStyle(.red) }
                }
                Section("اختبار المحادثة بالنص") {
                    TextField("رسالة للوكيل", text: $text)
                    Button("إرسال") {
                        let value = text
                        text = ""
                        Task { await session.sendText(value) }
                    }.disabled(!session.isConnected || text.isEmpty)
                }
                Section("تجربة أصوات المسابقة") {
                    Button("صوت الإجابة الصحيحة", systemImage: "checkmark.circle") {
                        Task { await session.previewGameSound(correct: true) }
                    }
                    Button("صوت الإجابة الخاطئة", systemImage: "xmark.circle") {
                        Task { await session.previewGameSound(correct: false) }
                    }
                }.disabled(session.isStarting || session.isPreviewingSound)
                Section("الأدوات الأخيرة — الحالة الآمنة فقط") {
                    ForEach(session.diagnostics) { call in
                        DisclosureGroup {
                            Text(call.result).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).environment(\.layoutDirection, .leftToRight)
                        } label: {
                            Label(call.name, systemImage: call.success ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(call.success ? .green : .red)
                        }
                    }
                }
                Section("المحادثة — مؤقتة في الذاكرة") {
                    ForEach(session.transcript) { line in
                        VStack(alignment: .leading) {
                            Text(line.isHost ? "نجيب" : "اللاعبون").font(.caption.bold())
                            Text(line.text).font(.callout)
                        }
                    }
                }
            }
            .navigationTitle("تشخيص المطوّر")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        }
    }
}
