import AppKit
import CoreText
import Foundation

/// Registers the bundled Chinese serif once at launch.
///
/// The font is shipped with the app because it is not installed on macOS.
/// `KingHwaOldSong` is free to embed, but not to resell on its own; see the
/// licence file in Resources.
enum AppFonts {
    static let bundledChineseName = "KingHwaOldSong"
    static let fallbackChineseName = "Songti SC"

    private static var didRegister = false

    static func register() {
        guard !didRegister else { return }
        didRegister = true

        for url in candidateURLs() {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                &error
            )
            if !registered, let error {
                let nsError = error.takeRetainedValue() as Error
                let alreadyRegistered = (nsError as NSError).code == 105
                if !alreadyRegistered {
                    NSLog("EdgePeek: could not register font: \(nsError.localizedDescription)")
                }
            }
        }
    }

    /// Resolve the font name after registration. If the bundled font cannot be
    /// found (for example while running a loose debug binary), Songti SC keeps
    /// the interface readable. Registration is requested here so layout
    /// metrics resolved before launch cannot silently use the fallback face.
    static let chineseName: String = {
        register()
        if NSFont(name: bundledChineseName, size: 12) != nil {
            return bundledChineseName
        }
        return fallbackChineseName
    }()

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let resource = Bundle.main.url(
            forResource: bundledChineseName,
            withExtension: "ttf"
        ) {
            urls.append(resource)
        }
        if let resources = Bundle.main.resourceURL {
            urls.append(resources.appendingPathComponent("\(bundledChineseName).ttf"))
        }
        if let executable = Bundle.main.executableURL {
            urls.append(
                executable
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources/\(bundledChineseName).ttf")
            )
        }
        urls.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/\(bundledChineseName).ttf")
        )
        return urls
    }
}
