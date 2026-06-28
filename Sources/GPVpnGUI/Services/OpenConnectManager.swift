import Foundation

/// Connects/disconnects the VPN by invoking the privileged helper through
/// passwordless `sudo`. The helper itself runs `openconnect` as root.
final class OpenConnectManager {

    static let helperPath = "/usr/local/libexec/gp-vpn-helper"

    func connect(server: String, username: String, cookie: String, usergroup: String) async throws {
        let helper = Self.helperPath
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            throw VPNError(message: "Helper not installed. Click “Install Dependencies” first.")
        }

        try await Task.detached(priority: .userInitiated) {
            let result = try ProcessRunner.run(
                "/usr/bin/sudo",
                ["-n", helper, "connect", server, username, usergroup],
                input: cookie
            )
            if result.status != 0 {
                if result.stderr.lowercased().contains("password") {
                    throw VPNError(message: "Passwordless access isn’t set up yet. Click “Install Dependencies”.")
                }
                let detail = result.stderr.isEmpty ? result.stdout : result.stderr
                throw VPNError(message: detail.isEmpty ? "openconnect failed to start." : detail.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }.value
    }

    func disconnect() async throws {
        let helper = Self.helperPath
        guard FileManager.default.isExecutableFile(atPath: helper) else { return }
        try await Task.detached(priority: .userInitiated) {
            _ = try ProcessRunner.run("/usr/bin/sudo", ["-n", helper, "disconnect"], input: nil)
        }.value
    }
}
