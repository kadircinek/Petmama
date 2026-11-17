#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Tanışma için tek seferlik onay (spec 5.5/0): 18+, kullanım koşulları ve kısa güvenlik ipuçları.
/// Sheet: `AppSheet.socialConsent`. Onay verilince kapanır; açan ekran sheet kapanınca tazelenir.
public struct SocialConsentSheet: View {
    @State private var model: SocialConsentViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    private let config: AppConfig

    public init(services: AppServices) {
        _model = State(initialValue: SocialConsentViewModel(services: services))
        config = services.config
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                SocialConsentContent(model: model, config: config, onConsented: consented, onOpenLegalFallback: openPrivacy)
                    .padding(MamaMetrics.screenPadding)
            }
            .mamaBackground()
            .navigationTitle("Tanışma")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .disabled(model.isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(model.isSubmitting)
    }

    private func consented() {
        router.showToast(String(localized: "Hoş geldin! Artık buluşmalara katılabilir, hayvanseverlerle tanışabilirsin."))
        dismiss()
    }

    /// Yasal metin URL'si yoksa: sheet kapanır, uygulama içi Gizlilik ve KVKK ekranı açılır.
    private func openPrivacy() {
        dismiss()
        router.push(.privacy)
    }
}

/// Onay içeriği; `SocialConsentSheet` ve "Buluşma aç" (onay yoksa ilk adım) birlikte kullanır.
struct SocialConsentContent: View {
    @Bindable var model: SocialConsentViewModel
    let config: AppConfig
    let onConsented: () -> Void
    let onOpenLegalFallback: () -> Void
    @State private var successFeedback = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            safetyTips
            checks
            if let error = model.error {
                BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
            }
            Button {
                Task { await submit() }
            } label: {
                if model.isSubmitting {
                    Text("Kaydediliyor…")
                } else {
                    Text("Onayla ve devam et")
                }
            }
            .buttonStyle(.mamaPrimary(systemImage: "checkmark"))
            .disabled(!model.canSubmit)
            Text("Bu onay bir kez istenir ve zamanıyla birlikte saklanır. Hayvanseverler'de görünmek ayrıca senin seçimin.")
                .font(MamaFont.footnote)
                .foregroundStyle(MamaColor.textSecondary)
        }
        .sensoryFeedback(.success, trigger: successFeedback)
    }

    private var header: some View {
        VStack(spacing: 10) {
            MascotView(.duo, mood: .happy, size: 96)
            Text("Mahallende birlikte besleyelim")
                .font(MamaFont.title2)
                .foregroundStyle(MamaColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Buluşmalara katılmak, buluşma açmak ve diğer hayvanseverlerle tanışmak için önce birkaç şeyi birlikte netleştirelim.")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var safetyTips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Güvenlik ipuçları")
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            tip("person.3.fill", String(localized: "Buluşmaları park girişi, iskele ya da meydan gibi herkese açık yerlerde yap."))
            tip("house.slash.fill", String(localized: "Ev adresini, telefonunu ya da tam konumunu sohbette paylaşma."))
            tip("exclamationmark.bubble.fill", String(localized: "Rahatsız eden bir mesaja uzun basıp \"Raporla\" ya da \"Engelle\"yi seç; bire bir sohbette engelleme sağ üstteki menüde de var."))
            tip("location.slash.fill", String(localized: "Hayvanseverler'de kesin konumun hiç görünmez; yalnızca yaklaşık mesafe aralığı gösterilir."))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    private func tip(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MamaColor.textPrimary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MamaColor.tileMint))
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var checks: some View {
        VStack(alignment: .leading, spacing: 14) {
            CheckboxRow(isOn: $model.adultConfirmed, accessibilityLabel: String(localized: "18 yaşından büyüğüm")) {
                Text("18 yaşından büyüğüm")
                    .font(MamaFont.bodyEmphasized)
                    .foregroundStyle(MamaColor.textPrimary)
            }
            CheckboxRow(isOn: $model.termsAccepted, accessibilityLabel: String(localized: "Kullanım koşullarını kabul ediyorum")) {
                legalText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    /// Markdown bağlantıları `openURL` ile yakalanır: URL tanımlıysa Safari, değilse uygulama içi özet.
    private var legalText: some View {
        Text("[Kullanım Koşulları](mama-legal://terms)'nı ve [KVKK Aydınlatma Metni](mama-legal://kvkk)'ni okudum, kabul ediyorum.")
            .font(MamaFont.subheadline)
            .foregroundStyle(MamaColor.textSecondary)
            .tint(MamaColor.textPrimary)
            .environment(\.openURL, OpenURLAction { url in
                switch url.host {
                case "terms":
                    if let target = config.termsURL { return .systemAction(target) }
                case "kvkk":
                    if let target = config.kvkkNoticeURL ?? config.privacyPolicyURL { return .systemAction(target) }
                default:
                    return .systemAction
                }
                onOpenLegalFallback()
                return .handled
            })
    }

    private func submit() async {
        guard await model.submit() else { return }
        successFeedback += 1
        onConsented()
    }
}

/// Kare onay kutusu + etiket. Kutunun kendisi dokunulabilir; etiketteki bağlantılar ayrı çalışır.
private struct CheckboxRow<Label: View>: View {
    @Binding var isOn: Bool
    let accessibilityLabel: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                isOn.toggle()
            } label: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isOn ? MamaColor.statusFed : MamaColor.textSecondary)
                    .frame(width: MamaMetrics.minTapSize, height: MamaMetrics.minTapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
            .accessibilityAddTraits(isOn ? .isSelected : [])
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        SocialConsentSheet(services: services)
    }
}
#endif
