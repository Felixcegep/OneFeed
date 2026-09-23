import SwiftUI

struct ReaderFocusSheet: View {
    @Binding var mode: String
    @Binding var intensity: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                modeRow
                intensityRow
                Text("Focus follows the line in the reading area while you scroll. Tap a sentence to hold your place.")
                    .font(.footnote)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(OneFeedTheme.pagePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(OneFeedTheme.paper)
            .navigationTitle("Focus")
            .oneFeedInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .oneFeedMacFormSheet()
        #if os(iOS)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(340), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(OneFeedTheme.paper)
        #endif
    }

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mode")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneFeedTheme.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                ForEach(ReaderFocusMode.allCases) { option in
                    modeChip(option)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus mode")
    }

    private func modeChip(_ option: ReaderFocusMode) -> some View {
        let selected = mode == option.rawValue
        return Button {
            mode = option.rawValue
        } label: {
            Text(option.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? OneFeedTheme.plaster : OneFeedTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    selected ? OneFeedTheme.ink : OneFeedTheme.paper,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(selected ? Color.clear : OneFeedTheme.sand, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var intensityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Intensity")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneFeedTheme.ink)
                Spacer()
                Text(intensityLabel)
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
            }
            Slider(value: $intensity, in: 0...1, step: 0.05)
                .tint(OneFeedTheme.ink)
                .disabled(mode == ReaderFocusMode.off.rawValue)
            HStack {
                Text("Subtle")
                Spacer()
                Text("Strong")
            }
            .font(.caption)
            .foregroundStyle(OneFeedTheme.stone)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus intensity")
        .accessibilityValue(intensityLabel)
    }

    private var intensityLabel: String {
        if intensity < 0.34 { return "Subtle" }
        if intensity > 0.72 { return "Strong" }
        return "Medium"
    }
}
