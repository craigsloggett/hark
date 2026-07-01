import AppKit
@testable import hark
import SwiftUI
import Testing

/// Not a test in the assertion sense: renders a set of views to PNGs for visual inspection.
/// Writes into the sandbox container's Documents; `make screenshots` copies them into the repo.
@MainActor
struct ScreenshotRenderer {
    private struct Shot {
        let name: String
        let size: CGSize
        let view: AnyView
    }

    /// Views that render with no injected state. Empty/placeholder states for the model-driven ones.
    private var shots: [Shot] {
        [
            Shot(name: "Settings", size: CGSize(width: 480, height: 560),
                 view: AnyView(SettingsView())),
            Shot(name: "GeneralSettings", size: CGSize(width: 480, height: 420),
                 view: AnyView(GeneralSettingsView())),
            Shot(name: "AdvancedSettings", size: CGSize(width: 480, height: 900),
                 view: AnyView(AdvancedSettingsView())),
            Shot(name: "SessionList-Empty", size: CGSize(width: 260, height: 380),
                 view: AnyView(SessionListView(model: LabelingModel()))),
            Shot(name: "TranscriptChat-Empty", size: CGSize(width: 520, height: 380),
                 view: AnyView(TranscriptChatView(model: LabelingModel()))),
            Shot(name: "PeopleInspector-Empty", size: CGSize(width: 280, height: 380),
                 view: AnyView(PeopleInspectorView(model: LabelingModel()))),
        ]
    }

    @Test func renderAll() throws {
        let outDir = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for shot in shots {
            try render(shot.view, size: shot.size,
                       to: outDir.appendingPathComponent("\(shot.name).png"))
        }
        print("Screenshots written to: \(outDir.path)")
    }

    private func render(_ view: AnyView, size: CGSize, to url: URL) throws {
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // A short spin lets List/ScrollView content lay out before capture.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }
}
