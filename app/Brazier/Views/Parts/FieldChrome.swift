import SwiftUI

/// A text field on the instrument: 16px so iOS does not zoom, surface plate, one hairline, 5px radius.
struct FieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(BrandFont.body)
            .foregroundStyle(Brand.Tone.paper)
            .tint(Brand.Tone.hot)
            .padding(.horizontal, Brand.Space.label)
            .frame(minHeight: Brand.hitTarget)
            .background(Brand.Tone.surface)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.control))
            .overlay { RoundedRectangle(cornerRadius: Brand.Radius.control).strokeBorder(Brand.Tone.line) }
    }
}

extension View {
    func fieldChrome() -> some View { modifier(FieldChrome()) }
}

/// A labelled block on a bench: eyebrow over content.
struct Labelled<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Space.inline) {
            Eyebrow(label)
            content
        }
    }
}
