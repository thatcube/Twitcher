import SwiftUI
import SDWebImage
import SDWebImageWebPCoder

@main
struct TwitcherApp: App {
    init() {
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
