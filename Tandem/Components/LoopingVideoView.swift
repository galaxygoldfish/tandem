import SwiftUI
import AVKit

/// Looping muted video player backed by an `AVPlayerLayer`. SwiftUI's
/// `VideoPlayer` ships with playback chrome we don't want, and `clipShape`
/// won't clip a hosted CALayer, so this representable owns its own layer
/// and exposes a `cornerRadius`, an optional `replayDelay` to hold on the
/// last frame between loops, and an `isPlaying` switch that freezes the
/// video on its final frame when set to false.
///
/// Used for the bicep-curl reference animation in `PatientSessionView`
/// and the baseline/MVC calibration animations in `TherapistView`.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    var cornerRadius: CGFloat = 0
    var replayDelay: TimeInterval = 0
    var isPlaying: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
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
        let delay = replayDelay
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak player] in
                    player?.seek(to: .zero)
                    player?.play()
                }
            } else {
                player.seek(to: .zero)
                player.play()
            }
        }
        player.play()
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.playerLayer.cornerRadius = cornerRadius
        guard let player = context.coordinator.player else { return }
        if isPlaying {
            if player.timeControlStatus != .playing {
                player.play()
            }
        } else {
            if let duration = player.currentItem?.duration,
               duration.isValid, !duration.isIndefinite {
                player.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.pause()
        }
    }

    static func dismantleNSView(_ nsView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    final class Coordinator {
        var player: AVPlayer?
        var observer: NSObjectProtocol?
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
