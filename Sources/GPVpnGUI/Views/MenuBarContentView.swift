import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Text(statusText)

        Divider()

        if app.isConnected {
            Button("Disconnect") { app.disconnect() }
        } else {
            Button("Connect") {
                if app.server.trimmingCharacters(in: .whitespaces).isEmpty {
                    openSettings()
                } else {
                    app.connect()
                }
            }
            .disabled(app.isBusy)
        }

        Button("Settings…") { openSettings() }

        Divider()

        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private var statusText: String {
        switch app.state {
        case .disconnected: return "Disconnected"
        case .authenticating: return "Signing in…"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error(let message): return "Error: \(message)"
        }
    }

    private func openSettings() {
        SettingsWindowManager.shared.show(app: app)
    }
}
