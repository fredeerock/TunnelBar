import Foundation

/// Detects and installs the runtime dependencies:
///   1. Homebrew (must be present — guides the user if not)
///   2. openconnect (installed via Homebrew)
///   3. The privileged helper + a scoped passwordless-sudo rule (one admin prompt)
final class DependencyManager {

    var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var openconnectInstalled: Bool {
        ["/opt/homebrew/bin/openconnect", "/usr/local/bin/openconnect", "/usr/bin/openconnect"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var helperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: OpenConnectManager.helperPath)
    }

    func installAll(log: @escaping (String) -> Void) async throws {
        guard let brew = brewPath else {
            throw VPNError(message: "Homebrew is required. Install it from https://brew.sh, then click “Install Dependencies” again.")
        }

        if openconnectInstalled {
            log("openconnect is already installed.")
        } else {
            log("Installing openconnect via Homebrew (this can take a few minutes)…")
            let result = try await Task.detached(priority: .userInitiated) {
                try ProcessRunner.run(brew, ["install", "openconnect"], input: nil)
            }.value
            if !result.stdout.isEmpty { log(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if !result.stderr.isEmpty { log(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard openconnectInstalled else {
                throw VPNError(message: "openconnect could not be installed. See the log above.")
            }
        }

        log("Installing the privileged helper. You’ll be asked for your password once…")
        try await installHelper()
        log("All set. You can now connect and disconnect without a password prompt.")
    }

    func uninstallAll(log: @escaping (String) -> Void) async throws {
        log("Removing the privileged helper. You’ll be asked for your password once…")
        try await removeHelper()
        log("Privileged helper removed.")

        if let brew = brewPath, openconnectInstalled {
            log("Uninstalling openconnect via Homebrew…")
            let result = try await Task.detached(priority: .userInitiated) {
                try ProcessRunner.run(brew, ["uninstall", "openconnect"], input: nil)
            }.value
            if !result.stdout.isEmpty { log(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if !result.stderr.isEmpty { log(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        } else {
            log("openconnect is not installed.")
        }
        log("Uninstall complete.")
    }

    private func installHelper() async throws {
        let user = NSUserName()
        let helperTmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("gp-vpn-helper.sh")
        try helperScriptSource.write(toFile: helperTmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: helperTmp) }

        // The installer validates the sudoers entry with visudo before placing it,
        // and scopes NOPASSWD to the single helper path only.
        let installScript = """
        #!/bin/bash
        set -e
        install -d -o root -g wheel -m 755 /usr/local/libexec
        install -o root -g wheel -m 755 '\(helperTmp)' '\(OpenConnectManager.helperPath)'
        SUDOERS_TMP=$(mktemp)
        printf '%s\\n' '\(user) ALL=(root) NOPASSWD: \(OpenConnectManager.helperPath)' > "$SUDOERS_TMP"
        visudo -cf "$SUDOERS_TMP"
        install -o root -g wheel -m 440 "$SUDOERS_TMP" /etc/sudoers.d/gp-vpn-gui
        rm -f "$SUDOERS_TMP"
        """
        try await runPrivilegedScript(installScript, canceledMessage: "Helper installation was canceled.")
    }

    private func removeHelper() async throws {
        let removeScript = """
        #!/bin/bash
        rm -f '\(OpenConnectManager.helperPath)' /etc/sudoers.d/gp-vpn-gui /var/run/gp-vpn-gui.pid /var/log/gp-vpn-gui.log
        """
        try await runPrivilegedScript(removeScript, canceledMessage: "Uninstall was canceled.")
    }

    /// Runs a bash script as root via a single native admin-password dialog.
    private func runPrivilegedScript(_ contents: String, canceledMessage: String) async throws {
        let scriptTmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("gp-vpn-priv-\(UUID().uuidString).sh")
        try contents.write(toFile: scriptTmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptTmp) }

        try await Task.detached(priority: .userInitiated) {
            let appleScript = "do shell script \"/bin/bash \\\"\(scriptTmp)\\\"\" with administrator privileges"
            let result = try ProcessRunner.run("/usr/bin/osascript", ["-e", appleScript], input: nil)
            if result.status != 0 {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.lowercased().contains("cancel") {
                    throw VPNError(message: canceledMessage)
                }
                throw VPNError(message: detail.isEmpty ? canceledMessage : detail)
            }
        }.value
    }
}
