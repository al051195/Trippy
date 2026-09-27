//
//  MediaImportService.swift
//  Trippy
//
//  Turns a `PhotosPicker` selection into `MediaAsset` values, then groups those
//  assets into moments using timestamp proximity.
//

import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

enum MediaImportService {

    /// Two shots further apart than this are considered different moments.
    static let momentGap: TimeInterval = 45 * 60

    /// Upper bound so one very long burst of photos doesn't become a single card.
    static let maxAssetsPerMoment = 6

    // MARK: - Loading

    static func load(items: [PhotosPickerItem]) async -> [MediaAsset] {
        var assets: [MediaAsset] = []
        for item in items {
            if let asset = await load(item) {
                assets.append(asset)
            }
        }
        return assets.sorted { $0.createdAt < $1.createdAt }
    }

    private static func load(_ item: PhotosPickerItem) async -> MediaAsset? {
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        let createdAt = captureDate(for: item.itemIdentifier) ?? .now

        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }

        if isVideo {
            return await videoAsset(from: data, createdAt: createdAt)
        }

        return MediaAsset(
            id: UUID(),
            kind: .photo,
            createdAt: createdAt,
            imageData: MediaImage.compressedJPEG(from: data),
            duration: nil,
            demoArtwork: nil
        )
    }

    /// The photo library knows the original capture date, which is what the
    /// temporal clustering should be based on. It falls back to "now" for assets
    /// the picker loaded without a library reference (iCloud, for instance).
    private static func captureDate(for identifier: String?) -> Date? {
        guard let identifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            .firstObject?
            .creationDate
    }

    /// Only the poster frame and duration are retained — enough to show the clip
    /// in the journal without holding whole videos in memory.
    private static func videoAsset(from data: Data, createdAt: Date) async -> MediaAsset? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "trippy-\(UUID().uuidString).mov")

        do {
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }

            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration))?.seconds ?? 0

            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = CGSize(width: 1600, height: 0)
            let poster = try? await generator.image(at: .zero).image

            return MediaAsset(
                id: UUID(),
                kind: .video,
                createdAt: createdAt,
                imageData: poster.flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) },
                duration: duration,
                demoArtwork: nil
            )
        } catch {
            return nil
        }
    }

    // MARK: - Clustering

    /// Groups assets into moments by temporal proximity. No geolocation needed:
    /// a walk with a phone produces a tight burst, a day of sightseeing doesn't.
    static func cluster(
        _ assets: [MediaAsset],
        gap: TimeInterval = momentGap,
        maxAssets: Int = maxAssetsPerMoment
    ) -> [Moment] {
        let sorted = assets.sorted { $0.createdAt < $1.createdAt }
        var groups: [[MediaAsset]] = []

        for asset in sorted {
            if let index = groups.indices.last,
               let previous = groups[index].last,
               asset.createdAt.timeIntervalSince(previous.createdAt) <= gap,
               groups[index].count < maxAssets {
                groups[index].append(asset)
            } else {
                groups.append([asset])
            }
        }

        return groups.map { group in
            let timestamp = group[group.count / 2].createdAt
            return Moment(
                id: UUID(),
                timestamp: timestamp,
                mediaAssets: group,
                suggestedTitle: nil,
                title: "",
                caption: "",
                aiDescription: nil,
                isFavorite: false
            )
        }
    }
}
