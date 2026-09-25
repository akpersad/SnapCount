import SwiftUI
import SnapCountCore

/// On-device verification for the WORKPLAN Phase 7 storage items. Reads the real files'
/// attributes rather than trusting that the code which wrote them did its job.
///
/// Network egress cannot be checked from inside the app. The footer points at iOS's App
/// Privacy Report, which can (see `docs/pre-trip-checklist.md`).
struct PrivacyCheckView: View {
    @State private var checks: [Check] = []

    var body: some View {
        List {
            Section {
                ForEach(checks) { check in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                            Text(check.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(check.passed ? .green : .red)
                    }
                }
            } footer: {
                Text("To confirm SnapCount sends nothing over the network, turn on App Privacy Report in Settings, Privacy & Security, use SnapCount for a day, then check that it lists no websites for SnapCount.")
            }
        }
        .navigationTitle("Privacy Check")
        .task { checks = Self.run() }
        .refreshable { checks = Self.run() }
    }

    struct Check: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let passed: Bool
    }

    static func run() -> [Check] {
        var checks: [Check] = []

        let plistProblems = PrivacyChecks.problems(in: Bundle.main.infoDictionary)
        checks.append(Check(
            title: "Meta analytics and crash reporting off",
            detail: plistProblems.isEmpty ? "Both opt-outs are set" : plistProblems.joined(separator: "; "),
            passed: plistProblems.isEmpty))

        let enrollment = try? EnrollmentStore.defaultURL()
        checks.append(fileCheck("Face data kept off backups", enrollment, missing: "Not enrolled yet"))
        checks.append(protectionCheck(enrollment))
        checks.append(fileCheck("Photo results kept off backups", try? PhotoRecordStore.defaultURL(), missing: "No photos checked yet"))

        let captures = try? CaptureStore.defaultDirectory()
        let captureCount = captures.map { CaptureStore(directory: $0).count } ?? 0
        checks.append(fileCheck(
            "Glasses photos kept off backups", captures,
            missing: "No glasses photos yet",
            present: "\(captureCount) photos, stored only in SnapCount"))
        return checks
    }

    /// Passes if the item is absent (nothing to leak) or present and excluded from backup.
    private static func fileCheck(_ title: String, _ url: URL?, missing: String, present: String = "Excluded from iCloud and computer backups") -> Check {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return Check(title: title, detail: missing, passed: true)
        }
        let excluded = (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true
        return Check(title: title, detail: excluded ? present : "Would be included in backups", passed: excluded)
    }

    private static func protectionCheck(_ url: URL?) -> Check {
        let title = "Face data locked with the phone"
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return Check(title: title, detail: "Not enrolled yet", passed: true)
        }
        let protection = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.protectionKey] as? FileProtectionType
        let passed = protection == .complete
        return Check(title: title, detail: passed ? "Unreadable while the phone is locked" : "Protection is \(protection?.rawValue ?? "unknown")", passed: passed)
    }
}
