import SwiftUI

/// Settings dialog that lets the user pick between the physical motor and
/// openEMSstim hardware as the stimulation output. Bound to
/// `SerialManager.useOpenEMSstim`.
struct StimulationMethodSheet: View {
    @EnvironmentObject var serialManager: SerialManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("Stimulation method")
                .font(.custom("IBMPlexMono-Medium", size: 15))

            Picker("Stimulation method", selection: $serialManager.useOpenEMSstim) {
                Text("Physical")
                    .font(.custom("IBMPlexMono-Regular", size: 10))
                    .padding(10)
                    .tag(false)
                Text("openEMS")
                    .font(.custom("IBMPlexMono-Regular", size: 10))
                    .padding(10)
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}
