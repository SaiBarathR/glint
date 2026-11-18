import AVFoundation

final class Speech: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speech()
    private let synth = AVSpeechSynthesizer()
    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { synth.isSpeaking }

    func toggle(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate); return }
        let u = AVSpeechUtterance(string: text)
        let prefs = Preferences.shared
        if !prefs.speechVoiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: prefs.speechVoiceID) { u.voice = voice }
        // 0.5 is the system default speaking rate.
        u.rate = Float(min(max(prefs.speechRate, 0.05), 1))
        synth.speak(u)
    }
}
