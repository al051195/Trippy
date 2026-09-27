//
//  MediaImage.swift
//  Trippy
//
//  Decoding and caching of imported images. Demo moments carry no image data at
//  all, so the views fall back to procedurally drawn artwork.
//

import ImageIO
import SwiftUI
import UIKit

enum MediaImage {

    /// Decodes `data` at a bounded pixel size. The framework performs the scale
    /// and colour conversion, so this stays cheap for full-resolution library
    /// assets.
    static func downsample(data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    /// Shrinks an imported photo so a whole trip stays in memory.
    static func compressedJPEG(from data: Data, maxPixelSize: Int = 1600) -> Data? {
        guard let image = downsample(data: data, maxPixelSize: maxPixelSize) else { return nil }
        return image.jpegData(compressionQuality: 0.82)
    }

    /// The images handed to the on-device model as multimodal attachments.
    /// Videos are skipped: only their poster frame is retained for display.
    static func attachments(for moment: Moment, maxPixelSize: Int = 768) -> [CGImage] {
        moment.mediaAssets
            .filter { $0.kind == .photo }
            .compactMap { asset in
                guard let data = asset.imageData else { return nil }
                return downsample(data: data, maxPixelSize: maxPixelSize)?.cgImage
            }
    }
}

/// Small decode cache so scrolling a long journal doesn't re-decode thumbnails.
@MainActor
final class MediaImageCache {

    static let shared = MediaImageCache()

    private var images: [UUID: UIImage] = [:]
    private var failed: Set<UUID> = []

    private init() {}

    func image(for asset: MediaAsset) -> UIImage? {
        if let cached = images[asset.id] { return cached }
        guard !failed.contains(asset.id) else { return nil }

        guard let data = asset.imageData,
              let image = MediaImage.downsample(data: data, maxPixelSize: 900) else {
            failed.insert(asset.id)
            return nil
        }

        images[asset.id] = image
        return image
    }

    /// Forgets a decode, so a media item the traveller deleted does not keep an
    /// image alive for the rest of the session.
    func evict(_ assetID: UUID) {
        images.removeValue(forKey: assetID)
        failed.remove(assetID)
    }
}
