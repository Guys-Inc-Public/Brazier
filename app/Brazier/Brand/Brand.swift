import SwiftUI

/// The eleven colours, the spacing steps, the four radii and the one curve from
/// Guys Inc Branding Standards (tokens/tokens.json). Application surfaces take the
/// instrument profile: radius 5 / 10 / 18 / 999, one light source above the page.
enum Brand {
    enum Tone {
        static let ink = Color(hex: 0x0E090F)      // page ground
        static let surface = Color(hex: 0x19121A)  // raised panels, table headers
        static let raise = Color(hex: 0x231D25)    // hover and active rows, the only hover fill
        static let line = Color(hex: 0x322B34)     // every border and divider, 1px
        static let hot = Color(hex: 0xFF67BD)      // interaction, primary buttons
        static let lilac = Color(hex: 0xA984FB)    // secondary emphasis
        static let paper = Color(hex: 0xF6F4F7)    // primary text
        static let muted = Color(hex: 0x969098)    // mono labels, metadata
        static let ok = Color(hex: 0x22DCB3)       // verified
        static let wait = Color(hex: 0xFEA845)     // pending
        static let stop = Color(hex: 0xF43A57)     // denied, failed
        /// The 1px lit top edge and shaded bottom edge of an operable part.
        static let lit = Color(red: 246 / 255, green: 244 / 255, blue: 247 / 255).opacity(0.055)
        static let shade = Color.black.opacity(0.42)
    }

    enum Space {
        static let hairline: CGFloat = 4
        static let inline: CGFloat = 8
        static let label: CGFloat = 12
        static let card: CGFloat = 20
        static let panel: CGFloat = 32
        static let block: CGFloat = 52
    }

    enum Radius {
        static let control: CGFloat = 5
        static let panel: CGFloat = 10
        static let card: CGFloat = 18
        static let round: CGFloat = 999
    }

    enum Motion {
        static let feedback: Double = 0.14
        static let entrance: Double = 0.46
        static let swap: Double = 0.70
        static let hold: Double = 0.62
        static var curve: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: entrance) }
        static var quick: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: feedback) }
    }

    static let hitTarget: CGFloat = 44
    static let notAffiliated = "Brazier is not affiliated with or endorsed by Grafana Labs. Grafana is a trademark of Grafana Labs."
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// State, and only state. Every state carries a colour, a pattern and a word.
enum Signal: Hashable {
    case ok, wait, stop, none

    var color: Color {
        switch self {
        case .ok: return Brand.Tone.ok
        case .wait: return Brand.Tone.wait
        case .stop: return Brand.Tone.stop
        case .none: return Brand.Tone.muted
        }
    }
}
