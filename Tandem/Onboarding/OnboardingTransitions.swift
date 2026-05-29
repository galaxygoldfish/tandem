import SwiftUI

extension AnyTransition {
    /// Slide-and-fade transition tuned for the onboarding flow. Combine with
    /// `.onboardingSpring` on the container to get the bouncy feel.
    static var onboardingStep: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
            removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.96))
        )
    }
}

extension Animation {
    /// Quick, low-overshoot spring used for onboarding step changes.
    static var onboardingSpring: Animation {
        .spring(response: 0.28, dampingFraction: 0.85)
    }
}
