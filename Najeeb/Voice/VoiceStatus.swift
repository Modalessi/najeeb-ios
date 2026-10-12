import Foundation

enum VoiceStatus: String {
    case idle, connecting, listening, speaking, processing, disconnected

    var label: String {
        switch self {
        case .idle: "جاهزين؟"
        case .connecting: "نجهّز المايك"
        case .listening: "نجيب يسمعكم"
        case .speaking: "نجيب يتكلم"
        case .processing: "لحظة ونرجع لكم"
        case .disconnected: "الاتصال متوقف — لعبتكم محفوظة"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "mic.circle"
        case .connecting, .processing: "ellipsis.circle"
        case .listening: "mic.fill"
        case .speaking: "waveform"
        case .disconnected: "wifi.slash"
        }
    }
}

struct ToolDiagnostic: Identifiable {
    let id = UUID()
    let name: String
    let result: String
    let success: Bool
}

struct TranscriptLine: Identifiable {
    let id: String
    let isHost: Bool
    let text: String
}
