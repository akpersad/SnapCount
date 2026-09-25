import SwiftUI

/// Phone-side controls for the glasses: register, connect, and a capture button for testing
/// without reaching for the HUD.
struct GlassesSection: View {
    let glasses: GlassesController

    var body: some View {
        Section {
            if let problem = glasses.configurationProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                switch glasses.registration {
                case .registered:
                    sessionRows
                case .registering:
                    LabeledContent("Meta AI app") { ProgressView() }
                case .available, .unavailable:
                    Button("Connect SnapCount to Meta AI") {
                        Task { await glasses.register() }
                    }
                }
            }
        } header: {
            Text("Glasses")
        } footer: {
            footer
        }
    }

    @ViewBuilder
    private var sessionRows: some View {
        switch glasses.connection {
        case .idle:
            Button("Start Glasses Session") {
                Task { await glasses.startSession() }
            }
        case .connecting:
            LabeledContent("Connecting") { ProgressView() }
        case .stopping:
            LabeledContent("Disconnecting") { ProgressView() }
        case .connected, .paused:
            LabeledContent("Status") {
                Text(glasses.connection == .paused ? "Paused" : connectedText)
            }
            Button("Take Photo with Glasses") { glasses.capture() }
                .disabled(glasses.connection != .connected || glasses.captureStatus == .capturing)
            captureRow
            Button("End Glasses Session", role: .destructive) { glasses.stopSession() }
        }
    }

    private var connectedText: String {
        glasses.displayActive ? "Connected, count on display" : "Connected"
    }

    @ViewBuilder
    private var captureRow: some View {
        switch glasses.captureStatus {
        case .idle:
            EmptyView()
        case .capturing:
            LabeledContent("Taking photo") { ProgressView() }
        case .saved(let date, let size):
            LabeledContent("Last photo", value: "\(date.formatted(date: .omitted, time: .shortened)), \(size)")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if glasses.registration != .registered {
                Text("Opens the Meta AI app to approve SnapCount. This needs an internet connection, so do it before you travel.")
            } else if glasses.connection == .connected {
                Text("Tap Take Photo on the glasses display, or here. Photos stay in SnapCount on this iPhone and are not added to your library.")
            } else if !glasses.deviceNames.isEmpty {
                Text("Available: \(glasses.deviceNames.joined(separator: ", "))")
            }
            if let problem = glasses.problem {
                Text(problem).foregroundStyle(.orange)
            }
        }
    }
}
