//
//  TripsSidebar.swift
//  Trippy
//
//  The first column: every journal the traveller has, with the tools to start a
//  new one, duplicate one, put one away, or reach settings.
//

import SwiftUI

struct TripsSidebar: View {

    let store: TripStore

    @State private var showsNewTrip = false
    @State private var showsSettings = false
    @State private var tripToEdit: Trip?
    @State private var tripToDelete: Trip?

    var body: some View {
        List(selection: store.selectedTripIDBinding) {
            if store.trips.isEmpty {
                ContentUnavailableView(
                    "No Trips",
                    systemImage: "suitcase.rolling",
                    description: Text("Create a trip to start keeping a journal.")
                )
            } else {
                ForEach(store.trips) { trip in
                    TripRow(trip: trip)
                        .tag(trip.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if store.library.canDelete(trip.id) {
                            Button(role: .destructive) {
                                tripToDelete = trip
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            tripToEdit = trip
                        } label: {
                            Label("Edit Trip", systemImage: "pencil")
                        }

                        Button {
                            store.select(tripID: trip.id)
                            store.duplicateSelectedTrip()
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }

                        ShareLink(item: trip.plainTextSummary) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        if store.library.canDelete(trip.id) {
                            Divider()

                            Button(role: .destructive) {
                                tripToDelete = trip
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Trips")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewTrip = true
                } label: {
                    Label("New Trip", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if store.selectedTrip != nil {
                        Button {
                            tripToEdit = store.selectedTrip
                        } label: {
                            Label("Edit Trip Info", systemImage: "pencil")
                        }
                    }

                    if store.library.trips.contains(where: { $0.name == DemoTrip.name }) == false {
                        Button {
                            store.addSampleTrip()
                        } label: {
                            Label("Add Sample Trip", systemImage: "sparkles")
                        }
                    }

                    Divider()

                    Button {
                        showsSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsNewTrip) {
            NewTripSheet(store: store)
        }
        .sheet(item: $tripToEdit) { trip in
            TripInfoSheet(store: store, trip: trip)
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView(store: store)
            }
        }
        .confirmationDialog(
            "Delete “\(tripToDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { tripToDelete != nil },
                set: { if !$0 { tripToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Trip", role: .destructive) {
                if let trip = tripToDelete {
                    store.deleteTrip(trip.id)
                }
                tripToDelete = nil
            }
            Button("Cancel", role: .cancel) { tripToDelete = nil }
        } message: {
            Text("The trip and everything in it will be removed from this device.")
        }
    }
}

// MARK: - Trip row

/// One trip in the sidebar: its cover photo, its name, and where and when.
private struct TripRow: View {

    let trip: Trip

    var body: some View {
        HStack(spacing: 12) {
            TripCoverView(trip: trip)

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(rowSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var rowSubtitle: String {
        let subtitle = trip.subtitleDescription
        if !subtitle.isEmpty { return subtitle }
        return trip.momentCount == 0
            ? "No moments yet"
            : "\(trip.momentCount) \(trip.momentCount == 1 ? "moment" : "moments")"
    }
}

/// A trip's first photo, or a plain placeholder for a trip with nothing in it
/// yet. Uses the system's own image and placeholder styles.
private struct TripCoverView: View {

    let trip: Trip

    var body: some View {
        Group {
            if let cover = trip.moments.first?.coverAsset {
                MediaThumbnail(asset: cover)
            } else {
                Image(systemName: "suitcase.rolling")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(.rect(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack {
        TripsSidebar(store: TripStore())
    }
}
