#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Profil üst fotoğrafı: birden fazla fotoğrafta sayfalı, yoksa hayvanın maskotu.
struct AnimalPhotoHeader: View {
    let animal: Animal

    var body: some View {
        Group {
            if animal.photoURLs.count > 1 {
                TabView {
                    ForEach(animal.photoURLs, id: \.self) { url in
                        AsyncPhoto(url: url, placeholderSystemImage: animal.species.systemImage)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            } else {
                // Fotoğraf yoksa hayvanın rengine uyan maskot (D18).
                AnimalAvatar(animal: animal)
                .accessibilityLabel(String(localized: "\(animal.displayName) fotoğrafı"))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous))
    }
}

/// Belirgin güvenlik uyarısı (FR-A4): hem kullanıcı hem hayvan güvenliği için.
struct AnimalWarningBanner: View {
    let warning: AnimalWarning

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(MamaColor.statusUrgent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(warning.label)
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.statusUrgent)
                Text(advice)
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                .fill(MamaColor.statusUrgent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                .strokeBorder(MamaColor.statusUrgent.opacity(0.5), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var advice: String {
        switch warning {
        case .doNotApproach:
            return String(localized: "Lütfen yaklaşma; mamayı uzaktan bırak. Hem senin hem onun güvenliği için.")
        case .skittish:
            return String(localized: "Ürkek bir dost. Yavaş hareket et, ani yaklaşma; mamayı bırakıp biraz uzaklaş.")
        case .mayBite:
            return String(localized: "Isırabilir. Elle besleme, dokunmaya çalışma; mamayı kaba bırak.")
        }
    }
}

/// Karakter etiketleri: referanstaki üçlü ikon kutuları.
struct TemperamentTiles: View {
    let tags: [TemperamentTag]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tags, id: \.self) { tag in
                VStack(spacing: 8) {
                    Image(systemName: tag.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(MamaColor.card.opacity(0.7)))
                        .accessibilityHidden(true)
                    Text(tag.label)
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                        .fill(tag.tileColor)
                )
                .accessibilityElement(children: .combine)
            }
        }
    }
}
#endif
