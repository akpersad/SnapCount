import SwiftUI
import SnapCountCore

/// App shell. Shows whether each stage the count depends on is ready. The enrollment and
/// review screens (WORKPLAN 3d, 3e) hang off this.
struct ContentView: View {
    @State private var model: Status = .checking
    @State private var enrollment: Status = .checking

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatusRow(title: "Recognition model", status: model)
                    StatusRow(title: "Enrollment", status: enrollment)
                } footer: {
                    Text("Everything runs on this iPhone. No photos or face data leave the device.")
                }
            }
            .navigationTitle("SnapCount")
        }
        .task { await refresh() }
    }

    private func refresh() async {
        do {
            _ = try await RecognitionModel.loadEmbedder()
            model = .ready("Ready")
        } catch {
            model = .problem(error.localizedDescription)
        }

        do {
            let store = try EnrollmentStore(fileURL: EnrollmentStore.defaultURL())
            if let person = try store.load()?.people.first {
                enrollment = .ready("\(person.displayName), \(person.sampleCount) photos")
            } else {
                enrollment = .problem("Not set up yet")
            }
        } catch {
            enrollment = .problem(error.localizedDescription)
        }
    }
}

enum Status: Equatable {
    case checking
    case ready(String)
    case problem(String)
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
}
