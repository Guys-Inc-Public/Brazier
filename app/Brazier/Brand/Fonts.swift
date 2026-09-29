import SwiftUI
import UIKit
import CoreText

/// Archivo for everything a person reads, Martian Mono for everything a machine wrote.
/// Both ship as variable fonts (OFL, in Resources/Fonts), so weight is a variation axis
/// carried by the font descriptor rather than a separate file per weight.
enum BrandFont {
    private static let weightAxis: Int = 0x7767_6874 // 'wght'

    static func archivo(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        Font(variable(family: "Archivo", size: size, weight: weight))
    }

    static func mono(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        Font(variable(family: "Martian Mono", size: size, weight: weight))
    }

    private static let widthAxis: Int = 0x7764_7468 // 'wdth'

    /// PostScript names of the default instances in the two files; the variation
    /// attribute then moves weight (and pins width to normal) on that face.
    private static func postScriptName(for family: String) -> String {
        family == "Archivo" ? "Archivo-SemiBold" : "MartianMono-SemiExpandedRegular"
    }

    static func variable(family: String, size: CGFloat, weight: CGFloat) -> UIFont {
        let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let variation: [Int: CGFloat] = [weightAxis: weight, widthAxis: 100]
        let base = UIFontDescriptor(name: postScriptName(for: family), size: size)
        let descriptor = base.addingAttributes([variationKey: variation])
        return UIFont(descriptor: descriptor, size: size)
    }

    // The scale: 10 micro label · 12 mono meta · 14 UI label · 16 body · 20 lead · 26 card title · 34 section head.
    static var display: Font { archivo(34, weight: 900) }
    static var title: Font { archivo(26, weight: 800) }
    static var lead: Font { archivo(20, weight: 700) }
    static var body: Font { archivo(16) }
    static var bodyStrong: Font { archivo(16, weight: 600) }
    static var label: Font { archivo(14, weight: 600) }
    static var small: Font { archivo(14) }
    static var eyebrow: Font { mono(10, weight: 500) }
    static var meta: Font { mono(12) }
    static var code: Font { mono(13) }
}
