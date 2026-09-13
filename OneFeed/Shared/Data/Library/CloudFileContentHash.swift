import CryptoKit
import Foundation

nonisolated enum CloudFileContentHash {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
