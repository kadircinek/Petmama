#if canImport(UIKit)
import MapKit
import SwiftUI
import MamaCore
import MamaDesign

/// Adım 1: harita ortasında sabit iğne; kullanıcı haritayı kaydırarak konumu ayarlar (FR-N2).
struct AddSpotLocationStep: View {
    let model: AddSpotFlowViewModel
    @Binding var position: MapCameraPosition
    @Binding var showsReminder: Bool

    var body: some View {
        VStack(spacing: 12) {
            if showsReminder {
                HStack(alignment: .top, spacing: 10) {
                    BannerView(
                        String(localized: "Kapı önlerini temiz tut, artık bırakma, giriş kapılarının önüne koyma."),
                        style: .info,
                        systemImage: "leaf.fill"
                    )
                    Button {
                        withAnimation { showsReminder = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(MamaColor.textSecondary)
                            .frame(width: MamaMetrics.minTapSize, height: MamaMetrics.minTapSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Hatırlatmayı kapat"))
                }
                .padding(.horizontal, 16)
            }
            Map(position: $position) {
                UserAnnotation()
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                model.moveCoordinate(to: Coordinate(context.region.center))
            }
            .overlay {
                CenterPin().allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
            .accessibilityLabel(Text("Konum seçme haritası. Haritayı kaydırarak iğneyi noktanın üstüne getir."))

            Label(model.coordinate.description, systemImage: "mappin")
                .font(MamaFont.caption.monospacedDigit())
                .foregroundStyle(MamaColor.textSecondary)
                .padding(.bottom, 4)
        }
    }
}

/// Harita ortasındaki sabit iğne; ucu tam merkezdedir.
private struct CenterPin: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: 14, height: 6)
            Image(systemName: "mappin")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(MamaColor.ink)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                .offset(y: -22)
        }
        .accessibilityHidden(true)
    }
}

/// Adım 2: tip (4 kart), tür ve isteğe bağlı ad.
struct AddSpotDetailsStep: View {
    @Bindable var model: AddSpotFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 10) {
                    ForEach(SpotType.allCases, id: \.self) { type in
                        ChoiceCard(type.label, subtitle: type.hint, systemImage: type.systemImage, tint: type.tint, isSelected: model.type == type) {
                            model.type = type
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hangi hayvanlar?")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    FlowLayout(spacing: 8) {
                        ForEach(SpotSpecies.allCases, id: \.self) { species in
                            SelectableChip(species.label, systemImage: species.systemImage, isSelected: model.species == species) {
                                model.species = species
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kısa bir ad (isteğe bağlı)")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    MamaTextField(placeholder: String(localized: "ör. Apartmanın arka bahçesi, çitin yanı"), text: $model.title)
                    if let warning = model.titleWarning {
                        Text(warning)
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.statusUrgent)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Adım 3: isteğe bağlı fotoğraf, not ve görünürlük (PRD 9.1).
struct AddSpotExtrasStep: View {
    @Bindable var model: AddSpotFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    PhotoInputButton { data in
                        model.setPhoto(data)
                    } label: {
                        Label(model.photoData == nil ? String(localized: "Fotoğraf ekle") : String(localized: "Fotoğrafı değiştir"), systemImage: "camera.fill")
                            .font(MamaFont.headline)
                            .foregroundStyle(MamaColor.textPrimary)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 48)
                            .background(Capsule().fill(MamaColor.card))
                            .overlay(Capsule().strokeBorder(MamaColor.stroke, lineWidth: 1))
                    }
                    if let data = model.photoData {
                        PhotoThumbnail(data: data) { model.setPhoto(nil) }
                    }
                }
                if model.photoUploadFailed {
                    Text("Fotoğraf yüklenemedi; nokta fotoğrafsız eklendi.")
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.statusNeeds)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Not (isteğe bağlı)")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    MamaTextField(placeholder: String(localized: "ör. Çınarın dibinde, mavi kap"), text: $model.note, multiline: true)
                    if let warning = model.noteWarning {
                        Text(warning)
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.statusUrgent)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Kimler görebilir?")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    ForEach(SpotVisibility.allCases, id: \.self) { visibility in
                        ChoiceCard(
                            visibility.label,
                            subtitle: visibility.explanation,
                            systemImage: visibility.systemImage,
                            tint: MamaColor.tileBlue,
                            isSelected: model.visibility == visibility
                        ) {
                            model.visibility = visibility
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Kart görünümlü metin alanı.
private struct MamaTextField: View {
    let placeholder: String
    @Binding var text: String
    var multiline = false

    var body: some View {
        Group {
            if multiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(3...6)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(MamaFont.body)
        .textFieldStyle(.plain)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous).fill(MamaColor.card))
        .overlay(
            RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                .strokeBorder(MamaColor.stroke, lineWidth: 1)
        )
    }
}

extension SpotType {
    var hint: String {
        switch self {
        case .food: return String(localized: "Mama kabı veya mama bırakılan yer")
        case .water: return String(localized: "Temiz su kabı")
        case .shelter: return String(localized: "Kulübe, kedi evi veya barınak")
        case .mixed: return String(localized: "Mama, su ve barınak bir arada")
        }
    }

    var tint: Color {
        switch self {
        case .food: return MamaColor.tileMint
        case .water: return MamaColor.tileBlue
        case .shelter: return MamaColor.tileLavender
        case .mixed: return MamaColor.tilePeach
        }
    }
}
#endif
