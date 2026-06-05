import SwiftUI
import AppKit

/// First screen the user sees. Shows the Tandem logo and tagline.
/// `onStart` advances the app flow to the hardware connection step.
struct WelcomeView: View {
    var onStart: () -> Void
    var onDebugPatientSession: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(height: 120)
            Text("Tandem")
                .font(.custom("Silkscreen-Regular", size: 64))
                .tracking(-7.68)
                .padding(.top, 30)
            Text("A human to human interface for naturalistic communication of motor movements tailored to physical therapy contexts")
                .font(.default)
                .frame(maxWidth: 550)
                .multilineTextAlignment(.center)
            Button(action: onStart) {
                HStack {
                    Text("Start")
                        .padding(.leading, 10)
                    Image(systemName: "arrow.right")
                        .padding(.leading, 10)
                        .padding(.vertical, 10)
                        .padding(.trailing, 10)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.top, 30)
            Button("Debug: patient session", action: onDebugPatientSession)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(WindowAccessor { centerMainWindowOnce($0) })
        .navigationTitle("Tandem")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(height: 40)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
