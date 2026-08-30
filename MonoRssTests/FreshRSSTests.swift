import Foundation
import Testing
@testable import MonoRss

private actor RecordingFreshRSSTransport: FreshRSSHTTPTransport {
    private(set) var requests: [URLRequest] = []
    var responseData: Data

    init(responseData: Data) {
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        if request.url?.path.hasSuffix("/reader/api/0/token") == true {
            return (Data("action-token\n".utf8), response)
        }
        return (responseData, response)
    }

    func lastRequest() -> URLRequest? { requests.last }
}

struct FreshRSSTests {
    @Test func clientLoginBuildsFormBodyWithoutLeakingCredentialsIntoURL() async throws {
        let transport = RecordingFreshRSSTransport(responseData: Data("Auth=server-token\nEmail=reader\n".utf8))
        let configuration = try FreshRSSConfiguration(baseURL: URL(string: "https://rss.example.test/freshrss/")!, username: "reader")
        let client = FreshRSSClient(configuration: configuration, transport: transport)
        let credentials = try FreshRSSCredentials(username: "reader", password: "p&ss word")

        let result = try await client.login(credentials: credentials)
        #expect(result.authToken == "server-token")
        let request = await transport.lastRequest()
        #expect(request?.url?.absoluteString == "https://rss.example.test/freshrss/api/greader.php/accounts/ClientLogin")
        #expect(request?.httpMethod == "POST")
        #expect(String(data: request?.httpBody ?? Data(), encoding: .utf8) == "Email=reader&Passwd=p%26ss%20word")
    }

    @Test func subscriptionAndItemDTOsMapReaderLabelsAndContent() async throws {
        let payload = #"{"items":[{"id":"tag:example,2026:item-1","title":"A story","timestampUsec":"1760000000000000","author":{"name":"Reader"},"origin":{"streamId":"feed/http://example.test/rss","title":"Example"},"canonical":[{"href":"https://example.test/story"}],"content":{"content":"<p>Body</p>"},"categories":["user/-/state/com.google/read","user/-/state/com.google/starred"]}]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FreshRSSStreamContentsResponse.self, from: payload)
        let item = try #require(decoded.items.first)
        #expect(item.isRead)
        #expect(item.isStarred)
        #expect(item.snapshot.remoteID == "tag:example,2026:item-1")
        #expect(item.snapshot.feedRemoteID == "feed/http://example.test/rss")
        #expect(item.snapshot.contentHTML == "<p>Body</p>")
        #expect(item.snapshot.url == URL(string: "https://example.test/story"))
    }

    @Test func unreadIDsRequestUsesReaderReadExclusionAndAuthorizationHeader() async throws {
        let transport = RecordingFreshRSSTransport(responseData: Data(#"{"itemRefs":[]}"#.utf8))
        let configuration = try FreshRSSConfiguration(baseURL: URL(string: "https://rss.example.test")!, username: "reader")
        let client = FreshRSSClient(configuration: configuration, transport: transport)

        _ = try await client.itemIDs(streamID: "feed/http://example.test/rss", authToken: "token", unreadOnly: true, limit: 9)
        let request = await transport.lastRequest()
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "GoogleLogin auth=token")
        #expect(request?.url?.path == "/api/greader.php/reader/api/0/stream/items/ids")
        let query = URLComponents(url: try #require(request?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first(where: { $0.name == "xt" })?.value == FreshRSSLabel.read)
        #expect(query?.first(where: { $0.name == "n" })?.value == "9")
    }

    @Test func itemIDsRequestSendsContinuationToken() async throws {
        let transport = RecordingFreshRSSTransport(responseData: Data(#"{"itemRefs":[]}"#.utf8))
        let configuration = try FreshRSSConfiguration(baseURL: URL(string: "http://rss.local")!, username: "reader")
        let client = FreshRSSClient(configuration: configuration, transport: transport)

        _ = try await client.itemIDs(streamID: "feed/http://example.test/rss", authToken: "token", unreadOnly: false, limit: 100, continuation: "page-2")
        let request = await transport.lastRequest()
        #expect(request?.url?.absoluteString.hasPrefix("http://rss.local/") == true)
        let query = URLComponents(url: try #require(request?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first(where: { $0.name == "c" })?.value == "page-2")
        #expect(query?.contains(where: { $0.name == "xt" }) == false)
    }

    @Test func mutationFetchesFreshRSSActionTokenAndSendsItInPOSTBody() async throws {
        let transport = RecordingFreshRSSTransport(responseData: Data("OK".utf8))
        let configuration = try FreshRSSConfiguration(baseURL: URL(string: "https://rss.example.test")!, username: "reader")
        let client = FreshRSSClient(configuration: configuration, transport: transport)

        try await client.markRead(itemID: "tag:example:item-1", authToken: "reader/auth")
        let request = await transport.lastRequest()
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/api/greader.php/reader/api/0/edit-tag")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "GoogleLogin auth=reader/auth")
        let body = String(data: request?.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("T=action-token"))
        #expect(body.contains("a=user%2F-%2Fstate%2Fcom.google%2Fread"))
    }
}
