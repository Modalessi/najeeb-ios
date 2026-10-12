import SwiftUI

@main
struct NajeebApp: App {
    @StateObject private var session = GameSession.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(session)
                .environment(\.layoutDirection, .rightToLeft)
                .tint(NajeebTheme.teal)
                .font(NajeebTheme.font(17))
                .preferredColorScheme(.light)
        }
    }
}
