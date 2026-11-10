#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Liste" segmenti (ekran 10): filtrelenmiş ve sıralanmış nokta kartları.
struct SpotListContent: View {
    let model: MapViewModel

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.isOffline {
                    BannerView(String(localized: "Çevrimdışı: son görülen noktalar gösteriliyor"), style: .warning, systemImage: "wifi.slash")
                }
                let spots = model.filteredListSpots
                if spots.isEmpty {
                    emptyState
                } else {
                    ForEach(spots) { spot in
                        Button {
                            router.push(.spot(spot.id))
                        } label: {
                            SpotCardView(spot: spot, now: model.now)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .refreshable { await model.loadList() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoadingList {
            ProgressView().padding(.top, 48)
        } else if model.listSpots.isEmpty {
            EmptyStateView(
                mascot: .duo,
                title: String(localized: "Bu sokağın ilk besleyicisi sen ol"),
                message: String(localized: "Seçtiğin mesafede kayıtlı nokta yok."),
                actionTitle: String(localized: "Nokta ekle")
            ) {
                router.present(.addSpot(nil), session: session)
            }
        } else {
            EmptyStateView(
                systemImage: "line.3.horizontal.decrease.circle",
                title: String(localized: "Bu filtreyle eşleşen nokta yok"),
                message: String(localized: "Filtreleri gevşetmeyi dene."),
                actionTitle: String(localized: "Filtreyi sıfırla")
            ) {
                Task { await model.resetFilter() }
            }
        }
    }
}

/// "İhtiyaçlar" segmenti: yakındaki açık ihtiyaçlar, acil olanlar önce (FR-I5, ekran 17).
struct NeedsListContent: View {
    let model: MapViewModel

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.isOffline {
                    BannerView(String(localized: "Çevrimdışı: ihtiyaçlar güncellenemedi"), style: .warning, systemImage: "wifi.slash")
                }
                let needs = model.filteredNeeds
                if needs.isEmpty {
                    if model.isLoadingNeeds {
                        ProgressView().padding(.top, 48)
                    } else {
                        EmptyStateView(
                            mascot: .duo,
                            mood: .happy,
                            title: String(localized: "Yakınında açık ihtiyaç yok"),
                            message: String(localized: "Bir hayvanın veterinere, kısırlaştırmaya veya barınağa ihtiyacı varsa bildirebilirsin."),
                            actionTitle: String(localized: "İhtiyaç bildir")
                        ) {
                            router.present(.createNeed(spotId: nil, animalId: nil), session: session)
                        }
                    }
                } else {
                    ForEach(needs) { need in
                        NeedCardView(
                            need: need,
                            now: model.now,
                            onClaim: { claim(need) },
                            onDetail: { router.push(.need(need.id)) }
                        )
                        .disabled(model.claimingNeedId == need.id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .refreshable { await model.loadNeeds() }
    }

    /// "Ben ilgileniyorum" giriş gerektirir (FR-P1).
    private func claim(_ need: Need) {
        guard session.isSignedIn else {
            router.present(.signIn, session: session)
            return
        }
        Task {
            let feedback = await model.claim(need)
            router.showToast(feedback.message, style: feedback.style)
        }
    }
}
#endif
