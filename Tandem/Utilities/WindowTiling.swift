import SwiftUI
import AppKit

/// Which half of the active screen a window should snap to.
enum TileSide {
    case left
    case right
}

/// Set to `true` after the first call to `centerMainWindowOnce`, so the user
/// can resize/move the window after launch without it snapping back.
private var hasCenteredMainWindow = false

/// Sizes the main window to half the screen width × three-quarters height
/// and centers it on the active screen. Runs at most once per app launch.
///
/// Clears the window's frame autosave name and defers the resize to the next
/// runloop tick so AppKit's state restoration (which fires after
/// `WindowAccessor.makeNSView`) doesn't overwrite our placement with the
/// previous launch's frame.
func centerMainWindowOnce(_ window: NSWindow) {
    guard !hasCenteredMainWindow else { return }
    hasCenteredMainWindow = true

    // Prevent AppKit from persisting/restoring this window's frame across launches.
    window.setFrameAutosaveName("")

    DispatchQueue.main.async {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = visible.width / 2
        let height = visible.height * 3 / 4
        let originX = visible.minX + (visible.width - width) / 2
        let originY = visible.minY + (visible.height - height) / 2
        window.setFrame(
            NSRect(x: originX, y: originY, width: width, height: height),
            display: true,
            animate: false
        )
    }
}

/// Resizes `window` to fill the visible frame of its screen (respecting the
/// menu bar and Dock). Used by the telehealth patient session, which lays out
/// a two-column UI and needs the extra width.
func maximizeWindow(_ window: NSWindow) {
    guard let screen = window.screen ?? NSScreen.main else { return }
    window.setFrame(screen.visibleFrame, display: true, animate: true)
}

/// Resizes `window` to half of its screen's visible frame (respecting the
/// menu bar and Dock). Used to side-by-side the therapist and patient
/// windows when the session starts.
func tileWindow(_ window: NSWindow, to side: TileSide) {
    guard let screen = window.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let halfWidth = visible.width / 2
    let originX = side == .left ? visible.minX : visible.minX + halfWidth
    let frame = NSRect(x: originX, y: visible.minY, width: halfWidth, height: visible.height)
    window.setFrame(frame, display: true, animate: true)
}

/// Tiny `NSViewRepresentable` that surfaces the host `NSWindow` to SwiftUI
/// via a callback. Used as a `.background(WindowAccessor { ... })` hook so
/// onboarding views can tile themselves on appear.
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
