import Foundation

enum RefreshFailure {
    /// User-facing copy, or `nil` when the work was cancelled or the connection dropped.
    /// App errors keep their sentence. Anything else uses `fallback`.
    nonisolated static func message(for error: Error, fallback: String = "Couldn’t refresh.") -> String? {
        guard UserFacingFailure.shouldSurface(error) else { return nil }
        return UserFacingFailure.message(for: error, fallback: fallback)
    }
}

enum UserFacingFailure {
    /// Uses an error's own sentence when the app wrote one. Otherwise the fallback, never a raw system dump.
    nonisolated static func shouldSurface(_ error: Error) -> Bool {
        !error.isCancellation && !error.isTransientNetwork
    }

    nonisolated static func message(for error: Error, fallback: String) -> String {
        if !shouldSurface(error) {
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

enum ImportBatchResult {
    /// One failure keeps its sentence. A mixed batch says how many landed and how many did not.
    nonisolated static func message(succeeded: Int, failed: Int, firstFailure: String?, emptyFallback: String) -> String? {
        guard failed > 0 else { return nil }
        if succeeded == 0 { return firstFailure ?? emptyFallback }
        return "Imported \(succeeded). \(failed) could not be imported."
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
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            let nsError = self as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
        }
    }
}
