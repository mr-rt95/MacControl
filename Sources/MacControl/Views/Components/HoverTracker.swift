//
//  HoverTracker.swift
//  MacControl
//

import SwiftUI
import AppKit

/// Reports the mouse position over a view. `onContinuousHover` needs macOS 13, so this
/// small AppKit bridge keeps the app compatible with macOS 12.
struct HoverTracker: NSViewRepresentable {

    /// Called with the position (top-left origin) or `nil` when the mouse leaves.
    var onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onMove = onMove
    }

    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?

        override var isFlipped: Bool { true }

        /// Never intercepts clicks or scrolling; tracking areas still deliver mouse movement.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            onMove?(nil)
        }
    }
}
