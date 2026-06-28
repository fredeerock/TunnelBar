import SwiftUI
import AppKit
import WebKit

/// High-level connection state for the VPN.
enum VPNState: Equatable {
    case disconnected
    case authenticating
    case connecting
    case connected
    case error(String)
}

/// A user-facing error with a friendly message.
struct VPNError: Error {
    let message: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var server: String = UserDefaults.standard.string(forKey: "lastServer") ?? ""
    @Published var state: VPNState = .disconnected
    @Published var log: String = ""
    @Published var dependenciesInstalled: Bool = false

    // Advanced options (defaults match `gp-saml-gui` behaviour on macOS).
    @Published var ignoreCertErrors: Bool = false

    // This app is macOS-only, so the reported clientos is always "Mac".
    let clientOS = "Mac"

    private let prelogin = PreloginService()
    private let openconnect = OpenConnectManager()
    let dependencies = DependencyManager()
    private var samlController: SAMLLoginController?

    // MARK: - Derived UI helpers

    var isConnected: Bool { state == .connected }

    var isBusy: Bool {
        switch state {
        case .authenticating, .connecting: return true
        default: return false
        }
    }

    var menuBarSymbol: String {
        switch state {
        case .connected: return "lock.shield.fill"
        case .authenticating, .connecting: return "lock.shield"
        default: return "lock.open"
        }
    }

    func appendLog(_ message: String) {
        log += message + "\n"
    }

    /// Re-checks whether openconnect and the privileged helper are present.
    func refreshDependencyStatus() {
        dependenciesInstalled = dependencies.openconnectInstalled && dependencies.helperInstalled
    }

    // MARK: - Actions

    func connect() {
        let target = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            state = .error("Enter a VPN address first.")
            return
        }
        guard !isBusy else { return }

        UserDefaults.standard.set(target, forKey: "lastServer")
        state = .authenticating
        appendLog("Looking for SAML login at \(target)…")

        Task {
            do {
                let auth = try await prelogin.fetch(
                    server: target,
                    clientOS: clientOS,
                    ignoreCert: ignoreCertErrors
                )
                appendLog("Got SAML \(auth.methodDescription). Opening login window…")

                let controller = SAMLLoginController(ignoreCert: ignoreCertErrors)
                samlController = controller
                let result = try await controller.present(auth: auth, defaultServer: target)
                samlController = nil
                appendLog("Signed in as \(result.username).")

                state = .connecting
                appendLog("Starting openconnect…")
                try await openconnect.connect(
                    server: result.server,
                    username: result.username,
                    cookie: result.cookie,
                    usergroup: result.usergroup
                )
                state = .connected
                appendLog("Connected.")
            } catch is CancellationError {
                samlController = nil
                state = .disconnected
                appendLog("Login canceled.")
            } catch let error as VPNError {
                samlController = nil
                state = .error(error.message)
                appendLog("Error: \(error.message)")
            } catch {
                samlController = nil
                state = .error(error.localizedDescription)
                appendLog("Error: \(error.localizedDescription)")
            }
        }
    }

    func disconnect() {
        Task {
            do {
                try await openconnect.disconnect()
                appendLog("Disconnected.")
            } catch {
                appendLog("Disconnect error: \(error.localizedDescription)")
            }
            state = .disconnected
        }
    }

    func installDependencies() async {
        appendLog("Checking dependencies…")
        do {
            try await dependencies.installAll { [weak self] message in
                Task { @MainActor in self?.appendLog(message) }
            }
        } catch let error as VPNError {
            appendLog("Error: \(error.message)")
        } catch {
            appendLog("Error: \(error.localizedDescription)")
        }
        refreshDependencyStatus()
    }

    func uninstallDependencies() async {
        appendLog("Uninstalling…")
        // Disconnect while the helper still exists.
        if state == .connected {
            try? await openconnect.disconnect()
            state = .disconnected
        }
        do {
            try await dependencies.uninstallAll { [weak self] message in
                Task { @MainActor in self?.appendLog(message) }
            }
        } catch let error as VPNError {
            appendLog("Error: \(error.message)")
        } catch {
            appendLog("Error: \(error.localizedDescription)")
        }

        // Wipe the saved gateway address and cached SAML credentials.
        server = ""
        UserDefaults.standard.removeObject(forKey: "lastServer")
        await clearWebData()
        appendLog("Cleared saved address and cached credentials.")
        refreshDependencyStatus()
    }

    private func clearWebData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0))
    }
}
