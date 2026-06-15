import Foundation
import Combine

@MainActor
final class SleepTimer: ObservableObject {
    static let shared = SleepTimer()

    @Published var remaining: TimeInterval = 0
    @Published var active = false
    @Published var fadeOut = true

    private var timer: AnyCancellable?
    private var fadeStarted = false

    private init() {}

    func start(minutes: Int) {
        cancel()
        remaining = TimeInterval(minutes * 60)
        active = true
        fadeStarted = false

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let s = self else { return }
                s.remaining -= 1

                if s.fadeOut && s.remaining <= 30 && s.remaining > 0 && !s.fadeStarted {
                    s.fadeStarted = true
                    s.startFade()
                }

                if s.remaining <= 0 {
                    s.fire()
                }
            }
    }

    func cancel() {
        timer?.cancel()
        timer = nil
        active = false
        remaining = 0
        fadeStarted = false

        AudioPlayer.shared.volume = max(AudioPlayer.shared.volume, 0.8)
    }

    private func startFade() {
        let originalVolume = AudioPlayer.shared.volume
        let steps = 30
        let decrement = originalVolume / Float(steps)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let s = self, s.active else { timer.invalidate(); return }
                let newVol = AudioPlayer.shared.volume - decrement
                if newVol <= 0 {
                    timer.invalidate()
                } else {
                    AudioPlayer.shared.volume = newVol
                }
            }
        }
    }

    private func fire() {
        let player = AudioPlayer.shared
        if player.playing { player.toggle() }
        cancel()
    }

    var displayTime: String {
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%d:%02d", m, s)
    }
}
