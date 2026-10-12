import SwiftUI

enum NajeebTheme {
    static let background = Color(red: 246 / 255, green: 244 / 255, blue: 238 / 255)
    static let surface = Color(red: 239 / 255, green: 237 / 255, blue: 232 / 255)
    static let border = Color(red: 219 / 255, green: 217 / 255, blue: 213 / 255)
    static let muted = Color(red: 77 / 255, green: 77 / 255, blue: 77 / 255)
    static let orange = color(0xFA541C)
    static let pink = color(0xD200AE)
    static let teal = color(0x00583D)
    static let mint = color(0x007A56)
    static let red = color(0xDC2626)

    static func teamColor(_ id: String) -> Color { id == "team1" ? orange : teal }

    static func helperColor(_ id: HelperID) -> Color {
        switch id {
        case .choices: orange
        case .hint: pink
        default: teal
        }
    }

    static func difficultyColor(_ difficulty: Difficulty) -> Color {
        switch difficulty {
        case .easy: color(0x00785C)
        case .medium: color(0xB45309)
        case .hard: color(0xB5002A)
        }
    }

    static func voiceColor(_ status: VoiceStatus) -> Color {
        switch status {
        case .idle: teal
        case .connecting, .processing: orange
        case .listening: mint
        case .speaking: pink
        case .disconnected: red
        }
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }

    static func font(_ size: CGFloat, weight: String = "Regular", relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("thmanyahsans-\(weight)", size: size, relativeTo: style)
    }
}

struct NajeebBackground: View {
    var body: some View {
        ZStack {
            NajeebTheme.background
            RadialGradient(colors: [NajeebTheme.orange.opacity(0.10), .clear], center: .topTrailing, startRadius: 0, endRadius: 440)
            RadialGradient(colors: [NajeebTheme.teal.opacity(0.08), .clear], center: .bottomLeading, startRadius: 0, endRadius: 400)
        }.ignoresSafeArea()
    }
}

struct NajeebButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NajeebTheme.font(17, weight: "Bold"))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.black)
            .background(NajeebTheme.orange, in: RoundedRectangle(cornerRadius: 14))
            .opacity(!enabled ? 0.35 : configuration.isPressed ? 0.75 : 1)
    }
}
