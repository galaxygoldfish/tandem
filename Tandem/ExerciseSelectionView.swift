import SwiftUI

struct ExerciseSelectionView: View {
    var onSelect: (Exercise) -> Void
    var onDeveloper: () -> Void
    var onBack: () -> Void

    enum Exercise: String, CaseIterable, Identifiable {
        case bicepCurl = "Bicep Curl"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Choose an exercise")
                .font(.title.bold())
            Text("Select the exercise to perform during this session")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(Exercise.allCases) { exercise in
                    Button(action: { onSelect(exercise) }) {
                        HStack {
                            Text(exercise.rawValue)
                                .font(.headline)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: 420)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onDeveloper) {
                    HStack {
                        Image(systemName: "hammer.fill")
                        Text("I'm a developer")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 420)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
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
            ToolbarItem(placement: .principal) {
                Color.clear.frame(height: 40)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
