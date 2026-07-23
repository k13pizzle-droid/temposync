import SwiftUI

/// TempoSync's visual identity: Lato everywhere, one user-picked accent.
enum Theme {

    // MARK: Typography (Lato, bundled under the SIL Open Font License)

    static func black(_ size: CGFloat) -> Font { .custom("Lato-Black", size: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("Lato-Bold", size: size) }
    static func regular(_ size: CGFloat) -> Font { .custom("Lato-Regular", size: size) }
    static func light(_ size: CGFloat) -> Font { .custom("Lato-Light", size: size) }

    /// Default body font injected at the app root; most Text picks this up automatically.
    static let body = regular(17)

    /// UIKit-side navigation titles (SwiftUI's nav bars read UIAppearance).
    /// Main-actor: UIAppearance proxies are main-actor isolated (Swift 6).
    @MainActor
    static func installNavigationFonts() {
        #if canImport(UIKit)
        let large = UIFont(name: "Lato-Black", size: 34) ?? .boldSystemFont(ofSize: 34)
        let regular = UIFont(name: "Lato-Bold", size: 17) ?? .boldSystemFont(ofSize: 17)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: large]
        UINavigationBar.appearance().titleTextAttributes = [.font: regular]
        #endif
    }

    // MARK: Accent color (Settings)

    static let accentDefaultsKey = "accent_color"

    struct Accent: Identifiable, Equatable {
        let id: String
        let name: String
        let color: Color
    }

    static let accents: [Accent] = [
        Accent(id: "pulse", name: "Pulse", color: Color(red: 0.35, green: 0.55, blue: 1.0)),
        Accent(id: "ember", name: "Ember", color: Color(red: 1.0, green: 0.45, blue: 0.25)),
        Accent(id: "violet", name: "Violet", color: Color(red: 0.62, green: 0.42, blue: 1.0)),
        Accent(id: "mint", name: "Mint", color: Color(red: 0.2, green: 0.82, blue: 0.65)),
        Accent(id: "rose", name: "Rose", color: Color(red: 1.0, green: 0.36, blue: 0.55)),
    ]

    static var accent: Color {
        let id = UserDefaults.standard.string(forKey: accentDefaultsKey) ?? "pulse"
        return accents.first(where: { $0.id == id })?.color ?? accents[0].color
    }
}
