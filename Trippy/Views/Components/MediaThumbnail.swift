//
//  MediaThumbnail.swift
//  Trippy
//
//  A moment's cover image, the procedurally drawn artwork that stands in for the
//  sample trip's photos, and the full-screen viewer they open.
//

import SwiftUI

struct MediaThumbnail: View {

    let asset: MediaAsset

    var body: some View {
        content
            // Explicit fill, so a photo of any aspect ratio is cropped to the
            // container rather than letterboxed inside it.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if asset.kind == .video {
                    Image(systemName: "video.fill")
                        .font(.caption2.weight(.bold))
                        .padding(5)
                        .background(.black.opacity(0.45), in: .capsule)
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image = MediaImageCache.shared.image(for: asset) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let artwork = asset.demoArtwork {
            DemoArtworkView(artwork: artwork)
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: asset.kind.symbolName)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

/// Stand-in for a photograph: a two-tone sky, a soft light bloom and a symbol.
struct DemoArtworkView: View {

    let artwork: DemoArtwork

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hue: artwork.hue / 360, saturation: 0.58, brightness: 0.88),
                        Color(hue: artwork.secondaryHue / 360, saturation: 0.74, brightness: 0.48)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.28))
                    .frame(width: size.width * 0.8, height: size.width * 0.8)
                    .blur(radius: 10)
                    .offset(x: size.width * 0.22, y: -size.height * 0.3)

                Image(systemName: artwork.symbolName)
                    .font(.system(size: min(size.width, size.height) * 0.34, weight: .ultraLight))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            }
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(DemoTrip.make().moments.prefix(3).flatMap(\.mediaAssets)) { asset in
            MediaThumbnail(asset: asset)
                .frame(width: 90, height: 90)
                .clipShape(.rect(cornerRadius: 10))
        }
    }
    .padding()
}
