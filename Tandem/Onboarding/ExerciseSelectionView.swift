import SwiftUI

/// Picks the exercise that drives the rest of the session.
/// Currently only Bicep Curl is supported.
struct ExerciseSelectionView: View {
    var onSelect: (Exercise) -> Void
    var onBack: () -> Void

    /// Available exercises. Add new cases here as future protocols come online.
    enum Exercise: String, CaseIterable, Identifiable {
        case bicepCurl    = "Bicep Curl"
        case shoulderShrug = "Shoulder Shrug"
        case wristFlex    = "Wrist Flex"
        var id: String { rawValue }

        /// Asset Catalog image name. Nil means fall back to `symbolName`.
        var imageName: String? {
            switch self {
            case .bicepCurl:    return "BicepCurl"
            case .shoulderShrug: return "ShoulderShrug"
            case .wristFlex:    return "WristFlex"
            }
        }

        /// SF Symbol used when no asset image is available.
        var symbolName: String {
            switch self {
            case .bicepCurl:    return "figure.strengthtraining.traditional"
            case .shoulderShrug: return "figure.arms.open"
            case .wristFlex:    return "hand.raised"
            }
        }

        /// Stable identifier used over the Tandem wire protocol so the patient
        /// Mac can decode which exercise the therapist selected. Kept separate
        /// from `rawValue` because rawValue may contain spaces / be localized.
        var wireKey: String {
            switch self {
            case .bicepCurl:    return "bicepCurl"
            case .shoulderShrug: return "shoulderShrug"
            case .wristFlex:    return "wristFlex"
            }
        }

        static func fromWireKey(_ key: String) -> Exercise? {
            Exercise.allCases.first { $0.wireKey == key }
        }

        /// Asset Catalog image shown on the patient's electrode-placement screen.
        /// Falls back to the bicep image for exercises that don't yet have their
        /// own placement asset — swap these in as the artwork lands.
        var electrodeImageName: String {
            switch self {
            case .bicepCurl:    return "BicepEMGElectrode"
            case .shoulderShrug: return "BicepEMGElectrode"
            case .wristFlex:    return "BicepEMGElectrode"
            }
        }

        /// Body part name used inline in the placement instructions copy.
        var bodyPart: String {
            switch self {
            case .bicepCurl:    return "bicep"
            case .shoulderShrug: return "shoulder"
            case .wristFlex:    return "wrist"
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Choose an exercise")
                .font(.custom("IBMPlexMono-Medium", size: 40))
                .tracking(-1)
            Text("Select the exercise that you'll be working with during this session")
                .font(.custom("IBMPlexMono-Regular", size: 16))
                .foregroundStyle(.black.opacity(0.6))
            Spacer()
            HStack(spacing: 40) {
                ForEach(Exercise.allCases) { exercise in
                    exerciseCard(exercise)
                }
            }
            Spacer()
        }
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

    private func exerciseCard(_ exercise: Exercise) -> some View {
        Button(action: { onSelect(exercise) }) {
            VStack(spacing: 12) {
                if let assetName = exercise.imageName {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: exercise.symbolName)
                        .font(.system(size: 64))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(exercise.rawValue)
                    .font(.custom("IBMPlexMono-Medium", size: 20))
                    .padding(.bottom, 20)
            }
            .padding(20)
            .frame(width: 350, height: 350)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 40))
            .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 40))
        }
        .buttonStyle(.plain)
    }
}
