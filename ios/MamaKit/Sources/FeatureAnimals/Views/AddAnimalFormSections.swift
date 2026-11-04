#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Başlıklı beyaz form kartı.
struct AnimalFormCard<Content: View>: View {
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

extension View {
    /// Form alanı zemini.
    func animalFieldBackground() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                    .fill(MamaColor.cardSecondary)
            )
    }

    func animalFieldLabel() -> some View {
        font(MamaFont.subheadline.weight(.semibold)).foregroundStyle(MamaColor.textSecondary)
    }
}

struct AnimalIdentitySection: View {
    @Bindable var model: AddAnimalViewModel

    var body: some View {
        AnimalFormCard("Kim bu dost?") {
            HStack(spacing: 10) {
                ForEach(AnimalSpecies.allCases, id: \.self) { species in
                    SelectableChip(species.label, systemImage: species.systemImage, isSelected: model.species == species) {
                        model.species = species
                    }
                }
            }
            TextField("Mahallede verilen isim, ör. Pamuk", text: $model.name)
                .textInputAutocapitalization(.words)
                .animalFieldBackground()
            TextField("Renk / desen, ör. sarman, tekir, siyah", text: $model.colorPattern)
                .animalFieldBackground()
            Text("Cinsiyet").animalFieldLabel()
            PillSegmentedControl(
                selection: $model.sex,
                options: AnimalSex.allCases.map { (value: $0, title: $0.label) }
            )
            Text("Tahmini yaş").animalFieldLabel()
            FlowLayout(spacing: 8) {
                ForEach(AgeEstimate.allCases, id: \.self) { age in
                    SelectableChip(age.label, isSelected: model.ageEstimate == age) {
                        model.ageEstimate = age
                    }
                }
            }
        }
    }
}

struct AnimalHealthSection: View {
    @Bindable var model: AddAnimalViewModel

    var body: some View {
        AnimalFormCard("Sağlık") {
            Text("Kısırlaştırılmış mı?").animalFieldLabel()
            PillSegmentedControl(
                selection: $model.neutered,
                options: NeuteredChoice.allCases.map { (value: $0, title: label(for: $0)) }
            )
            Toggle(isOn: $model.earTag) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kulak küpesi veya kesiği var")
                        .font(MamaFont.subheadline.weight(.semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                    Text("Kısırlaştırılmış sokak hayvanlarının işaretidir.")
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
            }
            .tint(MamaColor.statusFed)
            TextField("Aşı bilgisi (biliyorsan), ör. Kuduz 2026", text: $model.vaccinationInfo)
                .animalFieldBackground()
        }
    }

    private func label(for choice: NeuteredChoice) -> String {
        switch choice {
        case .unknown: return String(localized: "Bilinmiyor")
        case .yes: return String(localized: "Evet")
        case .no: return String(localized: "Hayır")
        }
    }
}

struct AnimalTemperamentSection: View {
    @Bindable var model: AddAnimalViewModel

    var body: some View {
        AnimalFormCard("Karakteri", subtitle: "Birden fazla seçebilirsin.") {
            FlowLayout(spacing: 8) {
                ForEach(TemperamentTag.allCases, id: \.self) { tag in
                    SelectableChip(tag.label, systemImage: tag.systemImage, isSelected: model.temperamentTags.contains(tag)) {
                        model.toggleTemperament(tag)
                    }
                }
            }
            Text("Uyarı (isteğe bağlı)").animalFieldLabel()
            FlowLayout(spacing: 8) {
                SelectableChip(String(localized: "Uyarı yok"), isSelected: model.warning == nil) {
                    model.warning = nil
                }
                ForEach(AnimalWarning.allCases, id: \.self) { warning in
                    SelectableChip(warning.label, systemImage: "exclamationmark.triangle.fill", isSelected: model.warning == warning) {
                        model.warning = warning
                    }
                }
            }
            Text("Uyarı profilin en üstünde gösterilir; hem insanların hem hayvanın güvenliği için.")
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
            TextField("Hakkında, ör. Sabahları bankların altında güneşlenir.", text: $model.about, axis: .vertical)
                .lineLimit(3...6)
                .animalFieldBackground()
        }
    }
}

struct AnimalPhotosSection: View {
    @Bindable var model: AddAnimalViewModel

    var body: some View {
        AnimalFormCard("Fotoğraflar", subtitle: "En fazla 3 fotoğraf. Konum bilgisi fotoğraftan silinir.") {
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

struct AnimalSpotSection: View {
    @Bindable var model: AddAnimalViewModel

    var body: some View {
        AnimalFormCard("Nerede görüyorsun?", subtitle: "İsteğe bağlı. Bir noktaya bağlarsan nokta sayfasında da görünür.") {
            if model.preselectedSpotId != nil {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(MamaColor.statusFed)
                        .accessibilityHidden(true)
                    Text(model.preselectedSpot?.title ?? String(localized: "Seçili nokta"))
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    Spacer(minLength: 0)
                }
            } else if model.isLoadingSpots {
                ProgressView().frame(maxWidth: .infinity)
            } else if model.nearbySpots.isEmpty {
                Text("Yakınında kayıtlı nokta bulamadık. Hayvanı noktasız da ekleyebilirsin.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                ForEach(Array(model.nearbySpots.prefix(6))) { spot in
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
