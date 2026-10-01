import Combine
import Foundation
import Observation

@MainActor
@Observable
final class PlayerStore {
    static let shared = PlayerStore()

    var currentSong: Song?
    var isPlaying: Bool = false
    var progress: TimeInterval = 0
    var seekRevision: Int = 0
    var shuffleOn: Bool = false
    var loopMode: AudioPlayer.LoopMode = .off
    var autoplayOn: Bool = false
    var queueTracks: [Track] = []
    var queueIndex: Int = 0
    var autoMixOn: Bool = false

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private let player = AudioPlayer.shared

    private init() {
        player.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] track in
                guard let self else { return }
                if self.currentSong?.trackhash != track?.trackhash {
                    self.seekRevision &+= 1
                }
                self.currentSong = track
            }
            .store(in: &cancellables)

        player.$shuffle
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.shuffleOn = $0 }
            .store(in: &cancellables)

        player.$loop
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.loopMode = $0 }
            .store(in: &cancellables)

        player.$queue
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.queueTracks = $0 }
            .store(in: &cancellables)

        player.$index
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.queueIndex = $0 }
            .store(in: &cancellables)

        player.$autoplay
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.autoplayOn = $0 }
            .store(in: &cancellables)

        player.$crossfadeDuration
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.autoMixOn = $0 > 0 }
            .store(in: &cancellables)

        player.$playing
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isPlaying = $0 }
            .store(in: &cancellables)

        player.$time
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                guard let self else { return }
                if abs(time - self.progress) > 1.5 {
                    self.seekRevision &+= 1
                    self.progress = time
                    return
                }
                if abs(time - self.progress) >= 0.25 {
                    self.progress = time
                }
            }
            .store(in: &cancellables)
    }

    func estimatedProgress(at date: Date = Date()) -> TimeInterval {
        player.smoothTime(at: date)
    }

    func seek(to time: TimeInterval) {
        player.seek(time)
        seekRevision &+= 1
    }
}
