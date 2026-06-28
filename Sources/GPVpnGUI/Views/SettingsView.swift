import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var installing = false
    @State private var uninstalling = false
    @State private var confirmUninstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TunnelBar")
                .font(.title2).bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("VPN address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("VPN gateway address", text: $app.server)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            HStack {
                if app.isConnected {
                    Button("Disconnect") { app.disconnect() }
                } else {
                    Button("Connect") { app.connect() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(app.isBusy || trimmedServer.isEmpty)
                }

                Spacer()
            }

            HStack {
                if app.dependenciesInstalled {
                    Button {
                        confirmUninstall = true
                    } label: {
                        Text(uninstalling ? "Uninstalling…" : "Uninstall Dependencies")
                    }
                    .disabled(installing || uninstalling)
                    .confirmationDialog(
                        "Remove openconnect and the privileged helper?",
                        isPresented: $confirmUninstall,
                        titleVisibility: .visible
                    ) {
                        Button("Uninstall Dependencies", role: .destructive) {
                            uninstalling = true
                            Task {
                                await app.uninstallDependencies()
                                uninstalling = false
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                } else {
                    Button {
                        installing = true
                        Task {
                            await app.installDependencies()
                            installing = false
                        }
                    } label: {
                        Text(installing ? "Installing…" : "Install Dependencies")
                    }
                    .disabled(installing || uninstalling)
                }

                Spacer()
            }

            statusLine

            Text("Log")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(app.log.isEmpty ? "—" : app.log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(6)
            }
            .frame(height: 120)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
        .frame(width: 460)
        .onAppear { app.refreshDependencyStatus() }
    }

    private var trimmedServer: String {
        app.server.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch app.state {
        case .disconnected: return "Disconnected"
        case .authenticating: return "Signing in…"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error(let message): return message
        }
    }

    private var statusColor: Color {
        switch app.state {
        case .connected: return .green
        case .authenticating, .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .secondary
        }
    }
}
