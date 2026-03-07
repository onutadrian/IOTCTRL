import AppKit
import SwiftUI

extension RGBColor {
    var swiftUIColor: Color {
        Color(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0
        )
    }
}

extension Color {
    var rgbColor: RGBColor? {
        let nsColor = NSColor(self)
        guard let converted = nsColor.usingColorSpace(.sRGB) else {
            return nil
        }

        return RGBColor(
            r: Int((converted.redComponent * 255.0).rounded()),
            g: Int((converted.greenComponent * 255.0).rounded()),
            b: Int((converted.blueComponent * 255.0).rounded())
        )
    }
}
