//
//  NewTripSheet.swift
//  Trippy
//
//  Starting a trip: a name, where it is, and optionally the dates it covers — so
//  a trip can be set up before a single photo exists.
//

import SwiftUI

struct NewTripSheet: View {

    let store: TripStore

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var destination = ""
    @State private var setsDates = false
    @State private var startDate = Date.now
    @State private var endDate = Date.now

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        DatePicker(
                            "Start",
                            selection: $startDate,
                            displayedComponents: .date
                        )

                        DatePicker(
                            "End",
                            selection: $endDate,
                            in: startDate...,
                            displayedComponents: .date
                        )
                    }
                } footer: {
                    Text("Without dates, the journal works them out from the photos you import.")
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() {
        store.newTrip(
            name: trimmedName.isEmpty ? "Untitled Trip" : trimmedName,
            destination: destination,
            startDate: setsDates ? startDate : nil,
            endDate: setsDates ? endDate : nil
        )
        dismiss()
    }
}

#Preview {
    NewTripSheet(store: TripStore())
}
