import Foundation

nonisolated struct GoogleDriveFile: Equatable, Sendable, Decodable {
    var id: String
    var name: String
    var md5Checksum: String?
}

nonisolated enum GoogleDriveAPIError: Error, Equatable, LocalizedError, Sendable {
    case unauthorized
    case httpFailure(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            String(localized: "Link Google Drive again to continue.")
        case .httpFailure(_, let message):
            String(localized: "Google Drive could not complete the request. \(message)")
        }
    }
}

protocol GoogleDriveAPIClienting: Sendable {
    func findBackupFile() async throws -> GoogleDriveFile?
    func createBackupFile(data: Data, name: String) async throws -> GoogleDriveFile
    func downloadFile(id: String) async throws -> Data
    func uploadFile(id: String, data: Data) async throws
    func accountEmail() async throws -> String?
}

@MainActor
final class GoogleDriveAPIClient: GoogleDriveAPIClienting {
    static let shared = GoogleDriveAPIClient(oauth: .shared)

    private let oauth: GoogleDriveOAuthClient
    private let session: URLSession

    init(oauth: GoogleDriveOAuthClient, session: URLSession = .shared) {
        self.oauth = oauth
        self.session = session
    }

    func findBackupFile() async throws -> GoogleDriveFile? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")
        components?.queryItems = [
            URLQueryItem(
                name: "q",
                value: "name='\(GoogleDriveOAuthConfig.backupFileName)' and trashed=false"
            ),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name,md5Checksum)"),
            URLQueryItem(name: "pageSize", value: "1")
        ]
        guard let url = components?.url else {
            throw GoogleDriveAPIError.httpFailure(
                status: 0,
                message: String(localized: "The Google Drive request was invalid.")
            )
        }
        let (data, _) = try await authorizedRequest(url: url, method: "GET")
        let decoded: FileListResponse
        do {
            decoded = try JSONDecoder().decode(FileListResponse.self, from: data)
        } catch {
            throw GoogleDriveAPIError.httpFailure(
                status: 200,
                message: String(localized: "The Google Drive response was invalid.")
            )
        }
        return decoded.files?.first
    }

    func createBackupFile(data: Data, name: String) async throws -> GoogleDriveFile {
        var components = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files")
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: "id,name,md5Checksum")
        ]
        guard let url = components?.url else {
            throw GoogleDriveAPIError.httpFailure(
                status: 0,
                message: String(localized: "The Google Drive request was invalid.")
            )
        }

        let metadata = CreateMetadata(name: name, mimeType: "application/json")
        let metadataData: Data
        do {
            metadataData = try JSONEncoder().encode(metadata)
        } catch {
            throw GoogleDriveAPIError.httpFailure(
                status: 0,
                message: String(localized: "The Google Drive request was invalid.")
            )
        }

        let boundary = "onefeed_google_drive_\(UUID().uuidString)"
        let body = Self.multipartRelatedBody(
            metadata: metadataData,
            fileData: data,
            boundary: boundary
        )
        let (responseData, _) = try await authorizedRequest(
            url: url,
            method: "POST",
            contentType: "multipart/related; boundary=\(boundary)",
            body: body
        )
        do {
            return try JSONDecoder().decode(GoogleDriveFile.self, from: responseData)
        } catch {
            throw GoogleDriveAPIError.httpFailure(
                status: 200,
                message: String(localized: "The Google Drive response was invalid.")
            )
        }
    }

    func downloadFile(id: String) async throws -> Data {
        var components = URLComponents(
            string: "https://www.googleapis.com/drive/v3/files/\(Self.pathEncoded(id))"
        )
        components?.queryItems = [
            URLQueryItem(name: "alt", value: "media")
        ]
        guard let url = components?.url else {
            throw GoogleDriveAPIError.httpFailure(
                status: 0,
                message: String(localized: "The Google Drive request was invalid.")
            )
        }
        let (data, _) = try await authorizedRequest(url: url, method: "GET")
        return data
    }

    func uploadFile(id: String, data: Data) async throws {
        var components = URLComponents(
            string: "https://www.googleapis.com/upload/drive/v3/files/\(Self.pathEncoded(id))"
        )
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "media")
        ]
        guard let url = components?.url else {
            throw GoogleDriveAPIError.httpFailure(
                status: 0,
                message: String(localized: "The Google Drive request was invalid.")
            )
        }
        _ = try await authorizedRequest(
            url: url,
            method: "PATCH",
            contentType: "application/json",
            body: data
        )
    }

    func accountEmail() async throws -> String? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/about")
        components?.queryItems = [
            URLQueryItem(name: "fields", value: "user(emailAddress)")
        ]
        guard let url = components?.url else {
            throw GoogleDriveAPIError.httpFailure(
                status: 0,
                message: String(localized: "The Google Drive request was invalid.")
            )
        }
        let (data, _) = try await authorizedRequest(url: url, method: "GET")
        let decoded: AboutResponse
        do {
            decoded = try JSONDecoder().decode(AboutResponse.self, from: data)
        } catch {
            throw GoogleDriveAPIError.httpFailure(
                status: 200,
                message: String(localized: "The Google Drive response was invalid.")
            )
        }
        let email = decoded.user?.emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (email?.isEmpty == false) ? email : nil
    }

    private func authorizedRequest(
        url: URL,
        method: String,
        contentType: String? = nil,
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let credentials = try await oauth.refreshIfNeeded()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GoogleDriveAPIError.httpFailure(status: 0, message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GoogleDriveAPIError.httpFailure(
                status: 0,
                message: String(localized: "The Google Drive response was invalid.")
            )
        }
        if http.statusCode == 401 {
            throw GoogleDriveAPIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleDriveAPIError.httpFailure(
                status: http.statusCode,
                message: Self.serverMessage(from: data, status: http.statusCode)
            )
        }
        return (data, http)
    }

    private static func pathEncoded(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }

    private static func multipartRelatedBody(metadata: Data, fileData: Data, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadata)
        append("\r\n--\(boundary)\r\n")
        append("Content-Type: application/json\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func serverMessage(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String,
               message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return message
            }
            if let description = object["error_description"] as? String,
               description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return description
            }
            if let error = object["error"] as? String,
               error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return error
            }
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           text.isEmpty == false {
            return text
        }
        return "HTTP \(status)"
    }

    private struct FileListResponse: Decodable {
        var files: [GoogleDriveFile]?
    }

    private struct CreateMetadata: Encodable {
        var name: String
        var mimeType: String
    }

    private struct AboutResponse: Decodable {
        var user: User?

        struct User: Decodable {
            var emailAddress: String?
        }
    }
}
