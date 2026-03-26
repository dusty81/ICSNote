import SwiftUI

@main
struct ICSNoteApp: App {
    @State private var settings = AppSettings()
    @State private var viewModel: AppViewModel?

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel {
                    MainView(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = AppViewModel(settings: settings)
                }
            }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settings: settings)
        }
    }
}
