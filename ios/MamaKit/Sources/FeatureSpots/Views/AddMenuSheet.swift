#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Orta "+ Ekle" menüsü (ekran 15). Seçilen modal bu sheet'in yerine açılır (`sheet(item:)` öğe değişince değiştirir).
public struct AddMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    public init(services: AppServices) {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                AddMenuRow(
                    title: String(localized: "Nokta ekle"),
                    subtitle: String(localized: "Yeni bir besleme noktası işaretle"),
                    systemImage: "mappin.and.ellipse",
                    tint: MamaColor.tileMint
                ) {
                    router.present(.addSpot(nil), session: session)
                }
                AddMenuRow(
                    title: String(localized: "Hayvan ekle"),
                    subtitle: String(localized: "Sokaktaki bir dostu tanıt"),
                    systemImage: "cat.fill",
                    tint: MamaColor.tileBlue
                ) {
                    router.present(.createAnimal(spotId: nil), session: session)
                }
                AddMenuRow(
                    title: String(localized: "İhtiyaç bildir"),
                    subtitle: String(localized: "Veteriner, kısırlaştırma, barınak…"),
                    systemImage: "cross.case.fill",
                    tint: MamaColor.tilePeach
                ) {
                    router.present(.createNeed(spotId: nil, animalId: nil), session: session)
                }
                AddMenuRow(
                    title: String(localized: "Mahalleye yaz"),
                    subtitle: String(localized: "Paylaş, sor ya da yerine bakacak birini bul"),
                    systemImage: "text.bubble.fill",
                    tint: MamaColor.tileMint
                ) {
                    router.present(.createPost(kind: nil, spotId: nil), session: session)
                }
                AddMenuRow(
                    title: String(localized: "Mama koydum"),
                    subtitle: String(localized: "Yakındaki noktayı otomatik seçeriz"),
                    systemImage: "pawprint.fill",
                    tint: MamaColor.tileLavender
                ) {
                    router.present(.quickFeed, session: session)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .mamaBackground()
            .navigationTitle("Ne eklemek istersin?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.66), .large])
        .presentationDragIndicator(.visible)
    }
}

private struct AddMenuRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    Text(subtitle)
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MamaColor.textSecondary)
            }
            .mamaCard(padding: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    PreviewEnvironment { services in
        Color.clear.sheet(isPresented: .constant(true)) {
            AddMenuSheet(services: services)
        }
    }
}
#endif
