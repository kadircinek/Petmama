import AppFeature
import SwiftUI

@main
struct MamaHaritasiApp: App {
    @UIApplicationDelegateAdaptor(MamaAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView(model: appDelegate.model)
        }
    }
}
