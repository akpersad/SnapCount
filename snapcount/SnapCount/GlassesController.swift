import Foundation
import ImageIO
import Observation
import Synchronization
import MWDATCore
import MWDATCamera
import MWDATDisplay

// No SwiftUI in this file: MWDATDisplay's Text, Button, and Image would clash with SwiftUI's.

/// Everything that talks to the glasses (WORKPLAN Phases 5 and 6): registration with the Meta AI
/// app, the camera permission, one device session, on-demand photo capture, and the HUD.
///
/// Capture is on demand, not continuous. In DAT 0.9 a photo can only be taken while the camera
/// stream is running, so each capture adds a camera, starts the stream, takes one photo, and
/// stops the camera again. That costs a second or two of startup per photo and saves the
/// battery an all-day stream would burn.
@MainActor
@Observable
final class GlassesController {
    enum Registration: Equatable {
        case unavailable, available, registering, registered
    }

    enum Connection: Equatable {
        case idle, connecting, connected, paused, stopping
    }

    enum CaptureStatus: Equatable {
        case idle
        case capturing
        case saved(at: Date, pixelSize: String)
        case failed(String)
    }

    private(set) var configurationProblem: String?
    private(set) var registration: Registration = .unavailable
    private(set) var deviceNames: [String] = []
    private(set) var connection: Connection = .idle
    private(set) var displayActive = false
    private(set) var captureStatus: CaptureStatus = .idle
    private(set) var problem: String?

    /// Receives each captured photo's bytes. Set by `AppModel` to hand photos to the counter.
    @ObservationIgnored var onPhoto: ((Data) throws -> Void)?

    @ObservationIgnored private var session: DeviceSession?
    @ObservationIgnored private var display: Display?
    @ObservationIgnored private var sessionTokens = ListenerTokenBag()
    @ObservationIgnored private var sessionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var captureTask: Task<Void, Never>?

    @ObservationIgnored private var hud = HUDContent()
    @ObservationIgnored private var hudSending = false
    @ObservationIgnored private var hudDirty = false

    private var wearables: any WearablesInterface { Wearables.shared }

    // MARK: Setup and registration (5a)

    /// Must run after `PrivacyChecks`, so the SDK never starts without its opt-outs.
    func configure() {
        do {
            try Wearables.configure()
        } catch .alreadyConfigured {
            // Fine: SwiftUI can re-run app setup, the SDK only needs it once.
        } catch {
            configurationProblem = error.description
            return
        }

        registration = Self.map(wearables.registrationState)
        Task { [weak self] in
            guard let stream = self?.wearables.registrationStateStream() else { return }
            for await state in stream {
                self?.registration = Self.map(state)
            }
        }
        Task { [weak self] in
            guard let stream = self?.wearables.devicesStream() else { return }
            for await ids in stream {
                guard let self else { return }
                deviceNames = ids.compactMap { self.wearables.deviceForIdentifier($0)?.nameOrId() }
            }
        }
    }

    /// Opens the Meta AI app to approve SnapCount. Needs internet, so it must happen on land.
    func register() async {
        problem = nil
        do {
            try await wearables.startRegistration()
        } catch .alreadyRegistered {
            registration = .registered
        } catch {
            problem = error.description
        }
    }

    func unregister() async {
        stopSession()
        do {
            try await wearables.startUnregistration()
        } catch {
            problem = error.description
        }
    }

    /// The Meta AI app returns here through `snapcount://` after registration.
    func handle(_ url: URL) async {
        do {
            _ = try await wearables.handleUrl(url)
        } catch {
            problem = error.description
        }
    }

    // MARK: Permission and session (5b, 5c)

    func startSession() async {
        guard session == nil, configurationProblem == nil else { return }
        problem = nil
        connection = .connecting

        do {
            var status = try await wearables.checkPermissionStatus(.camera)
            if status != .granted {
                status = try await wearables.requestPermission(.camera)
            }
            guard status == .granted else {
                connection = .idle
                problem = "Camera access was declined. Allow it for SnapCount in the Meta AI app to take photos from the glasses."
                return
            }
        } catch {
            connection = .idle
            problem = error.description
            return
        }

        let session: DeviceSession
        do {
            session = try wearables.createSession(deviceSelector: AutoDeviceSelector(wearables: wearables))
        } catch {
            connection = .idle
            problem = error.description
            return
        }
        self.session = session

        // Observe before starting: the streams do not replay a state that has already passed.
        sessionTasks.append(Task { [weak self] in
            for await state in session.stateStream() {
                self?.sessionStateChanged(state, session)
            }
            self?.sessionEnded()
        })
        sessionTasks.append(Task { [weak self] in
            for await error in session.errorStream() {
                self?.problem = error.description
            }
        })

        do {
            try session.start()
        } catch {
            problem = error.description
            sessionEnded()
        }
    }

    func stopSession() {
        captureTask?.cancel()
        session?.stop()
    }

    private func sessionStateChanged(_ state: DeviceSessionState, _ session: DeviceSession) {
        switch state {
        case .idle, .starting: connection = .connecting
        case .started:
            connection = .connected
            if display == nil { attachDisplay(to: session) }
        case .paused: connection = .paused
        case .stopping: connection = .stopping
        case .stopped: sessionEnded()
        }
    }

    private func sessionEnded() {
        guard session != nil || connection != .idle else { return }
        captureTask?.cancel()
        sessionTokens.clear()
        sessionTokens = ListenerTokenBag()
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = []
        session = nil
        display = nil
        displayActive = false
        connection = .idle
    }

    // MARK: Capture (5c, 5d)

    /// Takes one photo with the glasses camera. Ignored while a capture is already in flight:
    /// results carry no request ID, so two at once could not be told apart.
    func capture() {
        guard captureTask == nil else { return }
        guard let session, connection == .connected else {
            captureStatus = .failed("Connect the glasses first.")
            return
        }
        captureTask = Task { [weak self] in
            await self?.runCapture(on: session)
            self?.captureTask = nil
            self?.sendHUD()
        }
    }

    private func runCapture(on session: DeviceSession) async {
        captureStatus = .capturing
        sendHUD()

        let camera: Camera
        do {
            guard let added = try session.addCamera() else {
                captureStatus = .failed("The glasses camera is not ready yet. Try again in a moment.")
                return
            }
            camera = added
        } catch {
            captureStatus = .failed(error.description)
            return
        }

        let result = await Self.takeOnePhoto(with: camera)
        camera.stop()

        switch result {
        case .success(let data):
            do {
                try onPhoto?(data)
                captureStatus = .saved(at: Date(), pixelSize: Self.pixelSize(of: data))
            } catch {
                captureStatus = .failed("The photo could not be saved: \(error.localizedDescription)")
            }
        case .failure(let failure):
            captureStatus = .failed(failure.message)
        }
    }

    /// Starts the stream, captures once it is running, and returns the first photo, the first
    /// error, or a timeout, whichever comes first.
    private nonisolated static func takeOnePhoto(with camera: Camera) async -> Result<Data, CaptureFailure> {
        let stream = camera.stream
        let tokens = ListenerTokenBag()
        defer { tokens.clear() }

        return await withCheckedContinuation { continuation in
            let finish = Once(continuation)
            let requested = Mutex(false)

            // Listeners go on before `start()`, which can reach `.streaming` immediately.
            stream.statePublisher.listen { state in
                guard state == .streaming else { return }
                // `.streaming` can be published more than once. Capture on the first.
                let first = requested.withLock { done in defer { done = true }; return !done }
                if first, !stream.capturePhoto(format: .jpeg) {
                    finish(.failure(CaptureFailure("The glasses did not accept the capture request.")))
                }
            }.store(in: tokens)
            stream.photoDataPublisher.listen { photo in
                finish(.success(photo.data))
            }.store(in: tokens)
            stream.errorPublisher.listen { error in
                finish(.failure(CaptureFailure(error.description)))
            }.store(in: tokens)

            stream.start()

            Task {
                try? await Task.sleep(for: .seconds(30))
                finish(.failure(CaptureFailure("The photo took too long to arrive. Try again, or restart the glasses.")))
            }
        }
    }

    private static func pixelSize(of data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return "unknown size" }
        return "\(width) x \(height)"
    }

    // MARK: HUD (6a, 6b, 6c)

    /// Called whenever the count or the enrolled name changes. The whole view is re-sent each
    /// time because the display has no partial updates.
    func updateHUD(count: Int, name: String?, checking: Bool) {
        let next = HUDContent(count: count, name: name, checking: checking)
        guard next != hud else { return }
        hud = next
        sendHUD()
    }

    private func attachDisplay(to session: DeviceSession) {
        guard let device = wearables.deviceForIdentifier(session.deviceId), device.supportsDisplay() else {
            return
        }
        do {
            let display = try session.addDisplay()
            self.display = display
            display.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    self?.displayActive = state == .started
                    if state == .started { self?.sendHUD() }
                }
            }.store(in: sessionTokens)
            display.start()
        } catch {
            problem = error.description
        }
    }

    /// Sends the current HUD, coalescing bursts: if the count changes mid-send, one more send
    /// follows with the latest state rather than one per change.
    private func sendHUD() {
        guard let display, displayActive else { return }
        if hudSending {
            hudDirty = true
            return
        }
        hudSending = true
        Task { [weak self] in
            repeat {
                guard let self else { return }
                hudDirty = false
                do {
                    try await display.send(makeHUD())
                } catch {
                    problem = error.localizedDescription
                }
            } while self?.hudDirty == true
            self?.hudSending = false
        }
    }

    private func makeHUD() -> FlexBox {
        let label = hud.name.map { "photos of \($0) today" } ?? "Set up SnapCount on your phone"
        let status: String? = switch captureStatus {
        case .capturing: "Taking photo…"
        case .failed: "Photo failed. Try again."
        default: hud.checking ? "Checking photos…" : nil
        }
        let busy = captureTask != nil

        return FlexBox(direction: .column, spacing: 8, alignment: .center, crossAlignment: .center) {
            Text("\(hud.count)", style: .heading)
            Text(label, style: .meta, color: .secondary)
            if let status {
                Text(status, style: .meta)
            }
            Button(
                label: busy ? "Taking photo" : "Take photo",
                style: .primary,
                iconName: .fourCornerFrame
            ) { [weak self] in
                Task { @MainActor in self?.capture() }
            }
        }
        .padding(12)
    }

    private static func map(_ state: RegistrationState) -> Registration {
        switch state {
        case .unavailable: .unavailable
        case .available: .available
        case .registering: .registering
        case .registered: .registered
        @unknown default: .unavailable
        }
    }
}

private struct HUDContent: Equatable {
    var count = 0
    var name: String?
    var checking = false
}

struct CaptureFailure: Error, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Resumes a continuation exactly once, whichever of several callbacks gets there first.
private final class Once<T: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<T, Never>?>

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = Mutex(continuation)
    }

    func callAsFunction(_ value: T) {
        let pending = continuation.withLock { stored in
            defer { stored = nil }
            return stored
        }
        pending?.resume(returning: value)
    }
}
