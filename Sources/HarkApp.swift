import SwiftUI

@main
struct HarkApp: App {
    init() {
        Preferences.register()
    }

    var body: some Scene {
        Window("Hark", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
