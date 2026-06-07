import SwiftUI

struct TelehealthRoleView: View {
    var onTherapist: () -> Void
    var onPatient: () -> Void
    var onBack: () -> Void

    @State private var cardsVisible = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Who are you?")
                .font(.custom("IBMPlexMono-Medium", size: 40))
                .tracking(-1)
            Spacer()
            HStack(spacing: 40) {
                roleCard(
                    title: "Therapist",
                    subtitle: "",
                    systemImage: "waveform.path.ecg",
                    color: .green.opacity(0.5),
                    action: onTherapist
                )
                .scaleEffect(cardsVisible ? 1 : 0.6)
                .opacity(cardsVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.04), value: cardsVisible)
                roleCard(
                    title: "Patient",
                    subtitle: "",
                    systemImage: "bolt.fill",
                    color: .red.opacity(0.5),
                    action: onPatient
                )
                .scaleEffect(cardsVisible ? 1 : 0.6)
                .opacity(cardsVisible ? 1 : 0)
                .animation(.snappy(duration: 0.3, extraBounce: 0.35).delay(0.1), value: cardsVisible)
            }
            Spacer()
        }
        .onAppear { cardsVisible = true }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigation) {
                TandemTitleBar()
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func roleCard(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.custom("IBMPlexMono-Bold", size: 100))
                Text(title)
                    .font(.custom("IBMPlexMono-Bold", size: 40))
                    .tracking(-1)
                    .padding(.top, 20)
            }
            .frame(width: 400, height: 400)
            .padding(20)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 40))
            .contentShape(.rect(cornerRadius: 40))
            .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 40))
        }
        .buttonStyle(.plain)
    }
}
