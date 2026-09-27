//
//  MediaGalleryView.swift
//  Trippy
//
//  Full-screen viewing of a moment's media, with the system's own paging and
//  zoom behaviours.
//
//  There are two ways a photo can be shown here, and the display decides which:
//
//  * On Apple's iPhone Duo the photo is scaled to *cover* the screen and the
//    overflow is cropped, so it reaches all four edges. The Duo's outer display
//    is small enough that a fitted photo would be reduced to a stamp marooned in
//    the middle of a black page.
//  * Everywhere else the whole photo is shown and whatever the shape of the
//    screen leaves over stays black, which is how the system photo viewer
//    presents a picture and is the only sensible thing to do with a photo on a
//    display with room to show it.
//
//  Zooming always moves in from whichever of those two starting points the photo
//    has, and never past a scale that would reintroduce bars, so both
//    presentations keep the same gestures and the same guarantees.
//

import SwiftUI

/// How the gallery sizes a photo against the display.
enum MediaGalleryFit: Equatable {

    /// The photo covers the display and the overflow is cropped away.
    case fullBleed

    /// The whole photo is shown, with black left over where its shape and the
    /// screen's disagree.
    case standard

    /// Picks the presentation for a display of `size`.
    ///
    /// Only the iPhone Duo gets the edge-to-edge treatment. There is no public
    /// API that names the Duo, so it is recognised by the one thing that does
    /// set it apart from every other device: the proportions of its outer
    /// display. That display is compact and almost square — 466×678pt — where
    /// every other iPhone is a tall 19.5:9 slab (iPhone 16 Pro 402×874pt, iPhone
    /// SE 375×667pt) and every iPad is much larger (iPad Pro 13" 1032×1376pt).
    /// The two tests sit in the gaps between those three groups. Measuring the
    /// display rather than the model also means the Duo's roomy inner display
    /// lands on the standard presentation, which is what it wants.
    static func preferred(forDisplayOf size: CGSize) -> MediaGalleryFit {
        let shorter = min(size.width, size.height)
        let longer = max(size.width, size.height)

        let isCompact = shorter <= 500 && longer <= 750
        let isAlmostSquare = shorter / longer >= 0.62

        return isCompact && isAlmostSquare ? .fullBleed : .standard
    }

    /// The drawn artwork stands in for a photograph but has no pixels of its
    /// own, so in the standard presentation it is given a fixed 3:4 frame to sit
    /// in. That keeps the sample trip reading as a photo viewer rather than as a
    /// cropped backdrop, which is the whole difference the two modes make.
    private static let artworkFrame = CGSize(width: 3, height: 4)

    func baselineSize(ofArtworkIn container: CGSize) -> CGSize {
        switch self {
        case .fullBleed:
            return container
        case .standard:
            let scale = min(
                container.width / Self.artworkFrame.width,
                container.height / Self.artworkFrame.height
            )
            return CGSize(
                width: Self.artworkFrame.width * scale,
                height: Self.artworkFrame.height * scale
            )
        }
    }
}

struct MediaGalleryView: View {

    let assets: [MediaAsset]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    /// Set by whichever page is zoomed in. Paging is suspended while that is
    /// true, so a drag pans the photo instead of turning the page.
    @State private var isPagingSuspended = false

    init(assets: [MediaAsset], initialIndex: Int) {
        self.assets = assets
        self.initialIndex = min(max(initialIndex, 0), max(assets.count - 1, 0))
        _selection = State(initialValue: min(max(initialIndex, 0), max(assets.count - 1, 0)))
    }

    /// Deliberately not a `NavigationStack`. A navigation bar reserves a strip at
    /// the top of the screen and clips anything that tries to ignore the safe
    /// area, so a photo in one can never reach the top edge — hiding the bar's
    /// background just trades the bar for a strip of whatever is behind it, which
    /// in dark mode is black. Dropping the bar entirely is the only way the photo
    /// reaches all four edges, so the controls are drawn by hand instead.
    var body: some View {
        ZStack {
            // Only ever glimpsed if a page somehow fails to fill, such as during
            // the rubber band past the last one. Black is the right thing to be
            // behind a photograph.
            Color.black

            TabView(selection: $selection) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    ZoomableAsset(asset: asset, isZooming: $isPagingSuspended)
                        // The paging `TabView` occupies the whole screen, so its
                        // pages have to as well — otherwise each photo is laid out
                        // inside the safe area and the strips above and below it
                        // show through as bars.
                        .ignoresSafeArea()
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .scrollDisabled(isPagingSuspended)
        }
        // The safe area is expanded on the container rather than on the `TabView`.
        // Asking a paging `TabView` to ignore the safe area leaves its pages with
        // no size to lay out in, and they disappear — which looks exactly like a
        // black screen. Expanding the parent instead hands the pages a real
        // full-screen frame to fill.
        .ignoresSafeArea()
        .overlay(alignment: .top) { controls }
        .preferredColorScheme(.dark)
    }

    /// The page count and the way out, floating on the photo in glass rather than
    /// sitting in a bar of their own. `safeAreaPadding` pushes them clear of the
    /// camera housing and the top inset without reintroducing a strip.
    private var controls: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Done") { dismiss() }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .capsule)
                .shadow(radius: 24)
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.top, 18)
    }
}

// MARK: - Zoomable asset

/// A single photo, filling the display and pinch- or double-tap-zoomable, with
/// the drawn artwork standing in for the sample trip's moments.
private struct ZoomableAsset: View {

    let asset: MediaAsset

    /// Whether this page is zoomed past its filled baseline, which the gallery
    /// uses to hold paging still while the traveller drags around inside a photo.
    @Binding var isZooming: Bool

    /// How far past filling the display the traveller has zoomed. `1` is a perfect
    /// edge-to-edge crop, so this never goes below it.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    @State private var settledOffset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    /// Zooming out past this would reintroduce the bars, so it is the floor.
    private let maximumZoom: CGFloat = 6

    private var liveZoom: CGFloat {
        min(max(zoom * pinch, 1), maximumZoom)
    }

    private var isZoomed: Bool { liveZoom > 1.01 }

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size

            // A page fills the display, so its own size is the display's, and that
            // is what decides which of the two presentations is used.
            let fit = MediaGalleryFit.preferred(forDisplayOf: container)

            // A real photo is measured against the screen and then scaled to
            // either cover it or fit inside it, depending on the display. The
            // drawn artwork has no dimensions to measure, so it gets a frame.
            let baseline: CGSize = {
                guard let image = MediaImageCache.shared.image(for: asset) else {
                    return fit.baselineSize(ofArtworkIn: container)
                }
                let natural = image.size
                guard natural.width > 0, natural.height > 0 else { return container }

                // Covering crops whatever hangs over the edge; fitting keeps the
                // whole photo and lets black take up the difference.
                let scale = fit == .fullBleed
                    ? max(
                        container.width / natural.width,
                        container.height / natural.height
                    )
                    : min(
                        container.width / natural.width,
                        container.height / natural.height
                    )

                return CGSize(width: natural.width * scale, height: natural.height * scale)
            }()

            let drawn = CGSize(width: baseline.width * liveZoom, height: baseline.height * liveZoom)
            let offset = clamped(
                CGSize(
                    width: settledOffset.width + drag.width,
                    height: settledOffset.height + drag.height
                ),
                drawn: drawn,
                container: container
            )

            content
                .frame(width: drawn.width, height: drawn.height)
                .position(
                    x: container.width / 2 + offset.width,
                    y: container.height / 2 + offset.height
                )
        }
        // The overflow that `covering` created is cropped here, which is the
        // whole point: it is what makes the photo reach every edge.
        .clipped()
        .contentShape(.rect)
        .gesture(magnify)
        // Only claimed while there is actually something to drag around. A
        // `DragGesture` recognises every swipe whether or not it changes
        // anything, so leaving it attached at zoom 1 lets it win the gesture
        // against the paging `TabView` and the traveller can no longer change
        // page. The `isZoomed` test in `pan` guards the maths; this guards the
        // gesture's very existence.
        .simultaneousGesture(pan, isEnabled: isZoomed)
        .onTapGesture(count: 2) {
            withAnimation(.snappy) {
                if isZoomed {
                    zoom = 1
                    settledOffset = .zero
                } else {
                    zoom = 3
                }
            }
        }
        .onChange(of: isZoomed) { _, zoomed in
            isZooming = zoomed
            if !zoomed {
                settledOffset = .zero
            }
        }
        .onChange(of: liveZoom) { _, _ in
            isZooming = isZoomed
        }
        .overlay(alignment: .bottomTrailing) {
            if asset.kind == .video, let duration = asset.durationDescription {
                Label(duration, systemImage: "video.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(20)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = MediaImageCache.shared.image(for: asset) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
        } else if let artwork = asset.demoArtwork {
            DemoArtworkView(artwork: artwork)
        } else {
            ContentUnavailableView(
                asset.kind.displayName,
                systemImage: asset.kind.symbolName,
                description: Text("This item's image isn't stored in the app.")
            )
        }
    }

    /// Keeps the photo inside the frame: once it has been dragged, the offset is
    /// limited to the overhang, so the edges can never be pulled in to show the
    /// background behind them.
    private func clamped(_ offset: CGSize, drawn: CGSize, container: CGSize) -> CGSize {
        let limitX = max(0, (drawn.width - container.width) / 2)
        let limitY = max(0, (drawn.height - container.height) / 2)

        return CGSize(
            width: min(max(offset.width, -limitX), limitX),
            height: min(max(offset.height, -limitY), limitY)
        )
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                zoom = min(max(zoom * value.magnification, 1), maximumZoom)
            }
    }

    /// Only meaningful once there is overhang to move around; otherwise the drag
    /// is left to the gallery, which uses it to change page.
    private var pan: some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in
                guard isZoomed else { return }
                state = value.translation
            }
            .onEnded { value in
                guard isZoomed else { return }
                settledOffset.width += value.translation.width
                settledOffset.height += value.translation.height
            }
    }
}

#Preview {
    MediaGalleryView(assets: DemoTrip.make().moments[0].mediaAssets, initialIndex: 0)
}

