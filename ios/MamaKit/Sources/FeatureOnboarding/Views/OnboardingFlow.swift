#if canImport(UIKit)
import SwiftUI
import UIKit
import UserNotifications
import MamaCore
import MamaDesign

/// İlk kullanım akışı (ekran 2–7), tam ekran. Bittiğinde `onFinish()`.
public struct OnboardingFlow: View {
    @State private var model = OnboardingViewModel()
    @State private var signIn: SignInViewModel
    @State private var showLegal = false
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    private let services: AppServices
    private let onFinish: () -> Void

    public init(services: AppServices, onFinish: @escaping () -> Void) {
        self.services = services
        self.onFinish = onFinish
        _signIn = State(initialValue: SignInViewModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MamaBackground())
        .animation(.easeInOut(duration: 0.3), value: model.step)
        .task { await prepare() }
        .onChange(of: model.isFinished) { _, finished in
            if finished { onFinish() }
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn, model.step == .signIn { model.finish() }
        }
        .sheet(isPresented: $showLegal) {
            LegalHighlightsSheet(supportEmail: services.config.supportEmail)
        }
    }

    // MARK: - Üst çubuk

    private var topBar: some View {
        HStack(spacing: 16) {
            if let index = model.introIndex {
                ProgressSegments(count: OnboardingViewModel.introPageCount, current: index)
                MamaTextButton(String(localized: "Atla")) { model.skipIntro() }
                    .accessibilityHint(String(localized: "Tanıtımı geçer"))
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, MamaMetrics.screenPadding)
        .frame(height: 52)
    }

    // MARK: - Adımlar

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .intro:
            introPager
                .transition(.opacity)
        case .location:
            PermissionStepView(
                symbol: "location.fill",
                accents: ["mappin.circle.fill", "pawprint.fill", "checkmark.circle.fill"],
                tint: MamaColor.tileBlue,
                title: String(localized: "Konumunu kullanabilir miyiz?"),
                message: String(localized: "Yakındaki noktaları göstermek ve 'Mama koydum' dediğinde noktanın yanında olduğunu doğrulamak için. Konum geçmişini saklamayız."),
                points: [
                    .init(systemImage: "map.fill", text: String(localized: "Haritada sana en yakın mama noktalarını görürsün.")),
                    .init(systemImage: "checkmark.seal.fill", text: String(localized: "Check-in'de yalnızca noktaya olan mesafe (metre) kaydedilir.")),
                    .init(systemImage: "iphone", text: String(localized: "Yalnızca uygulamayı kullanırken; arka planda konum istemeyiz.")),
                ],
                primaryTitle: String(localized: "Konuma izin ver"),
                primaryIcon: "location.fill",
                isWorking: model.isRequesting,
                onPrimary: { Task { await model.requestLocation { await location.requestAuthorization() } } },
                onNotNow: { model.notNow() }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .notifications:
            PermissionStepView(
                symbol: "bell.fill",
                accents: ["cat.fill", "dog.fill", "heart.fill"],
                tint: MamaColor.tilePeach,
                title: String(localized: "Yakınında mama bekleyen hayvanlardan haberdar ol"),
                message: String(localized: "Yakınındaki bir kap boşaldığında veya takip ettiğin noktada bir şey değiştiğinde haber verelim."),
                points: [
                    .init(systemImage: "number.circle.fill", text: String(localized: "Günde en fazla \(NotificationPolicy.maxNeedFoodPushesPerDay) \"mama gerekli\" bildirimi.")),
                    .init(systemImage: "moon.zzz.fill", text: String(localized: "22:00–07:00 arası sessiz; geceleri rahatsız etmeyiz.")),
                    .init(systemImage: "slider.horizontal.3", text: String(localized: "Yarıçapı ve bildirim türlerini Ayarlar'dan değiştirebilirsin.")),
                ],
                primaryTitle: String(localized: "Bildirimlere izin ver"),
                primaryIcon: "bell.fill",
                isWorking: model.isRequesting,
                onPrimary: { Task { await model.requestNotifications { await requestNotificationPermission() } } },
                onNotNow: { model.notNow() }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .signIn:
            signInStep
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var introPager: some View {
        VStack(spacing: 16) {
            TabView(selection: Binding(get: { model.introIndex ?? 0 }, set: { model.showIntro(page: $0) })) {
                ForEach(OnboardingViewModel.introPages) { page in
                    IntroPageView(page: page).tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            Button(String(localized: "Devam")) { model.advance() }
                .buttonStyle(.mamaPrimary)
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.bottom, 8)
        }
    }

    private var signInStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                SignInContent(
                    model: signIn,
                    config: services.config,
                    onSignedIn: { model.finish() },
                    onOpenLegalFallback: { showLegal = true }
                )
                Button(String(localized: "Şimdilik gez")) { model.finish() }
                    .buttonStyle(.mamaSecondary(systemImage: "map"))
                Text("Hesapsız da haritayı gezebilir, noktaları görebilirsin. Mama koymak için sonra giriş yapman yeterli.")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - İzinler

    @MainActor
    private func prepare() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        model.prepare(
            locationDecided: location.authorization != .notDetermined,
            notificationsDecided: settings.authorizationStatus != .notDetermined,
            signedIn: session.isSignedIn
        )
    }

    /// İzin verilirse APNs kaydı başlar; token `MamaAppDelegate` üzerinden sunucuya gider.
    @MainActor
    private func requestNotificationPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }
}

#Preview {
    PreviewEnvironment(signedIn: false) { services in
        OnboardingFlow(services: services) {}
    }
}
#endif
