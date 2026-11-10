import AVFoundation
import SwiftUI
import UIKit

/// Live QR capture for pairing. The session is configured once and then left
/// running on a background queue; codes are delivered on the main actor and
/// de-duplicated so one code does not fire repeatedly.
@MainActor
final class QRScannerModel: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case scanning
        case denied
        case unavailable
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var code: String?

    let session = AVCaptureSession()
    var onCode: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.faye.RexRemote.qr")
    private var configured = false

    func start() {
        guard AVCaptureDevice.default(for: .video) != nil else {
            status = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.configure() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        let session = session
        if configured {
            queue.async {
                if !session.isRunning { session.startRunning() }
            }
            status = .scanning
            return
        }
        configured = true
        queue.async { [weak self] in
            session.beginConfiguration()
            session.sessionPreset = .high
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                if output.availableMetadataObjectTypes.contains(.qr) {
                    output.metadataObjectTypes = [.qr]
                }
            }
            session.commitConfiguration()
            session.startRunning()
            Task { @MainActor [weak self] in
                self?.status = .scanning
            }
        }
    }
}

extension QRScannerModel: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let value = metadataObjects
            .compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue })
            .first else { return }

        Task { @MainActor in
            guard value != self.code else { return }
            self.code = value
            self.onCode?(value)
        }
    }
}

/// Camera preview without the boilerplate.
struct QRCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // The layer class is fixed above, so this cast cannot fail.
            layer as! AVCaptureVideoPreviewLayer
        }

        init() {
            super.init(frame: .zero)
            previewLayer.videoGravity = .resizeAspectFill
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }
    }
}
