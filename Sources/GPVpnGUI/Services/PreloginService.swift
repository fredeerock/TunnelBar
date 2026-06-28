import Foundation

/// The SAML entry point returned by the VPN prelogin endpoint.
enum PreloginAuth {
    case post(html: String, baseURL: URL)
    case redirect(url: URL)

    var methodDescription: String {
        switch self {
        case .post: return "POST"
        case .redirect: return "REDIRECT"
        }
    }
}

/// Replicates the first step of `gp-saml-gui`: POST to the gateway's
/// `ssl-vpn/prelogin.esp` endpoint and extract the SAML request.
final class PreloginService {

    func fetch(server: String, clientOS: String, ignoreCert: Bool) async throws -> PreloginAuth {
        let host = normalizedHost(server)
        guard !host.isEmpty, let url = URL(string: "https://\(host)/ssl-vpn/prelogin.esp") else {
            throw VPNError(message: "Invalid VPN address.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // The gateway expects this exact User-Agent for the SAML protocol.
        request.setValue("PAN GlobalProtect", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let fields = [
            "tmp": "tmp",
            "kerberos-support": "yes",
            "ipv6-support": "yes",
            "clientVer": "4100",
            "clientos": clientOS
        ]
        request.httpBody = fields
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let session: URLSession
        if ignoreCert {
            session = URLSession(configuration: .ephemeral, delegate: InsecureSessionDelegate(), delegateQueue: nil)
        } else {
            session = URLSession(configuration: .ephemeral)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VPNError(message: "Could not reach \(host). \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VPNError(message: "The server returned an unexpected response. Check the VPN address.")
        }

        return try parse(data: data, host: host)
    }

    private func normalizedHost(_ server: String) -> String {
        var host = server.trimmingCharacters(in: .whitespacesAndNewlines)
        host = host.replacingOccurrences(of: "https://", with: "")
        host = host.replacingOccurrences(of: "http://", with: "")
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        return host
    }

    private func parse(data: Data, host: String) throws -> PreloginAuth {
        let parser = PreloginXMLParser()
        guard parser.parse(data) else {
            throw VPNError(message: "This does not look like a supported SAML VPN gateway.")
        }

        guard let method = parser.samlAuthMethod,
              let requestB64 = parser.samlRequest,
              let decoded = Data(base64Encoded: requestB64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let body = String(data: decoded, encoding: .utf8) else {
            if let status = parser.status, status != "Success" {
                throw VPNError(message: parser.msg ?? "The gateway reported a prelogin error.")
            }
            throw VPNError(message: "This gateway is not configured for SAML login (try a different address).")
        }

        switch method.uppercased() {
        case "POST":
            guard let base = URL(string: "https://\(host)") else {
                throw VPNError(message: "Invalid VPN address.")
            }
            return .post(html: body, baseURL: base)
        case "REDIRECT":
            guard let url = URL(string: body) else {
                throw VPNError(message: "The gateway returned an invalid SAML redirect.")
            }
            return .redirect(url: url)
        default:
            throw VPNError(message: "Unsupported SAML method (\(method)).")
        }
    }
}

/// Minimal XML parser for the `<prelogin-response>` document.
private final class PreloginXMLParser: NSObject, XMLParserDelegate {
    private(set) var rootTag: String?
    private(set) var status: String?
    private(set) var msg: String?
    private(set) var samlAuthMethod: String?
    private(set) var samlRequest: String?

    private var current = ""

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        let ok = parser.parse()
        return ok && rootTag == "prelogin-response"
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if rootTag == nil { rootTag = elementName }
        current = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "status": status = value
        case "msg": msg = value
        case "saml-auth-method": samlAuthMethod = value
        case "saml-request": samlRequest = value
        default: break
        }
        current = ""
    }
}

/// URLSession delegate that accepts any server certificate. Only used when the
/// user explicitly enables "Ignore certificate errors".
final class InsecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
