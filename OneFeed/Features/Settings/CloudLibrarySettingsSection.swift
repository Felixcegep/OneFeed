import SwiftUI

/// Folder pickers plus a first-class Google Drive link. Settings owns OAuth
/// and find-or-create; the library service only remembers the file.
struct CloudLibrarySettingsSection: View {
    var library: LibrarySyncService
    let isBusy: Bool
    let onChooseFolder: () -> Void
    let onChooseFile: () -> Void
    let onLinkGoogleDrive: () -> Void
    let onSyncNow: () -> Void
    let onUnlink: () -> Void
    let onKeepThisDevice: () -> Void
    let onUseCloudFile: () -> Void
    let onSyncModeChange: (CloudFileSyncMode) -> Void

    @State private var isConfirmingUnlink = false
    @State private var isShowingConflict = false

    var body: some View {
        Group {
            if let record = library.linkedRecord, record.usesGoogleDriveAPI {
                driveLinked(record)
            } else if library.isLinked {
                folderLinked
            } else {
                unlinked
            }
        }
        .confirmationDialog(
            "Stop using this folder?",
            isPresented: $isConfirmingUnlink,
            titleVisibility: .visible
        ) {
            Button("Stop Using Folder", role: .destructive, action: onUnlink)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(unlinkMessage)
        }
        .confirmationDialog(
            "This device and the cloud file both changed.",
            isPresented: $isShowingConflict,
            titleVisibility: .visible
        ) {
            Button("Keep this device", action: onKeepThisDevice)
            Button("Use cloud file", role: .destructive, action: onUseCloudFile)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Using the cloud file replaces the library on this device.")
        }
        .onChange(of: library.lastOutcome) { _, outcome in
            isShowingConflict = outcome == .conflict
        }
        .onAppear {
            isShowingConflict = library.lastOutcome == .conflict
        }
    }

    @ViewBuilder
    private func driveLinked(_ record: CloudFileLinkRecord) -> some View {
        LabeledContent("Location", value: record.locationKind.title)
        LabeledContent("File", value: record.displayName)
        if let email = record.googleDriveAccountEmail, email.isEmpty == false {
            LabeledContent("Account", value: email)
        }
        LabeledContent("Status", value: statusText)
        Picker("Sync", selection: Binding(
            get: { record.syncMode },
            set: onSyncModeChange
        )) {
            ForEach(CloudFileSyncMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .disabled(actionsDisabled)
        Button {
            onSyncNow()
        } label: {
            syncNowLabel
        }
        .disabled(actionsDisabled)
        Button("Stop Using Folder", systemImage: "xmark.circle", role: .destructive) {
            isConfirmingUnlink = true
        }
        .disabled(actionsDisabled)
    }

    @ViewBuilder
    private var folderLinked: some View {
        LabeledContent("Location", value: library.folderDisplayName ?? "Folder")
        if let lastSyncAt = library.lastSyncAt {
            LabeledContent("Last Sync", value: lastSyncAt.formatted(date: .abbreviated, time: .shortened))
        }
        if case .error(let message) = library.status {
            Text(message).font(.footnote).foregroundStyle(OneFeedTheme.error)
        }
        Button {
            onSyncNow()
        } label: {
            syncNowLabel
        }
        .disabled(actionsDisabled || library.status == .waitingForDownload)
        Button("Change Folder", systemImage: "folder") { onChooseFolder() }
            .disabled(actionsDisabled)
        Button("Choose Library File", systemImage: "doc") { onChooseFile() }
            .disabled(actionsDisabled)
        Button("Stop Using Folder", systemImage: "xmark.circle", role: .destructive) {
            isConfirmingUnlink = true
        }
        .disabled(actionsDisabled)
    }

    @ViewBuilder
    private var unlinked: some View {
        Button("Choose Folder", systemImage: "folder") { onChooseFolder() }
            .disabled(actionsDisabled)
        Button("Choose Library File", systemImage: "doc") { onChooseFile() }
            .disabled(actionsDisabled)
        Button("Google Drive", systemImage: "cloud") { onLinkGoogleDrive() }
            .disabled(actionsDisabled)
    }

    @ViewBuilder
    private var syncNowLabel: some View {
        if library.isSyncing || library.status == .syncing {
            Label {
                Text("Syncing…")
            } icon: {
                OneFeedMarkPulse(isActive: true, size: 18)
            }
        } else {
            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private var actionsDisabled: Bool {
        isBusy || library.isSyncing || library.status == .syncing
    }

    private var statusText: String {
        if library.isSyncing || library.status == .syncing {
            return "Syncing…"
        }
        if let message = library.lastErrorMessage, message.isEmpty == false {
            return message
        }
        switch library.lastOutcome {
        case .unlinked:
            return "Not linked"
        case .inSync:
            return syncedTimestampText
        case .pushed:
            return "Updated the cloud file"
        case .pulled:
            return "Updated this device"
        case .conflict:
            return "Both changed"
        case .skippedActiveSession:
            return "Waiting — reading in progress"
        case .failed(let message):
            return message
        }
    }

    private var unlinkMessage: String {
        if library.linkedRecord?.usesGoogleDriveAPI == true {
            return "Subscriptions stay on this device. Other devices stop receiving updates from this file. The Google Drive file is not deleted."
        }
        return "Subscriptions stay on this device. Other devices stop receiving updates from this file."
    }

    private var syncedTimestampText: String {
        guard let date = library.linkedRecord?.lastSyncedAt ?? library.lastSyncAt else {
            return "Linked"
        }
        return date.formatted(.relative(presentation: .named))
    }
}
