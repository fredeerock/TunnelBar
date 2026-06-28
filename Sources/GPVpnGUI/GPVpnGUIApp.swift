import SwiftUI

@main
struct GPVpnGUIApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(app)
        } label: {
            Image(systemName: app.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }
}
