//
//  AccessibilitySpeechController.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 03/07/2026.
//

import AVFoundation

/// Speak a composed VoiceOver utterance aloud with `AVSpeechSynthesizer`, so the
/// reviewer hears an element's announcement without turning on VoiceOver.
///
/// The description and hint are enqueued as separate utterances, giving the
/// natural pause VoiceOver leaves before a hint. The audio session ducks other
/// audio and is released when the mode is dismissed.
@MainActor
final class AccessibilitySpeechController {

    private let synthesizer = AVSpeechSynthesizer()
    private var didActivateSession = false

    /// Speak the utterance, interrupting anything already in progress.
    func speak(_ utterance: VoiceOverUtterance) {
        stop()
        guard !utterance.isEmpty else { return }
        activateSessionIfNeeded()
        enqueue(utterance.description)
        if let hint = utterance.hint {
            enqueue(hint)
        }
    }

    /// Stop any in-progress speech without releasing the audio session.
    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Stop and release the audio session, restoring other apps' audio — call
    /// when leaving accessibility mode.
    func end() {
        stop()
        guard didActivateSession else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        didActivateSession = false
    }

    private func enqueue(_ text: String) {
        guard !text.isEmpty else { return }
        // No explicit voice: AVSpeechSynthesizer defaults to the user's locale
        // voice, the closest readable match to their VoiceOver voice.
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    /// Play through the silent switch and duck other audio, matching the intent
    /// to hear the readout on demand.
    private func activateSessionIfNeeded() {
        guard !didActivateSession else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])
        try? session.setActive(true)
        didActivateSession = true
    }
}
