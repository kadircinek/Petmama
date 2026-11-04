#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Bu nokta zaten var mı?" (FR-N3): 15 m içindeki adaylar.
struct DuplicateSpotSheet: View {
    let candidates: [DuplicateCandidate]
    let isSubmitting: Bool
    let onSelect: (DuplicateCandidate) -> Void
    let onForce: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bu nokta zaten var mı?")
                        .font(MamaFont.title2)
                        .foregroundStyle(MamaColor.textPrimary)
                    Text("Çok yakında kayıtlı bir nokta var. Aynı yerse mevcut noktayı kullanmak haritayı düzenli tutar.")
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                    ForEach(candidates) { candidate in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "pawprint.fill")
                                    .foregroundStyle(MamaColor.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(MamaColor.tileMint))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title)
                                        .font(MamaFont.headline)
                                        .foregroundStyle(MamaColor.textPrimary)
                                    Text("\(MamaFormat.distance(candidate.distanceMeters)) uzakta")
                                        .font(MamaFont.caption)
                                        .foregroundStyle(MamaColor.textSecondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            Button("Evet, bu nokta") { onSelect(candidate) }
                                .buttonStyle(.mamaPrimary(systemImage: "checkmark"))
                        }
                        .mamaCard()
                    }
                    Button {
                        onForce()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Hayır, yine de ekle")
                        }
                    }
                    .buttonStyle(.mamaSecondary(systemImage: "plus.circle.fill"))
                    .disabled(isSubmitting)
                }
                .padding(20)
            }
            .mamaBackground()
            .navigationTitle("Mükerrer kontrolü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Geri dön") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Nokta eklemeden önce tek ekranlık sorumlu besleme hatırlatması (PRD 9.4).
struct FeedingReminderView: View {
    let onContinue: () -> Void

    private struct Item: Identifiable {
        var id: String { icon }
        let icon: String
        let text: String
    }

    private let items: [Item] = [
        Item(icon: "sparkles", text: String(localized: "Kapı önlerini ve kapların çevresini temiz tut.")),
        Item(icon: "trash.slash.fill", text: String(localized: "Artık bırakma; hayvanlar yedikten sonra kalanı topla.")),
        Item(icon: "door.left.hand.closed", text: String(localized: "Apartman ve dükkân giriş kapılarının önüne koyma.")),
        Item(icon: "person.2.fill", text: String(localized: "Komşularınla konuş; birlikte sahiplenilen nokta yaşar.")),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(MamaColor.statusFed)
                    .accessibilityHidden(true)
                Text("Önce küçük bir hatırlatma")
                    .font(MamaFont.title2)
                    .foregroundStyle(MamaColor.textPrimary)
                Text("Beslediğimiz noktaların uzun yaşaması komşularımızla iyi geçinmemize bağlı.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.icon)
                                .foregroundStyle(MamaColor.textPrimary)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(MamaColor.tileMint))
                                .accessibilityHidden(true)
                            Text(item.text)
                                .font(MamaFont.body)
                                .foregroundStyle(MamaColor.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .mamaCard()
                NavigationLink {
                    FeedingGuideScreen()
                } label: {
                    Label("Sorumlu besleme rehberini oku", systemImage: "book.fill")
                        .font(MamaFont.subheadline.weight(.semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                        .frame(minHeight: MamaMetrics.minTapSize)
                }
                Button("Anladım, devam", action: onContinue)
                    .buttonStyle(.mamaPrimary)
            }
            .padding(20)
        }
    }
}
#endif
