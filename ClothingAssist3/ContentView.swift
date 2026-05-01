import SwiftUI
import Speech
import AVFoundation
import Combine

struct ContentView: View {

    private let tsaBlue = Color(red: 0 / 255, green: 51 / 255, blue: 160 / 255)
    private let tsaRed = Color(red: 224 / 255, green: 58 / 255, blue: 62 / 255)

    @State private var status = "Hold to speak"
    @State private var guidanceText = "Say: Do these match? What color is this? Pick an outfit."
    @State private var isRecording = false
    @State private var transcript = ""
    @State private var pendingIntent: UserIntent? = nil
    @State private var showCamera = false

    @StateObject private var mic = SpeechRecorder()
    @StateObject private var speaker = VoiceSpeaker()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tsaBlue, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer().frame(height: 24)

                Text("OutfitAssist")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)

                Text("Hold the button in the middle and speak.")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Text(guidanceText)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 28)

                VStack(spacing: 6) {
                    Text("Do these match?")
                    Text("What colors are these?")
                    Text("Pick an outfit from these")
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)

                Spacer(minLength: 12)

                micButton

                fallbackButtons

                Spacer(minLength: 12)

                Text(status)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.35))
                            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    )
                    .animation(.easeInOut(duration: 0.2), value: status)

                if !transcript.isEmpty {
                    Text("\"\(transcript)\"")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.28))
                        )
                        .padding(.horizontal, 24)
                        .lineLimit(4)
                }

                Spacer().frame(height: 28)
            }
        }
        .onAppear {
            speaker.speak("Welcome to Outfit Assist. Hold the large red button in the middle of the screen and say, do these match, what color is this, or pick an outfit.")
        }
        .onDisappear { speaker.stop() }
        .fullScreenCover(isPresented: $showCamera, onDismiss: resetState) {
            if let intent = pendingIntent {
                CameraView(intent: intent)
            }
        }
    }

    // Hold-to-talk mic button.
    private var micButton: some View {
        Circle()
            .fill(isRecording ? Color.white : tsaRed)
            .frame(width: 172, height: 172)
            .shadow(color: tsaRed.opacity(0.45), radius: 22, x: 0, y: 12)
            .overlay(
                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 68, weight: .bold))
                    .foregroundColor(isRecording ? tsaRed : .white)
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isRecording ? 0.95 : 0.55), lineWidth: 5)
                    .padding(6)
            )
            .scaleEffect(isRecording ? 1.06 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isRecording)
            .accessibilityLabel("Hold to speak")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isRecording { startRecording() } }
                    .onEnded   { _ in stopRecording() }
            )
    }

    private var fallbackButtons: some View {
        VStack(spacing: 10) {
            Button("Match these") {
                openCamera(with: UserIntent(type: .matchCheck, colorTone: nil, brightness: nil, style: nil))
            }
            Button("Identify colors") {
                openCamera(with: UserIntent(type: .colorIdentify, colorTone: nil, brightness: nil, style: nil))
            }
            Button("Pick outfit") {
                openCamera(with: UserIntent(type: .outfitPick, colorTone: nil, brightness: nil, style: nil))
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .buttonStyle(.borderedProminent)
        .tint(tsaRed)
        .padding(.horizontal, 28)
    }

    private func startRecording() {
        speaker.stop()
        isRecording = true
        status = "Listening..."
        guidanceText = "Keep holding while you speak."
        transcript = ""
        mic.start { partial in
            transcript = partial
        } onError: { message in
            isRecording = false
            status = message
            speaker.speak(message)
        }
    }

    private func stopRecording() {
        isRecording = false
        mic.stop()

        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = "Hold to speak"
            guidanceText = "I did not catch that. Hold the red button and try again."
            speaker.speak("I did not catch that. Hold the red button and try again.")
            return
        }

        status = "Analyzing..."
        let intent = IntentParser.parse(transcript)
        pendingIntent = intent
        guidanceText = cameraGuidance(for: intent)
        speaker.speak(spokenCameraGuidance(for: intent))

        // Give users a moment to hear the prompt before the camera opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            status = "Done"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCamera = true
            }
        }
    }

    private func openCamera(with intent: UserIntent) {
        speaker.stop()
        mic.stop()
        isRecording = false
        transcript = ""
        pendingIntent = intent
        status = "Done"
        guidanceText = cameraGuidance(for: intent)
        showCamera = true
    }

    private func resetState() {
        mic.stop()
        speaker.stop()
        isRecording = false
        showCamera = false
        transcript = ""
        pendingIntent = nil
        status = "Hold to speak"
        guidanceText = "Say: Do these match? What color is this? Pick an outfit."
    }

    private func cameraGuidance(for intent: UserIntent) -> String {
        switch intent.type {
        case .matchCheck:
            return "Now take one photo with the clothing pieces next to each other."
        case .colorIdentify:
            return "Now point the camera at the item you want identified."
        case .outfitPick:
            return "Now lay out two or three choices and take one clear photo."
        }
    }

    private func spokenCameraGuidance(for intent: UserIntent) -> String {
        switch intent.type {
        case .matchCheck:
            return "Got it. I will check if they match. Put the clothing pieces next to each other and take a photo."
        case .colorIdentify:
            return "Got it. I will identify the color. Point the camera at the clothing item and take a photo."
        case .outfitPick:
            return "Got it. I will help pick an outfit. Lay out two or three choices and take one clear photo."
        }
    }
}

// Speech-to-text helper for the hold-to-talk flow.
@MainActor
final class SpeechRecorder: ObservableObject {
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var didInstallTap = false
    private var isStopping = false

    func start(onPartial: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        guard recognizer != nil else {
            onError("Speech is unavailable")
            return
        }

        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { onError("Speech permission needed") }
                return
            }

            AVAudioApplication.requestRecordPermission { granted in
                guard granted else {
                    DispatchQueue.main.async { onError("Microphone permission needed") }
                    return
                }
                DispatchQueue.main.async {
                    self.beginSession(onPartial: onPartial, onError: onError)
                }
            }
        }
    }

    func stop() {
        finishRecording(cancelTask: false)
    }

    private func finishRecording(cancelTask: Bool) {
        guard !isStopping else { return }
        isStopping = true

        if didInstallTap {
            engine.inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }

        if engine.isRunning {
            engine.stop()
        }

        request?.endAudio()
        if cancelTask {
            task?.cancel()
        }
        request = nil
        if cancelTask {
            task = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isStopping = false
    }

    private func beginSession(onPartial: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        // Clear any old session before starting a new one.
        if engine.isRunning { finishRecording(cancelTask: true) }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try? audioSession.setPreferredSampleRate(44_100)
            try? audioSession.setPreferredInputNumberOfChannels(1)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onError("Microphone is not ready")
            return
        }

        task?.cancel()
        task = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let node = engine.inputNode
        let fmt = node.outputFormat(forBus: 0)

        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            finishRecording(cancelTask: true)
            onError("Microphone is not ready")
            return
        }

        if didInstallTap {
            node.removeTap(onBus: 0)
            didInstallTap = false
        }

        // Some routes report 0 Hz here. Installing a tap with that format crashes.
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
            guard buf.frameLength > 0 else { return }
            req.append(buf)
        }
        didInstallTap = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            finishRecording(cancelTask: true)
            onError("Could not start listening")
            return
        }

        task = recognizer?.recognitionTask(with: req) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { onPartial(text) }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    self.finishRecording(cancelTask: error != nil)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
