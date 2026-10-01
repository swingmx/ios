import Foundation

struct AutoMixInfo: Decodable, Equatable {
    let bpm: Double
    let beatOffset: Double
    let cueIn: Double
    let mixOut: Double
    let mixDuration: Double
    let endAudible: Double
    let loudnessDb: Double

    enum CodingKeys: String, CodingKey {
        case bpm
        case beatOffset = "beat_offset"
        case cueIn = "cue_in"
        case mixOut = "mix_out"
        case mixDuration = "mix_duration"
        case endAudible = "end_audible"
        case loudnessDb = "loudness_db"
    }

    func rateToMatch(_ outgoing: AutoMixInfo) -> Float? {
        guard bpm > 0, outgoing.bpm > 0 else { return nil }
        let ratio = outgoing.bpm / bpm
        guard abs(ratio - 1) <= 0.06, abs(ratio - 1) > 0.005 else { return nil }
        return Float(ratio)
    }
}

@MainActor
final class AutoMixStore {
    static let shared = AutoMixStore()
    private var cache: [String: AutoMixInfo] = [:]
    private var inFlight: Set<String> = []

    func info(for trackhash: String) -> AutoMixInfo? { cache[trackhash] }

    func load(_ trackhash: String) {
        guard cache[trackhash] == nil, !inFlight.contains(trackhash), !trackhash.isEmpty else { return }
        inFlight.insert(trackhash)
        Task {
            defer { inFlight.remove(trackhash) }
            if let info: AutoMixInfo = try? await API.shared.get("/automix/\(trackhash)") {
                cache[trackhash] = info
            }
        }
    }

    func prepare(_ trackhashes: [String]) {
        let missing = trackhashes.filter { cache[$0] == nil && !$0.isEmpty }
        guard !missing.isEmpty else { return }
        struct Body: Encodable { let trackhashes: [String] }
        struct Ack: Decodable { let queued: Int? }
        Task { let _: Ack? = try? await API.shared.post("/automix/prepare", body: Body(trackhashes: missing)) }
        for h in missing.prefix(3) { load(h) }
    }
}
