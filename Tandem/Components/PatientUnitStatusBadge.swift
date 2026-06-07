//
//  TherapistUnitStatusBadge 2.swift
//  Tandem
//
//  Created by Sebastian Hriscu on 6/7/26.
//


import SwiftUI

/// Compact device status pill: patient unit image, connection dot, and
/// status text. Lives in the corner of the therapist placement screens so the
/// therapist can verify the TENS unit is online without leaving the page.
struct PatientUnitStatusBadge: View {
    @EnvironmentObject private var serialManager: SerialManager

    var body: some View {
        HStack(spacing: 0) { // Set spacing to 0 and manage it via paddings cleanly
            Image("TensUnit")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Patient Unit")
                    .font(.custom("IBMPlexMono-Medium", size: 16))
                    .foregroundStyle(.black)
                HStack(spacing: 6) {
                    Circle()
                        .fill(serialManager.isTensConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(serialManager.isTensConnected ? "Connected" : "Disconnected")
                        .font(.custom("IBMPlexMono-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 16)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            (serialManager.isTensConnected ? Color.green : Color.red).opacity(0.2),
            in: .rect(cornerRadius: 20)
        )
        // This ensures the badge container completely ignores layout changes happening in the center of the screen
        .fixedSize(horizontal: true, vertical: true)
    }
}
