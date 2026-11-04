#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Başlıklı beyaz form kartı.
struct NeedFormCard<Content: View>: View {
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

/// 8 ihtiyaç tipi (FR-I1).
struct NeedTypeGridSection: View {
    @Bindable var model: CreateNeedViewModel
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NeedFormCard("Ne gerekiyor?") {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(NeedType.allCases, id: \.self) { type in
                    NeedTypeTile(type: type, isSelected: model.type == type) {
                        model.type = type
                    }
                }
            }
        }
    }
}

struct NeedTypeTile: View {
    let type: NeedType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(type.tileColor))
                    .accessibilityHidden(true)
                Text(type.label)
                    .font(MamaFont.subheadline.weight(.semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct NeedUrgencySection: View {
    @Bindable var model: CreateNeedViewModel

    var body: some View {
        NeedFormCard("Ne kadar acil?") {
            ChoiceCard(
                String(localized: "Normal"),
                subtitle: String(localized: "Birkaç gün içinde çözülmesi yeterli"),
                systemImage: "clock",
                tint: MamaColor.tileBlue,
                isSelected: model.urgency == .normal
            ) {
                model.urgency = .normal
            }
            ChoiceCard(
                String(localized: "Acil"),
                subtitle: String(localized: "Yaralı veya hasta hayvan için"),
                systemImage: "exclamationmark.triangle.fill",
                tint: MamaColor.tilePeach,
                isSelected: model.urgency == .urgent
            ) {
                model.urgency = .urgent
            }
        }
    }
}

struct NeedDescriptionSection: View {
    @Bindable var model: CreateNeedViewModel

    var body: some View {
        NeedFormCard("Ne gördün?", subtitle: "Gönüllülerin hazırlıklı gelmesi için kısaca anlat.") {
            TextField("Ör. Arka bacağında yara var, topallıyor.", text: $model.descriptionText, axis: .vertical)
                .lineLimit(4...8)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                        .fill(MamaColor.cardSecondary)
                )
            HStack {
                Text("En az \(CreateNeedViewModel.minDescriptionLength) karakter")
                Spacer()
                Text("\(model.trimmedDescription.count)")
                    .monospacedDigit()
            }
            .font(MamaFont.caption)
            .foregroundStyle(
                model.trimmedDescription.count >= CreateNeedViewModel.minDescriptionLength
                    ? MamaColor.statusFed : MamaColor.textSecondary
            )
        }
    }
}

struct NeedPhotosSection: View {
    @Bindable var model: CreateNeedViewModel

    var body: some View {
        NeedFormCard("Fotoğraf (isteğe bağlı)", subtitle: "En fazla 3 fotoğraf. Yaralı hayvan fotoğrafları başkalarına bulanık gösterilir.") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.photos) { photo in
                        PhotoThumbnail(data: photo.data) { model.removePhoto(photo.id) }
                    }
                    if model.canAddPhoto {
                        PhotoInputButton(onPicked: { data in model.addPhoto(data) }) {
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
    }
}

/// Nokta verilmediyse 500 m içindeki noktalardan seçim (hayvana bağlı değilse zorunlu).
struct NeedSpotSection: View {
    @Bindable var model: CreateNeedViewModel

    private var title: LocalizedStringKey {
        model.isSpotRequired ? "Hangi noktada?" : "Hangi noktada? (isteğe bağlı)"
    }

    private var subtitle: LocalizedStringKey {
        model.isSpotRequired
            ? "Gönüllülerin yeri bulabilmesi için bir nokta seç."
            : "Seçmezsen hayvanın son görüldüğü nokta kullanılır."
    }

    var body: some View {
        NeedFormCard(title, subtitle: subtitle) {
            if model.isLoadingSpots {
                ProgressView().frame(maxWidth: .infinity)
            } else if model.nearbySpots.isEmpty {
                Text("Yakınında kayıtlı nokta bulamadık. Haritada noktayı açıp oradan da ihtiyaç bildirebilirsin.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                ForEach(Array(model.nearbySpots.prefix(8))) { spot in
                    ChoiceCard(
                        spot.title,
                        subtitle: spot.distanceMeters.map { MamaFormat.distance($0) },
                        systemImage: spot.type.systemImage,
                        isSelected: model.selectedSpotId == spot.id
                    ) {
                        model.toggleSpot(spot.id)
                    }
                }
            }
        }
    }
}
#endif
