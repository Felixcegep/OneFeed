import Observation
import SwiftData
import SwiftUI

struct LibrarianMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case user(String)
        case assistant(String)
        case actions([String])
        case pendingRemoval(String)
        case error(String)
    }

    let id: UUID
    var kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

@MainActor
@Observable
final class ExperimentalLibrarianViewModel {
    static let suggestions = [
        "Add kottke.org to Must read",
        "What sources are in Today?",
        "Make a folder called Newsletters",
        "Move a noisy source out of Today",
        "Also put a source in another folder",
        "Review what I'm not interested in"
    ]

    var draft = ""
    private(set) var messages: [LibrarianMessage] = []
    private(set) var isWorking = false
    private(set) var hasAPIKey = false
    private(set) var pendingRemoval: GeminiPendingRemoval?

    private var context: ModelContext?
    private var apiContents: [[String: Any]] = []
    private var openResponses: [[String: Any]] = []
    private var remainingCalls: [GeminiFunctionCall] = []

    private let gemini: any GeminiConversing
    private let librarian: GeminiLibrarian
    private let requireAPIKey: Bool

    @MainActor
    init(
        gemini: (any GeminiConversing)? = nil,
        librarian: GeminiLibrarian? = nil,
        requireAPIKey: Bool = true
    ) {
        self.gemini = gemini ?? GeminiClient()
        self.librarian = librarian ?? GeminiLibrarian(
            feedService: FeedService(),
            freshRSSService: FreshRSSSyncService()
        )
        self.requireAPIKey = requireAPIKey
        hasAPIKey = !requireAPIKey || GeminiAPIKeyStore.load() != nil
    }

    func configure(with context: ModelContext) {
        self.context = context
        refreshKey()
    }

    func refreshKey() {
        hasAPIKey = !requireAPIKey || GeminiAPIKeyStore.load() != nil
    }

    var canSend: Bool {
        !isWorking
            && pendingRemoval == nil
            && hasAPIKey
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clear() {
        messages = []
        apiContents = []
        openResponses = []
        remainingCalls = []
        pendingRemoval = nil
        isWorking = false
    }

    func sendSuggestion(_ text: String) async {
        draft = text
        await send()
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty else { return }
        draft = ""
        messages.append(LibrarianMessage(kind: .user(text)))
        apiContents.append(["role": "user", "parts": [["text": text]]])
        await stepConversation()
    }

    func confirmRemoval() async {
        guard let pending = pendingRemoval, let context, !isWorking else { return }
        pendingRemoval = nil
        isWorking = true
        let result = await librarian.perform(pending.call, in: context, allowRemoval: true)
        replacePending(with: .actions([result.message]))
        openResponses.append(Self.functionResponse(name: pending.call.name, result: result))
        let leftover = remainingCalls
        remainingCalls = []
        let shouldContinue = await drain(leftover)
        isWorking = false
        if shouldContinue {
            await stepConversation()
        }
    }

    func declineRemoval() async {
        guard let pending = pendingRemoval, !isWorking else { return }
        pendingRemoval = nil
        isWorking = true
        let result = GeminiToolResult(ok: false, message: "The reader kept \(pending.title).")
        replacePending(with: .actions(["Kept \(pending.title)."]))
        openResponses.append(Self.functionResponse(name: pending.call.name, result: result))
        let leftover = remainingCalls
        remainingCalls = []
        let shouldContinue = await drain(leftover)
        isWorking = false
        if shouldContinue {
            await stepConversation()
        }
    }

    private func stepConversation() async {
        guard let context else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            for _ in 0..<8 {
                let contentsJSON = try JSONSerialization.data(withJSONObject: apiContents)
                let result = try await gemini.generateLibrarian(
                    contentsJSON: contentsJSON,
                    systemInstruction: librarian.systemInstruction(in: context)
                )
                apiContents.append(result.modelContent)
                if result.functionCalls.isEmpty {
                    let reply = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !reply.isEmpty {
                        messages.append(LibrarianMessage(kind: .assistant(reply)))
                    }
                    return
                }
                if await drain(result.functionCalls) == false {
                    return
                }
            }
            messages.append(LibrarianMessage(kind: .error("Gemini kept making changes. Stopped after eight steps.")))
        } catch {
            messages.append(LibrarianMessage(kind: .error(UserFacingFailure.message(for: error, fallback: "That request did not finish."))))
        }
    }

    /// Returns true when every tool response for this model turn is ready to send.
    private func drain(_ calls: [GeminiFunctionCall]) async -> Bool {
        guard let context else { return true }
        var logs: [String] = []
        var queue = calls
        while let call = queue.first {
            queue.removeFirst()
            let result = await librarian.perform(call, in: context, allowRemoval: false)
            if result.needsConfirmation, let pending = result.pendingRemoval {
                if !logs.isEmpty {
                    messages.append(LibrarianMessage(kind: .actions(logs)))
                }
                pendingRemoval = pending
                remainingCalls = queue
                messages.append(LibrarianMessage(kind: .pendingRemoval(pending.title)))
                return false
            }
            openResponses.append(Self.functionResponse(name: call.name, result: result))
            if call.name != "list_library"
                && call.name != "list_not_interested"
                && call.name != "search_sources" {
                logs.append(result.message)
            }
        }
        if !logs.isEmpty {
            messages.append(LibrarianMessage(kind: .actions(logs)))
        }
        apiContents.append(["role": "user", "parts": openResponses])
        openResponses = []
        remainingCalls = []
        return true
    }

    private func replacePending(with kind: LibrarianMessage.Kind) {
        if let index = messages.lastIndex(where: {
            if case .pendingRemoval = $0.kind { return true }
            return false
        }) {
            messages[index].kind = kind
        } else {
            messages.append(LibrarianMessage(kind: kind))
        }
    }

    private static func functionResponse(name: String, result: GeminiToolResult) -> [String: Any] {
        [
            "functionResponse": [
                "name": name,
                "response": result.responseObject
            ]
        ]
    }
}

struct ExperimentalLibrarianView: View {
    var initialPrompt: String? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ExperimentalLibrarianViewModel()
    @State private var geminiKey = ""
    @State private var showingKeySheet = false
    @State private var didSendInitial = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    warning
                    if !viewModel.hasAPIKey {
                        missingKey
                    } else if viewModel.messages.isEmpty {
                        emptyConversation
                    } else {
                        ForEach(viewModel.messages) { message in
                            transcript(message)
                                .id(message.id)
                        }
                        if viewModel.isWorking {
                            workingRow
                                .id("working")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) {
                scroll(using: proxy)
            }
            .onChange(of: viewModel.isWorking) {
                scroll(using: proxy)
            }
        }
        .background(OneFeedTheme.plaster)
        .oneFeedMacReadingColumn()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.hasAPIKey {
                composer
            }
        }
        .oneFeedTabBarClearance()
        .navigationTitle("Librarian")
        .oneFeedInlineTitle()
        .toolbar {
            if !viewModel.messages.isEmpty && !viewModel.isWorking {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { viewModel.clear() }
                }
            }
        }
        .task {
            viewModel.configure(with: modelContext)
            geminiKey = GeminiAPIKeyStore.load() ?? ""
            if let initialPrompt, !didSendInitial, viewModel.hasAPIKey {
                didSendInitial = true
                await viewModel.sendSuggestion(initialPrompt)
            }
        }
        .sheet(isPresented: $showingKeySheet) {
            GeminiAPIKeyForm(key: $geminiKey) {
                GeminiAPIKeyStore.save(geminiKey)
                showingKeySheet = false
                viewModel.refreshKey()
            }
        }
    }

    private var warning: some View {
        Text("Gemini can add, put a source in another folder, move, archive, pause, or remove sources. This page is experimental — check Sources after it acts.")
            .font(.footnote)
            .foregroundStyle(OneFeedTheme.graphite)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
    }

    private var missingKey: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Gemini is not configured")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(OneFeedTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Add a Google AI Studio key. It is the same key used for video summaries, and it stays in the Keychain on this device.")
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add API key") { showingKeySheet = true }
                .buttonStyle(PrimaryActionStyle(expands: false))
        }
        .padding(16)
        .librarianPaper()
    }

    private var emptyConversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ask Gemini to tend the library")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(OneFeedTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Add a site, make a folder, park something in Archive, or review what you marked not interested.")
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                ForEach(ExperimentalLibrarianViewModel.suggestions, id: \.self) { suggestion in
                    Button {
                        Task { await viewModel.sendSuggestion(suggestion) }
                    } label: {
                        Text(suggestion)
                            .font(.body)
                            .foregroundStyle(OneFeedTheme.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .buttonStyle(DecisionActionStyle())
                    .disabled(viewModel.isWorking)
                }
            }
        }
    }

    @ViewBuilder
    private func transcript(_ message: LibrarianMessage) -> some View {
        switch message.kind {
        case .user(let text):
            labeledCard(label: "You", text: text, serif: false)
        case .assistant(let text):
            labeledCard(label: "Gemini", text: text, serif: true)
        case .actions(let lines):
            VStack(alignment: .leading, spacing: 8) {
                GalleryLabel(text: "Changed")
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.body)
                        .foregroundStyle(OneFeedTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .librarianPaper()
        case .pendingRemoval(let title):
            VStack(alignment: .leading, spacing: 12) {
                GalleryLabel(text: "Remove source")
                Text("Remove \(title) and its locally stored articles?")
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Keep") {
                        Task { await viewModel.declineRemoval() }
                    }
                    .buttonStyle(DecisionActionStyle(expands: false))
                    Button("Remove", role: .destructive) {
                        Task { await viewModel.confirmRemoval() }
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(OneFeedTheme.error)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 14)
                }
            }
            .padding(16)
            .librarianPaper()
            .accessibilityElement(children: .contain)
        case .error(let text):
            VStack(alignment: .leading, spacing: 8) {
                GalleryLabel(text: "Couldn’t finish")
                Text(text)
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .librarianPaper()
        }
    }

    private func labeledCard(label: String, text: String, serif: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GalleryLabel(text: label)
            Text(text)
                .font(serif ? OneFeedTheme.serifBody() : .body)
                .foregroundStyle(OneFeedTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .librarianPaper()
    }

    private var workingRow: some View {
        HStack(spacing: 12) {
            OneFeedMarkPulse(isActive: true, size: 22)
            Text("Working…")
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
        }
        .padding(16)
        .librarianPaper()
        .accessibilityLabel("Working")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(OneFeedTheme.sand)
                .frame(height: 1)
            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    viewModel.pendingRemoval == nil
                        ? "Add a source, make a folder…"
                        : "Confirm or keep the source first",
                    text: $viewModel.draft,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .disabled(viewModel.pendingRemoval != nil || viewModel.isWorking)
                .oneFeedSubmitGo()
                .onSubmit { Task { await viewModel.send() } }
                .accessibilityIdentifier("experimental-composer")
                Button("Send") {
                    Task { await viewModel.send() }
                }
                .buttonStyle(InkCapsuleStyle())
                .opacity(viewModel.canSend ? 1 : 0.4)
                .disabled(!viewModel.canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OneFeedTheme.paper)
        }
    }

    private func scroll(using proxy: ScrollViewProxy) {
        if viewModel.isWorking {
            proxy.scrollTo("working", anchor: .bottom)
        } else if let id = viewModel.messages.last?.id {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

private extension View {
    func librarianPaper() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(
                OneFeedTheme.paper,
                in: RoundedRectangle(cornerRadius: OneFeedTheme.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OneFeedTheme.cardRadius, style: .continuous)
                    .strokeBorder(OneFeedTheme.sand, lineWidth: 1)
            }
    }
}
