import SwiftUI
import AVFoundation
import Combine

struct ResultView: View {
    private let tsaBlue = Color(red: 0 / 255, green: 51 / 255, blue: 160 / 255)
    private let tsaRed = Color(red: 224 / 255, green: 58 / 255, blue: 62 / 255)

    let result: String
    let onTryAgain: () -> Void

    @StateObject private var tts = VoiceSpeaker()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, tsaBlue],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Keep this easy to read from arm's length.
                Text(result)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
                    .padding(.horizontal, 18)

                Spacer()

                Button {
                    tts.speak(result)
                } label: {
                    Text("Listen Again")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(tsaBlue)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 12)

                Button(action: onTryAgain) {
                    Text("Try Again")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(tsaRed)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onAppear  { tts.speak(result) }
        .onDisappear { tts.stop() }
    }
}

// Keep the synthesizer around while this view is on screen.
@MainActor
final class VoiceSpeaker: ObservableObject {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        let utt = AVSpeechUtterance(string: text)
        utt.rate           = 0.5  // Slower pace is easier to follow.
        utt.pitchMultiplier = 1.0
        utt.voice          = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utt)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
