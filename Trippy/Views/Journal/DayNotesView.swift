//
//  DayNotesView.swift
//  Trippy
//
//  The narrative for one day. The traveller can always write it by hand — this
//  screen is reachable whether or not a summary already exists, and whether or
//  not Apple Intelligence is available on the device.
//

import SwiftUI

struct DayNotesView: View {

    let store: TripStore
    let day: Date
    let canUseAI: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var confirmsDeletion = false
    @State private var didLoad = false

    private var isSummarizing: Bool { store.summarizingDays.contains(day) }

    private var hasNotes: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var momentCount: Int {
        let calendar = Calendar.current
        return store.moments.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .accessibilityLabel("Day notes")
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Write as much or as little as you like. Anything written here stays yours.")
                }

                if canUseAI {
                    Section {
                        Button {
                            Task { await store.summarize(day: day) }
                        } label: {
                            if isSummarizing {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Writing…")
                                }
                            } else {
                                Label(
                                    hasNotes ? "Rewrite with Apple Intelligence" : "Draft with Apple Intelligence",
                                    systemImage: "wand.and.stars"
                                )
                            }
                        }
                        .disabled(isSummarizing || momentCount == 0)
                    } footer: {
                        Text(momentCount == 0
                             ? "There's nothing in the trip for this day to summarise."
                             : "A first draft from the \(momentCount) moment\(momentCount == 1 ? "" : "s") in this day. You can rewrite it afterwards.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        Label("Delete Day Notes", systemImage: "trash")
                    }
                    .disabled(!hasNotes)
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.updateDaySummary(for: day, text: text)
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete these day notes?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    store.deleteDaySummary(for: day)
                    text = ""
                }
                Button("Cancel", role: .cancel) { }
            }
            .onAppear {
                // Read the stored notes once, so typing is never interrupted by a
                // model write landing underneath the cursor.
                guard !didLoad else { return }
                didLoad = true
                text = store.daySummary(for: day)?.text ?? ""
            }
            .onChange(of: day) { _, newDay in
                store.updateDaySummary(for: day, text: text)
                text = store.daySummary(for: newDay)?.text ?? ""
            }
        }
    }
}

#Preview {
    DayNotesView(store: TripStore(), day: DemoTrip.dayOne, canUseAI: true)
}
