import Foundation
import AVFoundation
import UIKit

/// Thin wrapper around an `AVCaptureSession` configured for still photo capture.
/// Camera is unavailable in the Simulator; the UI degrades gracefully.
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum Status {
        case idle, configuring, running, interrupted, denied, unavailable
    }

    let session = AVCaptureSession()
    private(set) var status: Status = .idle
    /// User-facing zoom, where 1 is the main (wide) lens.
    private(set) var zoomFactor: CGFloat = 1

    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    /// Device zoom factor that corresponds to 1× on a multi-lens virtual camera.
    private var baseZoom: CGFloat = 1
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var isConfigured = false
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?
    private var capturedImage: UIImage?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                               object: session, queue: nil) { [weak self] _ in
                self?.setStatus(.interrupted)
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                               object: session, queue: nil) { [weak self] _ in
                self?.setStatus(.running)
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                               object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.sessionQueue.async {
                    if !self.session.isRunning { self.session.startRunning() }
                    self.setStatus(self.session.isRunning ? .running : .interrupted)
                }
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Lifecycle

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.requestAccess { granted in
                guard granted else {
                    self.setStatus(.denied)
                    return
                }
                self.configureIfNeeded()
                if self.isConfigured, !self.session.isRunning {
                    self.session.startRunning()
                    self.setStatus(.running)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            self.setStatus(.configuring)
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.sessionQueue.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let device = Self.bestBackCamera(),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            setStatus(.unavailable)
            return
        }
        session.addInput(input)
        self.device = device

        // Virtual cameras start on the ultra-wide lens (zoom 1); the main lens sits
        // at the first switch-over factor. Starting there keeps 1× looking normal
        // while still letting the system switch to macro for close-up text.
        if device.constituentDevices.contains(where: { $0.deviceType == .builtInUltraWideCamera }),
           let wide = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            baseZoom = CGFloat(truncating: wide)
        }
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = baseZoom
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        }

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            setStatus(.unavailable)
            return
        }
        session.addOutput(photoOutput)
        if let largest = device.activeFormat.supportedMaxPhotoDimensions
            .max(by: { $0.width * $0.height < $1.width * $1.height }) {
            photoOutput.maxPhotoDimensions = largest
        }
        session.commitConfiguration()
        isConfigured = true
    }

    private static func bestBackCamera() -> AVCaptureDevice? {
        let preferred: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        for type in preferred {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    // MARK: Zoom

    func setZoom(_ requested: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            let minZoom = device.minAvailableVideoZoomFactor / self.baseZoom
            let maxZoom = min(device.maxAvailableVideoZoomFactor / self.baseZoom, 10)
            let clamped = min(max(requested, minZoom), maxZoom)
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = clamped * self.baseZoom
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.zoomFactor = clamped }
        }
    }

    // MARK: Capture

    /// Returns `nil` instead of capturing when the session isn't running
    /// (e.g. interrupted by a call), which would otherwise hang or throw.
    func capturePhoto() async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            sessionQueue.async { [weak self] in
                guard let self,
                      self.isConfigured,
                      self.session.isRunning,
                      self.captureContinuation == nil
                else {
                    cont.resume(returning: nil)
                    return
                }
                self.captureContinuation = cont
                let settings = AVCapturePhotoSettings()
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        sessionQueue.async { self.capturedImage = image }
    }

    /// Always the last callback for a capture, including failed ones, so the
    /// continuation is resumed here and nowhere else.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        sessionQueue.async {
            let image = self.capturedImage
            self.capturedImage = nil
            let cont = self.captureContinuation
            self.captureContinuation = nil
            cont?.resume(returning: image)
        }
    }

    // MARK: Helpers

    private func setStatus(_ newValue: Status) {
        DispatchQueue.main.async { self.status = newValue }
    }
}
