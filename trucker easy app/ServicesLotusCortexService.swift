// ServicesLotusCortexService.swift
// Partner link only — no Lotus API, no health data sent from Trucker Easy.

import Foundation

/// Public marketing / partner portal URL (configure in xcconfig). No PII appended.
enum LotusCortexService {
    private static let defaultPartnerURL = "https://lotus.ai"

    static var partnerPortalURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "LotusCortexWebBaseURL") as? String ?? ""
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
        if normalized.isEmpty || normalized.contains("$(") {
            return URL(string: defaultPartnerURL)!
        }
        return URL(string: normalized) ?? URL(string: defaultPartnerURL)!
    }

    static var isPartnerLinkConfigured: Bool { true }
}
