import AppKit
import CoreText
import SwiftUI

@MainActor
enum FigmaResources {
    private static var didRegisterFonts = false
    private static var imageCache: [String: NSImage] = [:]

    static func registerFontsIfNeeded() {
        guard !didRegisterFonts else {
            return
        }
        didRegisterFonts = true

        registerFont(named: "MartianMono-Regular", ext: "ttf")
        registerFont(named: "MartianMono-Medium", ext: "ttf")
    }

    static func image(named: String) -> NSImage? {
        if let cached = imageCache[named] {
            return cached
        }

        let candidates = [
            "\(named)_4x",
            "\(named)@4x",
            "\(named)@3x",
            "\(named)@2x",
            named
        ]

        for candidate in candidates {
            if let url = Bundle.module.url(forResource: candidate, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                imageCache[named] = image
                return image
            }
        }

        return nil
    }

    private static func registerFont(named: String, ext: String) {
        guard let url = Bundle.module.url(forResource: named, withExtension: ext) else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    @MainActor
    static func figmaMonoRegular(size: CGFloat) -> Font {
        FigmaResources.registerFontsIfNeeded()
        if NSFont(name: "MartianMono-Regular", size: size) != nil {
            return .custom("MartianMono-Regular", size: size)
        }
        return .system(size: size, weight: .regular, design: .monospaced)
    }

    @MainActor
    static func figmaMonoMedium(size: CGFloat) -> Font {
        FigmaResources.registerFontsIfNeeded()
        if NSFont(name: "MartianMono-Medium", size: size) != nil {
            return .custom("MartianMono-Medium", size: size)
        }
        return .system(size: size, weight: .medium, design: .monospaced)
    }
}
