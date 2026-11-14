#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Bana gelen tanışma istekleri. Rota: `AppRoute.connectionRequests`. Kabulde bire bir sohbet açılır.
/// Reddetmek sessizdir: gönderen "reddedildi" görmez.
public struct ConnectionRequestsScreen: View {
    @State private var model: AnimalLoversViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    @State private var respondingId: UUID?

    public init(services: AppServices) {
        _model = State(initialValue: AnimalLoversViewModel(services: services))
    }

    public var body: some View {
        content
            .mamaBackground()
            .navigationTitle(String(localized: "Tanışma istekleri"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session.userId) {
                guard session.isSignedIn else { return }
                await model.load(at: location.coordinate)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            LoadingView()
        } else if model.incoming.isEmpty {
            EmptyStateView(
                systemImage: "person.crop.circle.badge.checkmark",
                title: String(localized: "Bekleyen istek yok"),
                message: model.error?.userMessage ?? String(localized: "Biri seninle tanışmak istediğinde burada görünür.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let error = model.error {
                        BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                    }
                    ForEach(model.incoming) { request in
                        ConnectionRequestCard(
                            request: request,
                            isBusy: respondingId != nil,
                            onRespond: { accept in respond(request, accept: accept) }
                        )
                    }
                    Text("Reddettiğin kişiye bildirim gitmez; 30 gün boyunca sana yeniden istek gönderemez.")
                        .font(MamaFont.footnote)
                        .foregroundStyle(MamaColor.textSecondary)
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.vertical, 12)
            }
            .refreshable { await model.load(at: location.coordinate) }
        }
    }

    private func respond(_ request: ConnectionRequest, accept: Bool) {
        guard respondingId == nil else { return }
        respondingId = request.id
        Task {
            let conversationId = await model.respond(request, accept: accept)
            respondingId = nil
            if let conversationId {
                router.showToast(String(localized: "Bağlantı kuruldu! Artık yazışabilirsiniz."))
                router.push(.conversation(conversationId))
            }
        }
    }
}

private struct ConnectionRequestCard: View {
    let request: ConnectionRequest
    let isBusy: Bool
    let onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(name: request.displayName, url: request.avatarURL, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: request.displayName)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    if request.isVerifiedFeeder {
                        TagChip(String(localized: "Doğrulanmış besleyici"), systemImage: "checkmark.seal.fill", style: .positive)
                    }
                }
                Spacer(minLength: 0)
            }
            if let note = request.note, !note.isEmpty {
                Text(verbatim: "“\(note)”")
                    .font(MamaFont.body)
                    .foregroundStyle(MamaColor.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                            .fill(MamaColor.cardSecondary)
                    )
            }
            if !request.about.isEmpty {
                Text(verbatim: request.about)
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            if !request.interests.isEmpty {
                InterestTags(interests: request.interests)
            }
            HStack(spacing: 10) {
                Button { onRespond(true) } label: { Text("Kabul et") }
                    .buttonStyle(.mamaPrimary(systemImage: "checkmark"))
                Button { onRespond(false) } label: { Text("Reddet") }
                    .buttonStyle(.mamaSecondary(fullWidth: false))
            }
            .disabled(isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }
}

#Preview {
    PreviewEnvironment { services in
        ConnectionRequestsScreen(services: services)
    }
}
#endif
