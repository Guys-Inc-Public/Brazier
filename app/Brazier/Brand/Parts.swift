import SwiftUI

// The parts list from Branding Standards docs/reference/interface-components.md,
// the few this instrument uses. Each part means one thing.

/// Mono label, uppercase, 0.16em: names a thing a machine wrote or a section of a plate.
struct Eyebrow: View {
    let text: String
    var tone: Color = Brand.Tone.muted

    init(_ text: String, tone: Color = Brand.Tone.muted) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text.uppercased())
            .font(BrandFont.eyebrow)
            .tracking(1.6)
            .foregroundStyle(tone)
    }
}

/// 9px round, glow when lit. Hollow when the machine has no reading.
struct Lamp: View {
    let signal: Signal
    var size: CGFloat = 9

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(signal.color, lineWidth: 1.5)
            if signal != .none {
                Circle()
                    .fill(signal.color)
                    .shadow(color: signal.color.opacity(0.65), radius: size * 0.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A state, as a word in its colour with its border. Dashed when there is no reading.
struct StateChip: View {
    let word: String
    let signal: Signal

    var body: some View {
        Text(word.uppercased())
            .font(BrandFont.mono(10, weight: 500))
            .tracking(1.2)
            .foregroundStyle(signal.color)
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .overlay {
                RoundedRectangle(cornerRadius: Brand.Radius.control)
                    .strokeBorder(signal.color, style: StrokeStyle(lineWidth: 1, dash: signal == .none ? [3, 3] : []))
            }
            .accessibilityLabel(word)
    }
}

/// One shared hairline between readings that sit flush on the same plate.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Brand.Tone.line).frame(height: 1)
    }
}

/// Name over host, in mono. Identity and where it lives.
struct Nameplate: View {
    let name: String
    let host: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(BrandFont.bodyStrong).foregroundStyle(Brand.Tone.paper)
            Text(host).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted)
        }
    }
}

/// The as-of stamp: one per surface. A failed read never moves it.
struct AsOfStamp: View {
    let asOf: Date?
    let failedAt: Date?

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: Brand.Space.label) {
            if let asOf {
                Eyebrow("as of \(Self.clock.string(from: asOf))")
            } else {
                Eyebrow("no reading yet")
            }
            if let failedAt {
                HStack(spacing: Brand.Space.hairline) {
                    Lamp(signal: .stop, size: 7)
                    Eyebrow("read failed \(Self.clock.string(from: failedAt))", tone: Brand.Tone.stop)
                }
            }
        }
    }
}

/// A throw: writes state and reports PASS or REFUSE until acknowledged.
struct ThrowButtonStyle: ButtonStyle {
    var primary = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrandFont.label)
            .foregroundStyle(primary ? Brand.Tone.ink : Brand.Tone.paper)
            .frame(maxWidth: .infinity, minHeight: Brand.hitTarget)
            .padding(.horizontal, Brand.Space.label)
            .background(primary ? Brand.Tone.hot : Brand.Tone.raise)
            .overlay(alignment: .top) { Rectangle().fill(Brand.Tone.lit).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.Tone.shade).frame(height: 1) }
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.control))
            .overlay { RoundedRectangle(cornerRadius: Brand.Radius.control).strokeBorder(primary ? Brand.Tone.hot : Brand.Tone.line) }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(Brand.Motion.quick, value: configuration.isPressed)
    }
}

/// A momentary: no effect outside the surface. Text in hot, no fill.
struct MomentaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrandFont.label)
            .foregroundStyle(Brand.Tone.hot)
            .frame(minHeight: Brand.hitTarget)
            .padding(.horizontal, Brand.Space.inline)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Brand.Motion.quick, value: configuration.isPressed)
    }
}

enum ThrowResult: Equatable {
    case pass(String)
    case refuse(String)

    var signal: Signal { if case .pass = self { return .ok } else { return .stop } }
    var word: String { if case .pass = self { return "PASS" } else { return "REFUSE" } }
    var reason: String {
        switch self {
        case .pass(let s), .refuse(let s): return s
        }
    }
}

/// The latched outcome of a throw. Stays until the person acknowledges it.
struct LatchView: View {
    let result: ThrowResult
    let acknowledge: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Brand.Space.label) {
            StateChip(word: result.word, signal: result.signal)
            Text(result.reason)
                .font(BrandFont.small)
                .foregroundStyle(Brand.Tone.paper)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Clear", action: acknowledge)
                .buttonStyle(MomentaryButtonStyle())
        }
        .padding(Brand.Space.label)
        .background(Brand.Tone.surface)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.panel))
    }
}

struct Fault: Identifiable, Equatable {
    let id = UUID()
    let at: Date
    let call: String
    let reason: String
    /// The retention mark: acknowledged and kept. There is no way to erase a fault.
    var kept = false
}

/// Severity lamp, the call in mono, the plain reason. The machine failed; this is not a verdict.
struct FaultCard: View {
    let fault: Fault
    var retry: (() -> Void)?

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: Brand.Space.label) {
            Lamp(signal: .stop).padding(.top, 5)
            VStack(alignment: .leading, spacing: Brand.Space.hairline) {
                HStack(spacing: Brand.Space.inline) {
                    Text(fault.call).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Self.clock.string(from: fault.at)).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted)
                }
                Text(fault.reason).font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
                if let retry {
                    Button("Retry", action: retry).buttonStyle(MomentaryButtonStyle()).padding(.leading, -Brand.Space.inline)
                }
            }
        }
        .padding(Brand.Space.label)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.Tone.surface)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.panel))
    }
}

/// Sixteen bars rising and settling: requests in flight. Replaces every spinner.
struct MeterBridge: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                Capsule()
                    .fill(i >= 13 ? Brand.Tone.hot : Brand.Tone.muted)
                    .frame(width: 4, height: phase ? CGFloat(6 + (i * 7) % 18) : CGFloat(4 + (i * 5) % 14))
            }
        }
        .frame(height: 24, alignment: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { phase = true }
        }
        .accessibilityLabel("Reading")
    }
}

/// A hatched, flush control that cannot move, and says why in words.
struct Interlock: View {
    let reason: String

    var body: some View {
        HStack(spacing: Brand.Space.inline) {
            Image(systemName: "line.diagonal").foregroundStyle(Brand.Tone.muted)
            Text(reason).font(BrandFont.small).foregroundStyle(Brand.Tone.muted)
        }
        .frame(maxWidth: .infinity, minHeight: Brand.hitTarget)
        .background(
            RoundedRectangle(cornerRadius: Brand.Radius.control)
                .strokeBorder(Brand.Tone.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

/// Rows of key and value, flush on one plate, one hairline between them.
struct KeyValueRows: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Hairline() }
                HStack(alignment: .top, spacing: Brand.Space.label) {
                    Text(row.0).font(BrandFont.meta).foregroundStyle(Brand.Tone.muted)
                        .frame(width: 118, alignment: .leading)
                    Text(row.1).font(BrandFont.code).foregroundStyle(Brand.Tone.paper)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.vertical, Brand.Space.inline)
                .padding(.horizontal, Brand.Space.label)
            }
        }
        .background(Brand.Tone.surface)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.panel))
    }
}

/// A guarded throw: the cover lifts to show the cut list, then a 620 ms hold fires it.
/// Release retracts it and sends nothing.
struct GuardedThrow: View {
    let verb: String
    let cutList: [String]
    let fire: () -> Void

    @State private var lifted = false
    @State private var holding = false
    @State private var progress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Space.inline) {
            if !lifted {
                Button {
                    withAnimation(Brand.Motion.curve) { lifted = true }
                } label: {
                    HStack {
                        Image(systemName: "chevron.up")
                        Text("Lift the cover to \(verb.lowercased())")
                    }
                }
                .buttonStyle(ThrowButtonStyle(primary: false))
            } else {
                VStack(alignment: .leading, spacing: Brand.Space.hairline) {
                    Eyebrow("cut list", tone: Brand.Tone.stop)
                    ForEach(cutList, id: \.self) { line in
                        Text(line).font(BrandFont.small).foregroundStyle(Brand.Tone.paper)
                    }
                }
                .padding(Brand.Space.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.Tone.ink)
                .overlay(alignment: .top) { Rectangle().fill(Brand.Tone.shade).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Brand.Tone.lit).frame(height: 1) }
                .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.panel))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Brand.Radius.control).fill(Brand.Tone.raise)
                    GeometryReader { geo in
                        Rectangle().fill(Brand.Tone.stop.opacity(0.35)).frame(width: geo.size.width * progress)
                    }
                    HStack {
                        Text(holding ? "Holding…" : "Hold to \(verb.lowercased())")
                            .font(BrandFont.label)
                            .foregroundStyle(Brand.Tone.stop)
                        Spacer()
                        Eyebrow("620 ms", tone: Brand.Tone.stop)
                    }
                    .padding(.horizontal, Brand.Space.label)
                }
                .frame(height: Brand.hitTarget)
                .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.control))
                .overlay { RoundedRectangle(cornerRadius: Brand.Radius.control).strokeBorder(Brand.Tone.stop) }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !holding { beginHold() } }
                        .onEnded { _ in endHold() }
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Hold to \(verb)")
            }
        }
    }

    private func beginHold() {
        holding = true
        withAnimation(.linear(duration: Brand.Motion.hold)) { progress = 1 }
        holdTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(Brand.Motion.hold * 1000)))
            guard !Task.isCancelled, holding else { return }
            holding = false
            progress = 0
            fire()
        }
    }

    private func endHold() {
        guard holding else { return }
        holdTask?.cancel()
        holding = false
        withAnimation(Brand.Motion.quick) { progress = 0 }
    }
}
