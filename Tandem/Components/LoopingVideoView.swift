import SwiftUI
import AVKit

/// Looping muted video player backed by an `AVPlayerLayer`. SwiftUI's
/// `VideoPlayer` ships with playback chrome we don't want, and `clipShape`
/// won't clip a hosted CALayer, so this representable owns its own layer
/// and exposes a `cornerRadius`, an optional `replayDelay` to hold on the
/// last frame between loops, and an `isPlaying` switch that freezes the
/// video on its final frame when set to false.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    var cornerRadius: CGFloat = 0
    var replayDelay: TimeInterval = 0
    var isPlaying: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        let player = AVPlayer(url: url)
        player.isMuted = true
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.cornerRadius = cornerRadius
        view.playerLayer.masksToBounds = true

        context.coordinator.player = player
        
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            guard let coordinator = coordinator, let player = coordinator.player else { return }
            
            // CRITICAL: Only loop if we are actually supposed to be playing
            guard coordinator.parent.isPlaying else { return }
            
            let delay = coordinator.parent.replayDelay
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak player] in
                    // Re-verify playing state after the asynchronous delay block fires
                    guard let player = player, coordinator.parent.isPlaying else { return }
                    player.seek(to: .zero)
                    player.play()
                }
            } else {
                player.seek(to: .zero)
                player.play()
            }
        }
        
        if isPlaying {
            player.play()
        }
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.playerLayer.cornerRadius = cornerRadius
        
        // Keep the coordinator's reference to parent updated
        context.coordinator.parent = self
        
        guard let player = context.coordinator.player else { return }
        
        if isPlaying {
            if player.timeControlStatus != .playing {
                player.play()
            }
        } else {
            player.pause()
            // Optional: If you want it to snap to the end frame instantly upon disabling:
            if let duration = player.currentItem?.duration,
               duration.isValid, !duration.isIndefinite {
                player.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    static func dismantleNSView(_ nsView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    final class Coordinator {
        var parent: LoopingVideoView
        var player: AVPlayer?
        var observer: NSObjectProtocol?
        
        init(_ parent: LoopingVideoView) {
            self.parent = parent
        }
    }

    final class PlayerContainerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = playerLayer
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
}
