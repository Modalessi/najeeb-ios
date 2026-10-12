import SwiftUI

enum NajeebTheme {
    static let background = Color(red: 246 / 255, green: 244 / 255, blue: 238 / 255)
    static let surface = Color(red: 239 / 255, green: 237 / 255, blue: 232 / 255)
    static let border = Color(red: 219 / 255, green: 217 / 255, blue: 213 / 255)
    static let muted = Color(red: 77 / 255, green: 77 / 255, blue: 77 / 255)

    static func font(_ size: CGFloat, weight: String = "Regular", relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("thmanyahsans-\(weight)", size: size, relativeTo: style)
    }
}

struct NajeebButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NajeebTheme.font(17, weight: "Bold"))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
            .opacity(!enabled ? 0.35 : configuration.isPressed ? 0.75 : 1)
    }
}
