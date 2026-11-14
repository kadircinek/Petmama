#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

// Tanışma ekranlarının ortak parçaları. Ton: hayvan ve iş merkezli ("birlikte besleyelim", "tanış").

extension SocialInterest {
    var label: String {
        switch self {
        case .cats: return String(localized: "Kedi")
        case .dogs: return String(localized: "Köpek")
        case .birds: return String(localized: "Kuş")
        case .neutering: return String(localized: "Kısırlaştırma gönüllüsü")
        case .fostering: return String(localized: "Geçici yuva")
        case .vetTransport: return String(localized: "Veteriner taşıma")
        case .foodDonation: return String(localized: "Mama bağışı")
        case .photography: return String(localized: "Sokak hayvanı fotoğrafçılığı")
        }
    }

    var systemImage: String {
        switch self {
        case .cats: return "cat.fill"
        case .dogs: return "dog.fill"
        case .birds: return "bird.fill"
        case .neutering: return "cross.case.fill"
        case .fostering: return "house.fill"
        case .vetTransport: return "car.fill"
        case .foodDonation: return "takeoutbag.and.cup.and.straw.fill"
        case .photography: return "camera.fill"
        }
    }
}

extension DistanceBand {
    /// Kesin mesafe hiçbir zaman gösterilmez; yalnızca aralık.
    var label: String {
        switch self {
        case .under1km: return String(localized: "1 km'den yakın")
        case .from1to3km: return String(localized: "1–3 km")
        case .from3to10km: return String(localized: "3–10 km")
        }
    }
}

/// Başlıklı beyaz form kartı. Başlıklar çağıran yerde `String(localized:)` ile verilir (metin çıkarımı için).
struct SocialFormCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }
}

/// Giriş yapmamış kullanıcıya: buluşmalar ve hayvanseverler yalnızca giriş yapanlara açık.
struct SocialSignInGate: View {
    let message: String
    let onSignIn: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MascotView(.duo, mood: .happy, size: 120)
                Text("Mahallende birlikte besleyelim")
                    .font(MamaFont.title2)
                    .foregroundStyle(MamaColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: message)
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button(action: onSignIn) {
                    Text("Giriş yap")
                }
                .buttonStyle(.mamaPrimary)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .mamaCard(padding: 24)
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.top, 24)
        }
    }
}

/// Sosyal onay verilmemişse: kısa açıklama + onay ekranını açan buton.
struct SocialConsentPrompt: View {
    let title: String
    let message: String
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MamaColor.tileBlue))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    Text(verbatim: message)
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                }
            }
            Button(action: onStart) {
                Text("Tanışmaya başla")
            }
            .buttonStyle(.mamaPrimary(systemImage: "checkmark"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }
}

/// İlgi etiketleri; ortak olanlar vurgulanır.
struct InterestTags: View {
    let interests: [SocialInterest]
    var highlighted: Set<SocialInterest> = []

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(interests, id: \.self) { interest in
                TagChip(
                    interest.label,
                    systemImage: interest.systemImage,
                    style: highlighted.contains(interest) ? .positive : .neutral
                )
            }
        }
    }
}

/// Sayaç: "12/300".
struct CharacterCounter: View {
    let count: Int
    let limit: Int

    var body: some View {
        Text(verbatim: "\(count)/\(limit)")
            .font(MamaFont.caption)
            .monospacedDigit()
            .foregroundStyle(count > limit ? MamaColor.statusUrgent : MamaColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel(String(localized: "\(count) / \(limit) karakter"))
    }
}

/// Form metin alanı arka planı.
extension View {
    func socialFieldBackground() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                    .fill(MamaColor.cardSecondary)
            )
    }
}

enum SocialGate {
    /// Onay gerektiren eylemden önce: onay yoksa `true` (sunucu okunamazsa da onay ekranı gösterilir).
    static func needsConsent(_ services: AppServices) async -> Bool {
        let profile = try? await services.social.socialProfile()
        return (profile ?? nil)?.hasConsented != true
    }
}
#endif
