import Foundation
import MamaCore

/// Push bildirimine dokunulunca açılacak hedef. `push-dispatch` edge function'ı
/// APNs payload'una `spot_id` / `need_id` / `post_id` / `kind` ekler.
public enum PushPayload {
    public static func route(from userInfo: [AnyHashable: Any]) -> (route: AppRoute, tab: AppTab)? {
        if let raw = userInfo["post_id"] as? String, let id = UUID(uuidString: raw) {
            return (.post(id), .community)
        }
        if let raw = userInfo["need_id"] as? String, let id = UUID(uuidString: raw) {
            return (.need(id), .community)
        }
        if let raw = userInfo["spot_id"] as? String, let id = UUID(uuidString: raw) {
            return (.spot(id), .map)
        }
        return nil
    }

    /// APNs cihaz jetonu → onaltılık dizgi.
    public static func hexToken(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
