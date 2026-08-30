import SwiftData
import SwiftUI

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SourcesViewModel()

    var body: some View {
        Group {
            if viewModel.feeds.isEmpty {
                ContentUnavailableView {
                    Label("No sources", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Follow websites and feeds you actually want to read.")
                } actions: {
                    Button("Add Source") { viewModel.isPresentingAddSource = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.primary)
                }
            } else {
                List {
                    ForEach(viewModel.feeds) { feed in
                        NavigationLink(value: feed.id) { SourceRow(feed: feed) }
                    }
                    .onDelete(perform: viewModel.delete)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.configure(with: modelContext) }
        .toolbar {
            Button("Add Source", systemImage: "plus") { viewModel.isPresentingAddSource = true }
        }
        .navigationDestination(for: UUID.self) { id in
            if let feed = viewModel.feeds.first(where: { $0.id == id }) {
                SourceDetailView(feed: feed, context: modelContext)
            }
        }
        .sheet(isPresented: $viewModel.isPresentingAddSource, onDismiss: viewModel.reload) { AddSourceView() }
    }
}

private struct SourceRow: View {
    let feed: Feed

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(feed.title)
                .font(.headline)
            HStack(spacing: 5) {
                Text(feed.websiteURL?.host() ?? feed.feedURL.host() ?? feed.feedURL.absoluteString)
                    .lineLimit(1)
                if !feed.isEnabled {
                    Text("·")
                    Text("Paused")
                } else if feed.remoteID != nil {
                    Text("·")
                    Text("FreshRSS")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint(feed.isEnabled ? "Opens source details" : "Paused. Opens source details")
    }
}

private struct SourceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SourceDetailViewModel

    init(feed: Feed, context: ModelContext) {
        _viewModel = State(initialValue: SourceDetailViewModel(feed: feed, context: context))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Website", value: viewModel.feed.websiteURL?.host() ?? "—")
                LabeledContent("Feed", value: viewModel.feed.feedURL.absoluteString)
            }
            Section {
                Toggle("Included in Next", isOn: $viewModel.isEnabled)
            } footer: {
                Text("When this is off, the source stays in your library but does not enter the current-article queue.")
            }
            Section {
                Button("Remove Source", role: .destructive) { viewModel.isConfirmingRemoval = true }
            }
        }
        .navigationTitle(viewModel.feed.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove this source and its locally stored articles?", isPresented: $viewModel.isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove Source", role: .destructive) {
                dismiss()
                Task { @MainActor in viewModel.remove() }
            }
        }
    }
}

private struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = AddSourceViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Website or RSS URL") {
                    TextField("example.com", text: $viewModel.address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { add() }
                }
                if let errorMessage = viewModel.presentedError {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isAdding ? "Adding…" : "Add") { add() }
                        .disabled(viewModel.address.isEmpty || viewModel.isAdding)
                }
            }
        }
    }

    private func add() { Task { if await viewModel.add(in: modelContext) { dismiss() } } }
}
