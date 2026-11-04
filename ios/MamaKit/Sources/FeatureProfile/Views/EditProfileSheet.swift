#if canImport(UIKit)
import SwiftUI
import UIKit
import MamaCore
import MamaDesign

/// Profili düzenle (`AppSheet.editProfile`): görünen ad, mahalle, profil fotoğrafı.
public struct EditProfileSheet: View {
    @State private var model: EditProfileViewModel? = nil
    @State private var savedCount = 0
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let model {
                    EditProfileForm(model: model, onSave: { save(model) })
                } else {
                    LoadingView()
                }
            }
            .mamaBackground()
            .navigationTitle(String(localized: "Profili düzenle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Vazgeç")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Kaydet")) {
                        if let model { save(model) }
                    }
                    .fontWeight(.semibold)
                    .disabled(!(model?.canSave ?? false))
                }
            }
        }
        .interactiveDismissDisabled(model?.isSaving ?? false)
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear {
            // Profil ortamdan gelir; init'te okunamadığı için ilk görünümde kurulur.
            if model == nil {
                model = EditProfileViewModel(profile: session.profile, services: services)
            }
        }
    }

    private func save(_ model: EditProfileViewModel) {
        Task {
            guard await model.save(session: session) else { return }
            savedCount += 1
            router.showToast(String(localized: "Profilin güncellendi."))
            dismiss()
        }
    }
}

private struct EditProfileForm: View {
    @Bindable var model: EditProfileViewModel
    let onSave: () -> Void

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        avatar
                        PhotoInputButton(onPicked: { model.setAvatar($0) }) {
                            Label(String(localized: "Fotoğrafı değiştir"), systemImage: "camera.fill")
                                .font(MamaFont.subheadline.weight(.semibold))
                                .frame(minHeight: MamaMetrics.minTapSize)
                        }
                        if model.pendingAvatar != nil {
                            MamaTextButton(String(localized: "Seçimi geri al")) { model.discardPendingAvatar() }
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } footer: {
                Text("Fotoğraf yüklenmeden önce küçültülür ve içindeki konum bilgisi silinir.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            Section {
                TextField(String(localized: "Görünen ad"), text: $model.displayName)
                    .textContentType(.nickname)
                    .submitLabel(.next)
            } header: {
                Text("Görünen ad")
            } footer: {
                Text("Check-in'lerinde ve koruyucu listelerinde bu ad görünür.")
            }

            Section {
                TextField(String(localized: "Örn. Moda"), text: $model.neighborhood)
                    .textContentType(.sublocality)
                    .submitLabel(.done)
                    .onSubmit(onSave)
            } header: {
                Text("Mahalle (isteğe bağlı)")
            }

            if let message = model.errorMessage ?? model.validationIssue {
                Section {
                    BannerView(message, style: .error)
                }
                .listRowBackground(Color.clear)
            }
        }
        .disabled(model.isSaving)
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = model.pendingAvatar, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .accessibilityLabel(String(localized: "Seçilen profil fotoğrafı"))
        } else {
            AvatarView(name: model.displayName, url: model.avatarURL, size: 104)
        }
    }
}

#Preview {
    PreviewEnvironment { services in EditProfileSheet(services: services) }
}
#endif
