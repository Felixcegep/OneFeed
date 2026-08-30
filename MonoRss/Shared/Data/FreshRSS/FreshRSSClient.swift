import Foundation

nonisolated public protocol FreshRSSHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: FreshRSSHTTPTransport {}

nonisolated public protocol FreshRSSAPI: Sendable {
    func login(credentials: FreshRSSCredentials) async throws -> FreshRSSAuthResponse
    func subscriptions(authToken: String) async throws -> FreshRSSSubscriptionResponse
    func itemIDs(streamID: String, authToken: String, unreadOnly: Bool, limit: Int, continuation: String?) async throws -> FreshRSSStreamItemIDsResponse
    func itemContents(itemIDs: [String], authToken: String) async throws -> FreshRSSStreamContentsResponse
    func markRead(itemID: String, authToken: String) async throws
    func markUnread(itemID: String, authToken: String) async throws
    func setStarred(itemID: String, authToken: String, starred: Bool) async throws
}

public actor FreshRSSClient: FreshRSSAPI {
    public let configuration: FreshRSSConfiguration
    private let transport: any FreshRSSHTTPTransport
    private let decoder: JSONDecoder
    private var actionTokens: [String: String] = [:]

    public init(configuration: FreshRSSConfiguration,
                transport: any FreshRSSHTTPTransport = URLSession.shared) {
        self.configuration = configuration
        self.transport = transport
        self.decoder = JSONDecoder()
    }

    public func login(credentials: FreshRSSCredentials) async throws -> FreshRSSAuthResponse {
        var request = URLRequest(url: configuration.endpoint("api/greader.php/accounts/ClientLogin"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([("Email", credentials.username), ("Passwd", credentials.password)])

        let (data, _) = try await send(request)
        guard let body = String(data: data, encoding: .utf8) else { throw FreshRSSError.invalidResponse }
        let values = body.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).reduce(into: [String: String]()) { result, line in
            let pieces = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pieces.count == 2 { result[pieces[0]] = pieces[1] }
        }
        guard let token = values["Auth"], !token.isEmpty else { throw FreshRSSError.missingAuthToken }
        return FreshRSSAuthResponse(authToken: token, userName: values["Email"])
    }

    public func subscriptions(authToken: String) async throws -> FreshRSSSubscriptionResponse {
        let request = authorizedGET(path: "api/greader.php/reader/api/0/subscription/list", token: authToken,
                                    query: [("output", "json")])
        return try await decode(FreshRSSSubscriptionResponse.self, request: request)
    }

    public func itemIDs(streamID: String, authToken: String, unreadOnly: Bool = true,
                        limit: Int = 1_000, continuation: String? = nil) async throws -> FreshRSSStreamItemIDsResponse {
        var query: [(String, String)] = [
            ("output", "json"),
            ("s", streamID),
            ("n", String(max(1, min(limit, 1_000))))
        ]
        if unreadOnly { query.append(("xt", FreshRSSLabel.read)) }
        if let continuation, !continuation.isEmpty { query.append(("c", continuation)) }
        let request = authorizedGET(path: "api/greader.php/reader/api/0/stream/items/ids", token: authToken, query: query)
        return try await decode(FreshRSSStreamItemIDsResponse.self, request: request)
    }

    public func itemContents(itemIDs: [String], authToken: String) async throws -> FreshRSSStreamContentsResponse {
        guard !itemIDs.isEmpty else { return FreshRSSStreamContentsResponse(items: []) }
        var request = authorizedGET(path: "api/greader.php/reader/api/0/stream/items/contents", token: authToken,
                                    query: [("output", "json")])
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(itemIDs.map { ("i", $0) })
        return try await decode(FreshRSSStreamContentsResponse.self, request: request)
    }

    public func markRead(itemID: String, authToken: String) async throws {
        try await editTag(itemID: itemID, token: authToken, add: FreshRSSLabel.read)
    }

    public func markUnread(itemID: String, authToken: String) async throws {
        try await editTag(itemID: itemID, token: authToken, remove: FreshRSSLabel.read)
    }

    public func setStarred(itemID: String, authToken: String, starred: Bool) async throws {
        if starred {
            try await editTag(itemID: itemID, token: authToken, add: FreshRSSLabel.starred)
        } else {
            try await editTag(itemID: itemID, token: authToken, remove: FreshRSSLabel.starred)
        }
    }

    /// FreshRSS requires a short action token (`T`) for mutating endpoints.
    /// It is separate from the `GoogleLogin` authorization token and must not
    /// be sent in a URL.
    public func actionToken(authToken: String) async throws -> String {
        if let cached = actionTokens[authToken] { return cached }
        let request = authorizedGET(path: "api/greader.php/reader/api/0/token", token: authToken, query: [])
        let (data, _) = try await send(request)
        guard let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw FreshRSSError.invalidResponse
        }
        actionTokens[authToken] = value
        return value
    }

    private func editTag(itemID: String, token: String, add: String? = nil, remove: String? = nil) async throws {
        guard add != nil || remove != nil else { throw FreshRSSError.unsupportedMutation }
        let mutationToken = try await actionToken(authToken: token)
        var request = authorizedPOST(path: "api/greader.php/reader/api/0/edit-tag", token: token)
        var fields: [(String, String)] = [("T", mutationToken), ("i", itemID)]
        if let add { fields.append(("a", add)) }
        if let remove { fields.append(("r", remove)) }
        request.httpBody = formEncoded(fields)
        _ = try await send(request)
    }

    private func authorizedGET(path: String, token: String, query: [(String, String)]) -> URLRequest {
        var components = URLComponents(url: configuration.endpoint(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("GoogleLogin auth=\(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func authorizedPOST(path: String, token: String) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint(path))
        request.httpMethod = "POST"
        request.setValue("GoogleLogin auth=\(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let (data, _) = try await send(request)
        do { return try decoder.decode(type, from: data) }
        catch { throw FreshRSSError.decodingFailed }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let result = try await transport.data(for: request)
            guard let http = result.1 as? HTTPURLResponse else { throw FreshRSSError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw FreshRSSError.httpStatus(http.statusCode, nil)
            }
            return result
        } catch let error as FreshRSSError {
            throw error
        } catch {
            throw error
        }
    }

    private func formEncoded(_ fields: [(String, String)]) -> Data {
        let value = fields.map { "\($0.0.percentEncodedForm)=\($0.1.percentEncodedForm)" }.joined(separator: "&")
        return Data(value.utf8)
    }
}

nonisolated private extension String {
    var percentEncodedForm: String {
        // application/x-www-form-urlencoded leaves only unreserved form
        // characters unescaped; notably, `/` must be encoded in stream IDs
        // and FreshRSS labels.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
