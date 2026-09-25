import SwiftUI
import SnapCountCore

/// App shell. Today's count on top, then whether each stage the count depends on is ready.
/// The review screen (WORKPLAN 3e) hangs off this.
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if let person = app.person {
                    TodaySection(library: app.library, person: person)
                }
                GlassesSection(glasses: app.glasses)
                Section {
                    StatusRow(title: "Recognition model", status: app.modelStatus)
                    NavigationLink {
                        EnrollmentView()
                    } label: {
                        StatusRow(title: "Enrollment", status: app.enrollmentStatus)
                    }
                    NavigationLink("Privacy Check") {
                        PrivacyCheckView()
                    }
                } footer: {
                    Text("Everything runs on this iPhone. No photos or face data leave the device.")
                }
            }
            .navigationTitle("SnapCount")
        }
        .task { await app.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.library.requestScan() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Midnight, or a time zone change at sea. Either can change what "today" means.
            app.library.requestScan()
        }
    }
}

private struct TodaySection: View {
    let library: LibraryIngest
    let person: EnrolledPerson
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            switch library.access {
            case .unknown:
                Button("Allow Access to Photos") {
                    Task { await library.requestAccess() }
                }
            case .denied:
                Button("Turn On Photo Access in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .full, .limited:
                count
                if let progress = library.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                        Text("Checking new photos: \(progress.done) of \(progress.total)")
                            .font(.subheadline)
                    }
                }
            }
        } header: {
            Text("Today")
        } footer: {
            footer
        }
    }

    private var count: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(library.todayCount, format: .number)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.default, value: library.todayCount)
            Text("photos of \(person.displayName), out of \(library.todayTotal) taken today")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch library.access {
            case .unknown:
                Text("SnapCount reads today's photos to count the ones that include \(person.displayName). They are checked on this iPhone and never uploaded.")
            case .denied:
                Text("Photo access is off, so only glasses captures can be counted.")
            case .limited:
                Text("Access is limited to the photos you chose. New photos are not counted until you add them in Settings.")
            case .full:
                EmptyView()
            }
            if person.matchThreshold == nil {
                Text("Using a default match cutoff. Add photos of other children in Enrollment to tune it.")
            }
            if library.cloudOnlyCount > 0 {
                Text("\(library.cloudOnlyCount) of today's photos are only in iCloud and were skipped. SnapCount never downloads photos.")
            }
            if library.failedCount > 0 {
                Text("\(library.failedCount) of today's photos could not be checked. SnapCount will try them again.")
            }
            if let error = library.lastError {
                Text("Could not save results: \(error)")
            }
        }
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
