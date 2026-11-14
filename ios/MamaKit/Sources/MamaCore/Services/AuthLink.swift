import Foundation

/// E-posta doğrulama ve şifre sıfırlama bağlantıları (deep link). Supabase Auth bu adreslere döner:
///
///   mamaharitasi://auth-callback?code=…                 → e-posta doğrulandı (PKCE)
///   mamaharitasi://auth-callback?flow=recovery&code=…   → şifre sıfırlama (redirect'i biz böyle veririz)
///   mamaharitasi://auth-callback#…&type=recovery        → şifre sıfırlama (implicit akış)
///   mamaharitasi://auth-callback#error=…                → süresi dolmuş / kullanılmış bağlantı
public enum AuthLink {
    public enum Kind: Equatable, Sendable {
        case emailConfirmed
        case passwordRecovery
        case failed(String)
    }

    public static let scheme = "mamaharitasi"
    public static let callbackHost = "auth-callback"
    public static let callbackURL = URL(string: "\(scheme)://\(callbackHost)")!
    public static let expiredMessage =
        "Bu bağlantının süresi dolmuş ya da daha önce kullanılmış. Yeni bir bağlantı isteyebilirsin."

    /// Bizim bağlantımız değilse `nil`.
    public static func parse(_ url: URL) -> Kind? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == callbackHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] { params[item.name] = item.value ?? "" }
        if let fragment = components.fragment {
            var fragmentComponents = URLComponents()
            fragmentComponents.query = fragment
            for item in fragmentComponents.queryItems ?? [] { params[item.name] = item.value ?? "" }
        }

        if params["error"] != nil || params["error_code"] != nil { return .failed(expiredMessage) }
        if params["flow"] == "recovery" || params["type"] == "recovery" { return .passwordRecovery }
        return .emailConfirmed
    }

    /// Şifre sıfırlama e-postasının döneceği adres: uygulama bunu görünce "yeni şifre" ister.
    public static func recoveryRedirect(from base: URL) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "flow", value: "recovery")]
        return components.url ?? base
    }
}
