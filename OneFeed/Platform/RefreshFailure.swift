import Foundation

enum RefreshFailure {
    /// User-facing copy for a failed refresh, or `nil` when the work was simply cancelled or a slow source timed out.
    nonisolated static func message(for error: Error) -> String? {
        if error.isCancellation || error.isTransientNetwork { return nil }
        return error.localizedDescription
    }
}

enum UserFacingFailure {
    /// Uses an error's own sentence when the app wrote one. Otherwise the fallback, never a raw system dump.
    nonisolated static func message(for error: Error, fallback: String) -> String {
        if error.isCancellation || error.isTransientNetwork {
            return fallback
        }
        if !(error is NSError),
           let described = error as? LocalizedError,
           let text = described.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return fallback
    }
}

enum ReaderFailure {
    /// Calm copy for Gemini and network failures. Raw API text stays out of the reader.
    nonisolated static func message(for error: Error) -> String {
        if let gemini = error as? GeminiClientError {
            return gemini.errorDescription ?? "Gemini could not finish that."
        }
        if error.isTransientNetwork {
            return "The connection dropped. Try again."
        }
        return "That did not finish. Try again."
    }
}

extension Error {
    nonisolated var isCancellation: Bool {
        if self is CancellationError { return true }
        if (self as? URLError)?.code == .cancelled { return true }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    nonisolated var isTransientNetwork: Bool {
        let code = (self as? URLError)?.code
            ?? URLError.Code(rawValue: (self as NSError).code)
        switch code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            let nsError = self as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
        }
    }
}
