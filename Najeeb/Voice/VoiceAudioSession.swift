import AVFoundation
import LiveKit

actor VoiceAudioSession {
    private var isConfigured = false

    func prepare() async throws {
        if !isConfigured {
            #if targetEnvironment(simulator)
            // AVAudioEngine can report a zero-channel input on Simulator. Select
            // WebRTC's AudioUnit implementation before its connection factory exists.
            try AudioManager.set(audioDeviceModuleType: .platformDefault)
            #endif
            isConfigured = true
        }
        #if targetEnvironment(simulator)
        let mode: AVAudioSession.Mode = .videoChat
        #else
        let mode: AVAudioSession.Mode = .default
        #endif
        AudioManager.shared.sessionConfiguration = AudioSessionConfiguration(
            category: .playAndRecord,
            categoryOptions: [.allowBluetoothHFP, .defaultToSpeaker],
            mode: mode
        )
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: mode, options: [.allowBluetoothHFP, .defaultToSpeaker])
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            guard try await session.activate(options: []) else { throw SessionError.connectionFailed }
            return
        }
        #endif
        try session.setActive(true)
    }

    func release() async {
        // A pending SDK startup may reopen recording after Stop was pressed.
        // Repeat cleanup after that startup finishes, even if it was released once.
        guard isConfigured else { return }
        let manager = AudioManager.shared
        #if !targetEnvironment(simulator)
        try? await manager.setRecordingAlwaysPreparedMode(false)
        #endif
        try? manager.stopLocalRecording()
        let session = AVAudioSession.sharedInstance()
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            _ = try? await session.deactivate(options: [.notifyOthersOnDeactivation])
            return
        }
        #endif
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
