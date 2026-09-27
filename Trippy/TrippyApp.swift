//
//  TrippyApp.swift
//  Trippy
//
//  Created by Antoine LEPRETRE on 26/09/2026.
//

import SwiftUI

@main
struct TrippyApp: App {

    /// The single source of truth for the whole app. It is created once here so
    /// that the trip list, the journal and every sheet share the same selection.
    @State private var store = TripStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
