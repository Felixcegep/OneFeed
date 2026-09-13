import Foundation
import Testing
@testable import OneFeed

@Suite(.serialized)
@MainActor
struct GoogleDriveAPIClientTests {
    @Test func findBackupFileParsesFirstFileIncludingUnusedChecksum() async throws {
        let harness = try GoogleDriveAPIClientTestHarness()
        defer { harness.tearDown() }

        GoogleDriveURLProtocolStub.handler = { _ in
            let body = Data(
                #"{"files":[{"id":"file-1","name":"OneFeed.library.json","md5Checksum":"abc123"}]}"#.utf8
            )
            return (200, body)
        }

        let file = try await harness.makeClient().findBackupFile()
        #expect(file?.id == "file-1")
        #expect(file?.name == "OneFeed.library.json")
        #expect(file?.md5Checksum == "abc123")

        let request = GoogleDriveURLProtocolStub.requests.first
        #expect(request?.url?.absoluteString.contains("/drive/v3/files") == true)
        #expect(request?.url?.absoluteString.contains("pageSize=1") == true)
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-access")
    }

    @Test func downloadFileReturnsBody() async throws {
        let harness = try GoogleDriveAPIClientTestHarness()
        defer { harness.tearDown() }

        let payload = Data("backup-body".utf8)
        GoogleDriveURLProtocolStub.handler = { _ in
            (200, payload)
        }

        let data = try await harness.makeClient().downloadFile(id: "file-1")
        #expect(data == payload)

        let request = GoogleDriveURLProtocolStub.requests.first
        #expect(request?.url?.absoluteString.contains("alt=media") == true)
        #expect(request?.url?.absoluteString.contains("/files/file-1") == true)
    }

    @Test func unauthorizedStatusThrowsUnauthorized() async throws {
        let harness = try GoogleDriveAPIClientTestHarness()
        defer { harness.tearDown() }

        GoogleDriveURLProtocolStub.handler = { _ in
            (401, Data(#"{"error":{"message":"Invalid Credentials"}}"#.utf8))
        }

        await #expect(throws: GoogleDriveAPIError.unauthorized) {
            _ = try await harness.makeClient().downloadFile(id: "file-1")
        }
        #expect(GoogleDriveAPIError.unauthorized.errorDescription == "Link Google Drive again to continue.")
    }
}

@MainActor
private struct GoogleDriveAPIClientTestHarness {
    let tokenStore: GoogleDriveTokenStore
    let session: URLSession

    init() throws {
        GoogleDriveURLProtocolStub.reset()
        let tokenStore = GoogleDriveTokenStore(
            service: "felix.MonoRss.googleDriveOAuth.apiTests.\(UUID().uuidString)",
            account: "credentials"
        )
        tokenStore.delete()
        try tokenStore.save(
            GoogleDriveCredentials(
                accessToken: "test-access",
                refreshToken: "test-refresh",
                expiresAt: Date.distantFuture,
                tokenType: "Bearer",
                accountEmail: "user@example.com"
            )
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GoogleDriveURLProtocolStub.self]
        self.tokenStore = tokenStore
        self.session = URLSession(configuration: configuration)
    }

    func makeClient() -> GoogleDriveAPIClient {
        let oauth = GoogleDriveOAuthClient(tokenStore: tokenStore, session: session)
        return GoogleDriveAPIClient(oauth: oauth, session: session)
    }

    func tearDown() {
        GoogleDriveURLProtocolStub.reset()
        tokenStore.delete()
    }
}

private final class GoogleDriveURLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) -> (Int, Data))?
    private static var _requests: [URLRequest] = []

    static var handler: (@Sendable (URLRequest) -> (Int, Data))? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    static var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    static func reset() {
        lock.withLock {
            _handler = nil
            _requests = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler: (@Sendable (URLRequest) -> (Int, Data))?
        Self.lock.lock()
        Self._requests.append(request)
        handler = Self._handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, data) = handler(request)
        let url = request.url ?? URL(string: "https://www.googleapis.com/")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
