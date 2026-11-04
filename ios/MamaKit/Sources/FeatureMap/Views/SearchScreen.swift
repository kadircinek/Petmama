#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Arama (ekran 12): son aramalar, popüler aramalar ("Moda Parkı", "Kedi evleri", "Mama gerekli") ve sonuçlar.
public struct SearchScreen: View {
    @State private var model: SearchViewModel
    @Environment(AppRouter.self) private var router
    @Environment(LocationStore.self) private var location

    public init(services: AppServices) {
        _model = State(initialValue: SearchViewModel(services: services))
    }

    public var body: some View {
        // `$model.x` doğrudan @State Binding'inden; yerel @Bindable, @Sendable kapanışlarda (.task/Task) yakalanmasın.
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.showsSuggestions {
                    suggestions
                } else {
                    results
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.immediately)
        .mamaBackground()
        .navigationTitle("Ara")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nokta, sokak veya park ara")
        .onSubmit(of: .search) { model.commitCurrentQuery() }
        .task(id: model.query) {
            // Yazarken gecikmeli arama.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await model.search(near: location.coordinate)
        }
    }

    // MARK: - Öneriler

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !model.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(String(localized: "Son aramalar"), actionTitle: String(localized: "Temizle")) {
                        model.clearRecents()
                    }
                    VStack(spacing: 0) {
                        ForEach(model.recentSearches, id: \.self) { term in
                            recentRow(term)
                            if term != model.recentSearches.last { Divider() }
                        }
                    }
                    .mamaCard(padding: 6)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(String(localized: "Popüler"))
                FlowLayout(spacing: 8) {
                    ForEach(SearchViewModel.PopularSearch.allCases, id: \.self) { popular in
                        SelectableChip(popular.title, systemImage: popular.systemImage, isSelected: false) {
                            Task { await model.runPopular(popular, near: location.coordinate) }
                        }
                    }
                }
            }
        }
    }

    private func recentRow(_ term: String) -> some View {
        HStack(spacing: 12) {
            Button {
                model.query = term
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(MamaColor.textSecondary)
                    Text(term)
                        .font(MamaFont.body)
                        .foregroundStyle(MamaColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: MamaMetrics.minTapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                model.removeRecent(term)
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MamaColor.textSecondary)
                    .frame(width: MamaMetrics.minTapSize, height: MamaMetrics.minTapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(term) aramasını sil"))
        }
        .padding(.leading, 10)
    }

    // MARK: - Sonuçlar

    @ViewBuilder
    private var results: some View {
        if let popular = model.activePopular {
            HStack {
                Label(popular.title, systemImage: popular.systemImage)
                    .font(MamaFont.title3)
                    .foregroundStyle(MamaColor.textPrimary)
                Spacer()
                MamaTextButton(String(localized: "Temizle")) { model.clearPopular() }
            }
        }
        if model.isSearching && model.results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if let error = model.error, model.results.isEmpty {
            EmptyStateView(systemImage: "wifi.slash", title: String(localized: "Arama yapılamadı"), message: error.userMessage)
        } else if model.results.isEmpty, model.hasSearched {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: String(localized: "Sonuç bulamadık"),
                message: emptyMessage
            )
        } else {
            LazyVStack(spacing: 12) {
                ForEach(model.results) { spot in
                    Button {
                        model.commitCurrentQuery()
                        router.push(.spot(spot.id))
                    } label: {
                        SpotCardView(spot: spot, now: model.now)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyMessage: String {
        switch model.activePopular {
        case .needsFood: return String(localized: "Yakınında şu an mama bekleyen nokta yok. Harika!")
        case .catHouses: return String(localized: "Yakınında kayıtlı kedi evi yok. İlkini sen ekleyebilirsin.")
        case .modaPark, .none: return String(localized: "Başka bir sokak ya da park adı dene.")
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        SearchScreen(services: services)
    }
}
#endif
