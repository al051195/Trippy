//
//  ImageAnalyzer.swift
//  Trippy
//
//  Vision-based enrichment: objects/scenes, recognised animals and on-image text.
//  The result is folded into the prompt sent to the on-device model rather than
//  being shown to the traveller.
//

import UIKit
import Vision

enum ImageAnalyzer {

    /// A short, plain-English note about one image, or `nil` if Vision found
    /// nothing worth passing along.
    nonisolated static func analyze(_ image: CGImage) async -> String? {
        await Task.detached(priority: .userInitiated) {
            analyzeSynchronously(image)
        }.value
    }

    private nonisolated static func analyzeSynchronously(_ image: CGImage) -> String? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        var fragments: [String] = []

        if let scene = classifyScenes(image, handler: handler) {
            fragments.append(scene)
        }
        if let animals = recognizeAnimals(image, handler: handler) {
            fragments.append(animals)
        }
        if let text = recognizeText(image, handler: handler) {
            fragments.append(text)
        }

        guard !fragments.isEmpty else { return nil }
        return fragments.joined(separator: " ")
    }

    /// `VNClassifyImageRequest` needs the Neural Engine, so it is skipped on the
    /// simulator where it would always come back empty.
    private nonisolated static func classifyScenes(_ image: CGImage, handler: VNImageRequestHandler) -> String? {
        #if targetEnvironment(simulator)
        return nil
        #else
        let request = VNClassifyImageRequest()
        try? handler.perform([request])
        let labels = (request.results ?? [])
            .filter { $0.confidence > 0.16 }
            .prefix(5)
            .map(\.identifier)
        guard !labels.isEmpty else { return nil }
        return "Scene: \(labels.joined(separator: ", "))."
        #endif
    }

    private nonisolated static func recognizeAnimals(_ image: CGImage, handler: VNImageRequestHandler) -> String? {
        let request = VNRecognizeAnimalsRequest()
        try? handler.perform([request])
        // Each detected animal carries an array of classifications rather than a
        // single label, so flatten them before ranking.
        let labels = (request.results ?? [])
            .flatMap(\.labels)
            .filter { $0.confidence > 0.3 }
            .prefix(3)
            .map(\.identifier)
        guard !labels.isEmpty else { return nil }
        return "Animals: \(labels.joined(separator: ", "))."
    }

    private nonisolated static func recognizeText(_ image: CGImage, handler: VNImageRequestHandler) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        try? handler.perform([request])
        let strings = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .prefix(4)
        guard !strings.isEmpty else { return nil }
        return "Visible text: \(strings.joined(separator: ", "))."
    }
}
