import Foundation

// MARK: - Compatibility

/// Supported OS range per the class-13 MobileGestalt bug:
///   iOS 26.0 ... iOS 27.2.1 (build 24B156)
/// Anything newer than 27.2.1 is unverified and treated as unsupported.
enum DeviceCompatibility {

    /// Reference build of the newest verified-supported OS (27.2.1).
    /// Builds are compared alpha-first, so 24B119 (27.2) sorts below this.
    static let newestSupportedBuild = Build(alpha: "B", number: 156, seed: "")

    /// Human-readable form of `newestSupportedBuild`. The unsupported
    /// screen reads it from here so the two can't drift apart.
    static let newestVerifiedDescription = "iOS 27.2.1 (build 24B156)"

    struct OSInfo {
        let version: OperatingSystemVersion
        let build: String?
    }

    enum Status {
        case supported
        case unsupported(reason: String)
    }

    struct Build: Comparable {
        let alpha: String
        let number: Int
        let seed: String

        static func < (lhs: Build, rhs: Build) -> Bool {
            if lhs.alpha != rhs.alpha { return lhs.alpha < rhs.alpha }
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.seed < rhs.seed
        }

        /// "24A5390f" -> (alpha: "A", number: 5390, seed: "f")
        static func parse(_ raw: String) -> Build? {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let letterStart = s.firstIndex(where: { $0.isLetter }) else { return nil }
            var letterEnd = letterStart
            while letterEnd < s.endIndex, s[letterEnd].isLetter {
                letterEnd = s.index(after: letterEnd)
            }
            let alpha = String(s[letterStart..<letterEnd]).uppercased()

            let numStart = letterEnd
            var numEnd = numStart
            while numEnd < s.endIndex, s[numEnd].isNumber {
                numEnd = s.index(after: numEnd)
            }
            guard numStart < numEnd, let number = Int(String(s[numStart..<numEnd])) else {
                return nil
            }
            let seed = String(s[numEnd...])
            return Build(alpha: alpha, number: number, seed: seed)
        }
    }

    /// Reads the marketing OS version and build string of the running system.
    static func currentOS() -> OSInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var build: String? = nil
        let paths = [
            "/System/Library/CoreServices/SystemVersion.plist",
            "/System/Library/CoreServices/.system_version.plist"
        ]
        for p in paths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let b = plist["ProductBuildVersion"] as? String {
                build = b
                break
            }
        }
        return OSInfo(version: version, build: build)
    }

    /// Evaluates support. `build` may be nil; iOS 27 then falls back to the
    /// marketing version (27.2.x accepted, anything newer refused).
    static func evaluate(version: OperatingSystemVersion,
                         build: String?) -> Status {
        let major = version.majorVersion

        if major < 26 {
            return .unsupported(reason:
                "This app requires iOS 26.0 or newer. You are running iOS \(major).")
        }

        if major > 27 {
            return .unsupported(reason:
                "iOS \(major) is patched. The MobileGestalt access used by this app is only verified up to \(newestVerifiedDescription).")
        }

        if major == 27 {
            guard let raw = build, let parsed = Build.parse(raw) else {
                // No build string to compare against — fall back to the
                // marketing version so a failed SystemVersion.plist read
                // can't lock out a release we know is inside the range.
                if version.minorVersion > 2 ||
                    (version.minorVersion == 2 && version.patchVersion > 1) {
                    return .unsupported(reason:
                        "Unable to verify your iOS 27 build. Only up to \(newestVerifiedDescription) is supported; newer builds are patched.")
                }
                return .supported
            }
            if parsed > newestSupportedBuild {
                return .unsupported(reason:
                    "Your build \(raw) is newer than \(newestVerifiedDescription) and is patched.")
            }
        }

        return .supported
    }

    static var currentStatus: Status {
        let os = currentOS()
        return evaluate(version: os.version, build: os.build)
    }

    static var currentInfo: OSInfo { currentOS() }

    // MARK: - Feature gating

    /// Tweaks and Siri AI Setup need iOS 27 for full support. iOS 26.x is
    /// limited to PosterBoard, which works standalone on both versions.
    static func fullFeatureStatus(feature: String) -> Status {
        let version = currentOS().version
        if version.majorVersion < 27 {
            return .unsupported(reason:
                "\(feature) requires iOS 27. You are running iOS \(version.majorVersion).\(version.minorVersion), which currently supports PosterBoard only.")
        }
        return .supported
    }

    static var supportsFullFeatureSet: Bool {
        if case .supported = fullFeatureStatus(feature: "This feature") { return true }
        return false
    }
}
