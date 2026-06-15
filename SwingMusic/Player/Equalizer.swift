import AVFoundation
import Combine

@MainActor
final class Equalizer: ObservableObject {
    static let shared = Equalizer()

    struct Preset: Identifiable, Hashable {
        let id: String
        let name: String
        let gains: [Float]
    }

    static let presets: [Preset] = [
        Preset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0]),
        Preset(id: "bass", name: "Bass Boost", gains: [6, 4, 0, 0, 0]),
        Preset(id: "treble", name: "Treble Boost", gains: [0, 0, 0, 4, 6]),
        Preset(id: "vocal", name: "Vocal", gains: [-2, 0, 4, 2, 0]),
        Preset(id: "rock", name: "Rock", gains: [4, 2, -1, 3, 4]),
        Preset(id: "pop", name: "Pop", gains: [-1, 2, 4, 2, -1]),
        Preset(id: "jazz", name: "Jazz", gains: [3, 0, 1, 2, 4]),
        Preset(id: "electronic", name: "Electronic", gains: [5, 3, 0, 2, 4]),
        Preset(id: "classical", name: "Classical", gains: [0, 0, 0, 2, 4]),
        Preset(id: "hiphop", name: "Hip-Hop", gains: [5, 4, 0, 1, 3]),
    ]

    let bandLabels = ["60", "230", "910", "4k", "14k"]
    let bandFrequencies: [Float] = [60, 230, 910, 4000, 14000]

    @Published var enabled = false {
        didSet { UserDefaults.standard.set(enabled, forKey: "eq.enabled"); applyToPlayer() }
    }
    @Published var bands: [Float] = [0, 0, 0, 0, 0] {
        didSet { saveBands(); applyToPlayer() }
    }
    @Published var selectedPreset: Preset? = nil

    private init() {
        enabled = UserDefaults.standard.bool(forKey: "eq.enabled")
        if let data = UserDefaults.standard.data(forKey: "eq.bands"),
           let saved = try? JSONDecoder().decode([Float].self, from: data), saved.count == 5 {
            bands = saved
        }
    }

    func applyPreset(_ preset: Preset) {
        selectedPreset = preset
        bands = preset.gains
    }

    private func saveBands() {
        if let data = try? JSONEncoder().encode(bands) {
            UserDefaults.standard.set(data, forKey: "eq.bands")
        }
    }

    func applyToPlayer() {

    }
}
