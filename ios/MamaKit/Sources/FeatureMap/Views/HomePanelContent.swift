#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Ana sayfa içeriği (ekran 8): selamlama, 4 pastel hızlı eylem, yakında mama gereken noktalar, "Bugün mahallende".
struct HomePanelContent: View {
    let model: MapViewModel

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            greeting
            LazyVGrid(columns: columns, spacing: 12) {
                QuickActionTile(String(localized: "Mama koy"), subtitle: String(localized: "100 m içindeki noktaya"),
                                systemImage: "pawprint.fill", tint: MamaColor.tileMint) {
                    router.present(.quickFeed, session: session)
                }
                QuickActionTile(String(localized: "Nokta ekle"), subtitle: String(localized: "Yeni besleme noktası"),
                                systemImage: "mappin.and.ellipse", tint: MamaColor.tileBlue) {
                    router.present(.addSpot(nil), session: session)
                }
                QuickActionTile(String(localized: "İhtiyaçlar"), subtitle: String(localized: "Veteriner, kısırlaştırma…"),
                                systemImage: "cross.case.fill", tint: MamaColor.tileLavender) {
                    router.select(.needs)
                }
                QuickActionTile(String(localized: "Bağış"), subtitle: String(localized: "Mama paketine destek ol"),
                                systemImage: "heart.fill", tint: MamaColor.tilePeach) {
                    router.select(.donate)
                }
            }
            if model.isNeighborhoodEmpty {
                EmptyStateView(
                    systemImage: "pawprint",
                    title: String(localized: "Bu sokağın ilk besleyicisi sen ol"),
                    message: String(localized: "Yakınında henüz kayıtlı bir besleme noktası yok."),
                    actionTitle: String(localized: "Nokta ekle")
                ) {
                    router.present(.addSpot(nil), session: session)
                }
                .mamaCard()
            } else {
                needsFoodStrip
                summaryCard
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingLine)
                .font(MamaFont.title2)
                .foregroundStyle(MamaColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Bugün mahallene bir kap mama?")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
        }
    }

    private var greetingLine: String {
        let hello = MamaFormat.greeting(at: model.now)
        guard let name = session.profile?.displayName, !name.isEmpty else { return hello }
        return "\(hello), \(name)"
    }

    private var needsFoodStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Yakınında mama gereken noktalar"))
            let spots = model.needsFoodSpots
            if spots.isEmpty {
                Label("Şu an yakınında mama bekleyen nokta yok. Harika!", systemImage: "checkmark.circle.fill")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(spots) { spot in
                            Button {
                                router.push(.spot(spot.id))
                            } label: {
                                NeedsFoodSpotChip(spot: spot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        if let summary = model.summary {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bugün mahallende")
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                Text("\(summary.fedSpotsToday) nokta beslendi · \(summary.openNeeds) ihtiyaç açık")
                    .font(MamaFont.title3)
                    .foregroundStyle(MamaColor.textPrimary)
                if summary.needsFoodSpots > 0 {
                    Label("\(summary.needsFoodSpots) nokta mama bekliyor", systemImage: SpotStatus.needsFood.systemImage)
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.statusNeeds)
                }
                Text("Son 7 günde \(summary.activeSpots7d) noktaya uğrandı.")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .mamaCard()
            .accessibilityElement(children: .combine)
        }
    }
}

/// Şeritteki küçük "mama bekliyor" kartı.
private struct NeedsFoodSpotChip: View {
    let spot: Spot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncPhoto(url: spot.photoURL, placeholderSystemImage: "pawprint.fill", placeholderTint: MamaColor.statusNeeds)
                .frame(width: 140, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
            Text(spot.title)
                .font(MamaFont.subheadline.weight(.semibold))
                .foregroundStyle(MamaColor.textPrimary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: SpotStatus.needsFood.systemImage)
                    .foregroundStyle(MamaColor.statusNeeds)
                Text(SpotStatus.needsFood.label)
                if let distance = spot.distanceMeters {
                    Text("· \(MamaFormat.distance(distance))")
                }
            }
            .font(MamaFont.caption)
            .foregroundStyle(MamaColor.textSecondary)
            .lineLimit(1)
        }
        .frame(width: 140)
        .mamaCard(padding: 10)
        .accessibilityElement(children: .combine)
    }
}
#endif
