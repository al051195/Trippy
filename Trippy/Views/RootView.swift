//
//  RootView.swift
//  Trippy
//
//  The app's whole structure, in one `NavigationSplitView`.
//
//  Three columns, which is the shape Apple uses for anything with a collection,
//  a list of things inside it and a detail: trips on the left, the journal in the
//  middle, one moment on the right.
//
//  Nothing here branches on the device. `NavigationSplitView` already collapses
//  into a single stack on iPhone and on an iPhone Duo's compact outer display,
//  and shows all three columns on an iPad or a Duo's inner display, so the same
//  code covers every screen the app can be on.
//

import SwiftUI

struct RootView: View {

    let store: TripStore

    var body: some View {
        @Bindable var store = store

        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $store.preferredCompactColumn
        ) {
            TripsSidebar(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 340)
        } content: {
            JournalColumn(store: store)
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            MomentDetailView(store: store)
        }
        .navigationSplitViewStyle(.balanced)
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            // The model can finish downloading, or Apple Intelligence can be
            // enabled, while the app is in the background.
            if phase == .active {
                store.ai.refreshAvailability()
            }
        }
    }

    /// The sidebar is worth showing on its own when nothing is selected yet, so
    /// the app opens on the traveller's trips rather than on a detail pane.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @Environment(\.scenePhase) private var scenePhase
}

#Preview {
    RootView(store: TripStore())
}
