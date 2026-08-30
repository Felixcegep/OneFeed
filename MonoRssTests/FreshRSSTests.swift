import Foundation
import Testing
@testable import MonoRss

private actor RecordingFreshRSSTransport: FreshRSSHTTPTransport {
    private(set) var requests: [URLRequest] = []
    var responseData: Data
    var statusCode: Int = 200

    init(responseData: Data, statusCode: Int = 200) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let code = request.httpMethod == "GET" && request.url?.path.hasSuffix("/accounts/ClientLogin") == true && statusCode == 401
            ? 200 : statusCode
        let payload = code == 200 && request.url?.path.hasSuffix("/accounts/ClientLogin") == true && statusCode == 401
            ? Data("Auth=server-token\nEmail=reader\n".utf8) : responseData
        let response = HTTPURLResponse(
            url: request.url!, statusCode: code, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        if request.url?.path.hasSuffix("/reader/api/0/token") == true {
            return (Data("action-token\n".utf8), response)
        }
        return (payload, response)
    }

    func lastRequest() -> URLRequest? { requests.last }
    func requestCount() -> Int { requests.count }
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

    @Test func clientLoginFallsBackToGETWhenPOSTIsUnauthorized() async throws {
        let transport = RecordingFreshRSSTransport(responseData: Data("Unauthorized!".utf8), statusCode: 401)
        let configuration = try FreshRSSConfiguration(baseURL: URL(string: "http://100.65.245.62:8081")!, username: "felix")
        let client = FreshRSSClient(configuration: configuration, transport: transport)
        let result = try await client.login(credentials: try FreshRSSCredentials(username: "felix", password: "12345"))
        #expect(result.authToken == "server-token")
        #expect(await transport.requestCount() == 2)
        let request = await transport.lastRequest()
        #expect(request?.httpMethod == "GET")
        let query = URLComponents(url: try #require(request?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first(where: { $0.name == "Email" })?.value == "felix")
        #expect(query?.first(where: { $0.name == "Passwd" })?.value == "12345")
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

    @Test func tinyRSSItemDecodesConsumeMinutesContentTypeAndReadLater() throws {
        let payload = #"{"id":"tag:google.com,2005:reader/item/000000000000000a","title":"Talk","published":1700000000,"author":"Host","contentType":"youtube","consumeMinutes":18,"durationSeconds":1080,"summary":{"content":"<p>Talk</p>"},"categories":["user/-/state/com.google/reading-list","user/-/label/Read Later"],"origin":{"streamId":"feed/3"},"canonical":[{"href":"https://youtube.com/watch?v=abcdefghijk"}]}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(FreshRSSItem.self, from: payload)
        #expect(item.isReadLater)
        #expect(item.snapshot.isStarred)
        #expect(item.snapshot.contentKind == "youtube")
        #expect(item.snapshot.consumeMinutes == 18)
        #expect(item.snapshot.durationSeconds == 1080)
        #expect(item.publishedAt == Date(timeIntervalSince1970: 1_700_000_000))
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

    @Test func streamContentsUsesGoogleReaderPathNotItemsContentsPOST() async throws {
        let transport = RecordingFreshRSSTransport(responseData: Data(#"{"items":[]}"#.utf8))
        let configuration = try FreshRSSConfiguration(baseURL: URL(string: "http://100.65.245.62:8081")!, username: "felix")
        let client = FreshRSSClient(configuration: configuration, transport: transport)
        _ = try await client.streamContents(streamID: "feed/1", authToken: "token", unreadOnly: false, limit: 20)
        let request = await transport.lastRequest()
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.path == "/api/greader.php/reader/api/0/stream/contents/feed/1")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "GoogleLogin auth=token")
    }

    @Test func streamContentsSendsContinuationAndLimit() async throws {
        let transport = RecordingFreshRSSTransport(responseData: Data(#"{"items":[]}"#.utf8))
        let configuration = try FreshRSSConfiguration(baseURL: URL(string: "http://rss.local")!, username: "felix")
        let client = FreshRSSClient(configuration: configuration, transport: transport)
        _ = try await client.streamContents(streamID: "feed/1", authToken: "token", unreadOnly: false, limit: 50, continuation: "12")
        let query = URLComponents(url: try #require(await transport.lastRequest()?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first(where: { $0.name == "n" })?.value == "50")
        #expect(query?.first(where: { $0.name == "c" })?.value == "12")
    }

    @Test func itemContentsSendsActionToken() async throws {
        let transport = RecordingFreshRSSTransport(responseData: Data(#"{"items":[]}"#.utf8))
        let configuration = try FreshRSSConfiguration(baseURL: URL(string: "https://rss.example.test")!, username: "reader")
        let client = FreshRSSClient(configuration: configuration, transport: transport)
        _ = try await client.itemContents(itemIDs: ["tag:example:item-1"], authToken: "token")
        let request = await transport.lastRequest()
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/api/greader.php/reader/api/0/stream/items/contents")
        let body = String(data: request?.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("T=action-token"))
        #expect(body.contains("i=tag%3Aexample%3Aitem-1"))
    }

    @Test func quickAddAndUnsubscribeSendActionToken() async throws {
        let transport = RecordingFreshRSSTransport(responseData: Data(#"{"numResults":1,"query":"https://example.test/rss","streamId":"feed/4","streamName":"Example"}"#.utf8))
        let configuration = try FreshRSSConfiguration(baseURL: URL(string: "http://rss.local")!, username: "felix")
        let client = FreshRSSClient(configuration: configuration, transport: transport)
        let added = try await client.quickAdd(url: "https://example.test/rss", authToken: "token")
        #expect(added.streamID == "feed/4")
        var body = String(data: await transport.lastRequest()?.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("T=action-token"))
        #expect(body.contains("quickadd=https%3A%2F%2Fexample.test%2Frss"))

        try await client.unsubscribe(streamID: "feed/4", authToken: "token")
        body = String(data: await transport.lastRequest()?.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("ac=unsubscribe"))
        #expect(body.contains("s=feed%2F4"))
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
