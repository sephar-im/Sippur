import Foundation

enum AppMetadata {
    static let appName = "Sepharim Sippur"

    static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? versionString
    }

    static var copyrightString: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 Sepharim Sippur. All rights reserved."
    }

    static var summary: String {
        "Fast local voice capture that turns speech into text notes on your Mac."
    }
}
