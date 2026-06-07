import SwiftUI
import AppKit

/// First screen the user sees. Shows the Tandem logo and tagline.
/// `onStart` advances the app flow to the hardware connection step.
struct WelcomeView: View {
    var onStart: () -> Void
    var onDebugPatientSession: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            Spacer()
            HStack(spacing: 16) {
                Image("LightningBolt")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                Text("Tandem")
                    .font(.custom("Silkscreen-Regular", size: 140))
                    .tracking(-12)
                    .foregroundStyle(.black)
            }
            .padding(.top, 30)
            Text("Together in motion")
                .font(.custom("Silkscreen-Regular", size: 40))
                .tracking(-5)
                .multilineTextAlignment(.center)
                .foregroundStyle(.black.opacity(0.5))
            Spacer()
            Button(action: onStart) {
                HStack(spacing: 16) {
                    Text("Start")
                        .font(.custom("IBMPlexMono-Regular", size: 28))
                        .padding(.horizontal, 30)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 48)
                .padding(.vertical, 24)
                .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
            Button("Debug: therapist session", action: onDebugPatientSession)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(WindowAccessor { centerMainWindowOnce($0) })
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
        }
    }
}
