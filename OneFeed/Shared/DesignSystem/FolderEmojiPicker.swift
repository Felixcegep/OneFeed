import SwiftUI

struct FolderIconTarget: Identifiable {
    let name: String
    var id: String { name }
}

struct FolderEmojiPicker: View {
    let folderName: String
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String

    init(folderName: String, onSelect: @escaping (String) -> Void) {
        self.folderName = folderName
        self.onSelect = onSelect
        _selected = State(initialValue: FolderEmoji.glyph(for: folderName))
    }

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(spacing: 8) {
                        Text(selected)
                            .font(.system(size: 64))
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        Text(folderName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(OneFeedTheme.graphite)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    ForEach(FolderEmojiPalette.categories) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OneFeedTheme.graphite)
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(category.glyphs, id: \.self) { glyph in
                                    Button {
                                        selected = glyph
                                        FolderEmoji.set(glyph, for: folderName)
                                        onSelect(glyph)
                                        dismiss()
                                    } label: {
                                        Text(glyph)
                                            .font(.system(size: 28))
                                            .frame(maxWidth: .infinity)
                                            .frame(minHeight: 44)
                                            .background(
                                                selected == glyph ? OneFeedTheme.warm1 : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            )
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(glyph) for \(folderName)")
                                    .accessibilityAddTraits(selected == glyph ? .isSelected : [])
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, OneFeedTheme.pagePadding)
                .padding(.bottom, 32)
            }
            .background(OneFeedTheme.plaster)
            .navigationTitle("Folder icon")
            .oneFeedInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .oneFeedMacSheetCanvas()
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

struct FolderEmojiButton: View {
    let name: String
    var onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            Text(FolderEmoji.glyph(for: name))
                .font(.system(size: 28))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Change icon for \(name), currently \(FolderEmoji.glyph(for: name))")
        .accessibilityHint("Opens the emoji picker")
    }
}
