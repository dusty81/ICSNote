import SwiftUI

@main
struct ICSNoteApp: App {
    var body: some Scene {
        WindowGroup {
            Text("ICSNote")
                .frame(width: 320, height: 400)
        }
        .windowResizability(.contentSize)
    }
}
