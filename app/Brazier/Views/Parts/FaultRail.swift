import SwiftUI

/// Everything the machine has said this session, newest first. Collapses to a spine of lamps.
/// An entry is acknowledged by keeping it; nothing here can be erased.
struct FaultRail: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        let faults = model.unkeptFaults
        if !faults.isEmpty {
            VStack(spacing: Brand.Space.inline) {
                Button {
                    withAnimation(Brand.Motion.curve) { open.toggle() }
                } label: {
                    HStack(spacing: Brand.Space.inline) {
                        HStack(spacing: 3) {
                            ForEach(faults.prefix(6)) { _ in Lamp(signal: .stop, size: 7) }
                        }
                        Eyebrow("\(faults.count) fault\(faults.count == 1 ? "" : "s")", tone: Brand.Tone.stop)
                        Spacer()
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.Tone.muted)
                    }
                    .frame(minHeight: Brand.hitTarget)
                    .padding(.horizontal, Brand.Space.label)
                    .background(Brand.Tone.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.panel))
                }
                .buttonStyle(.plain)
                if open {
                    ForEach(faults.prefix(5)) { fault in
                        VStack(alignment: .leading, spacing: 0) {
                            FaultCard(fault: fault)
                            Button("Keep") { model.keep(fault) }
                                .buttonStyle(MomentaryButtonStyle())
                        }
                    }
                }
            }
        }
    }
}
