import AppKit
import OrbitCore

enum OrbitSound: Equatable {
    case stretch, focus, reminder
}

extension AlertTone {
    var systemName: NSSound.Name {
        switch self {
        case .pop: return "Pop"
        case .glass: return "Glass"
        case .tink: return "Tink"
        case .ping: return "Ping"
        }
    }
}

/// Retains the sound for playback and keeps simultaneous alerts from stacking.
@MainActor
final class OrbitSoundPlayer {
    private var current: NSSound?

    func play(_ cue: AlertTone) {
        current?.stop()
        guard let sound = NSSound(named: cue.systemName) else { return }
        sound.volume = 0.4
        current = sound
        sound.play()
    }
}
