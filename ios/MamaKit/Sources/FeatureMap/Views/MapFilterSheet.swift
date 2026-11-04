#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Filtre ve sıralama (ekran 11, FR-H5): mesafe 1–10 km, tür, durum, ihtiyaç tipi, "Sadece takip ettiklerim", sıralama.
struct MapFilterSheet: View {
    let canFilterFollowed: Bool
    let onApply: (SpotFilter) -> Void

    @State private var draft: SpotFilter
    @Environment(\.dismiss) private var dismiss

    init(filter: SpotFilter, canFilterFollowed: Bool, onApply: @escaping (SpotFilter) -> Void) {
        self.canFilterFollowed = canFilterFollowed
        self.onApply = onApply
        _draft = State(initialValue: filter)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    distanceSection
                    chipSection(String(localized: "Tür")) {
                        ForEach(AnimalSpecies.allCases, id: \.self) { species in
                            SelectableChip(species.label, systemImage: species.systemImage, isSelected: draft.species.contains(species)) {
                                toggle(species, in: \.species)
                            }
                        }
                    }
                    chipSection(String(localized: "Durum")) {
                        ForEach(SpotStatus.allCases, id: \.self) { status in
                            SelectableChip(status.label, systemImage: status.systemImage, isSelected: draft.statuses.contains(status)) {
                                toggle(status, in: \.statuses)
                            }
                        }
                    }
                    chipSection(String(localized: "İhtiyaç tipi")) {
                        ForEach(NeedType.allCases, id: \.self) { type in
                            SelectableChip(type.label, systemImage: type.systemImage, isSelected: draft.needTypes.contains(type)) {
                                toggle(type, in: \.needTypes)
                            }
                        }
                    }
                    followedSection
                    chipSection(String(localized: "Sıralama")) {
                        ForEach(SpotFilter.Sort.allCases, id: \.self) { sort in
                            SelectableChip(sort.label, systemImage: sort.systemImage, isSelected: draft.sort == sort) {
                                draft.sort = sort
                            }
                        }
                    }
                }
                .padding(20)
            }
            .mamaBackground()
            .navigationTitle("Filtre ve sıralama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Sıfırla") { draft = .default }
                        .buttonStyle(.mamaSecondary(fullWidth: false))
                        .disabled(draft.isDefault)
                    Button("Uygula") {
                        onApply(draft)
                        dismiss()
                    }
                    .buttonStyle(.mamaPrimary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .presentationDetents([.large])
    }

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mesafe")
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                Spacer()
                Text(MamaFormat.distance(draft.maxDistanceKm * 1000))
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .monospacedDigit()
            }
            Slider(value: $draft.maxDistanceKm, in: 1...10, step: 0.5) {
                Text("En fazla mesafe")
            } minimumValueLabel: {
                Text("1 km").font(MamaFont.caption)
            } maximumValueLabel: {
                Text("10 km").font(MamaFont.caption)
            }
            .tint(MamaColor.ink)
            Text("Liste ve İhtiyaçlar'da uygulanır; harita görünen bölgeyi gösterir.")
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
        }
    }

    private var followedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $draft.onlyFollowed) {
                Text("Sadece takip ettiklerim")
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
            }
            .tint(MamaColor.statusFed)
            .disabled(!canFilterFollowed)
            if !canFilterFollowed {
                Text("Takip ettiğin noktaları görmek için giriş yap.")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
            }
        }
    }

    private func chipSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 8) {
                content()
            }
        }
    }

    private func toggle<Value: Hashable>(_ value: Value, in keyPath: WritableKeyPath<SpotFilter, Set<Value>>) {
        if draft[keyPath: keyPath].contains(value) {
            draft[keyPath: keyPath].remove(value)
        } else {
            draft[keyPath: keyPath].insert(value)
        }
    }
}

#Preview {
    MapFilterSheet(filter: SpotFilter(statuses: [.needsFood]), canFilterFollowed: true) { _ in }
}
#endif
