#if canImport(UIKit)
import AuthenticationServices
import SwiftUI
import MamaCore
import MamaDesign

/// Giriş içeriği (ekran 7). `SignInScreen` sheet'i ve ilk kullanım akışı aynı içeriği kullanır.
struct SignInContent: View {
    @Bindable var model: SignInViewModel
    let config: AppConfig
    let onSignedIn: () -> Void
    /// Yasal metin URL'si tanımlı değilse uygulama içi gizlilik özetine gitmek için.
    let onOpenLegalFallback: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @State private var rawNonce: String?
    @State private var successCount = 0

    private enum Field: Hashable { case name, email, password }

    var body: some View {
        VStack(spacing: 20) {
            header
            appleButton
            separator
            emailCard
            if model.showsDemoHint { demoHint }
            legalFooter
        }
        .sensoryFeedback(.success, trigger: successCount)
    }

    // MARK: - Bölümler

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(MamaColor.ink)
                .frame(width: 68, height: 68)
                .background(Circle().fill(MamaColor.mint))
                .accessibilityHidden(true)
            Text("Hoş geldin")
                .font(MamaFont.largeTitle)
                .foregroundStyle(MamaColor.textPrimary)
            Text("Mama koymak ve nokta eklemek için giriş yap. Haritayı gezmek için hesap gerekmez.")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var appleButton: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: { request in
                let nonce = AppleSignInNonce.random()
                rawNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleSignInNonce.sha256(nonce)
            },
            onCompletion: { result in handleApple(result) }
        )
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        // Stil, tema değişince kendiliğinden güncellenmiyor; kimlik değişimiyle yeniden kurulur.
        .id(colorScheme)
        .frame(height: 54)
        .clipShape(Capsule())
        .disabled(model.isWorking)
    }

    private var separator: some View {
        HStack(spacing: 12) {
            Rectangle().fill(MamaColor.stroke).frame(height: 1)
            Text("veya e-posta ile")
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
                .fixedSize()
            Rectangle().fill(MamaColor.stroke).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private var emailCard: some View {
        VStack(spacing: 14) {
            PillSegmentedControl(
                selection: Binding(get: { model.mode }, set: { model.switchMode(to: $0) }),
                options: [
                    (value: SignInViewModel.Mode.signIn, title: String(localized: "Giriş")),
                    (value: SignInViewModel.Mode.signUp, title: String(localized: "Kayıt ol")),
                ]
            )
            if model.isSignUp {
                InputField(systemImage: "person.fill") {
                    TextField(String(localized: "Adın (haritada görünür)"), text: $model.displayName)
                        .textContentType(.nickname)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .email }
                }
            }
            InputField(systemImage: "envelope.fill") {
                TextField(String(localized: "E-posta"), text: $model.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }
            InputField(systemImage: "lock.fill") {
                SecureField(String(localized: "Şifre (en az 8 karakter)"), text: $model.password)
                    .textContentType(model.isSignUp ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            }
            if let message = model.errorMessage {
                BannerView(message, style: .error)
            }
            if let message = model.infoMessage {
                BannerView(message, style: .success)
            }
            Button(action: submit) {
                if model.isWorking {
                    ProgressView().tint(MamaColor.onInk)
                } else {
                    Text(model.isSignUp ? String(localized: "Hesap oluştur") : String(localized: "Giriş yap"))
                }
            }
            .buttonStyle(.mamaPrimary)
            .disabled(!model.canSubmit)
            if !model.isSignUp {
                MamaTextButton(String(localized: "Şifremi unuttum")) {
                    focusedField = nil
                    Task { await model.sendPasswordReset() }
                }
            }
        }
        .mamaCard()
        .animation(.easeInOut(duration: 0.2), value: model.mode)
    }

    private var demoHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Demo modu"), systemImage: "sparkles")
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textPrimary)
            Text("Bu sürüm Kadıköy demo verisiyle çalışıyor. Denemek için şu bilgileri kullanabilirsin:")
                .font(MamaFont.footnote)
                .foregroundStyle(MamaColor.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: SignInViewModel.demoEmail)
                Text(verbatim: SignInViewModel.demoPassword)
            }
            .font(.system(.footnote, design: .monospaced, weight: .semibold))
            .foregroundStyle(MamaColor.textPrimary)
            .textSelection(.enabled)
            Text("Apple ile giriş de demo kullanıcısıyla oturum açar.")
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
            Button(String(localized: "Demo bilgilerini doldur")) { model.fillDemoCredentials() }
                .buttonStyle(.mamaSecondary(systemImage: "wand.and.stars", fullWidth: false))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous).fill(MamaColor.tileLavender))
    }

    /// Markdown bağlantıları `openURL` ile yakalanır: URL tanımlıysa Safari, değilse uygulama içi özet.
    private var legalFooter: some View {
        Text("Devam ederek [Kullanım Koşulları](mama-legal://terms) ve [KVKK Aydınlatma Metni](mama-legal://kvkk)'ni kabul etmiş olursun.")
            .font(MamaFont.footnote)
            .foregroundStyle(MamaColor.textSecondary)
            .tint(MamaColor.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
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

    // MARK: - Eylemler

    private func submit() {
        focusedField = nil
        Task {
            if await model.submit(session: session) {
                successCount += 1
                onSignedIn()
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let payload = AppleCredentialPayload(authorization: authorization), let nonce = rawNonce else {
                model.appleSignInFailed(canceled: false)
                return
            }
            Task {
                if await model.signInWithApple(idToken: payload.idToken, nonce: nonce, fullName: payload.fullName, session: session) {
                    successCount += 1
                    onSignedIn()
                }
            }
        case .failure(let error):
            model.appleSignInFailed(canceled: AppleCredentialPayload.isCancellation(error))
        }
    }
}

/// İkonlu, yumuşak zeminli metin alanı.
struct InputField<Content: View>: View {
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(MamaColor.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            content()
                .font(MamaFont.body)
                .foregroundStyle(MamaColor.textPrimary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                .fill(MamaColor.cardSecondary)
        )
    }
}
#endif
