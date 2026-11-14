import Foundation
import MamaCore

/// Info.plist'teki (xcconfig'den gelen) yapılandırma. `MAMA_SUPABASE_URL` boşsa demo modu (D7).
public struct AppConfiguration: Equatable, Sendable {
    public var supabaseURL: URL?
    public var supabaseAnonKey: String?
    public var app: AppConfig

    public var usesSupabase: Bool { supabaseURL != nil && !(supabaseAnonKey ?? "").isEmpty }

    public init(supabaseURL: URL?, supabaseAnonKey: String?, app: AppConfig) {
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.app = app
    }

    public static func from(infoDictionary info: [String: Any]) -> AppConfiguration {
        func string(_ key: String) -> String? {
            guard let raw = info[key] as? String else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Çözülmemiş xcconfig değişkeni ("$(MAMA_…)") boş sayılır.
            return value.isEmpty || value.hasPrefix("$(") ? nil : value
        }
        func url(_ key: String) -> URL? {
            string(key).flatMap(URL.init(string:)).flatMap { $0.scheme == nil ? nil : $0 }
        }

        let supabaseURL = url("MAMA_SUPABASE_URL")
        let anonKey = string("MAMA_SUPABASE_ANON_KEY")
        let isDemo = supabaseURL == nil || anonKey == nil

        var donation = DonationConfig.placeholder
        if let partner = string("MAMA_PARTNER_NAME") { donation.partnerName = partner }
        donation.donationURL = url("MAMA_DONATION_URL")
        if let rate = string("MAMA_USD_TRY_RATE").flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }) {
            donation.usdToTry = rate
        }

        var app = AppConfig(isDemo: isDemo, donation: donation)
        if let email = string("MAMA_SUPPORT_EMAIL") { app.supportEmail = email }
        app.privacyPolicyURL = url("MAMA_PRIVACY_URL")
        app.termsURL = url("MAMA_TERMS_URL")
        app.kvkkNoticeURL = url("MAMA_KVKK_URL")
        // Info.plist: MAMA_APNS_ENV = $(APS_ENVIRONMENT) → "development" (Debug) | "production" (Release).
        if string("MAMA_APNS_ENV") == "development" { app.apnsEnvironment = .sandbox }

        if isDemo, donation.donationURL == nil {
            // Demo modunda bağış akışı denenebilsin diye örnek alan adı.
            app.donation = DonationConfig(partnerName: "Ortak dernek (demo)", donationURL: URL(string: "https://example.org/bagis"), usdToTry: 41.5)
        }
        return AppConfiguration(supabaseURL: supabaseURL, supabaseAnonKey: anonKey, app: app)
    }
}
