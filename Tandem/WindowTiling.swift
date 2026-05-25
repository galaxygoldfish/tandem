import SwiftUI
import AppKit

enum TileSide {
    case left
    case right
}

func tileWindow(_ window: NSWindow, to side: TileSide) {
    guard let screen = window.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let halfWidth = visible.width / 2
    let originX = side == .left ? visible.minX : visible.minX + halfWidth
    let frame = NSRect(x: originX, y: visible.minY, width: halfWidth, height: visible.height)
    window.setFrame(frame, display: true, animate: true)
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
