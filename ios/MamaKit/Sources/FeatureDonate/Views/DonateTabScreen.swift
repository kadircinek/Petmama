#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Bağış" sekmesinin kökü (ekran 18, PRD 8.1–8.2). `NavigationStack`'i AppFeature sağlar.
/// Bağış derneğin kendi sayfasında, **harici Safari'de** alınır (D2); uygulama içinde ödeme yok.
public struct DonateTabScreen: View {
    @State private var model: DonateViewModel
    @Environment(\.openURL) private var openURL

    public init(services: AppServices) {
        self.init(services: services, defaults: .standard)
    }

    init(services: AppServices, defaults: UserDefaults) {
        _model = State(initialValue: DonateViewModel(services: services, defaults: defaults))
    }

    public var body: some View {
        // `$model.quantity` doğrudan `@State`'in Binding'inden; yerel `@Bindable var` `.task`/`.refreshable`
        // (`@Sendable`) kapanışlarında yakalanmasın.
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DonationTransparencyCard(text: model.transparencyText)
                if let counter = model.monthlyCounterText {
                    DonationCounterCard(title: counter, subtitle: model.donorCountText)
                }
                SectionHeader(String(localized: "Bir paket seç"))
                ForEach(model.packages) { package in
                    DonationPackageCard(
                        title: model.title(for: package),
                        species: package.species,
                        price: model.priceText(for: package),
                        tryText: model.tryText(for: package),
                        impact: model.impactText(for: package),
                        isSelected: model.selectedPackage?.id == package.id
                    ) {
                        model.select(package)
                    }
                }
                quantityCard(quantity: $model.quantity)
                donateButton
                NavigationLink(value: AppRoute.donationTrace) {
                    DonationTraceRow()
                }
                .buttonStyle(.plain)
                DeliveryPhotosPlaceholder()
            }
            .padding(MamaMetrics.screenPadding)
        }
        .mamaBackground()
        .navigationTitle("Bağış")
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func quantityCard(quantity: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: quantity, in: DonateViewModel.quantityRange) {
                Text("Adet: \(model.clampedQuantity)")
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
            }
            if let total = model.totalText {
                Text(total)
                    .font(MamaFont.title3)
                    .foregroundStyle(MamaColor.textPrimary)
            }
            if let package = model.selectedPackage {
                Text(sentenceCase(model.impactText(for: package, quantity: model.clampedQuantity)))
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                if model.tryText(for: package) != nil {
                    Text("TL karşılığı günlük kurla, yaklaşık hesaplanır.")
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
            }
        }
        .mamaCard()
    }

    private var donateButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                donate()
            } label: {
                Text("Dernek sayfasında bağış yap")
            }
            .buttonStyle(.mamaPrimary(systemImage: "arrow.up.right"))
            .disabled(!model.isConfigured || model.isOpening)

            if model.isConfigured {
                Text("Bağış sayfası Safari'de açılır. Ödeme bilgilerin Mama Haritası'na gelmez.")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                Label(String(localized: "Ortak dernek yakında açıklanacak"), systemImage: "clock.fill")
                    .font(MamaFont.subheadline.weight(.semibold))
                    .foregroundStyle(MamaColor.textSecondary)
            }
        }
    }

    /// Link → yalnızca "sayfaya gidildi" kaydı → harici Safari (PRD 8.2; SFSafariViewController değil).
    private func donate() {
        Task {
            guard let url = await model.prepareDonation() else { return }
            openURL(url)
        }
    }

    private func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: Locale(identifier: "tr_TR")) + text.dropFirst()
    }
}

#Preview {
    PreviewEnvironment { services in
        DonateTabScreen(services: services)
    }
}
#endif
