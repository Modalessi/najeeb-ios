import AVFoundation
import OSLog

// AVAudioPlayer setup can activate AVAudioSession synchronously. Keep every
// player access on this serial queue so playback never blocks the UI thread.
nonisolated final class GameSounds: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.najeeb.game-sounds")
    private var activePlayer: AVAudioPlayer?
    private var completion: CheckedContinuation<Void, Never>?
    private var timeout: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.najeeb.voiceprototype", category: "GameSounds")

    func play(correct: Bool) async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                self.stopPlayback()
                guard let player = self.player(correct: correct) else { continuation.resume(); return }
                self.activePlayer = player
                self.completion = continuation
                guard player.play() else { self.stopPlayback(); return }
                let timeout = DispatchWorkItem { [weak self] in self?.stopPlayback() }
                self.timeout = timeout
                self.queue.asyncAfter(deadline: .now() + 2, execute: timeout)
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                self.stopPlayback()
                continuation.resume()
            }
        }
    }

    private func stopPlayback() {
        timeout?.cancel()
        timeout = nil
        activePlayer?.stop()
        activePlayer = nil
        let pending = completion
        completion = nil
        pending?.resume()
    }

    private func player(correct: Bool) -> AVAudioPlayer? {
        let bundle = Bundle.main
        let name = correct ? "correct" : "incorrect"
        guard let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") else {
            logger.error("Missing bundled game sound: \(name, privacy: .public)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            guard player.duration > 0, player.duration <= 1 else { return nil }
            player.volume = 0.35
            player.delegate = self
            player.prepareToPlay()
            return player
        } catch {
            logger.error("Could not load game sound: \(name, privacy: .public)")
            return nil
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish(player, successfully: flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish(player, successfully: false)
    }

    private func finish(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        queue.async { [self] in
            guard let active = self.activePlayer, ObjectIdentifier(active) == identifier else { return }
            self.logger.info("Game sound finished: \(active.url?.lastPathComponent ?? "unknown", privacy: .public), success: \(flag)")
            self.stopPlayback()
        }
    }
}
