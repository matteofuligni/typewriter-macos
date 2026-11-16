import AVFoundation
import Observation

enum SoundPreset: String, CaseIterable, Identifiable {
    case classic, dry, soft

    var id: Self { self }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .dry: "Crisp"
        case .soft: "Soft"
        }
    }

    var description: String {
        switch self {
        case .classic: "Metallic strike with a bell"
        case .dry: "Short, bright click"
        case .soft: "Lower, muted strike with no bell"
        }
    }

    var prefix: String {
        switch self {
        case .classic: ""
        case .dry: "crisp-"
        case .soft: "soft-"
        }
    }
}

@MainActor @Observable final class SoundBank {
    enum Stroke { case letter, backspace, carriage }
    static let shared = SoundBank()

    var enabled = UserDefaults.standard.object(forKey: "typewriterSound") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "typewriterSound") }
    }
    var preset = SoundPreset(rawValue: UserDefaults.standard.string(forKey: "soundPreset") ?? "") ?? .classic {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: "soundPreset")
            prepare()
        }
    }

    @ObservationIgnored private var letters: [AVAudioPlayer] = []
    @ObservationIgnored private var carriage: AVAudioPlayer?
    @ObservationIgnored private var backspace: [AVAudioPlayer] = []
    @ObservationIgnored private var prepared: SoundPreset?
    @ObservationIgnored private var keyIndex = 0
    @ObservationIgnored private var backIndex = 0
    @ObservationIgnored private var audition: Task<Void, Never>?

    func prepare() {
        guard prepared != preset else { return }
        prepared = preset
        letters = (0..<8).compactMap { player("key-\($0)") }
        backspace = (0..<3).compactMap { _ in player("backspace") }
        carriage = player("carriage")
    }

    private func player(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.module.url(forResource: preset.prefix + name, withExtension: "wav", subdirectory: "Sounds"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 0.54
        player.prepareToPlay()
        return player
    }

    func select(_ preset: SoundPreset) {
        self.preset = preset
        enabled = true
        audition?.cancel()
        play(.letter)
        audition = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            if !Task.isCancelled { self?.play(.carriage) }
        }
    }

    func play(_ stroke: Stroke) {
        guard enabled else { return }
        prepare()
        let selection: AVAudioPlayer?
        switch stroke {
        case .letter:
            guard !letters.isEmpty else { return }
            selection = letters[keyIndex % letters.count]
            keyIndex += 1
        case .backspace:
            guard !backspace.isEmpty else { return }
            selection = backspace[backIndex % backspace.count]
            backIndex += 1
        case .carriage:
            selection = carriage
        }
        selection?.currentTime = 0
        selection?.play()
    }
}
