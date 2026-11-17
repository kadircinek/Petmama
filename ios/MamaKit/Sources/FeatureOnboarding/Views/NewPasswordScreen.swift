#if canImport(UIKit)
import SwiftUI
import UIKit
import MamaCore
import MamaDesign

/// Şifre sıfırlama bağlantısıyla gelindiğinde açılan sheet. `onFinish(true)` şifre kaydedilince.
public struct NewPasswordScreen: View {
    @State private var model = NewPasswordViewModel()
    @Environment(SessionStore.self) private var session
    @FocusState private var focusedField: Field?
    private let onFinish: (Bool) -> Void

    private enum Field: Hashable { case password, confirmation }

    public init(onFinish: @escaping (Bool) -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    form
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .mamaBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onFinish(false)
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
        .onAppear { focusedField = .password }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(MamaColor.ink)
                .frame(width: 68, height: 68)
                .background(Circle().fill(MamaColor.mint))
                .accessibilityHidden(true)
            Text("Yeni şifre belirle")
                .font(MamaFont.largeTitle)
                .foregroundStyle(MamaColor.textPrimary)
            Text("Bağlantı doğrulandı. Hesabın için yeni bir şifre seç.")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var form: some View {
        VStack(spacing: 14) {
            InputField(systemImage: "lock.fill") {
                SecureField(String(localized: "Yeni şifre (en az 8 karakter)"), text: $model.password)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirmation }
            }
            InputField(systemImage: "lock.rotation") {
                SecureField(String(localized: "Yeni şifre (tekrar)"), text: $model.confirmation)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirmation)
                    .submitLabel(.done)
                    .onSubmit(submit)
            }
            if let message = model.errorMessage {
                BannerView(message, style: .error)
            }
            Button(action: submit) {
                if model.isWorking {
                    ProgressView().tint(MamaColor.onInk)
                } else {
                    Text("Şifreyi kaydet")
                }
            }
            .buttonStyle(.mamaPrimary)
            .disabled(!model.canSubmit)
        }
        .mamaCard()
    }

    private func submit() {
        focusedField = nil
        Task {
            if await model.submit(session: session) { onFinish(true) }
        }
    }
}
#endif
