import SwiftUI
import AVFoundation
import UIKit

struct CameraView: View {
    private let tsaBlue = Color(red: 0 / 255, green: 51 / 255, blue: 160 / 255)
    private let tsaRed = Color(red: 224 / 255, green: 58 / 255, blue: 62 / 255)

    let intent: UserIntent
    @Environment(\.dismiss) private var dismiss

    @State private var resultText: String? = nil
    @State private var isAnalyzing = false
    @StateObject private var speaker = VoiceSpeaker()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let text = resultText {
                // Keep result and camera in one full-screen flow.
                ResultView(result: text) {
                    dismiss()
                }
            } else {
                CameraPreviewView(
                    onCapture: processImage,
                    onCancel: { dismiss() }
                )

                VStack(spacing: 8) {
                    Text("Lay clothes flat with space between items")
                    Text("Use good lighting")
                }
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55)))
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 54)

                // Dim the camera while we process the image.
                if isAnalyzing {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    VStack(spacing: 18) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.6)
                        Text("Analyzing your outfit...")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 8).fill(tsaBlue.opacity(0.85)))
                    }
                }
            }
        }
        .onAppear {
            speaker.speak(cameraPrompt)
        }
        .onDisappear { speaker.stop() }
    }

    private func processImage(_ image: UIImage) {
        speaker.stop()
        isAnalyzing = true
        speaker.speak("Analyzing your outfit now.")
        let capturedIntent = intent
        Task.detached(priority: .userInitiated) {
            let text = ColorAnalyzer.analyze(image: image, intent: capturedIntent)
            await MainActor.run {
                resultText  = text
                isAnalyzing = false
            }
        }
    }

    private var cameraPrompt: String {
        switch intent.type {
        case .matchCheck:
            return "Camera is ready. Put both clothing pieces in the frame, then tap the red capture button."
        case .colorIdentify:
            return "Camera is ready. Fill the frame with the clothing item, then tap the red capture button."
        case .outfitPick:
            return "Camera is ready. Lay out your options with space between them, then tap the red capture button."
        }
    }
}

// SwiftUI wrapper for the UIKit camera controller.
struct CameraPreviewView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CameraVC {
        let vc = CameraVC()
        vc.onCapture = onCapture
        vc.onCancel  = onCancel
        return vc
    }

    func updateUIViewController(_ vc: CameraVC, context: Context) {}

    static func dismantleUIViewController(_ vc: CameraVC, coordinator: ()) {
        vc.stopSession()
    }
}

final class CameraVC: UIViewController {
    var onCapture: ((UIImage) -> Void)?
    var onCancel:  (() -> Void)?

    private let sessionQueue = DispatchQueue(label: "OutfitAssist.camera.session")
    private var session: AVCaptureSession?
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didAddControls = false
    private var isCapturing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if let session = self.session, session.isRunning {
                session.stopRunning()
            }

            self.session = nil

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.previewLayer?.session = nil
                self.previewLayer?.removeFromSuperlayer()
                self.previewLayer = nil
            }
        }
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupSession() }
                } else {
                    DispatchQueue.main.async {
                        self?.showLabel("Camera access is required.\nGo to Settings to enable it.")
                    }
                }
            }
        default:
            showLabel("Camera access is required.\nGo to Settings to enable it.")
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session != nil { return }

            let s = AVCaptureSession()
            s.beginConfiguration()
            if s.canSetSessionPreset(.photo) {
                s.sessionPreset = .photo
            }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input  = try? AVCaptureDeviceInput(device: device),
                s.canAddInput(input), s.canAddOutput(self.photoOutput)
            else {
                s.commitConfiguration()
                DispatchQueue.main.async {
                    self.showLabel("Camera unavailable on this device.")
                }
                return
            }

            s.addInput(input)
            s.addOutput(self.photoOutput)
            s.commitConfiguration()
            self.session = s

            DispatchQueue.main.async {
                let preview = AVCaptureVideoPreviewLayer(session: s)
                preview.videoGravity = .resizeAspectFill
                preview.frame = self.view.bounds
                self.view.layer.insertSublayer(preview, at: 0)
                self.previewLayer = preview
                self.addControls()
            }

            s.startRunning()
        }
    }

    private func addControls() {
        guard !didAddControls else { return }
        didAddControls = true

        // Outer ring makes the shutter easier to spot.
        let ring = UIView()
        ring.backgroundColor = .clear
        ring.layer.borderColor = UIColor.white.cgColor
        ring.layer.borderWidth = 3
        ring.layer.cornerRadius = 46
        ring.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ring)

        let shutter = UIButton()
        shutter.backgroundColor = UIColor(red: 224 / 255, green: 58 / 255, blue: 62 / 255, alpha: 1)
        shutter.layer.cornerRadius = 38
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.addTarget(self, action: #selector(shoot), for: .touchUpInside)
        shutter.addTarget(self, action: #selector(shutterDown(_:)), for: .touchDown)
        shutter.addTarget(self, action: #selector(shutterUp(_:)),   for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(shutter)

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancel)

        NSLayoutConstraint.activate([
            ring.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ring.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            ring.widthAnchor.constraint(equalToConstant: 92),
            ring.heightAnchor.constraint(equalToConstant: 92),

            shutter.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            shutter.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            shutter.widthAnchor.constraint(equalToConstant: 76),
            shutter.heightAnchor.constraint(equalToConstant: 76),

            cancel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cancel.centerYAnchor.constraint(equalTo: ring.centerYAnchor)
        ])
    }

    @objc private func shoot() {
        guard session?.isRunning == true, !isCapturing else { return }
        isCapturing = true
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    @objc private func cancelTapped() { onCancel?() }

    // Tiny press animation so the button feels responsive.
    @objc private func shutterDown(_ btn: UIButton) {
        UIView.animate(withDuration: 0.08) { btn.transform = CGAffineTransform(scaleX: 0.88, y: 0.88) }
    }

    @objc private func shutterUp(_ btn: UIButton) {
        UIView.animate(withDuration: 0.08) { btn.transform = .identity }
    }

    private func showLabel(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }
}

extension CameraVC: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        isCapturing = false

        guard error == nil,
              let raw  = photo.fileDataRepresentation(),
              let img  = UIImage(data: raw),
              // JPEG 0.8 keeps memory use in check on device.
              let jpeg = img.jpegData(compressionQuality: 0.8),
              let compressed = UIImage(data: jpeg)
        else { return }

        DispatchQueue.main.async { [weak self] in
            self?.stopSession()
            self?.onCapture?(compressed)
        }
    }
}
