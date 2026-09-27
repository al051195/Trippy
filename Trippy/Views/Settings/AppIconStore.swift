//
//  AppIconStore.swift
//  Trippy
//
//  Reads the icon names Xcode compiled into the app bundle so the settings list
//  always matches the icons the project actually ships, and switches between
//  them.
//

import Observation
import SwiftUI
import UIKit

/// One selectable app icon. `alternateName == nil` is the primary icon.
struct AppIconChoice: Identifiable, Hashable {
    let alternateName: String?

    /// The name of the compiled icon in the asset catalog, which is also what the
    /// Home Screen shows, so the row can show the real thing.
    let iconName: String
    let title: String
    let subtitle: String

    var id: String { alternateName ?? "primary" }
}

@MainActor
@Observable
final class AppIconStore {

    private(set) var choices: [AppIconChoice] = []
    private(set) var currentIconName: String?
    private(set) var isSwitching = false
    var errorMessage: String?

    /// `false` where the system refuses icon changes (visionOS, some managed
    /// configurations).
    private(set) var isSupported = false

    init() {
        isSupported = UIApplication.shared.supportsAlternateIcons
        currentIconName = UIApplication.shared.alternateIconName
        choices = Self.discoverChoices()
    }

    func select(_ choice: AppIconChoice) async {
        guard isSupported, choice.alternateName != currentIconName, !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }

        do {
            try await UIApplication.shared.setAlternateIconName(choice.alternateName)
            currentIconName = UIApplication.shared.alternateIconName
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reads the icon names out of `CFBundleIcons` so the list can never drift
    /// into offering an icon the app doesn't ship.
    private static func discoverChoices() -> [AppIconChoice] {
        let info = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let alternates = info?["CFBundleAlternateIcons"] as? [String: Any]
        let primary = info?["CFBundlePrimaryIcon"] as? [String: Any]

        var discovered: [AppIconChoice] = [
            AppIconChoice(
                alternateName: nil,
                iconName: primary?["CFBundleIconName"] as? String ?? "AppIcon",
                title: "Default",
                subtitle: "The original Trippy icon"
            )
        ]

        for name in (alternates?.keys.sorted() ?? []) {
            let entry = alternates?[name] as? [String: Any]
            discovered.append(
                AppIconChoice(
                    alternateName: name,
                    iconName: entry?["CFBundleIconName"] as? String ?? name,
                    title: name,
                    subtitle: "Alternate icon"
                )
            )
        }

        return discovered
    }
}

/// The icon as it will actually sit on the Home Screen, read from the same
/// compiled asset the system installs.
struct AppIconPreview: View {

    let iconName: String

    var body: some View {
        Group {
            if UIImage(named: iconName) != nil {
                Image(iconName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(.rect(cornerRadius: 10))
    }
}
