import SwiftUI

/// Shared rep-counter card used on both the therapist and patient session screens.
/// When `isEditable` is true (therapist), it shows compact goal +/− controls and
/// an undo button. When false (patient), the card is purely read-only.
struct RepCounterCard: View {
    @EnvironmentObject var serialManager: SerialManager
    let isEditable: Bool

    private let circlesPerRow = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: title left, count right
            HStack {
                Text("Reps")
                    .font(.title3.bold())
                Spacer()
                Text("\(serialManager.repCount) / \(serialManager.targetReps)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            repCircles

            // Therapist-only controls: goal adjuster + undo, in a subtle footer
            if isEditable {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Text("Goal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(action: {
                            if serialManager.targetReps > 1 { serialManager.targetReps -= 1 }
                        }) {
                            Image(systemName: "minus")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Text("\(serialManager.targetReps)")
                            .font(.subheadline.monospacedDigit())
                            .frame(minWidth: 20, alignment: .center)

                        Button(action: {
                            if serialManager.targetReps < 20 { serialManager.targetReps += 1 }
                        }) {
                            Image(systemName: "plus")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()

                    Button(action: { serialManager.undoLastRep() }) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(serialManager.repCount == 0)

                    Button(role: .destructive, action: { serialManager.resetReps() }) {
                        Label("Clear", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(serialManager.repCount == 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var repCircles: some View {
        let rows = (serialManager.targetReps + circlesPerRow - 1) / circlesPerRow
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<circlesPerRow, id: \.self) { col in
                        let index = row * circlesPerRow + col
                        if index < serialManager.targetReps {
                            repCircle(index: index)
                        }
                    }
                }
            }
        }
    }

    private func repCircle(index: Int) -> some View {
        let completed = index < serialManager.repCount
        let isJustCompleted = index == serialManager.repCount - 1

        return ZStack {
            Circle()
                .fill(completed ? Color.accentColor : Color.secondary.opacity(0.2))
                .frame(width: 28, height: 28)

            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isJustCompleted ? 1.15 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: serialManager.repCount)
    }
}
