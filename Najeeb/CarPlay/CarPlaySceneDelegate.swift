import CarPlay
import Combine
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CPInterfaceController?
    private var template: CPVoiceControlTemplate?
    private var states: [String: CPVoiceControlState] = [:]
    private var observers = Set<AnyCancellable>()
    private let session = GameSession.shared

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        controller = interfaceController
        session.setCarPlayConnected(true)
        guard #available(iOS 26.4, *) else {
            session.carPlayMessage = "CarPlay conversational templates require iOS 26.4 or newer."
            return
        }
        installTemplate()
        session.$voiceStatus.combineLatest(session.$state)
            .throttle(for: .milliseconds(350), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.updateButtons()
                self?.updateStatus()
            }.store(in: &observers)
        // Voice is started by the supported Start control, never just by connecting a car.
    }

    @available(iOS 26.4, *)
    private func installTemplate() {
        guard let controller else { return }
        states = [:]
        let definitions: [(String, String, String)] = [
            ("idle", "نجيب", "mic.circle"),
            ("listening", "أسمعكم", "mic.fill"),
            ("speaking", "نجيب يتكلم", "waveform"),
            ("processing", "لحظة", "ellipsis.circle"),
            ("disconnected", "الاتصال متوقف", "wifi.slash")
        ]
        let voiceStates = definitions.map { id, title, symbol in
            let state = CPVoiceControlState(
                identifier: id, titleVariants: [title],
                image: UIImage(systemName: symbol), repeats: false
            )
            states[id] = state
            return state
        }
        let template = CPVoiceControlTemplate(voiceControlStates: voiceStates)
        self.template = template
        updateButtons()
        controller.setRootTemplate(template, animated: false) { [weak self] success, error in
            guard let self else { return }
            if success {
                self.updateStatus()
            } else {
                self.session.carPlayMessage = "CarPlay could not present the voice template. Verify the entitlement/profile. \(error?.localizedDescription ?? "")"
            }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        session.setCarPlayConnected(false)
        observers.removeAll()
        controller = nil
        template = nil
        states = [:]
        // A CarPlay disconnect stops capture and checkpoints the shared game.
        Task { await session.stopVoice() }
    }

    private func updateStatus() {
        let id = session.voiceStatus == .connecting ? "processing" : session.voiceStatus.rawValue
        guard template?.activeStateIdentifier != id else { return }
        template?.activateVoiceControlState(withIdentifier: id)
    }

    @available(iOS 26.4, *)
    private func updateButtons() {
        for (identifier, state) in states {
            let ended = session.state.phase == .ended || session.state.phase == .finished
            let stopped = identifier == "idle" || identifier == "disconnected"
            if ended || (stopped && !session.isConnected) {
                let start = button(ended ? "لعبة جديدة" : "ابدأ المسابقة", symbol: "play.fill") { [weak self] in
                    guard let self else { return }
                    Task {
                        if ended { await self.session.stopVoice(); self.session.newGame() }
                        await self.session.startVoice()
                    }
                }
                start.isEnabled = ended ? !session.isStarting : session.canStart
                state.actionButtons = [start]
            } else {
                let stop = button("إنهاء المسابقة", symbol: "stop.fill") { [weak self] in
                    guard let self else { return }
                    Task { await self.session.quitGame() }
                }
                if session.state.phase == .playing || session.state.phase == .paused {
                    let paused = session.state.phase == .paused
                    let pause = button(paused ? "كمّل" : "توقّف مؤقتًا", symbol: paused ? "play.fill" : "pause.fill") { [weak self] in
                        guard let self else { return }
                        Task { await self.session.togglePause() }
                    }
                    state.actionButtons = [pause, stop]
                } else {
                    state.actionButtons = [stop]
                }
            }
        }
    }

    private func button(_ title: String, symbol: String, action: @escaping @MainActor () -> Void) -> CPButton {
        let button = CPButton(image: UIImage(systemName: symbol) ?? UIImage()) { _ in action() }
        button.title = title
        return button
    }
}
