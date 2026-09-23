import Foundation

/// Launch-time verification of the Info.plist settings the privacy guarantee depends on.
///
/// Fails closed. Meta's analytics and crash reporting are both on unless explicitly opted out,
/// and the opt-out keys are easy to get subtly wrong (they are nested dictionaries, and a
/// bare `OptOut` directly under `MWDAT` is silently ignored). A crash on launch is a far better
/// outcome than an app that quietly reports home from a cruise ship.
enum PrivacyChecks {
    static func verifyOrHalt(info: [String: Any]? = Bundle.main.infoDictionary) {
        let problems = problems(in: info)
        guard problems.isEmpty else {
            fatalError("Privacy configuration invalid: " + problems.joined(separator: "; "))
        }
    }

    static func problems(in info: [String: Any]?) -> [String] {
        guard let mwdat = info?["MWDAT"] as? [String: Any] else {
            return ["MWDAT dictionary missing from Info.plist"]
        }

        var problems: [String] = []
        for section in ["Analytics", "CrashReporting"] {
            let optOut = (mwdat[section] as? [String: Any])?["OptOut"] as? Bool
            if optOut != true { problems.append("MWDAT.\(section).OptOut is not true") }
        }

        // An unsubstituted $(VAR) means Secrets.xcconfig was not applied to the build.
        for key in ["MetaAppID", "ClientToken", "TeamID"] {
            let value = mwdat[key] as? String ?? ""
            if value.isEmpty || value.hasPrefix("$(") {
                problems.append("MWDAT.\(key) is not set; check Secrets.xcconfig")
            }
        }
        return problems
    }
}
