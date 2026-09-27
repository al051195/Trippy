//
//  SettingsView.swift
//  Trippy
//
//  Alternate app icon picker, plus a read-only note about the on-device model.
//

import SwiftUI

struct SettingsView: View {

    let store: TripStore

    @State private var icons = AppIconStore()

    var body: some View {
        List {
            Section {
                ForEach(icons.choices) { choice in
                    Button {
                        Task { await icons.select(choice) }
                    } label: {
                        row(for: choice)
                    }
                    .buttonStyle(.plain)
                    .disabled(icons.isSwitching)
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text("App Icon")
            } footer: {
                Text("Both icon designs ship with the app. Changing the icon takes a moment and the system shows a confirmation.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("On-device AI") {
                    Text(availabilityText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Foundation Models")
            } footer: {
                Text(footerText)
            }

            Section {
                LabeledContent("Version") {
                    Text(versionText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("About")
            } footer: {
                Text("Trippy is a private, on-device travel journal. Your photos, notes and trips never leave this device.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availabilityText: String {
        store.ai.isAvailable ? "Available" : "Unavailable"
    }

    private var footerText: String {
        store.ai.isAvailable
            ? "Title suggestions, natural-language search and day summaries are enabled on this device."
            : "\(store.ai.availabilityDescription) Trippy stays fully usable without it: you can title moments by hand, browse everything chronologically and write your own day notes."
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return build
        default:
            return "—"
        }
    }

    private func row(for choice: AppIconChoice) -> some View {
        HStack(spacing: 12) {
            AppIconPreview(iconName: choice.iconName)

            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title)
                    .font(.body)
                Text(choice.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if choice.alternateName == icons.currentIconName {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tint)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(.rect)
        .padding(.vertical, 2)
    }
}

// MARK: - Icon preview

#Preview {
    NavigationStack {
        SettingsView(store: TripStore())
    }
}
