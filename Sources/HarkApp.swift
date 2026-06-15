import SwiftUI

@main
struct HarkApp: App {
    var body: some Scene {
        Window("Hark", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
