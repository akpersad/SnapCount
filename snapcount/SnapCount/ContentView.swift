import SwiftUI
import SnapCountCore

/// App shell. Shows whether each stage the count depends on is ready. The review screen
/// (WORKPLAN 3e) hangs off this.
struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatusRow(title: "Recognition model", status: app.modelStatus)
                    NavigationLink {
                        EnrollmentView()
                    } label: {
                        StatusRow(title: "Enrollment", status: app.enrollmentStatus)
                    }
                } footer: {
                    Text("Everything runs on this iPhone. No photos or face data leave the device.")
                }
            }
            .navigationTitle("SnapCount")
        }
        .task { await app.load() }
    }
}

private struct StatusRow: View {
    let title: String
    let status: Status

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            switch status {
            case .checking:
                ProgressView()
            case .ready(let detail):
                Label(detail, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .problem(let detail):
                Label(detail, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
