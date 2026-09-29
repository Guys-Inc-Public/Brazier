import SwiftUI

/// One step of the walkthrough: a title, a lead, the step's own content, and a footer pinned above the keyboard.
struct StepPage<Content: View, Footer: View>: View {
    let title: String
    let lead: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Space.card) {
                    Text(title).font(BrandFont.title).foregroundStyle(Brand.Tone.paper)
                    Text(lead).font(BrandFont.body).foregroundStyle(Brand.Tone.muted)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Brand.Space.card)
            }
            .scrollDismissesKeyboard(.interactively)
            Hairline()
            footer
                .padding(.horizontal, Brand.Space.card)
                .padding(.vertical, Brand.Space.label)
        }
    }
}

/// Back on the left, the throw on the right; an interlock with the reason while the throw cannot move.
struct StepButtons: View {
    var back: (() -> Void)?
    let primary: String
    var blocker: String?
    var busy = false
    let action: () -> Void
    var secondary: (title: String, action: () -> Void)?

    var body: some View {
        VStack(spacing: Brand.Space.hairline) {
            HStack(spacing: Brand.Space.label) {
                if let back {
                    Button("Back", action: back).buttonStyle(MomentaryButtonStyle()).padding(.leading, -Brand.Space.inline)
                }
                if busy {
                    HStack(spacing: Brand.Space.label) { MeterBridge(); Eyebrow("working") }
                        .frame(maxWidth: .infinity, minHeight: Brand.hitTarget)
                } else if let blocker {
                    Interlock(reason: blocker)
                } else {
                    Button(primary, action: action).buttonStyle(ThrowButtonStyle())
                }
            }
            if let secondary {
                Button(secondary.title, action: secondary.action)
                    .buttonStyle(MomentaryButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A plate for one way of doing a thing: title, optional chip, one line of why, and the controls.
struct MethodCard<Content: View>: View {
    let title: String
    var chip: String?
    let text: String
    var open: Binding<Bool>?
    @ViewBuilder let content: Content

    private var isOpen: Bool { open?.wrappedValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Space.label) {
            Button {
                guard let open else { return }
                withAnimation(Brand.Motion.curve) { open.wrappedValue.toggle() }
            } label: {
                HStack(spacing: Brand.Space.inline) {
                    Text(title).font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
                    if let chip { StateChip(word: chip, signal: .ok) }
                    Spacer(minLength: 0)
                    if open != nil {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.Tone.muted)
                    }
                }
                .frame(minHeight: Brand.hitTarget - Brand.Space.label)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(open == nil)
            Text(text).font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
            if isOpen { content }
        }
        .padding(Brand.Space.label)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Tone.surface)
        .overlay(alignment: .top) { Rectangle().fill(Brand.Tone.lit).frame(height: 1) }
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.panel))
        .overlay { RoundedRectangle(cornerRadius: Brand.Radius.panel).strokeBorder(Brand.Tone.line) }
    }
}

/// A lamp beside a reading, the shape every check on the walkthrough reports in.
struct ReadingLine: View {
    let signal: Signal
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Brand.Space.inline) {
            Lamp(signal: signal).padding(.top, 5)
            Text(text).font(BrandFont.small).foregroundStyle(signal == .stop ? Brand.Tone.paper : Brand.Tone.paper)
        }
    }
}

/// A numbered instruction, mono number, plain text.
struct NumberedLine: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Brand.Space.inline) {
            Text("\(n)").font(BrandFont.meta).foregroundStyle(Brand.Tone.hot).frame(width: 14, alignment: .trailing)
            Text(text).font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
        }
    }
}
