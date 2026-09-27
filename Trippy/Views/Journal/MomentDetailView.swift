//
//  MomentDetailView.swift
//  Trippy
//
//  The third column: one moment, in full. Its media, the words written about it,
//  when it happened, and everything that can be done to it.
//
//  This is the surface that makes a moment editable in a way the sample trip
//  could only pretend to be: media can be added and removed, the date corrected,
//  the moment favourited, retitled, rewritten or deleted — none of which needs
//  Apple Intelligence.
//

import PhotosUI
import SwiftUI

struct MomentDetailView: View {

    let store: TripStore

    @State private var showsGallery = false
    @State private var showsDeleteConfirmation = false
    @State private var assetToDelete: MediaAsset?
    @State private var showsDayNotes: DayNotesTarget?

    var body: some View {
        Group {
            if let moment = store.selectedMoment {
                List {
                    mediaSection(moment)
                    detailsSection(moment)
                    assetsSection(moment)
                    intelligenceSection(moment)
                    dangerSection(moment)
                }
                .navigationTitle(moment.displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar(moment) }
            } else {
                ContentUnavailableView(
                    "No Moment Selected",
                    systemImage: "photo.on.rectangle",
                    description: Text("Choose a moment from the journal to see its details.")
                )
            }
        }
        .fullScreenCover(isPresented: $showsGallery) {
            if let moment = store.selectedMoment {
                MediaGalleryView(assets: moment.mediaAssets, initialIndex: 0)
            }
        }
        .sheet(item: $showsDayNotes) { target in
            DayNotesView(store: store, day: target.day, canUseAI: store.isAIEnabled)
        }
        .confirmationDialog(
            "Remove This Photo?",
            isPresented: Binding(
                get: { assetToDelete != nil },
                set: { if !$0 { assetToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let moment = store.selectedMoment, let asset = assetToDelete {
                    store.deleteMedia(momentID: moment.id, assetID: asset.id)
                }
                assetToDelete = nil
            }
            Button("Cancel", role: .cancel) { assetToDelete = nil }
        } message: {
            Text(assetToDelete?.kind == .video
                 ? "The clip's poster frame will be removed from this moment."
                 : "The photo will be removed from this moment. Your photo library is not changed.")
        }
        .confirmationDialog(
            "Delete Moment?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Moment", role: .destructive) {
                if let moment = store.selectedMoment {
                    store.deleteMoment(moment.id)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The moment and its words will be removed from this trip.")
        }
    }

    // MARK: - Media

    @ViewBuilder
    private func mediaSection(_ moment: Moment) -> some View {
        Section {
            if moment.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "No Media",
                        systemImage: "photo.badge.plus",
                        description: Text("Add photos or videos to this moment.")
                    )

                    ImportMediaPicker(
                        title: "Add to This Moment",
                        isImporting: store.isImporting,
                        maximumSelectionCount: 60
                    ) { items in
                        await store.addItems(items, to: moment.id)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            } else {
                Button {
                    showsGallery = true
                } label: {
                    MomentGalleryStrip(assets: moment.mediaAssets)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Details

    @ViewBuilder
    private func detailsSection(_ moment: Moment) -> some View {
        Section("Details") {
            DatePicker(
                "Captured",
                selection: store.timestampBinding(for: moment.id)
            )

            TextField("Title", text: store.titleBinding(for: moment.id))
                .font(.body)

            TextField(
                "Caption",
                text: store.captionBinding(for: moment.id),
                axis: .vertical
            )
            .lineLimit(1...6)

            Toggle("Favorite", isOn: store.favoriteBinding(for: moment.id))

            if let suggestion = moment.pendingSuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Suggested Title", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(suggestion)
                        .font(.subheadline)

                    HStack {
                        Spacer()
                        Button("Use This Title") {
                            store.acceptSuggestion(for: moment.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Individual media

    @ViewBuilder
    private func assetsSection(_ moment: Moment) -> some View {
        if !moment.isEmpty {
            Section {
                ForEach(moment.mediaAssets) { asset in
                    MediaAssetRow(asset: asset) {
                        assetToDelete = asset
                    }
                }

                ImportMediaPicker(
                    title: "Add to This Moment",
                    isImporting: store.isImporting,
                    maximumSelectionCount: 60
                ) { items in
                    await store.addItems(items, to: moment.id)
                }
            } header: {
                Text("Media")
            } footer: {
                Text("Moment count: \(moment.photoCount) photo\(moment.photoCount == 1 ? "" : "s") and \(moment.videoCount) video\(moment.videoCount == 1 ? "" : "s").")
            }
        }
    }

    // MARK: - Apple Intelligence

    @ViewBuilder
    private func intelligenceSection(_ moment: Moment) -> some View {
        Section {
            if store.isAIEnabled {
                Button {
                    Task { await store.suggestTitle(for: moment.id) }
                } label: {
                    Label(
                        moment.suggestedTitle == nil ? "Suggest a Title" : "Suggest Another Title",
                        systemImage: "wand.and.stars"
                    )
                }
                .disabled(store.suggestingTitleIDs.contains(moment.id))

                Button {
                    Task { await store.describe(momentID: moment.id) }
                } label: {
                    Label(
                        moment.aiDescription == nil ? "Describe for Search" : "Describe Again",
                        systemImage: "text.magnifyingglass"
                    )
                }
                .disabled(store.describingIDs.contains(moment.id))
            } else {
                Label {
                    Text("Apple Intelligence isn't available, so titles and descriptions are written by hand.")
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            if store.isAIEnabled, let description = moment.aiDescription {
                Text(description)
            } else if store.isAIEnabled {
                Text("A description is stored with the moment so it can be found later by what is in the photos.")
            }
        }
    }

    // MARK: - Removing

    @ViewBuilder
    private func dangerSection(_ moment: Moment) -> some View {
        Section {
            Button {
                showsDayNotes = DayNotesTarget(day: store.selectedTrip?.day(of: moment) ?? moment.timestamp)
            } label: {
                Label("Edit Day Notes", systemImage: "text.alignleft")
            }

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete Moment", systemImage: "trash")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ moment: Moment) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    store.toggleFavorite(moment.id)
                } label: {
                    Label(
                        moment.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: moment.isFavorite ? "star.slash" : "star"
                    )
                }

                ShareLink(item: shareText(for: moment)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Divider()

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete Moment", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private func shareText(for moment: Moment) -> String {
        var lines = [moment.displayTitle, moment.timestamp.formatted(date: .complete, time: .shortened)]
        if !moment.trimmedCaption.isEmpty { lines.append(moment.trimmedCaption) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Gallery strip

/// The moment's media as a horizontally paging strip, which opens the full-screen
/// viewer.
private struct MomentGalleryStrip: View {

    let assets: [MediaAsset]

    var body: some View {
        TabView {
            ForEach(assets) { asset in
                MediaThumbnail(asset: asset)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: assets.count > 1 ? .automatic : .never))
        .frame(height: 240)
        .ignoresSafeArea()
    }
}

// MARK: - Media row

/// One photo or video inside a moment, with the controls to take it back out.
private struct MediaAssetRow: View {

    let asset: MediaAsset
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MediaThumbnail(asset: asset)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.kind.displayName)
                    .font(.body)

                Text(asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let duration = asset.durationDescription {
                    Text(duration)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Remove from Moment", systemImage: "trash")
            }
        }
    }
}

#Preview {
    NavigationStack {
        MomentDetailView(store: TripStore())
    }
}
