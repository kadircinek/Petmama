#if canImport(UIKit)
import SwiftUI
import MamaCore

/// Harita pini: nokta fotoğraflı yuvarlak pin; fotoğraf yoksa maskot (kedi, köpek veya ikisi).
/// Maskotun ifadesi durumu da anlatır: mama kondu → gülen, mama bekliyor → bekleyen gözler (D18).
/// Kenarlık durum rengi; acil ihtiyaçta dışta kırmızı halka (FR-H3, PRD 6.1 "Avatar pinleri").
public struct SpotPinView: View {
    let status: SpotStatus
    let hasUrgentNeed: Bool
    let type: SpotType
    let species: SpotSpecies
    let photoURL: URL?
    let isSelected: Bool
    let isApproximate: Bool

    public init(
        status: SpotStatus,
        hasUrgentNeed: Bool,
        type: SpotType,
        species: SpotSpecies = .both,
        photoURL: URL?,
        isSelected: Bool = false,
        isApproximate: Bool = false
    ) {
        self.status = status
        self.hasUrgentNeed = hasUrgentNeed
        self.type = type
        self.species = species
        self.photoURL = photoURL
        self.isSelected = isSelected
        self.isApproximate = isApproximate
    }

    public init(spot: Spot, isSelected: Bool = false, now: Date = Date()) {
        self.init(
            status: spot.currentStatus(now: now),
            hasUrgentNeed: spot.hasUrgentNeed,
            type: spot.type,
            species: spot.species,
            photoURL: spot.photoURL,
            isSelected: isSelected,
            isApproximate: !spot.isLocationExact
        )
    }

    private var size: CGFloat { isSelected ? 52 : 42 }

    public var body: some View {
        ZStack {
            if isApproximate {
                Circle()
                    .fill(status.color.opacity(0.12))
                    .overlay(Circle().strokeBorder(status.color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: size + 34, height: size + 34)
            }
            if hasUrgentNeed {
                Circle()
                    .strokeBorder(MamaColor.statusUrgent, lineWidth: 3)
                    .frame(width: size + 12, height: size + 12)
            }
            Group {
                if let photoURL {
                    AsyncImage(url: photoURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            iconContent
                        }
                    }
                } else {
                    iconContent
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(status.color, lineWidth: 3))
            .background(Circle().fill(MamaColor.card))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .overlay(alignment: .bottomTrailing) {
                // Su kabı, kulübe ve karışık noktalar küçük bir rozetle ayırt edilir.
                if type != .food {
                    SpotTypeIcon(type, size: size * 0.44)
                        .background(Circle().fill(MamaColor.card).padding(-1.5))
                        .offset(x: size * 0.14, y: size * 0.14)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var accessibilityText: String {
        var parts = [type.label, species.label, status.label]
        if hasUrgentNeed { parts.append(String(localized: "acil ihtiyaç var")) }
        return parts.joined(separator: ", ")
    }

    private var iconContent: some View {
        ZStack {
            Circle().fill(status.color.opacity(0.16))
            MascotView(MascotSpecies(species), mood: MascotMood(status: status), size: size * 0.86)
        }
    }
}

/// Küme rozeti: toplam nokta sayısı + turuncu "mama gerekli" sayısı (FR-H2).
public struct ClusterPinView: View {
    let count: Int
    let needsFoodCount: Int
    let hasUrgentNeed: Bool

    public init(count: Int, needsFoodCount: Int, hasUrgentNeed: Bool = false) {
        self.count = count
        self.needsFoodCount = needsFoodCount
        self.hasUrgentNeed = hasUrgentNeed
    }

    private var diameter: CGFloat { min(72, 40 + CGFloat(count).squareRoot() * 4) }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Text("\(count)")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(MamaColor.textPrimary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(MamaColor.card))
                .overlay(Circle().strokeBorder(hasUrgentNeed ? MamaColor.statusUrgent : MamaColor.mint, lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            if needsFoodCount > 0 {
                Text("\(needsFoodCount)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(MamaColor.onStatus)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Capsule().fill(MamaColor.statusNeeds))
                    .offset(x: 6, y: -6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(count) nokta, \(needsFoodCount) tanesi mama bekliyor"))
    }
}

/// Lejant: pin renklerinin anlamı.
public struct StatusLegend: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SpotStatus.allCases, id: \.self) { status in
                HStack(spacing: 10) {
                    Image(systemName: status.systemImage).foregroundStyle(status.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.label).font(MamaFont.subheadline.weight(.semibold))
                        Text(status.explanation).font(MamaFont.caption).foregroundStyle(MamaColor.textSecondary)
                    }
                }
            }
            HStack(spacing: 10) {
                Circle().strokeBorder(MamaColor.statusUrgent, lineWidth: 3).frame(width: 18, height: 18)
                Text("Kırmızı halka: acil ihtiyaç (yaralı/hasta hayvan)")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
            }
        }
    }
}
#endif
