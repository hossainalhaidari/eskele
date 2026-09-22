import SwiftUI

/// The designs, drawn as miniatures and picked the way macOS picks its appearance: a row of tiles,
/// the current one ringed in the accent colour, its name in bold underneath.
///
/// Something is always selected. Move a setting one of the shipped designs owns and the selection
/// lands on Custom rather than on nothing — which is the honest answer, because the bar still has a
/// shape, just not one of the three that came with the app.
struct DesignPresetPicker: View {
    @Binding var settings: Settings

    /// Four tiles and their rings at the miniature's own size fit across the 520pt settings window
    /// with room to spare, so they are drawn at it rather than scaled.
    private static let tileWidth = BarSilhouette.naturalSize.width
    private static let tileHeight = BarSilhouette.naturalSize.height
    private static let cornerRadius = BarSilhouette.naturalCornerRadius
    /// Room for the selection ring to sit outside the tile without touching it.
    private static let ringInset: CGFloat = 3

    private var selection: DesignPreset { DesignPreset.matching(settings) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(DesignPreset.allCases) { preset in
                tile(preset)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func tile(_ preset: DesignPreset) -> some View {
        let isSelected = selection == preset
        let preview = preset.preview(in: settings)

        return Button {
            settings = preset.applied(to: settings)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if let preview {
                        BarSilhouette(settings: preview)
                    } else {
                        unmadeCustom
                    }
                }
                .frame(width: Self.tileWidth, height: Self.tileHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(.black.opacity(0.25), lineWidth: 0.5)
                }
                .padding(Self.ringInset)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius + Self.ringInset, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .opacity(isSelected ? 1 : 0)
                }

                Text(preset.title)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
        .buttonStyle(.plain)
        // A Custom nobody has made yet has nothing to go back to, so there is nothing to pick.
        .disabled(preview == nil)
        .help(preview == nil ? Self.unmadeCustomHelp : preset.detail)
        .accessibilityLabel(preset.title)
        .accessibilityHint(preview == nil ? Self.unmadeCustomHelp : preset.detail)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The Custom tile before there is a custom design: a blank of the same shape, so the row keeps
    /// its rhythm and the slot reads as one waiting to be filled rather than one that is missing.
    private var unmadeCustom: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.quaternary)
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }

    private static let unmadeCustomHelp = """
        Change any setting below and the result is kept here, ready to come back to.
        """
}
