//
//  JournalColumn.swift
//  Trippy
//
//  The middle column: one trip's moments, grouped into days, each day headed by
//  a glass card that carries the date and that day's notes.
//
//  It is a `List` whose rows are glass cards — what the traveller sees is the
//  present view's layout, while the list underneath keeps the things only a list
//  can do: pushing the detail column, swipe actions and selection.
//

import PhotosUI
import SwiftUI

struct JournalColumn: View {

    let store: TripStore

    @State private var showsDayNotes: DayNotesTarget?
    @State private var momentToDelete: Moment?

    var body: some View {
        Group {
            if let trip = store.selectedTrip {
                content(for: trip)
            } else {
                ContentUnavailableView(
                    "No Trip Selected",
                    systemImage: "suitcase.rolling",
                    description: Text("Choose a trip to read its journal.")
                )
            }
        }
        .navigationTitle(store.selectedTrip?.name ?? "Journal")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: Binding(
                get: { store.searchQuery },
                set: { store.searchQueryChanged($0) }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search this trip"
        )
        .toolbar { toolbarContent }
        .sheet(item: $showsDayNotes) { target in
            DayNotesView(store: store, day: target.day, canUseAI: store.isAIEnabled)
        }
        .confirmationDialog(
            "Delete Moment?",
            isPresented: Binding(
                get: { momentToDelete != nil },
                set: { if !$0 { momentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Moment", role: .destructive) {
                if let moment = momentToDelete {
                    store.deleteMoment(moment.id)
                }
                momentToDelete = nil
            }
            Button("Cancel", role: .cancel) { momentToDelete = nil }
        } message: {
            Text("The moment and its \(momentToDelete?.mediaCount ?? 0) items will be removed from this device.")
        }
    }

    // MARK: - List

    @ViewBuilder
    private func content(for trip: Trip) -> some View {
        if trip.isEmpty {
            emptyTrip(trip: trip)
        } else if store.dayGroups.isEmpty {
            noSearchResults
        } else {
            journal(for: trip)
        }
    }

    /// Laid out the way the old present view was: every day opens with a single
    /// glass card carrying the date and that day's notes, followed by the day's
    /// moments as cards of their own.
    ///
    /// It stays a `List` rather than becoming a `ScrollView`, because the list is
    /// what teaches the split view to push the detail column on iPhone, and what
    /// gives the traveller swipe-to-delete and swipe-to-favourite. The cards are
    /// the row backgrounds, so the list's own chrome is turned off.
    private func journal(for trip: Trip) -> some View {
        List(selection: store.selectedMomentIDBinding) {
            ForEach(store.dayGroups) { group in
                Section {
                    dayCard(group)

                    ForEach(group.moments) { moment in
                        MomentCard(
                            moment: moment,
                            isDescribing: store.describingIDs.contains(moment.id),
                            isSelected: store.selectedMomentID == moment.id
                        )
                        .tag(moment.id)
                        .listRowInsets(Self.cardInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                momentToDelete = moment
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                store.toggleFavorite(moment.id)
                            } label: {
                                Label(
                                    moment.isFavorite ? "Unfavorite" : "Favorite",
                                    systemImage: moment.isFavorite ? "star.slash" : "star"
                                )
                            }
                            .tint(.yellow)
                        }
                        .contextMenu {
                            Button {
                                store.toggleFavorite(moment.id)
                            } label: {
                                Label(
                                    moment.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                    systemImage: moment.isFavorite ? "star.slash" : "star"
                                )
                            }

                            Button {
                                showsDayNotes = DayNotesTarget(day: trip.day(of: moment))
                            } label: {
                                Label("Day Notes", systemImage: "text.alignleft")
                            }

                            ShareLink(item: moment.displayTitle) {
                                Label("Share Title", systemImage: "square.and.arrow.up")
                            }

                            Divider()

                            Button(role: .destructive) {
                                momentToDelete = moment
                            } label: {
                                Label("Delete Moment", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    /// The margin and gap every card in the journal shares.
    private static let cardInsets = EdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 18)

    // MARK: - Rows

    /// The day's narrative, which the traveller can always write by hand — with or
    /// without Apple Intelligence, and whether or not a summary already exists.
    ///
    /// The date is written here and nowhere else, so each day reads as a single
    /// block: when it was, how many items it holds, and what was said about it.
    private func dayCard(_ group: DayGroup) -> some View {
        let summary = group.summary
        let isSummarizing = store.summarizingDays.contains(group.day)
        let hasNotes = summary?.isEmpty == false

        return Button {
            showsDayNotes = DayNotesTarget(day: group.day)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.weekday)
                            .font(.title3.weight(.semibold))

                        Text(group.dateDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if group.mediaCount > 0 {
                        Text("\(group.mediaCount) \(group.mediaCount == 1 ? "item" : "items")")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if let text = summary?.trimmedText, !text.isEmpty {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)

                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isSummarizing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Writing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !hasNotes {
                    Label("Add Day Notes", systemImage: "square.and.pencil")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MomentCard.inset)
            .glassEffect(.regular, in: .rect(cornerRadius: MomentCard.cornerRadius))
            .contentShape(.rect(cornerRadius: MomentCard.cornerRadius))
        }
        .buttonStyle(.plain)
        .listRowInsets(Self.cardInsets)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ImportMediaPicker(
                isImporting: store.isImporting,
                maximumSelectionCount: 60
            ) { items in
                await store.importItems(items)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: Binding(
                    get: { store.sortOrder },
                    set: { store.sortOrder = $0 }
                )) {
                    ForEach(TripSortOrder.allCases) { order in
                        Label(order.title, systemImage: order.symbolName)
                            .tag(order)
                    }
                }

                if let trip = store.selectedTrip, !trip.isEmpty {
                    ShareLink(item: trip.plainTextSummary) {
                        Label("Share Journal", systemImage: "square.and.arrow.up")
                    }

                    Divider()
                }

                if store.isSearchingForSomething {
                    Button(role: .destructive) {
                        store.clearSearch()
                    } label: {
                        Label("Clear Search", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Empty states

    private func emptyTrip(trip: Trip) -> some View {
        ContentUnavailableView {
            Label("No Moments Yet", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Import photos or videos and they will be grouped into moments by when they were taken.")
        } actions: {
            ImportMediaPicker(
                title: "Import Photos or Videos",
                isImporting: store.isImporting,
                maximumSelectionCount: 60
            ) { items in
                await store.importItems(items)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var noSearchResults: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("Nothing in this trip matches “\(store.searchQuery)”.")
        } actions: {
            Button("Clear Search") {
                store.clearSearch()
            }
        }
    }
}

// MARK: - Day notes target

/// `Date` alone is not a safe `Identifiable` for a sheet, so the target is
/// wrapped to give the sheet something to key on.
struct DayNotesTarget: Identifiable, Hashable {
    let day: Date
    var id: Date { day }
}

#Preview {
    NavigationStack {
        JournalColumn(store: TripStore())
    }
}
