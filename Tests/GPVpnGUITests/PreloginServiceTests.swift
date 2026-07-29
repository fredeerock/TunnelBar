import XCTest
@testable import GPVpnGUI

final class PreloginServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    func testFetchRetriesAfterTimeoutThenSucceeds() async throws {
        let redirectURL = "https://sso.example.edu/login"
        let xml = preloginXML(method: "REDIRECT", decodedRequest: redirectURL)

        MockURLProtocol.enqueue(.failure(URLError(.timedOut)))
        MockURLProtocol.enqueue(.success(statusCode: 200, data: xml))

        let service = makeService()
        let result = try await service.fetch(server: "vpn.example.edu", clientOS: "Mac", ignoreCert: false)

        switch result {
        case .redirect(let url):
            XCTAssertEqual(url.absoluteString, redirectURL)
        default:
            XCTFail("Expected redirect auth method")
        }

        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testFetchTimesOutAfterRetries() async {
        MockURLProtocol.enqueue(.failure(URLError(.timedOut)))
        MockURLProtocol.enqueue(.failure(URLError(.timedOut)))

        let service = makeService()

        do {
            _ = try await service.fetch(server: "vpn.example.edu", clientOS: "Mac", ignoreCert: false)
            XCTFail("Expected timeout error")
        } catch let error as VPNError {
            XCTAssertTrue(error.message.contains("timed out"), "Unexpected message: \(error.message)")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    private func makeService() -> PreloginService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]

        return PreloginService(
            sessionFactory: { _ in URLSession(configuration: config) },
            retryDelayNanoseconds: 1,
            sleepFn: { _ in }
        )
    }

    private func preloginXML(method: String, decodedRequest: String) -> Data {
        let encoded = Data(decodedRequest.utf8).base64EncodedString()
        let xml = """
        <prelogin-response>
          <status>Success</status>
          <saml-auth-method>\(method)</saml-auth-method>
          <saml-request>\(encoded)</saml-request>
        </prelogin-response>
        """
        return Data(xml.utf8)
    }
}

private final class MockURLProtocol: URLProtocol {
    enum MockResult {
        case success(statusCode: Int, data: Data)
        case failure(URLError)
    }

    private static let stateQueue = DispatchQueue(label: "MockURLProtocol.state")
    private static var queue: [MockResult] = []
    private static var count: Int = 0

    static var requestCount: Int {
        stateQueue.sync { count }
    }

    static func reset() {
        stateQueue.sync {
            queue.removeAll()
            count = 0
        }
    }

    static func enqueue(_ result: MockResult) {
        stateQueue.sync {
            queue.append(result)
        }
    }

    private static func dequeue() -> MockResult? {
        stateQueue.sync {
            guard !queue.isEmpty else { return nil }
            count += 1
            return queue.removeFirst()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let result = Self.dequeue() else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        switch result {
        case .success(let statusCode, let data):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)

        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
