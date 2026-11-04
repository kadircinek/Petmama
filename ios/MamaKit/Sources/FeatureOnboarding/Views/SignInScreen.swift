#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Giriş / kayıt sheet'i (`AppSheet.signIn`, FR-P1). `onFinish(true)` giriş yapılınca, `false` kapatılınca.
public struct SignInScreen: View {
    @State private var model: SignInViewModel
    @State private var didFinish = false
    @Environment(AppRouter.self) private var router
    private let services: AppServices
    private let onFinish: (Bool) -> Void

    public init(services: AppServices, onFinish: @escaping (Bool) -> Void) {
        self.services = services
        self.onFinish = onFinish
        _model = State(initialValue: SignInViewModel(services: services))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                SignInContent(
                    model: model,
                    config: services.config,
                    onSignedIn: { finish(true) },
                    onOpenLegalFallback: openPrivacy
                )
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .mamaBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        finish(false)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: MamaMetrics.minTapSize, minHeight: MamaMetrics.minTapSize)
                    }
                    .accessibilityLabel(String(localized: "Kapat"))
                }
            }
        }
        .interactiveDismissDisabled(model.isWorking)
        // Aşağı kaydırarak kapatılırsa da bekleyen modal temizlensin.
        .onDisappear { finish(false) }
    }

    private func finish(_ success: Bool) {
        guard !didFinish else { return }
        didFinish = true
        onFinish(success)
    }

    /// Yasal metin URL'si yoksa: sheet kapanır, uygulama içi Gizlilik ve KVKK ekranı açılır.
    private func openPrivacy() {
        finish(false)
        router.push(.privacy)
    }
}

#Preview {
    PreviewEnvironment(signedIn: false) { services in
        SignInScreen(services: services) { _ in }
    }
}
#endif
