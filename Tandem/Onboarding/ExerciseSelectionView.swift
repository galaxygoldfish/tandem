import SwiftUI

/// Picks the exercise that drives the rest of the session.
/// Currently only Bicep Curl is supported.
struct ExerciseSelectionView: View {
    var onSelect: (Exercise) -> Void
    var onBack: () -> Void

    /// Available exercises. Add new cases here as future protocols come online.
    enum Exercise: String, CaseIterable, Identifiable {
        case bicepCurl = "Bicep Curl"
        var id: String { rawValue }

        /// Asset Catalog image displayed on the selection card.
        var imageName: String {
            switch self {
            case .bicepCurl: return "BicepCurl"
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Choose an exercise")
                .font(.title.bold())
            Text("Select the exercise to perform during this session")
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 16) {
                ForEach(Exercise.allCases) { exercise in
                    exerciseCard(exercise)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Tandem")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .principal) {
                Color.clear.frame(height: 40)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func exerciseCard(_ exercise: Exercise) -> some View {
        Button(action: { onSelect(exercise) }) {
            VStack(spacing: 12) {
                Image(exercise.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(exercise.rawValue)
                    .font(.title3.bold())
            }
            .padding(20)
            .frame(width: 220, height: 220)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
