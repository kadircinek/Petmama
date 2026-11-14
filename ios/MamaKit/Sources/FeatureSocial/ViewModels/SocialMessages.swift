import Foundation
import MamaCore

/// Tanışma eylemlerinin kullanıcıya gösterilecek Türkçe mesajları. `nil` = mesaj gerektirmeyen başarı.
public enum SocialMessages {
    public static let consentRequired = "Önce sosyal onayı vermelisin."
    public static let meetupFull = "Bu buluşma doldu."

    public static func message(for outcome: JoinMeetupOutcome) -> String? {
        switch outcome {
        case .joined: return nil
        case .full: return meetupFull
        case .removed: return "Düzenleyen seni bu buluşmadan çıkardı, tekrar katılamazsın."
        case .cancelled: return "Bu buluşma iptal edildi."
        case .ended: return "Bu buluşma sona erdi."
        case .consentRequired: return consentRequired
        case .notFound: return "Bu buluşma artık görünmüyor."
        }
    }

    public static func message(for outcome: CreateMeetupOutcome) -> String? {
        switch outcome {
        case .created: return nil
        case .consentRequired: return consentRequired
        case .rejectedContent: return MamaError.rejectedContent.userMessage
        case .limitReached(let limit): return "Bugün \(limit) buluşma oluşturdun, yarın devam edebilirsin."
        case .invalid(let reason): return message(for: reason)
        }
    }

    public static func message(for reason: MeetupInvalidReason) -> String {
        switch reason {
        case .titleLength: return "Başlık \(SocialPolicy.titleLength.lowerBound) ile \(SocialPolicy.titleLength.upperBound) karakter arasında olmalı."
        case .descriptionTooLong: return "Açıklama en fazla \(SocialPolicy.maxDescription) karakter olabilir."
        case .placeNameLength: return "Buluşma yerini yazar mısın? En fazla \(SocialPolicy.placeNameLength.upperBound) karakter."
        case .startTooSoon: return "Buluşma en erken 1 saat sonrasına planlanabilir."
        case .startTooLate: return "Buluşma en fazla \(SocialPolicy.maxLeadDays) gün sonrasına planlanabilir."
        case .durationRange: return "Süre 30 dakika ile 8 saat arasında olmalı."
        case .capacityRange: return "Kişi sınırı \(SocialPolicy.capacity.lowerBound) ile \(SocialPolicy.capacity.upperBound) arasında olmalı."
        case .spotNotFound: return "Seçtiğin nokta artık görünmüyor."
        }
    }

    public static func message(for outcome: SendRequestOutcome) -> String? {
        switch outcome {
        case .sent: return "İsteğin gönderildi."
        case .autoAccepted: return "Bağlantı kuruldu! Artık yazışabilirsiniz."
        case .consentRequired: return consentRequired
        case .notVisible: return "İkinizin de Hayvanseverler'de görünür olması gerekiyor."
        case .alreadyConnected: return "Zaten bağlantıdasınız."
        case .alreadyPending: return "İsteğin zaten bekliyor."
        case .cooldown: return "Bu kişiye şimdilik tekrar istek gönderemezsin."
        case .rejectedContent: return MamaError.rejectedContent.userMessage
        case .limitReached(let limit): return "Bugün \(limit) istek gönderdin, yarın devam edebilirsin."
        case .noteTooLong: return "Not en fazla \(SocialPolicy.maxNote) karakter olabilir."
        case .notFound: return "Bu kişi artık görünmüyor."
        }
    }

    public static func message(for outcome: SocialProfileOutcome) -> String? {
        switch outcome {
        case .saved: return nil
        case .consentRequired: return consentRequired
        case .rejectedContent: return MamaError.rejectedContent.userMessage
        case .aboutTooLong: return "Hakkında kısmı en fazla \(SocialPolicy.maxAbout) karakter olabilir."
        case .locationRequired: return "Görünür olmak için yaklaşık konumuna ihtiyacımız var."
        }
    }

    public static func message(for outcome: SendMessageOutcome) -> String? {
        switch outcome {
        case .sent: return nil
        case .notMember: return "Bu sohbetin üyesi değilsin."
        case .readOnly: return "Bu sohbet artık yalnızca okunabiliyor."
        case .rejectedContent: return MamaError.rejectedContent.userMessage
        case .rateLimited: return "Çok hızlı yazıyorsun, biraz bekleyip tekrar dene."
        case .bodyEmpty: return "Bir şeyler yazar mısın?"
        case .bodyTooLong: return "Mesaj en fazla \(SocialPolicy.maxMessage) karakter olabilir."
        }
    }
}
