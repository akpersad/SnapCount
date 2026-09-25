import PhotosUI
import SwiftUI
import SnapCountCore

/// Pick photos, build the reference, review it, save. Also where re-enrollment and deletion
/// live.
struct EnrollmentView: View {
    @Environment(AppModel.self) private var app
    @State private var flow = EnrollmentFlow()

    @State private var name = ""
    @State private var references: [PhotosPickerItem] = []
    @State private var negatives: [PhotosPickerItem] = []
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let person = app.person, case .idle = flow.phase {
                CurrentEnrollmentSection(person: person) { confirmingDelete = true }
            }

            switch flow.phase {
            case .idle:
                pickerSections
            case .analyzing(let done, let total):
                Section {
                    ProgressView(value: Double(done), total: Double(max(total, 1))) {
                        Text("Analyzing photo \(min(done + 1, total)) of \(total)")
                    }
                } footer: {
                    Text("This runs on this iPhone. Keep the app open until it finishes.")
                }
            case .finished(let result):
                EnrollmentResultSections(result: result)
                Section {
                    Button(saveLabel(for: result.evaluation.outcome)) {
                        save(result.evaluation.person)
                    }
                    Button("Start over", role: .cancel) { flow.reset() }
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Start over") { flow.reset() }
                }
            }
        }
        .navigationTitle("Enrollment")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if name.isEmpty, let person = app.person { name = person.displayName }
        }
        .confirmationDialog(
            "Delete enrollment?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                do { try app.deleteEnrollment() } catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text("SnapCount will stop recognizing this person until you set it up again.")
        }
        .alert(
            "Could not save",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var pickerSections: some View {
        Section("Who to count") {
            TextField("Name", text: $name)
                .textContentType(.name)
        }

        // The picker label closure is Sendable, so it cannot read view state directly.
        let referenceCount = references.count
        let negativeCount = negatives.count
        Section {
            PhotosPicker(
                selection: $references,
                maxSelectionCount: 40,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                PickerRow(title: "Photos of them", count: referenceCount)
            }
            PhotosPicker(
                selection: $negatives,
                maxSelectionCount: 80,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                PickerRow(title: "Photos of other children", count: negativeCount)
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("""
                Pick 15 to 30 photos of them from the last year, with varied angles and \
                lighting. Then pick 30 or more photos of other children around the same age. \
                Those must not include them. The other children are how SnapCount learns \
                where to draw the line.
                """)
        }

        Section {
            Button(app.person == nil ? "Build reference" : "Build new reference") {
                guard let embedder = app.embedder else { return }
                flow.start(
                    name: name, references: references, negatives: negatives, embedder: embedder)
            }
            .disabled(!canStart)
        } footer: {
            if app.embedder == nil {
                Text("The recognition model is not loaded.")
            } else if references.count < 2 {
                Text("Pick at least 2 photos of them to continue.")
            }
        }
    }

    private var canStart: Bool {
        app.embedder != nil
            && references.count >= 2
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveLabel(for outcome: EnrollmentEvaluation.Outcome) -> String {
        if case .tuned = outcome { return "Save" }
        return "Save with default threshold"
    }

    private func save(_ person: EnrolledPerson) {
        do {
            try app.save(person)
            references = []
            negatives = []
            flow.reset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PickerRow: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(count == 0 ? "Choose" : "\(count) selected")
                .foregroundStyle(.secondary)
        }
    }
}

private struct CurrentEnrollmentSection: View {
    let person: EnrolledPerson
    let onDelete: () -> Void

    var body: some View {
        Section("Current") {
            LabeledContent("Name", value: person.displayName)
            LabeledContent("Photos used", value: "\(person.sampleCount)")
            LabeledContent("Match threshold") {
                if let threshold = person.matchThreshold {
                    Text(threshold, format: .number.precision(.fractionLength(2)))
                } else {
                    Text("Default (not tuned)").foregroundStyle(.orange)
                }
            }
            LabeledContent("Set up", value: person.enrolledAt.formatted(date: .abbreviated, time: .shortened))
            Button("Delete enrollment", role: .destructive, action: onDelete)
        }
    }
}

private struct EnrollmentResultSections: View {
    let result: EnrollmentResult

    var body: some View {
        Section {
            outcome
            LabeledContent(
                "Usable photos of them",
                value: "\(result.referenceFaces.count) of \(result.referencePhotoCount)")
            LabeledContent(
                "Faces in other photos",
                value: "\(result.negativeFaces.count) from \(result.negativePhotoCount) photos")
        } header: {
            Text("Result")
        } footer: {
            if result.unusableReferences > 0 {
                Text("""
                    \(result.unusableReferences) of their photos had no face clear enough to \
                    use. Blurry, dark, small, or turned-away faces are skipped.
                    """)
            } else if result.referenceFaces.count < 10 {
                Text("Fewer than 10 usable photos. Adding more makes recognition more reliable.")
            }
        }

        if !result.weakestReferences.isEmpty {
            Section {
                FaceStrip(faces: result.weakestReferences)
            } header: {
                Text("Least typical photos of them")
            } footer: {
                Text("""
                    Check each one is really them and not someone else in the photo. Replace any \
                    that score far below the rest.
                    """)
            }
        }

        if !result.closestNegatives.isEmpty {
            Section {
                FaceStrip(faces: result.closestNegatives)
            } header: {
                Text("Most similar other faces")
            } footer: {
                Text("If one of these is actually them, remove that photo from the other children.")
            }
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch result.evaluation.outcome {
        case .tuned(let tuned):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready. Match threshold \(tuned.threshold, format: .number.precision(.fractionLength(2)))")
                    Text("Found \(percent(tuned.recall)) of their photos with no false matches on your set.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .insufficientData:
            Label(
                "Not tuned. Add photos of other children so SnapCount can pick a threshold. Until then it uses a cautious default.",
                systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .notDiscriminative:
            Label(
                "These photos do not separate them from the other children well enough. Try clearer, more varied photos of them, and check the other children set does not include them.",
                systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct FaceStrip: View {
    let faces: [ScoredFace]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(faces) { face in
                VStack(spacing: 4) {
                    Image(uiImage: face.crop)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityHidden(true)
                    if let score = face.score {
                        Text(score, format: .number.precision(.fractionLength(2)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Similarity \(score.formatted(.number.precision(.fractionLength(2))))")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
