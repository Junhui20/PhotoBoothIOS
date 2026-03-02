import AudioToolbox
import AVFoundation

/// Plays sounds at key moments during the photobooth session.
///
/// Uses system sounds as placeholders. Replace WAV files in bundle for custom branding.
final class SoundManager {

    static let shared = SoundManager()

    private var countdownPlayer: AVAudioPlayer?
    private var shutterPlayer: AVAudioPlayer?

    private init() {
        // Pre-configure audio session for playback alongside camera
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Play countdown beep (system sound fallback).
    func playCountdownBeep() {
        // Use system sound as placeholder — replace with custom WAV if added to bundle
        if let url = Bundle.main.url(forResource: "countdown_beep", withExtension: "wav") {
            playSound(url: url, player: &countdownPlayer)
        } else {
            // Fallback: system keyboard click sound
            AudioServicesPlaySystemSound(1104)
        }
    }

    /// Play shutter click sound.
    func playShutterClick() {
        if let url = Bundle.main.url(forResource: "shutter_click", withExtension: "wav") {
            playSound(url: url, player: &shutterPlayer)
        } else {
            // Fallback: system photo shutter sound
            AudioServicesPlaySystemSound(1108)
        }
    }

    private func playSound(url: URL, player: inout AVAudioPlayer?) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            // Silent fail — sounds are non-critical
        }
    }
}
