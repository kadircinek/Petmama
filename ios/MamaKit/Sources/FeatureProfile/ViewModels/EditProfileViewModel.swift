import Foundation
import Observation
import MamaCore

/// Profili düzenle: görünen ad, mahalle, profil fotoğrafı.
@MainActor
@Observable
public final class EditProfileViewModel {
    public var displayName: String
    public var neighborhood: String
    public private(set) var avatarURL: URL?
    /// Seçilmiş ama henüz yüklenmemiş fotoğraf (kaydet'te yüklenir).
    public private(set) var pendingAvatar: Data?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let services: AppServices

    public static let maximumNameLength = 40
    public static let maximumNeighborhoodLength = 60

    public init(profile: UserProfile?, services: AppServices) {
        self.services = services
        self.displayName = profile?.displayName ?? ""
        self.neighborhood = profile?.neighborhood ?? ""
        self.avatarURL = profile?.avatarURL
    }

    /// Formdaki ilk sorun; `nil` = kaydedilebilir.
    public var validationIssue: String? {
        let name = trimmedName
        if name.isEmpty { return "Görünen ad boş olamaz." }
        if name.count > Self.maximumNameLength { return "Görünen ad en fazla \(Self.maximumNameLength) karakter olabilir." }
        if trimmedNeighborhood.count > Self.maximumNeighborhoodLength {
            return "Mahalle en fazla \(Self.maximumNeighborhoodLength) karakter olabilir."
        }
        if ContentFilter.containsProfanity(name) || ContentFilter.containsProfanity(trimmedNeighborhood) {
            return MamaError.rejectedContent.userMessage
        }
        return nil
    }

    public var canSave: Bool { !isSaving && validationIssue == nil }

    public func setAvatar(_ data: Data) {
        pendingAvatar = data
        errorMessage = nil
    }

    public func discardPendingAvatar() {
        pendingAvatar = nil
    }

    /// Fotoğraf (varsa) yüklenir, profil güncellenir ve oturuma yazılır.
    @discardableResult
    public func save(session: SessionStore) async -> Bool {
        errorMessage = nil
        if let issue = validationIssue {
            errorMessage = issue
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            var url = avatarURL
            if let data = pendingAvatar {
                // Yükleyici EXIF/GPS'i temizler ve görseli küçültür (MediaUploader sözleşmesi).
                url = try await services.media.uploadJPEG(data)
            }
            let hood = trimmedNeighborhood
            let updated = try await services.profiles.updateProfile(
                displayName: trimmedName,
                neighborhood: hood.isEmpty ? nil : hood,
                avatarURL: url
            )
            session.update(updated)
            avatarURL = updated.avatarURL
            pendingAvatar = nil
            return true
        } catch {
            errorMessage = MamaError.classify(error).userMessage
            return false
        }
    }

    private var trimmedName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNeighborhood: String { neighborhood.trimmingCharacters(in: .whitespacesAndNewlines) }
}
