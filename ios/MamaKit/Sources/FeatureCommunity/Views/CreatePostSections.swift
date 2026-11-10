#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Başlıklı beyaz form kartı.
struct CommunityFormCard<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let content: Content

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
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

extension CommunityPostKind {
    /// Metin alanındaki yönlendirme; tür değişince değişir.
    var composerPlaceholder: String {
        switch self {
        case .note: return String(localized: "Ör. Pamuk bugün çok neşeliydi, kaplar dolu.")
        case .question: return String(localized: "Ör. Kış için kulübeyi nasıl yalıtıyorsunuz?")
        case .coverRequest: return String(localized: "Ne zaman yoksun, mama nerede duruyor, nelere dikkat edilmeli?")
        case .supply: return String(localized: "Ör. Elimde açılmamış 3 kg yavru maması var, ihtiyacı olana verebilirim.")
        case .alert: return String(localized: "Ne gördün, nerede ve ne zaman? Sakin ve net yaz.")
        }
    }
}

/// Beş paylaşım türü: sıkışık ızgara + seçili türün açıklaması.
struct CreatePostKindSection: View {
    let model: CreatePostViewModel
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        CommunityFormCard("Ne paylaşmak istersin?") {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(CommunityPostKind.allCases, id: \.self) { kind in
                    CreatePostKindTile(kind: kind, isSelected: model.kind == kind) {
                        model.kind = kind
                    }
                }
            }
            Text(verbatim: model.kind.explanation)
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
        }
    }
}

struct CreatePostKindTile: View {
    let kind: CommunityPostKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(kind.tileColor))
                    .accessibilityHidden(true)
                Text(verbatim: kind.label)
                    .font(MamaFont.subheadline.weight(.semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                    .fill(MamaColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? MamaColor.ink : MamaColor.stroke, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(kind.explanation)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Metin alanı + canlı sayaç (600).
struct CreatePostBodySection: View {
    @Bindable var model: CreatePostViewModel

    var body: some View {
        CommunityFormCard("Ne anlatmak istersin?") {
            TextField(model.kind.composerPlaceholder, text: $model.bodyText, axis: .vertical)
                .lineLimit(4...10)
                .font(MamaFont.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                        .fill(MamaColor.cardSecondary)
                )
            Text(verbatim: "\(model.trimmedBody.count)/\(CommunityPolicy.maxBodyLength)")
                .font(MamaFont.caption)
                .monospacedDigit()
                .foregroundStyle(model.isOverLimit ? MamaColor.statusUrgent : MamaColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(String(localized: "\(model.trimmedBody.count) / \(CommunityPolicy.maxBodyLength) karakter"))
        }
    }
}

/// "Yerime bakar mısın?" tarihleri: İstanbul gününe göre, başlangıç ≥ bugün, en fazla 30 gün.
struct CreatePostCoverDatesSection: View {
    @Bindable var model: CreatePostViewModel

    var body: some View {
        CommunityFormCard("Ne zaman yoksun?", subtitle: "En fazla \(CommunityPolicy.maxCoverDays) günlük bir aralık seçebilirsin.") {
            DatePicker("İlk gün", selection: $model.coverFrom, in: model.earliestCoverStart..., displayedComponents: .date)
            DatePicker("Son gün", selection: $model.coverTo, in: model.coverToRange, displayedComponents: .date)
            if let range = CommunityFormat.coverRange(from: model.coverFrom, to: model.coverTo) {
                TagChip(range, systemImage: "calendar", style: .info)
            }
        }
        .font(MamaFont.subheadline)
        .environment(\.calendar, CommunityFormat.istanbulCalendar)
        .environment(\.timeZone, CommunityFormat.istanbulCalendar.timeZone)
        .onChange(of: model.coverFrom) { _, _ in
            model.normalizeCoverDates()
        }
    }
}

/// "Nokta bağla": önce koruyucusu olunan noktalar, sonra yakındakiler. "Yerime bakar mısın?" için zorunlu.
struct CreatePostSpotSection: View {
    let model: CreatePostViewModel

    private var title: LocalizedStringKey {
        model.isSpotRequired ? "Hangi noktaya bakılacak?" : "Nokta bağla (isteğe bağlı)"
    }

    private var subtitle: LocalizedStringKey {
        model.isSpotRequired
            ? "Gönüllüler nereye uğrayacağını böyle bilir."
            : "Paylaşımın bir noktayla ilgiliyse seç; kartta bağlantısı görünür."
    }

    var body: some View {
        CommunityFormCard(title, subtitle: subtitle) {
            if model.spotOptions.isEmpty {
                if model.hasLoadedSpots {
                    emptyText
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(model.spotOptions) { option in
                    ChoiceCard(
                        option.spot.title,
                        subtitle: detail(for: option),
                        systemImage: option.spot.type.systemImage,
                        tint: option.source == .nearby ? MamaColor.tileMint : MamaColor.tileLavender,
                        isSelected: model.selectedSpotId == option.id
                    ) {
                        model.toggleSpot(option.id)
                    }
                }
            }
            if model.hasLoadedSpots, model.selectedSpotId != nil, model.selectedSpot == nil {
                // Seçili nokta listede yoksa (yüklenemediyse) bağlı olduğu yine de görünsün.
                TagChip(String(localized: "Bir nokta bağlı"), systemImage: "mappin.and.ellipse", style: .info)
            }
        }
    }

    private var emptyText: Text {
        model.isSpotRequired
            ? Text("Yakınında ya da koruyucusu olduğun bir nokta bulamadık. Haritadan noktanı açıp oradan da “Yerime bakar mısın?” diyebilirsin.")
            : Text("Yakınında kayıtlı nokta bulamadık. Nokta bağlamadan da paylaşabilirsin.")
    }

    /// "Koruyucusu olduğun nokta · 180 m"
    private func detail(for option: CommunitySpotOption) -> String? {
        let distance = option.distanceMeters.map { MamaFormat.distance($0) }
        switch option.source {
        case .guarded:
            let label = String(localized: "Koruyucusu olduğun nokta")
            return distance.map { "\(label) · \($0)" } ?? label
        case .preset, .nearby:
            return distance
        }
    }
}

/// İsteğe bağlı tek fotoğraf. EXIF/GPS temizliği yüklemeden önce yapılır.
struct CreatePostPhotoSection: View {
    let model: CreatePostViewModel

    var body: some View {
        CommunityFormCard("Fotoğraf (isteğe bağlı)") {
            if let photo = model.photo {
                PhotoThumbnail(data: photo.data) { model.removePhoto() }
            } else {
                PhotoInputButton(onPicked: { data in model.setPhoto(data) }) {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.title3)
                        Text("Ekle").font(MamaFont.caption)
                    }
                    .foregroundStyle(MamaColor.textSecondary)
                    .frame(width: 96, height: 96)
                    .background(
                        RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                            .strokeBorder(MamaColor.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    )
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Fotoğraf ekle"))
            }
        }
    }
}
#endif
