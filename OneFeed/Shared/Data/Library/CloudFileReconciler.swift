import Foundation

/// Three-way compare between this device's portable library file, the linked
/// cloud file, and the last snapshot this installation successfully pushed or pulled.
///
/// KeePass-style: one file is the shared copy. Local SwiftData stays the
/// working store. This decision never mutates either side.
nonisolated enum CloudFileReconcileDecision: Equatable, Sendable {
    /// Local bytes match the linked file. Nothing to write.
    case inSync
    /// This device changed; the linked file still matches the last sync.
    case push
    /// The linked file changed; this device still matches the last sync.
    case pull
    /// Both sides changed since the last successful sync, or an existing file
    /// is being linked against different local data.
    case conflict
}

nonisolated enum CloudFileReconciler {
    /// `remoteHash` is `nil` when the linked file is missing. A missing file is a
    /// push, not a conflict: this device still holds the working copy.
    ///
    /// Hashes are SHA-256 of the JSON body. Drive `md5Checksum` is never used.
    static func decide(
        localHash: String,
        remoteHash: String?,
        lastSyncedHash: String?
    ) -> CloudFileReconcileDecision {
        guard let remoteHash, remoteHash.isEmpty == false else {
            return .push
        }
        if localHash == remoteHash {
            return .inSync
        }
        if let lastSyncedHash, lastSyncedHash.isEmpty == false {
            if remoteHash == lastSyncedHash {
                return .push
            }
            if localHash == lastSyncedHash {
                return .pull
            }
        }
        return .conflict
    }
}
