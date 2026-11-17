#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Mahalle › "Buluşmalar" bölümü: yakındaki buluşmalar, yakından uzağa. Yalnızca giriş yapanlara açık.
/// Onaysız kullanıcı listeyi görür; katılmak ya da açmak onay ister (spec 5.5/0).
public struct MeetupsListView: View {
    @State private var model: MeetupsViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location

    public init(services: AppServices) {
        _model = State(initialValue: MeetupsViewModel(services: services))
    }

    public var body: some View {
        content
            .task(id: session.userId) { await reload() }
            .onChange(of: router.sheet) { old, new in
                // Yeni buluşma ya da onay sheet'i kapanınca tazele.
                if old != nil, new == nil { Task { await reload() } }
            }
            .onChange(of: location.coordinate == nil) { _, isNil in
                if !isNil { Task { await reload() } }
            }
    }

    @ViewBuilder
    private var content: some View {
        if session.isRestoring, !session.isSignedIn {
            LoadingView()
        } else if !session.isSignedIn {
            SocialSignInGate(
                message: String(localized: "Mahallendeki mama turlarını, kulübe atölyelerini ve kısırlaştırma günlerini görmek için giriş yap.")
            ) {
                router.present(.signIn, session: session)
            }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if model.needsConsent, !model.meetups.isEmpty {
                    BannerView(
                        String(localized: "Katılmak ya da buluşma açmak için önce kısa bir onay vereceksin (18+)."),
                        style: .info,
                        systemImage: "person.badge.shield.checkmark.fill"
                    )
                }
                if let error = model.error {
                    BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                }
                if !model.hasLoaded || (model.isLoading && model.meetups.isEmpty) {
                    LoadingView(String(localized: "Buluşmalar yükleniyor"))
                        .frame(height: 240)
                } else if model.isEmpty {
                    EmptyStateView(
                        mascot: .duo,
                        mood: .happy,
                        title: String(localized: "Yakında buluşma yok"),
                        message: String(localized: "Mahallende birlikte mama turu, kulübe atölyesi ya da kısırlaştırma günü planla; komşu besleyiciler katılsın."),
                        actionTitle: String(localized: "Buluşma aç"),
                        action: create
                    )
                } else if model.meetups.isEmpty {
                    Button {
                        Task { await reload() }
                    } label: {
                        Text("Tekrar dene")
                    }
                    .buttonStyle(.mamaSecondary(systemImage: "arrow.clockwise", fullWidth: false))
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(model.meetups) { meetup in
                        Button {
                            router.push(.meetup(meetup.id))
                        } label: {
                            MeetupCard(meetup: meetup, now: model.now)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        .refreshable { await reload() }
        .overlay(alignment: .bottom) {
            if !model.meetups.isEmpty {
                Button(action: create) {
                    Text("Buluşma aç")
                }
                .buttonStyle(.mamaPrimary(systemImage: "plus", fullWidth: false))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(.bottom, 12)
            }
        }
    }

    private func reload() async {
        guard session.isSignedIn else { return }
        await model.load(near: location.coordinate ?? .modaKadikoy)
    }

    /// Onay adımı gerekiyorsa "Buluşma aç" sheet'i önce onu gösterir.
    private func create() {
        router.present(.createMeetup(spotId: nil), session: session)
    }
}

#Preview {
    PreviewEnvironment { services in
        MeetupsListView(services: services)
    }
}
#endif
