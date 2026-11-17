#if canImport(UIKit)
import SwiftUI
import UIKit
import MamaCore
import MamaDesign

/// Ayarlar (ekran 23): bildirimler, dil, gizlilik, iletişim, çıkış ve hesap silme (FR-P3).
public struct SettingsScreen: View {
    @State private var model: SettingsViewModel
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(\.openURL) private var openURL
    private let config: AppConfig

    public init(services: AppServices) {
        _model = State(initialValue: SettingsViewModel(services: services))
        config = services.config
    }

    public var body: some View {
        Form {
            if let error = model.error {
                Section { BannerView(error.userMessage, style: .warning) }
                    .listRowBackground(Color.clear)
            }
            if session.isSignedIn {
                NotificationPreferencesSection(model: model)
            } else {
                signInPrompt
            }
            languageSection
            privacySection
            if session.isSignedIn {
                BlockedUsersSection(model: model)
            }
            communitySection
            if session.isSignedIn {
                accountSection
            }
            versionFooter
        }
        .mamaBackground()
        .navigationTitle(String(localized: "Ayarlar"))
        .task(id: session.userId) { await model.load(isSignedIn: session.isSignedIn) }
        // Kısa gecikmeyle kaydet: art arda değişikliklerde yalnızca son hal gönderilir.
        .task(id: model.preferences) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await model.savePreferences()
        }
        .confirmationDialog(String(localized: "Hesabın silinsin mi?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(model.requiresAppleConfirmationToDelete
                   ? String(localized: "Apple ile onayla ve sil")
                   : String(localized: "Hesabımı kalıcı olarak sil"), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(String(localized: "Vazgeç"), role: .cancel) {}
        } message: {
            Text(SettingsViewModel.deleteAccountExplanation)
        }
        .confirmationDialog(String(localized: "Çıkış yapılsın mı?"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(String(localized: "Çıkış yap"), role: .destructive) {
                Task { await signOut() }
            }
            Button(String(localized: "Vazgeç"), role: .cancel) {}
        }
    }

    // MARK: - Bölümler

    private var signInPrompt: some View {
        Section {
            Button {
                router.present(.signIn, session: session)
            } label: {
                Label(String(localized: "Bildirim ayarları için giriş yap"), systemImage: "person.crop.circle.badge.checkmark")
            }
        } footer: {
            Text("Haritayı hesapsız gezebilirsin; bildirimler ve takip için giriş gerekir.")
        }
    }

    private var languageSection: some View {
        Section {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                HStack {
                    Label(String(localized: "Uygulama dili"), systemImage: "globe")
                        .foregroundStyle(MamaColor.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(MamaColor.textSecondary)
                        .accessibilityHidden(true)
                }
            }
        } header: {
            Text("Dil")
        } footer: {
            Text("Türkçe ve İngilizce desteklenir. Dili iPhone Ayarlar › Mama Haritası › Dil bölümünden değiştirebilirsin.")
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink(value: AppRoute.privacy) {
                Label(String(localized: "Gizlilik ve KVKK özeti"), systemImage: "hand.raised.fill")
            }
            LegalLinkRow(title: String(localized: "KVKK aydınlatma metni"), systemImage: "doc.text.fill", url: config.kvkkNoticeURL)
            LegalLinkRow(title: String(localized: "Gizlilik politikası"), systemImage: "lock.shield.fill", url: config.privacyPolicyURL)
            LegalLinkRow(title: String(localized: "Kullanım koşulları"), systemImage: "doc.plaintext.fill", url: config.termsURL)
        } header: {
            Text("Gizlilik")
        } footer: {
            Text("Konum geçmişini saklamayız; yalnızca check-in anındaki mesafe kaydedilir.")
        }
    }

    private var communitySection: some View {
        Section {
            NavigationLink(value: AppRoute.feedingGuide) {
                Label(String(localized: "Sorumlu besleme rehberi"), systemImage: "book.fill")
            }
            Button {
                if let url = supportMailURL { openURL(url) }
            } label: {
                HStack {
                    Label(String(localized: "Bize ulaş"), systemImage: "envelope.fill")
                        .foregroundStyle(MamaColor.textPrimary)
                    Spacer()
                    Text(verbatim: model.supportEmail)
                        .font(MamaFont.footnote)
                        .foregroundStyle(MamaColor.textSecondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("Topluluk")
        }
    }

    private var accountSection: some View {
        Section {
            Button {
                confirmSignOut = true
            } label: {
                Label(String(localized: "Çıkış yap"), systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(MamaColor.textPrimary)
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                HStack {
                    Label(String(localized: "Hesabı sil"), systemImage: "trash.fill")
                    if model.isDeletingAccount {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.isDeletingAccount)
        } header: {
            Text("Hesap")
        } footer: {
            Text("Hesabını silince kişisel verilerin silinir; eklediğin noktalar topluluk için anonim olarak kalır.")
        }
    }

    private var versionFooter: some View {
        Section {
            EmptyView()
        } footer: {
            VStack(spacing: 4) {
                Image(systemName: "pawprint.fill")
                    .foregroundStyle(MamaColor.mint)
                    .accessibilityHidden(true)
                Text("Mama Haritası \(appVersion)")
                if config.isDemo {
                    Text("Demo modu")
                }
            }
            .font(MamaFont.caption)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Eylemler

    private func deleteAccount() async {
        // Apple ile açılan hesapta Apple token'ı iptal edilmeli: önce yeniden Apple onayı (5.1.1(v)).
        var appleCode: String?
        if model.requiresAppleConfirmationToDelete {
            do {
                appleCode = try await AppleReauthorization.authorizationCode()
            } catch is CancellationError {
                return
            } catch {
                model.error = .invalidInput(SessionStore.appleConfirmationRequiredMessage)
                return
            }
        }
        guard await model.deleteAccount(session: session, appleAuthorizationCode: appleCode) else { return }
        router.popToRoot()
        router.showToast(String(localized: "Hesabın silindi. Bugüne kadar koyduğun her kap mama için teşekkürler."), style: .info)
    }

    private func signOut() async {
        await model.signOut(session: session)
        router.popToRoot()
        router.showToast(String(localized: "Çıkış yaptın. Görüşmek üzere!"), style: .info)
    }

    private var supportMailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = model.supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: String(localized: "Mama Haritası destek"))]
        return components.url
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    PreviewEnvironment { services in SettingsScreen(services: services) }
}
#endif
