//
//  TripInfoSheet.swift
//  Trippy
//
//  Renaming a trip, changing where it is, and correcting the dates it covers —
//  all of which the sample trip has from the start and a brand new trip does not.
//

import SwiftUI

struct TripInfoSheet: View {

    let store: TripStore
    let trip: Trip

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var destination: String
    @State private var setsDates: Bool
    @State private var startDate: Date
    @State private var endDate: Date

    init(store: TripStore, trip: Trip) {
        self.store = store
        self.trip = trip
        _name = State(initialValue: trip.name)
        _destination = State(initialValue: trip.destination)
        _setsDates = State(initialValue: trip.startDate != nil || trip.endDate != nil)
        _startDate = State(initialValue: trip.startDate ?? trip.resolvedStartDate ?? .now)
        _endDate = State(initialValue: trip.endDate ?? trip.resolvedEndDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("Destination", text: $destination)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Toggle("Set Dates", isOn: $setsDates.animation())

                    if setsDates {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)

                        DatePicker(
                            "End",
                            selection: $endDate,
                            in: startDate...,
                            displayedComponents: .date
                        )
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    Text(datesFooter)
                }

                Section("Contents") {
                    LabeledContent("Moments", value: "\(trip.momentCount)")
                    LabeledContent("Photos and Videos", value: "\(trip.mediaCount)")
                    LabeledContent("Favorites", value: "\(trip.favoriteCount)")

                    if let range = trip.dateRangeDescription, !setsDates {
                        LabeledContent("Dates", value: range)
                    }
                }
            }
            .navigationTitle("Trip Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var datesFooter: String {
        if setsDates {
            return "These dates are what the journal shows for this trip."
        }
        if let range = trip.dateRangeDescription {
            return "Currently showing \(range), worked out from the photos in the trip."
        }
        return "Currently the journal works the dates out from the photos you import."
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateTripDetails(
            id: trip.id,
            name: trimmed.isEmpty ? "Untitled Trip" : trimmed,
            destination: destination,
            startDate: setsDates ? startDate : nil,
            endDate: setsDates ? endDate : nil
        )
        dismiss()
    }
}

#Preview {
    TripInfoSheet(store: TripStore(), trip: DemoTrip.make())
}
