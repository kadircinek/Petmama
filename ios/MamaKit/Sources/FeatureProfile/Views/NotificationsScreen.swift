#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Bildirimler (ekran 22): "Bugün" / "Daha önce".
public struct NotificationsScreen: View {
    @State private var model: NotificationsViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    public init(services: AppServices) {
        _model = State(initialValue: NotificationsViewModel(services: services))
    }

    public var body: some View {
        List {
            if let error = model.error {
                BannerView(error.userMessage, style: .warning)
                    .listRowBackground(Color.clear)
            }
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.items) { notification in
                        Button {
                            open(notification)
                        } label: {
                            NotificationRow(notification: notification, relativeTime: model.relativeTime(for: notification))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(MamaColor.card)
                    }
                } header: {
                    Text(title(for: section.kind))
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .mamaBackground()
        .overlay { emptyState }
        .navigationTitle(String(localized: "Bildirimler"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Tümünü okundu işaretle")) {
                    Task { await model.markAllRead() }
                }
                .font(MamaFont.subheadline.weight(.semibold))
                .disabled(!model.hasUnread)
            }
        }
        .task(id: session.userId) { await model.load() }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.hasLoaded && model.isEmpty {
            EmptyStateView(
                systemImage: "bell",
                title: String(localized: "Henüz bildirimin yok"),
                message: session.isSignedIn
                    ? String(localized: "Yakınında mama bekleyen bir nokta olduğunda veya takip ettiğin noktada bir şey değiştiğinde burada göreceksin.")
                    : String(localized: "Bildirim almak için giriş yapman gerekiyor.")
            )
        } else if model.isLoading && !model.hasLoaded {
            LoadingView()
        }
    }

    private func open(_ notification: AppNotification) {
        Task {
            if let route = await model.open(notification) {
                router.push(route)
            }
        }
    }

    private func title(for kind: NotificationsViewModel.SectionKind) -> String {
        switch kind {
        case .today: return String(localized: "Bugün")
        case .earlier: return String(localized: "Daha önce")
        }
    }
}

#Preview {
    PreviewEnvironment { services in NotificationsScreen(services: services) }
}
#endif
