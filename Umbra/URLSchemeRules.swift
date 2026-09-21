import Foundation

struct URLSchemeRule: Equatable {
    let source: String
    let target: String
    var enabled: Bool

    var title: String { "\(source) → \(target)" }
}

enum URLSchemeRules {
    static let key = "urlSchemeReplacements"

    static var isSupported: Bool {
        guard let version = RHBackend.relaxinMarketingVersion(),
            version.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                UInt($0) != nil
            })
        else { return false }
        return version.compare("0.5.4", options: .numeric) != .orderedAscending
    }

    static func normalize(_ input: String?) -> String? {
        guard var scheme = input?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else { return nil }
        if scheme.hasSuffix("://") { scheme.removeLast(3) }
        guard let first = scheme.utf8.first, (97...122).contains(first),
            scheme.utf8.allSatisfy({
                (97...122).contains($0) || (48...57).contains($0) || [43, 45, 46].contains($0)
            }),
            !scheme.hasPrefix("itms"),
            ![
                "http", "https", "file", "data", "javascript", "about", "tel", "telprompt",
                "sms", "mailto", "facetime", "facetime-audio",
            ].contains(scheme)
        else { return nil }
        return scheme
    }

    private static func configuration() throws -> [String: Any] {
        guard let value = RHBackend.configuration(forKey: key) else { return [:] }
        guard let rules = value as? [String: Any] else {
            throw failure(localized("The saved configuration is not a valid dictionary."))
        }
        return rules
    }

    static func load() throws -> [URLSchemeRule] {
        try configuration().compactMap { source, value in
            guard normalize(source) == source,
                let entry = value as? [String: Any],
                let target = entry["target"] as? String, normalize(target) == target,
                target != source, let enabled = entry["enabled"] as? NSNumber,
                CFGetTypeID(enabled) == CFBooleanGetTypeID()
            else { return nil }
            return URLSchemeRule(source: source, target: target, enabled: enabled.boolValue)
        }.sorted { $0.source < $1.source }
    }

    static func save(_ rule: URLSchemeRule, replacing original: String?) throws {
        guard normalize(rule.source) == rule.source,
            normalize(rule.target) == rule.target
        else { throw failure(localized("Enter a custom App scheme, such as filza.")) }
        guard rule.source != rule.target else {
            throw failure(localized("The source and target schemes must be different."))
        }
        var rules = try configuration()
        guard original == rule.source || rules[rule.source] == nil else {
            throw failure(localized("A rule for this source scheme already exists."))
        }
        if let original { rules.removeValue(forKey: original) }
        rules[rule.source] = ["target": rule.target, "enabled": rule.enabled]
        try RHBackend.setConfiguration(rules, forKey: key)
    }

    static func remove(_ source: String) throws {
        var rules = try configuration()
        rules.removeValue(forKey: source)
        try RHBackend.setConfiguration(rules, forKey: key)
    }

    static func failure(_ message: String) -> NSError {
        NSError(
            domain: "com.umbra.manager.urlschemes", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
    }
}
