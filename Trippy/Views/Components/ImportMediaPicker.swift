//
//  ImportMediaPicker.swift
//  Trippy
//
//  The one place media enters the app, wrapping the system photo picker so the
//  same import is available from the journal toolbar and from an empty trip.
//

import PhotosUI
import SwiftUI

struct ImportMediaPicker: View {

    /// Shown instead of the symbol while the import is running. The picker's
    /// label closure is `@Sendable`, so main-actor state has to be read here
    /// rather than captured inside it.
    let isImporting: Bool

    let maximumSelectionCount: Int?

    /// Overrides the symbol-only toolbar appearance.
    var title: String?

    let onImport: ([PhotosPickerItem]) async -> Void

    init(
        title: String? = nil,
        isImporting: Bool,
        maximumSelectionCount: Int? = 60,
        onImport: @escaping ([PhotosPickerItem]) async -> Void
    ) {
        self.title = title
        self.isImporting = isImporting
        self.maximumSelectionCount = maximumSelectionCount
        self.onImport = onImport
    }

    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: maximumSelectionCount,
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos])
        ) {
            label
        }
        .disabled(isImporting)
        .accessibilityLabel(title ?? "Import Photos or Videos")
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await onImport(items)
                selection = []
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if isImporting {
            if title != nil {
                Label("Importing…", systemImage: "photo.badge.plus")
            } else {
                ProgressView()
            }
        } else if let title {
            Label(title, systemImage: "photo.badge.plus")
        } else {
            Label("Import", systemImage: "photo.badge.plus")
        }
    }
}

#Preview {
    ImportMediaPicker(isImporting: false, maximumSelectionCount: 60) { _ in }
}
