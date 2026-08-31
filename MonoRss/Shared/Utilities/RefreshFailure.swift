import Foundation

enum RefreshFailure {
    /// User-facing copy for a failed refresh, or `nil` when the work was simply cancelled or a slow source timed out.
    nonisolated static func message(for error: Error) -> String? {
        if error.isCancellation || error.isTransientNetwork { return nil }
        return error.localizedDescription
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
