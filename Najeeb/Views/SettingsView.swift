import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.saved
    @State private var email = ""
    @State private var otp = ""
    @State private var name = ""
    @State private var sentOTP = false
    @State private var requiresName = false
    @State private var showsNamePrompt = false
    @State private var action: SettingsAction?
    @State private var feedback: SettingsFeedback?
    @State private var task: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    private var busy: Bool { action != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("حساب نجيب للأسئلة الحقيقية") {
                    if session.isSignedIn {
                        Label("تم تسجيل الدخول", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("تسجيل الخروج", role: .destructive) {
                            run(.logout) { try await session.logout() }
                        }.disabled(busy || !session.canReplaceSession)
                    } else {
                        TextField("البريد الإلكتروني", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.send).onSubmit(sendOTP)
                            .disabled(busy)
                        Button(action == .sendOTP ? "نرسل رمز الدخول…" : sentOTP ? "إرسال رمز جديد" : "أرسل رمز الدخول", action: sendOTP)
                            .disabled(busy || !session.canReplaceSession)
                        if sentOTP {
                            TextField("رمز الدخول — ستة حروف أو أرقام", text: $otp)
                                .textContentType(.oneTimeCode).textInputAutocapitalization(.characters)
                                .autocorrectionDisabled().focused($focusedField, equals: .otp)
                                .submitLabel(.done).onSubmit(verifyOTP)
                                .disabled(busy)
                            Button(action == .verifyOTP ? "نتحقق من الرمز…" : requiresName ? "إكمال الحساب" : "تأكيد الدخول", action: verifyOTP)
                                .disabled(busy || !session.canReplaceSession)
                        }
                    }
                    status(for: .account)
                    if !session.canReplaceSession {
                        Text("أوقف الجلسة الصوتية أول عشان تقدر تسجّل الدخول أو تغيّر الإعدادات.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("إيقاف الجلسة الصوتية") {
                            run(.stopVoice) { await session.stopVoice() }
                        }.disabled(busy)
                    }
                }
                Section("الوكيل الصوتي") {
                    TextField("معرّف ElevenLabs Agent", text: $settings.agentID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focusedField, equals: .agent).disabled(busy)
                    Button("حفظ معرّف الوكيل") {
                        run(.saveSettings) {
                            try session.saveSettings(settings)
                            feedback = SettingsFeedback(target: .connection, message: "حفظنا الإعدادات.")
                        }
                    }.disabled(busy || !session.canReplaceSession)
                    status(for: .connection)
                }
                Section("أصوات المسابقة") {
                    Toggle("صوت للإجابة الصحيحة والخاطئة", isOn: $session.soundEffectsEnabled)
                }
                Section {
                    Text("صوتك يرسل إلى ElevenLabs أثناء الجلسة. لا نحفظ تسجيلات صوتية في التطبيق. جهّز الحساب والإعدادات قبل الطريق.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NajeebTheme.background)
            .font(NajeebTheme.font(17))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("إعداد نجيب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { focusedField = nil; dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("إخفاء لوحة المفاتيح") { focusedField = nil }
                }
            }
            .onChange(of: email) { old, new in
                guard old.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != new.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !busy else { return }
                resetOTP()
                if feedback?.target == .account { feedback = nil }
            }
            .onDisappear { task?.cancel() }
            .alert("حياك الله! وش اسمك؟", isPresented: $showsNamePrompt) {
                TextField("اسمك", text: $name).textContentType(.name)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                Button("إكمال تسجيل الدخول") { submitOTP(name: name) }
                    .disabled(busy || !session.canReplaceSession || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("إلغاء", role: .cancel) { }
            } message: {
                Text("نحتاج اسمك عشان نكمل حسابك في نجيب.")
            }
        }
    }

    @ViewBuilder
    private func status(for target: FeedbackTarget) -> some View {
        if let action, action.target == target {
            ProgressView(action.progress).accessibilityLabel(action.progress)
        }
        if let feedback, feedback.target == target {
            Label(feedback.message, systemImage: feedback.isError ? "exclamationmark.circle" : "checkmark.circle")
                .font(.callout).foregroundStyle(feedback.isError ? .red : .green)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func sendOTP() {
        let requestedEmail = email
        run(.sendOTP) {
            try session.saveSettings(settings)
            try Task.checkCancellation()
            try await session.requestOTP(email: requestedEmail)
            try Task.checkCancellation()
            sentOTP = true
            otp = ""
            name = ""
            requiresName = false
            showsNamePrompt = false
            feedback = SettingsFeedback(target: .account, message: "أرسلنا رمز الدخول لبريدك. اكتب الرمز هنا، وشيّك الرسائل غير المرغوب فيها إذا ما وصلك.")
            focusedField = .otp
        }
    }

    private func verifyOTP() {
        if requiresName {
            focusedField = nil
            showsNamePrompt = true
        } else {
            submitOTP(name: nil)
        }
    }

    private func submitOTP(name: String?) {
        run(.verifyOTP) {
            let needsName = try await session.verifyOTP(email: email, otp: otp, name: name)
            try Task.checkCancellation()
            requiresName = needsName
            showsNamePrompt = needsName
            feedback = SettingsFeedback(target: .account, message: needsName ? "نحتاج اسمك لإكمال حسابك." : "يا هلا! جاهزين للمسابقة.")
            if !needsName { resetOTP() }
            focusedField = nil
        }
    }

    private func resetOTP() {
        sentOTP = false
        requiresName = false
        showsNamePrompt = false
        otp = ""
        name = ""
    }

    private func run(_ action: SettingsAction, _ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        focusedField = nil
        self.action = action
        feedback = nil
        task = Task { @MainActor in
            defer { self.action = nil; task = nil }
            do { try await work() }
            catch is CancellationError { }
            catch {
                feedback = SettingsFeedback(
                    target: action.target,
                    message: (error as? LocalizedError)?.errorDescription ?? "تعذّر إكمال الطلب. جرّب مرة ثانية.",
                    isError: true
                )
            }
        }
    }

    private enum Field: Hashable { case email, otp, agent }
    private enum FeedbackTarget { case account, connection }
    private struct SettingsFeedback {
        let target: FeedbackTarget
        let message: String
        var isError = false
    }
    private enum SettingsAction {
        case saveSettings, sendOTP, verifyOTP, logout, stopVoice

        var target: FeedbackTarget { self == .saveSettings ? .connection : .account }
        var progress: String {
            switch self {
            case .saveSettings: "نحفظ الإعدادات…"
            case .sendOTP: "نرسل رمز الدخول…"
            case .verifyOTP: "نتحقق من رمز الدخول…"
            case .logout: "نسجّل الخروج…"
            case .stopVoice: "نوقف الجلسة الصوتية…"
            }
        }
    }
}
