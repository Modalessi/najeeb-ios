import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: GameSession
    @State private var showsSettings = false
    @State private var showsDiagnostics = false
    @State private var confirmsQuit = false

    private var ended: Bool { session.state.phase == .ended || session.state.phase == .finished }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height { landscapeLayout(size: geometry.size) }
                else { portraitLayout }
            }
            .background { NajeebBackground() }
            .navigationTitle("نجيب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NajeebTheme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("نجيب").font(NajeebTheme.font(22, weight: "Black", relativeTo: .title2)).foregroundStyle(NajeebTheme.teal)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("الإعدادات", systemImage: "gearshape") { showsSettings = true }
                        Button("تشخيص المطوّر", systemImage: "stethoscope") { showsDiagnostics = true }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.accessibilityLabel("المزيد")
                }
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .sheet(isPresented: $showsDiagnostics) { DiagnosticsView() }
            .confirmationDialog("تنهي المسابقة الحالية؟", isPresented: $confirmsQuit, titleVisibility: .visible) {
                Button("إنهاء المسابقة", role: .destructive) { Task { await session.quitGame() } }
                Button("إلغاء", role: .cancel) { }
            }
        }
    }

    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !session.state.teams.isEmpty { scoreboard(compact: false) }
                gameContent
                controls
            }.padding(24).frame(maxWidth: 860).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            gameActions.padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: 480).frame(maxWidth: .infinity)
                .background(NajeebTheme.background)
                .overlay(alignment: .top) { Rectangle().fill(NajeebTheme.border.opacity(0.6)).frame(height: 1) }
        }
    }

    private func landscapeLayout(size: CGSize) -> some View {
        VStack(spacing: 16) {
            if !session.state.teams.isEmpty { scoreboard(compact: true) }
            HStack(alignment: .top, spacing: 24) {
                ScrollView { gameContent }.frame(maxWidth: .infinity)
                VStack(spacing: 12) {
                    ScrollView { controls }
                    gameActions
                }.frame(width: min(260, size.width * 0.35))
            }
        }.padding(16).frame(maxWidth: 860).frame(maxWidth: .infinity)
    }

    private func scoreboard(compact: Bool) -> some View {
        HStack(spacing: 16) {
            ForEach(session.state.teams) { team in
                let current = session.state.currentTeamID == team.id
                let accent = NajeebTheme.teamColor(team.id)
                Group {
                    if compact {
                        HStack {
                            Text(team.name).font(NajeebTheme.font(16, weight: "Bold"))
                            Spacer()
                            if current { Circle().fill(accent).frame(width: 7, height: 7).accessibilityLabel("عليكم الدور") }
                            Text(team.score, format: .number).font(NajeebTheme.font(24, weight: "Black", relativeTo: .title2))
                        }.padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 6) {
                            Text(team.name).font(NajeebTheme.font(18, weight: "Bold", relativeTo: .headline))
                                .lineLimit(2).multilineTextAlignment(.center)
                            Text(team.score, format: .number).font(NajeebTheme.font(32, weight: "Black", relativeTo: .title))
                            Text(current ? "عليكم الدور" : " ").font(NajeebTheme.font(12, weight: "Medium")).foregroundStyle(NajeebTheme.muted)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 10 : 16)
                .background(accent.opacity(current ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(current ? 0.65 : 0.25), lineWidth: current ? 2 : 1))
                .overlay(alignment: .top) {
                    Capsule().fill(accent).frame(width: 36, height: 4).padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder private var gameContent: some View {
        if let winner = session.state.winner {
            VStack(spacing: 12) {
                Image(systemName: "trophy.fill").font(.system(size: 48)).foregroundStyle(NajeebTheme.orange)
                Text(winner.isTie ? "تعادل!" : "الفوز لـ\(winner.teamName ?? "")")
                    .font(NajeebTheme.font(30, weight: "Black", relativeTo: .title))
                Text("خلصت المسابقة، يعطيكم العافية!").foregroundStyle(NajeebTheme.muted)
            }.frame(maxWidth: .infinity).padding(.vertical, 32)
                .background(NajeebTheme.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        } else if ended {
            Text("انتهت المسابقة").font(NajeebTheme.font(28, weight: "Black", relativeTo: .title))
                .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let question = session.state.currentQuestion {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(question.categoryName).foregroundStyle(NajeebTheme.pink)
                    Spacer()
                    Text("\(question.difficulty.arabicName) · \(question.points)")
                        .foregroundStyle(NajeebTheme.difficultyColor(question.difficulty))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(NajeebTheme.difficultyColor(question.difficulty).opacity(0.10), in: Capsule())
                }.font(NajeebTheme.font(14, weight: "Medium"))
                Text(question.text).font(NajeebTheme.font(26, weight: "Bold", relativeTo: .title2))
                    .fixedSize(horizontal: false, vertical: true)
                if let choices = question.choices {
                    ForEach(Array(choices.enumerated()), id: \.offset) { index, text in
                        Text("\(index + 1). \(text)").font(NajeebTheme.font(18, weight: "Medium"))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(NajeebTheme.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                if let hint = question.hint {
                    Label(hint, systemImage: "lightbulb").foregroundStyle(NajeebTheme.teal)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(NajeebTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                Divider()
                Text("يا نجيب… أو: إجابتنا هي…").font(NajeebTheme.font(16, weight: "Bold")).foregroundStyle(NajeebTheme.teal)
                Text("السؤال \(session.state.completedQuestions + 1) من 18").font(NajeebTheme.font(12)).foregroundStyle(NajeebTheme.muted)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(NajeebTheme.pink.opacity(0.14), lineWidth: 1))
        } else {
            VStack(spacing: 20) {
                Image(systemName: "waveform").font(.system(size: 48, weight: .light))
                    .foregroundStyle(NajeebTheme.teal).frame(width: 112, height: 112)
                    .background(NajeebTheme.mint.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(NajeebTheme.mint.opacity(0.16), lineWidth: 1))
                    .padding(.top, 24)
                Text(session.state.selectedCategories.isEmpty ? "المسابقة تبدأ بسوالفكم" : "نجهّز المسابقة")
                    .font(NajeebTheme.font(28, weight: "Black", relativeTo: .title))
                Text("اختاروا ست فئات، سمّوا فريقين، والباقي على نجيب.")
                    .multilineTextAlignment(.center).foregroundStyle(NajeebTheme.muted)
                if !session.state.selectedCategories.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Array(session.state.selectedCategories.enumerated()), id: \.element.id) { index, category in
                            let color = [NajeebTheme.teal, NajeebTheme.pink, NajeebTheme.orange][index % 3]
                            Text(category.name).font(NajeebTheme.font(14, weight: "Medium"))
                                .foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 8)
                                .frame(maxWidth: .infinity).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }.frame(maxWidth: .infinity).padding(.bottom, 16)
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            if !ended {
                HStack(spacing: 8) {
                    Circle().fill(NajeebTheme.voiceColor(session.voiceStatus)).frame(width: 7, height: 7)
                    Text(session.state.phase == .paused ? "المسابقة متوقفة مؤقتًا" : session.voiceStatus.label)
                        .font(NajeebTheme.font(14, weight: "Medium"))
                }.padding(.horizontal, 12).padding(.vertical, 8)
                    .background(NajeebTheme.voiceColor(session.voiceStatus).opacity(0.08), in: Capsule())
                    .accessibilityElement(children: .combine)
                if let team = session.state.teams.first(where: { $0.id == session.state.currentTeamID }) {
                    HStack(spacing: 8) {
                        ForEach(session.state.availableHelpers) { helper in
                            Text(helper.name)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .foregroundStyle(.black)
                                .background(NajeebTheme.helperColor(helper.id).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                .strikethrough(team.usedHelperIDs.contains(helper.id))
                                .opacity(team.usedHelperIDs.contains(helper.id) ? 0.3 : 1)
                        }
                    }.font(NajeebTheme.font(14, weight: "Bold"))
                    Text("يا نجيب، نبي تلميح / خيارات / القنبلة")
                        .font(NajeebTheme.font(12)).foregroundStyle(NajeebTheme.muted).multilineTextAlignment(.center)
                }
            }
            if let outcome = session.state.lastAnswer {
                let teamName = session.state.teams.first { $0.id == outcome.teamID }?.name ?? ""
                HStack(spacing: 8) {
                    Image(systemName: outcome.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text("آخر إجابة: \(teamName) · \(outcome.isCorrect ? "صحيحة" : "خاطئة")")
                    Spacer(minLength: 4)
                    Text(outcome.awardedPoints > 0 ? "+\(outcome.awardedPoints)" : "\(outcome.awardedPoints)")
                        .environment(\.layoutDirection, .leftToRight)
                }.font(NajeebTheme.font(13, weight: "Medium"))
                    .foregroundStyle(outcome.isCorrect ? NajeebTheme.teal : NajeebTheme.red)
                    .padding(12).background((outcome.isCorrect ? NajeebTheme.mint : NajeebTheme.red).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var gameActions: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    if ended || session.requiresNewGame { await session.stopVoice(); session.newGame() }
                    if session.isConnected {
                        if session.state.phase == .playing || session.state.phase == .paused { await session.togglePause() }
                        else { await session.stopVoice() }
                    }
                    else { await session.startVoice() }
                }
            } label: {
                Label(primaryTitle, systemImage: primarySymbol)
            }
            .buttonStyle(NajeebButtonStyle())
            .disabled(session.isStarting || (ended ? false : session.requiresNewGame ? !session.canReplaceSession : !session.canStart))
            if !ended && (!session.state.selectedCategories.isEmpty || session.isConnected) {
                Button("إنهاء المسابقة") { confirmsQuit = true }
                    .font(NajeebTheme.font(15, weight: "Medium")).frame(minHeight: 44)
                    .disabled(session.isStarting)
            }
            if let error = session.errorMessage { Text(error).font(NajeebTheme.font(14)).foregroundStyle(.red) }
        }
    }

    private var primaryTitle: String {
        if ended || session.requiresNewGame { return "ابدأ لعبة جديدة" }
        if session.isConnected && session.state.phase == .playing { return "وقف شوي" }
        if session.state.phase == .paused { return "كمّل المسابقة" }
        if session.isConnected { return "وقف الصوت" }
        return session.state.selectedCategories.isEmpty ? "ابدأ مع نجيب" : "كمّل مع نجيب"
    }

    private var primarySymbol: String {
        if session.isConnected && session.state.phase != .playing && session.state.phase != .paused { return "stop.fill" }
        return session.isConnected && session.state.phase == .playing ? "pause.fill" : "play.fill"
    }
}
